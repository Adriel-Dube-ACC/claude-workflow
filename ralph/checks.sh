#!/bin/bash
set -uo pipefail

# Run every command listed under "## Checks" in AGENTS.md, from the project root.
#   ./ralph/checks.sh           # human output; a failing check prints its log tail
#   ./ralph/checks.sh --json    # machine output: [{"command","exit_code","seconds"}]
#   ./ralph/checks.sh --list    # print the parsed commands, run nothing
#   ./ralph/checks.sh --from <file> [--json|--list]
#                               # read the Checks from another AGENTS.md (e.g. the
#                               # base branch's copy) instead of ./AGENTS.md
#
# Exit 0 only if at least one check exists and every check exits 0. An empty
# Checks section is a failure: a gate that runs nothing passes everything.
#
# A check is a "- `cmd`" line under "## Checks" that is not inside an HTML
# comment (the templates ship commented-out candidates). Only the first
# backtick span on the line is run, so "- `npm test` (slow, ~40s)" works.

MODE="human"
SRC=""
while (( $# )); do
  case "$1" in
    --json) MODE="json" ;;
    --list) MODE="list" ;;
    --from) SRC="${2:-}"; [[ -n "$SRC" ]] || { echo "checks: --from needs a file" >&2; exit 2; }; shift ;;
    *)      echo "Usage: $0 [--from <AGENTS.md>] [--json|--list]" >&2; exit 2 ;;
  esac
  shift
done
[[ -z "$SRC" || "$SRC" == /* ]] || SRC="$PWD/$SRC"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2
SRC="${SRC:-AGENTS.md}"
[[ -f "$SRC" ]] || { echo "checks: no AGENTS.md at $SRC" >&2; exit 2; }

CMDS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && CMDS+=("$line")
done < <(awk '
  /^## Checks/ { inchecks = 1; next }
  /^## /       { inchecks = 0 }
  /<!--/       { incomment = 1 }
  /-->/        { incomment = 0; next }
  inchecks && !incomment && /^- `/ {
    s = $0; sub(/^- `/, "", s); sub(/`.*$/, "", s); print s
  }
' "$SRC")

if (( ${#CMDS[@]} == 0 )); then
  echo "checks: AGENTS.md has no runnable Checks — there is no gate. Add one real, verified command." >&2
  [[ "$MODE" == "json" ]] && echo "[]"
  exit 1
fi

if [[ "$MODE" == "list" ]]; then
  printf '%s\n' "${CMDS[@]}"
  exit 0
fi

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/ralph-checks.XXXXXX")"
FAILED=0
JSON="[]"
i=0
for cmd in "${CMDS[@]}"; do
  i=$((i + 1))
  log="$LOGDIR/check-$i.log"
  start=$(date +%s)
  bash -c "$cmd" >"$log" 2>&1
  code=$?
  secs=$(( $(date +%s) - start ))
  (( code == 0 )) || FAILED=1
  JSON=$(jq -c --arg c "$cmd" --argjson e "$code" --argjson s "$secs" \
    '. + [{command: $c, exit_code: $e, seconds: $s}]' <<<"$JSON")
  if [[ "$MODE" == "human" ]]; then
    if (( code == 0 )); then
      printf 'PASS  (exit 0, %ss)  %s\n' "$secs" "$cmd"
    else
      printf 'FAIL  (exit %s, %ss)  %s\n' "$code" "$secs" "$cmd"
      echo "----- last 40 lines of $log"
      tail -n 40 "$log"
      echo "-----"
    fi
  fi
done

if [[ "$MODE" == "json" ]]; then
  jq . <<<"$JSON"
else
  passed=$(jq '[.[] | select(.exit_code == 0)] | length' <<<"$JSON")
  echo "checks: $passed/${#CMDS[@]} passed (full logs: $LOGDIR)"
fi
exit $FAILED
