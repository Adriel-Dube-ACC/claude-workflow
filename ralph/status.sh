#!/bin/bash
set -uo pipefail

# Machine-readable issue status (issues/status.json) and the append-only
# progress log (issues/progress.md).
#
#   ./ralph/status.sh validate          # schema + cross-checks against issues/*.md
#   ./ralph/status.sh summary [--line]  # passing count, failing issues, next runnable
#   ./ralph/status.sh next              # id of the next runnable AFK issue (exit 1 if none)
#   ./ralph/status.sh pass <id>         # run AGENTS.md Checks + the issue's own check;
#                                       # flip passes:true ONLY if every one exits 0
#   ./ralph/status.sh progress "<text>" # append a timestamped line to issues/progress.md
#
# "passes" starts false for every issue and is flipped only by `pass`, which
# records the evidence in a "verified" object. `validate` rejects any
# passes:true without that evidence, so a hand-edited flag fails the gate.
#
# status.json shape:
#   { "version": 1, "prd": "issues/prd.md",
#     "issues": [ { "id": "001", "file": "001-walking-skeleton.md",
#                   "title": "...", "type": "AFK|HITL",
#                   "behaviour": "one sentence a user could observe",
#                   "check": "shell command that proves this issue end to end",
#                   "blockedBy": ["..."], "passes": false } ] }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2
STATUS="issues/status.json"
PROGRESS="issues/progress.md"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "status: $*" >&2; exit 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
head_sha() { git rev-parse --short HEAD 2>/dev/null || echo "no-commit"; }

progress() {
  if [[ ! -f "$PROGRESS" ]]; then
    mkdir -p "$(dirname "$PROGRESS")"
    cat >"$PROGRESS" <<'EOF'
# Progress log

Append-only, newest at the bottom. Every Ralph pass adds to it: the loop logs
each iteration's start, `ralph/status.sh pass` logs PASS/FAIL with exit codes,
and the agent logs what it did and what the next pass should pick up.
Read the last ~30 lines before starting work; never rewrite earlier entries.

EOF
  fi
  printf -- '- %s %s\n' "$(now)" "$*" >>"$PROGRESS"
}

need_status() {
  [[ -f "$STATUS" ]] || die "$STATUS not found — run /prd-to-issues to create it"
  jq -e . "$STATUS" >/dev/null 2>&1 || die "$STATUS is not valid JSON"
}

issue_path() { # issue_path <file> -> issues/<file> or issues/done/<file>
  if [[ -f "issues/$1" ]]; then echo "issues/$1"
  elif [[ -f "issues/done/$1" ]]; then echo "issues/done/$1"
  else return 1
  fi
}

section() { # section <file> <heading> — body of "## <heading>", HTML comments dropped; exit 1 if absent
  awk -v h="## $2" '
    $0 == h || index($0, h " ") == 1 { on = 1; found = 1; next }
    on && /^## / { on = 0 }
    /<!--/ { c = 1 }
    on && !c { print }
    /-->/ { c = 0 }
    END { exit !found }
  ' "$1"
}

validate() {
  need_status
  local errs=0 line
  while IFS= read -r line; do
    [[ -n "$line" ]] && { echo "status: $line" >&2; errs=$((errs + 1)); }
  done < <(jq -r '
    def req($k; $t): if (has($k) and (.[$k] | type) == $t) then empty
                     else "issue \(.id // "?"): field \"\($k)\" missing or not a \($t)" end;
    (if .version == 1 then empty else "version must be 1" end),
    (if (.issues | type) == "array" and (.issues | length) > 0 then empty
     else "issues must be a non-empty array" end),
    ((.issues // []) | map(.id) | group_by(.) | map(select(length > 1) | .[0])
       | .[] | "duplicate id \(.)"),
    ((.issues // []) | map(.id) as $ids | .[] |
       req("id"; "string"), req("file"; "string"), req("title"; "string"),
       req("behaviour"; "string"), req("check"; "string"),
       req("blockedBy"; "array"), req("passes"; "boolean"),
       (if (.type == "AFK" or .type == "HITL") then empty
        else "issue \(.id): type must be AFK or HITL" end),
       (if ((.check // "") | test("^\\s*$")) then "issue \(.id): check is empty" else empty end),
       (.id as $me | (.blockedBy // [])[] | select(. as $b | $ids | index($b) | not)
          | "issue \($me): blockedBy unknown id \(.)"),
       (if .passes == true and ((.verified.at // "") == "")
        then "issue \(.id): passes is true without verified evidence — only `ralph/status.sh pass` may flip it"
        elif .passes == true and (.verified.check.command != .check or .verified.check.exit_code != 0)
        then "issue \(.id): verified evidence is for a different check (or a non-zero exit) — run `ralph/status.sh pass \(.id)` again"
        else empty end))
  ' "$STATUS")

  # Recorded evidence must point at a real commit.
  local b
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    b="${line#* }"
    git cat-file -e "$b^{commit}" 2>/dev/null \
      || { echo "status: issue ${line%% *}: verified.base $b is not a commit in this repo" >&2; errs=$((errs + 1)); }
  done < <(jq -r '.issues[] | select(.passes == true and (.verified.base // "") != "" and .verified.base != "no-commit") | "\(.id) \(.verified.base)"' "$STATUS")

  # Every listed file exists, and every issue file is listed.
  local f
  while IFS= read -r f; do
    issue_path "$f" >/dev/null || { echo "status: file $f not found in issues/ or issues/done/" >&2; errs=$((errs + 1)); }
  done < <(jq -r '.issues[]?.file // empty' "$STATUS")
  for f in issues/[0-9]*.md issues/done/[0-9]*.md; do
    [[ -e "$f" ]] || continue
    jq -e --arg b "$(basename "$f")" '.issues | map(.file) | index($b)' "$STATUS" >/dev/null \
      || { echo "status: $f has no entry in $STATUS" >&2; errs=$((errs + 1)); }
  done

  # status.json must agree with what each issue file declares. Only fields the
  # file actually has are compared, so a terse issue file is not an error.
  local id file path want got
  while IFS=$'\t' read -r id file; do
    path="$(issue_path "$file")" || continue
    [[ "$file" == "$id"-* ]] || { echo "status: issue $id: file $file does not start with \"$id-\"" >&2; errs=$((errs + 1)); }
    if section "$path" Type >/dev/null; then
      got=$(section "$path" Type | grep -oE '\b(AFK|HITL)\b' | head -n1)
      want=$(jq -r --arg id "$id" '.issues[] | select(.id == $id) | .type' "$STATUS")
      [[ "$got" == "$want" ]] || { echo "status: issue $id: $path says type ${got:-none}, $STATUS says $want" >&2; errs=$((errs + 1)); }
    fi
    got=$(section "$path" Check | grep -m1 -oE '`[^`]+`' | sed 's/^`//; s/`$//')
    if [[ -n "$got" ]]; then
      want=$(jq -r --arg id "$id" '.issues[] | select(.id == $id) | .check' "$STATUS")
      [[ "$got" == "$want" ]] || { echo "status: issue $id: $path Check is '$got', $STATUS check is '$want'" >&2; errs=$((errs + 1)); }
    fi
    if section "$path" "Blocked by" >/dev/null; then
      got=$(section "$path" "Blocked by" | grep -oE '(^|[^0-9A-Za-z])[0-9]{3,}-[A-Za-z0-9._-]*\.md' \
            | grep -oE '[0-9]{3,}-' | tr -d - | sort -u | paste -sd, -)
      want=$(jq -r --arg id "$id" '.issues[] | select(.id == $id) | .blockedBy | sort | unique | join(",")' "$STATUS")
      [[ "$got" == "$want" ]] || { echo "status: issue $id: $path is blocked by [${got}], $STATUS blockedBy is [${want}]" >&2; errs=$((errs + 1)); }
    fi
  done < <(jq -r '.issues[]? | select(.id and .file) | "\(.id)\t\(.file)"' "$STATUS")

  # A passing issue whose blocker is not passing means the order was skipped.
  while IFS= read -r line; do
    [[ -n "$line" ]] && { echo "status: $line" >&2; errs=$((errs + 1)); }
  done < <(jq -r '
    (.issues | map({key: .id, value: .passes}) | from_entries) as $p
    | .issues[] | select(.passes == true) | .id as $me
    | .blockedBy[] | select($p[.] != true) | "issue \($me): passes but blocker \(.) does not"
  ' "$STATUS")

  if (( errs )); then echo "status: INVALID ($errs problem(s))" >&2; return 1; fi
  echo "status: valid — $(jq -r '.issues | "\(map(select(.passes)) | length)/\(length) passing"' "$STATUS")"
}

next_runnable() {
  jq -r '
    (.issues | map({key: .id, value: .passes}) | from_entries) as $p
    | [.issues[] | select(.passes == false and .type == "AFK")
                 | select(all(.blockedBy[]; $p[.] == true))][0].id // empty
  ' "$STATUS"
}

summary() {
  need_status
  local nxt; nxt="$(next_runnable)"
  if [[ "${1:-}" == "--line" ]]; then
    jq -r --arg n "${nxt:-none}" '.issues | "\(map(select(.passes)) | length)/\(length) passing, next AFK: \($n)"' "$STATUS"
    return
  fi
  jq -r '
    .issues | "\(map(select(.passes)) | length)/\(length) issues passing",
    (.[] | "  [\(if .passes then "x" else " " end)] \(.id) \(.type) \(.title)\(if (.blockedBy | length) > 0 then "  (blocked by \(.blockedBy | join(", ")))" else "" end)")
  ' "$STATUS"
  echo "next runnable AFK issue: ${nxt:-none}"
}

pass() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "usage: status.sh pass <id>"
  validate >/dev/null || die "fix $STATUS before flipping anything (run: ralph/status.sh validate)"
  jq -e --arg id "$id" '.issues | map(.id) | index($id)' "$STATUS" >/dev/null || die "no issue with id $id"

  local blockers
  blockers=$(jq -r --arg id "$id" '
    (.issues | map({key: .id, value: .passes}) | from_entries) as $p
    | .issues[] | select(.id == $id) | [.blockedBy[] | select($p[.] != true)] | join(", ")
  ' "$STATUS")
  if [[ -n "$blockers" ]]; then
    progress "FAIL $id — refused: blocker(s) $blockers not passing yet"
    die "issue $id is blocked by $blockers, which do not pass yet"
  fi

  # The gate must be the committed one: no uncommitted edits to ralph/, and the
  # working AGENTS.md Checks exactly as committed. An uncommitted extra check
  # would run inside this same pass and could change the tree under the others,
  # so changing the gate is its own commit (like changing an issue's check).
  if git rev-parse --verify --quiet HEAD >/dev/null; then
    if ! git diff --quiet HEAD -- ralph/ 2>/dev/null; then
      progress "FAIL $id — refused: uncommitted changes to ralph/"
      die "ralph/ has uncommitted changes — the gate scripts must be the committed ones"
    fi
    local head_agents
    head_agents="$(mktemp)"
    git show HEAD:AGENTS.md >"$head_agents" 2>/dev/null || : >"$head_agents"
    if [[ "$("$HERE/checks.sh" --from "$head_agents" --list 2>/dev/null)" != "$("$HERE/checks.sh" --list 2>/dev/null)" ]]; then
      rm -f "$head_agents"
      progress "FAIL $id — refused: AGENTS.md Checks differ from the committed ones"
      die "the working AGENTS.md Checks differ from HEAD's — commit the Checks change on its own, then pass"
    fi
    rm -f "$head_agents"
  fi

  local checks_json checks_exit
  checks_json="$("$HERE/checks.sh" --json)"
  checks_exit=$?
  local summary_codes
  summary_codes=$(jq -r 'map("\(.command) → \(.exit_code)") | join("; ")' <<<"$checks_json" 2>/dev/null || echo "no checks")
  if (( checks_exit != 0 )); then
    progress "FAIL $id — AGENTS.md Checks: $summary_codes"
    jq -r '.[] | select(.exit_code != 0) | "  exit \(.exit_code): \(.command)"' <<<"$checks_json" >&2 2>/dev/null || true
    die "AGENTS.md Checks are not green — $id stays failing (run ralph/checks.sh for the logs)"
  fi

  local cmd code committed
  cmd=$(jq -r --arg id "$id" '.issues[] | select(.id == $id) | .check' "$STATUS")
  # The check is what the flag means, so it must be the committed one: editing
  # it and passing in the same breath would let a weaker check flip the flag.
  if git rev-parse --verify --quiet HEAD >/dev/null; then
    committed=$(git show "HEAD:$STATUS" 2>/dev/null | jq -r --arg id "$id" '.issues[]? | select(.id == $id) | .check' 2>/dev/null)
    if [[ "$committed" != "$cmd" ]]; then
      progress "FAIL $id — refused: its check differs from the committed one (commit check changes on their own first)"
      die "issue $id's check is uncommitted or changed since HEAD (HEAD: '${committed:-none}', now: '$cmd') — commit the change on its own, then pass"
    fi
  fi
  echo "status: running issue $id check: $cmd"
  bash -c "$cmd"
  code=$?
  if (( code != 0 )); then
    progress "FAIL $id — issue check \`$cmd\` exited $code (AGENTS.md Checks green: $summary_codes)"
    die "issue $id check exited $code — passes stays false"
  fi

  local tmp; tmp="$(mktemp)"
  jq --arg id "$id" --arg at "$(now)" --arg base "$(head_sha)" \
     --argjson checks "$checks_json" --arg cmd "$cmd" '
    .issues |= map(if .id == $id then
      .passes = true
      | .verified = {at: $at, base: $base, check: {command: $cmd, exit_code: 0}, agentsChecks: $checks}
    else . end)
  ' "$STATUS" >"$tmp" && mv "$tmp" "$STATUS"
  progress "PASS $id — issue check \`$cmd\` → 0; AGENTS.md Checks: $summary_codes (base $(head_sha))"
  echo "status: $id passes ($(summary --line))"
}

case "${1:-}" in
  validate) validate ;;
  summary)  summary "${2:-}" ;;
  next)     need_status; n="$(next_runnable)"; [[ -n "$n" ]] && echo "$n" || exit 1 ;;
  pass)     pass "${2:-}" ;;
  progress) shift; [[ $# -gt 0 ]] || die "usage: status.sh progress \"<text>\""; progress "$*" ;;
  *)        sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
