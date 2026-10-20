#!/bin/bash
set -uo pipefail

# Opt-in Claude Code hooks that carry Ralph state across a compaction.
#   ./ralph/context-hooks.sh install [--shared]    # add the two hooks to .claude/settings.local.json
#                                                  # (--shared: .claude/settings.json, committed)
#   ./ralph/context-hooks.sh uninstall [--shared]  # remove them again
#   ./ralph/context-hooks.sh snapshot              # write the state note now and print it
#   ./ralph/context-hooks.sh show                  # print the last state note
#   ./ralph/context-hooks.sh precompact            # PreCompact hook handler (JSON on stdin)
#   ./ralph/context-hooks.sh sessionstart          # SessionStart "compact" hook handler
#
# PreCompact writes a short note (current issue, failing checks, next step, the
# /compact focus line); SessionStart with source "compact" re-injects it as
# additionalContext, so the summary cannot lose what the files already know.
# The note lives under the git dir (per worktree, never committed). Nothing here
# touches ~/.claude/settings.json, and the handlers always exit 0: a hook that
# exits 2 would block the compaction.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS="issues/status.json"
PROGRESS="issues/progress.md"
MARK="ralph/context-hooks.sh"
FRESH_SECS=$((30 * 60)) # a note older than this from another session is stale

state_path() { # state_path <name> — per-worktree path under the git dir
  local p
  if p="$(git rev-parse --git-path "ralph/$1" 2>/dev/null)"; then echo "$p"
  else echo ".claude/ralph/$1"
  fi
}
# Hooks may run from any directory: use the session's cwd from the hook input,
# else $CLAUDE_PROJECT_DIR, else the project this script lives in.
enter_root() { # enter_root [<cwd>]
  local d
  for d in "${1:-}" "${CLAUDE_PROJECT_DIR:-}" "$HERE/.."; do
    [[ -n "$d" && -d "$d" ]] || continue
    if [[ "$d" != "$HERE/.." ]] && ! git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then continue; fi
    cd "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo "$d")" || continue
    NOTE="$(state_path context.md)"
    CHECKS_RECORD="$(state_path last-checks.json)"
    return 0
  done
  return 1
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
clip() { cut -c1-"${1:-300}"; }

has_status() { [[ -f "$STATUS" ]] && jq -e . "$STATUS" >/dev/null 2>&1; }
known_id() { has_status && jq -e --arg id "$1" '.issues | map(.id) | index($id)' "$STATUS" >/dev/null 2>&1; }

# Agent-written progress lines; the loop's own start/stop lines say nothing about the work.
handoff_lines() {
  [[ -f "$PROGRESS" ]] || return 0
  grep -E '^- [0-9]{4}-' "$PROGRESS" | grep -vE '^- [^ ]+ (loop( \(sandboxed\))?:|once:)'
}

current_issue() { # prints "<id>\t<how it was found>"
  local branch id line
  branch="$(git branch --show-current 2>/dev/null || true)"
  id="$(grep -oE '(^|[^0-9])[0-9]{3,}([^0-9]|$)' <<<"$branch" | grep -oE '[0-9]{3,}' | head -n1)"
  if [[ -n "$id" ]] && known_id "$id"; then printf '%s\tbranch %s\n' "$id" "$branch"; return; fi
  line="$(handoff_lines | tail -n1)"
  id="$(sed -nE 's/^- [^ ]+ ((PASS|FAIL) )?([0-9]{3,})[: ].*/\3/p' <<<"$line")"
  if [[ -n "$id" ]]; then printf '%s\tlast progress line\n' "$id"; return; fi
  if [[ -x ralph/status.sh ]] && id="$(./ralph/status.sh next 2>/dev/null)"; then
    printf '%s\tnext runnable in %s\n' "$id" "$STATUS"; return
  fi
  printf -- '-\tnone found\n'
}

note_body() { # note_body <event> <session_id> <compact focus>
  local event="$1" sid="$2" focus="$3" id how branch head dirty title summary last
  IFS=$'\t' read -r id how < <(current_issue)
  [[ "$id" == "-" ]] && id=""
  branch="$(git branch --show-current 2>/dev/null || echo '?')"
  head="$(git log -1 --format='%h %s' 2>/dev/null | clip 100 || echo 'no commits')"
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

  echo "# Ralph state note"
  echo
  echo "Written $(now) by $event (session ${sid:-unknown}). Facts from files and git, not from memory."
  echo
  echo "- Branch: ${branch:-detached} at ${head:-?}; ${dirty:-0} uncommitted path(s)$( (( ${dirty:-0} > 0 )) && echo ' — commit at the next green ./ralph/checks.sh')"
  if [[ -n "$id" ]]; then
    title="$(has_status && jq -r --arg id "$id" '.issues[] | select(.id == $id) | "\(.title) (\(.type)), check: `\(.check)`"' "$STATUS" 2>/dev/null)"
    echo "- Current issue: $id${title:+ — $title} (from $how)"
  else
    echo "- Current issue: none found (no issue branch, progress line or runnable issue)"
  fi
  if [[ -x ralph/status.sh ]] && summary="$(./ralph/status.sh summary --line 2>/dev/null)"; then
    echo "- Issue status: $summary"
  fi
  if [[ -f "$CHECKS_RECORD" ]] && jq -e . "$CHECKS_RECORD" >/dev/null 2>&1; then
    jq -r '
      (.results | map(select(.exit_code != 0))) as $f
      | "- Last ./ralph/checks.sh run: \(.at) at \(.head) — \(.results | length - ($f | length))/\(.results | length) passed"
        + (if ($f | length) > 0 then "; failing: " + ($f | map("`\(.command)` (exit \(.exit_code))") | join(", ")) else "" end)
    ' "$CHECKS_RECORD" | clip 600
  else
    echo "- Last ./ralph/checks.sh run: none recorded in this worktree"
  fi
  last="$(handoff_lines | tail -n1 | sed -E 's/^- //')"
  echo "- Next step (last line of $PROGRESS): ${last:-none written yet}" | clip 600
  [[ -n "$focus" ]] && echo "- /compact focus: $focus" | clip 400
  echo
  echo "Before continuing: re-read the issue file and the last ~30 lines of $PROGRESS, and re-run ./ralph/checks.sh."
}

write_note() { # write_note <event> <session_id> <focus>
  mkdir -p "$(dirname "$NOTE")" || return 1
  local tmp; tmp="$(mktemp)"
  { note_body "$@"; } >"$tmp" && mv "$tmp" "$NOTE"
  printf '%s\n' "$2" >"$NOTE.session"
}

hook_input() { # reads hook JSON from stdin when there is any
  [[ -t 0 ]] && { echo '{}'; return; }
  local raw; raw="$(cat)"
  jq -e . >/dev/null 2>&1 <<<"$raw" && echo "$raw" || echo '{}'
}

precompact() {
  local in sid trigger focus
  in="$(hook_input)"
  enter_root "$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null)" || exit 0
  sid="$(jq -r '.session_id // ""' <<<"$in")"
  trigger="$(jq -r '.trigger // "unknown"' <<<"$in")"
  focus="$(jq -r '.custom_instructions // ""' <<<"$in")"
  write_note "PreCompact ($trigger)" "$sid" "$focus" 2>/dev/null || true
  exit 0
}

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

sessionstart() {
  local in sid source saved age
  in="$(hook_input)"
  enter_root "$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null)" || exit 0
  sid="$(jq -r '.session_id // ""' <<<"$in")"
  source="$(jq -r '.source // ""' <<<"$in")"
  [[ "$source" == "compact" && -f "$NOTE" ]] || exit 0
  saved="$(cat "$NOTE.session" 2>/dev/null || true)"
  age=$(( $(date +%s) - $(mtime "$NOTE") ))
  # The note is for the session that just compacted; another session's old note would mislead.
  if [[ -n "$sid" && -n "$saved" && "$sid" != "$saved" ]] && (( age > FRESH_SECS )); then exit 0; fi
  jq -n --rawfile note "$NOTE" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ($note[0:9000])}}'
  exit 0
}

settings_file() { [[ "${1:-}" == "--shared" ]] && echo .claude/settings.json || echo .claude/settings.local.json; }

install() {
  local f; f="$(settings_file "${1:-}")"
  command -v jq >/dev/null || { echo "context-hooks: jq is required" >&2; exit 1; }
  mkdir -p .claude
  [[ -f "$f" ]] || echo '{}' >"$f"
  jq -e . "$f" >/dev/null 2>&1 || { echo "context-hooks: $f is not valid JSON — fix it first" >&2; exit 1; }
  local tmp; tmp="$(mktemp)"
  jq --arg mark "$MARK" '
    def ours: (.hooks // []) | any((.command // "") | contains($mark));
    def put($ev; $entry): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not))) + [$entry]);
    put("PreCompact"; {hooks: [{type: "command", command: ("\"$CLAUDE_PROJECT_DIR\"/" + $mark + " precompact"), timeout: 30}]})
    | put("SessionStart"; {matcher: "compact", hooks: [{type: "command", command: ("\"$CLAUDE_PROJECT_DIR\"/" + $mark + " sessionstart"), timeout: 10}]})
  ' "$f" >"$tmp" && mv "$tmp" "$f"
  echo "context-hooks: PreCompact + SessionStart(compact) hooks installed in $f"
  if [[ "$f" == .claude/settings.local.json ]] && git rev-parse --git-dir >/dev/null 2>&1 \
     && ! git check-ignore -q "$f"; then
    echo "$f" >>"$(git rev-parse --git-path info/exclude)"
    echo "context-hooks: $f added to .git/info/exclude (personal settings stay out of commits)"
  fi
  echo "context-hooks: takes effect in new sessions; the note is written to $NOTE"
}

uninstall() {
  local f; f="$(settings_file "${1:-}")"
  [[ -f "$f" ]] || { echo "context-hooks: $f not found — nothing to remove"; return 0; }
  local tmp; tmp="$(mktemp)"
  jq --arg mark "$MARK" '
    if .hooks then
      .hooks |= (with_entries(.value |= map(select((.hooks // []) | any((.command // "") | contains($mark)) | not)))
                 | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$f" >"$tmp" && mv "$tmp" "$f"
  echo "context-hooks: removed from $f"
}

case "${1:-}" in
  precompact|sessionstart) ;;
  *) enter_root "$PWD" || { echo "context-hooks: no project found" >&2; exit 1; } ;;
esac

case "${1:-}" in
  precompact)   precompact ;;
  sessionstart) sessionstart ;;
  snapshot)     write_note "snapshot" "${CLAUDE_SESSION_ID:-}" "${2:-}" && cat "$NOTE" ;;
  show)         if [[ -f "$NOTE" ]]; then cat "$NOTE"; else echo "context-hooks: no note yet ($NOTE)" >&2; exit 1; fi ;;
  install)      install "${2:-}" ;;
  uninstall)    uninstall "${2:-}" ;;
  *)            sed -n '4,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
