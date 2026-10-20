#!/bin/bash
set -eo pipefail

# Ralph loop — fresh context per iteration, file-based state between them.
#   ./ralph/loop.sh plan        # one gap-analysis pass: regenerate/repair issues
#   ./ralph/loop.sh build 10    # implement up to 10 tasks, one per iteration
#   RALPH_INBOUND=accept ./ralph/loop.sh build 10   # also accept messages from your other sessions

MODE="${1:-build}"
ITERATIONS="${2:-1}"

if [[ "$MODE" != "plan" && "$MODE" != "build" ]]; then
  echo "Usage: $0 [plan|build] [iterations]"
  exit 1
fi

PROMPT_FILE="ralph/PROMPT_${MODE}.md"
[[ -f "$PROMPT_FILE" ]] || { echo "Missing $PROMPT_FILE — run from the project root."; exit 1; }

# Cross-session messages from your other sessions (SendMessage). Unset keeps
# Claude Code's default. RALPH_INBOUND=accept lets a sibling's "users.name is now
# users.display_name — rebase" reach this unattended worker; a held message in a
# -p session expires after ~5 minutes. hold / refuse tighten it instead.
INBOUND_ARGS=()
case "${RALPH_INBOUND:-}" in
  "") ;;
  accept|hold|refuse) INBOUND_ARGS=(--settings "{\"crossSessionInbound\":\"$RALPH_INBOUND\"}") ;;
  *) echo "RALPH_INBOUND must be accept, hold or refuse (got: $RALPH_INBOUND)"; exit 1 ;;
esac

# jq filter to extract streaming text from assistant messages
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
# jq filter to extract final result
final_result='select(.type == "result").result // empty'

# Append to issues/progress.md (no-op if the status helper is missing).
log_progress() { [[ -x ralph/status.sh ]] && ./ralph/status.sh progress "$*" || true; }
state() { echo "HEAD $(git rev-parse --short HEAD 2>/dev/null || echo none), $(./ralph/status.sh summary --line 2>/dev/null || echo 'no status.json')"; }

for ((i=1; i<=ITERATIONS; i++)); do
  log_progress "loop: $MODE iteration $i/$ITERATIONS started — $(state)"
  echo "=== ralph $MODE — iteration $i/$ITERATIONS — branch: $(git branch --show-current 2>/dev/null || echo '?') ==="
  tmpfile=$(mktemp)

  # auto mode: a classifier approves routine commands so tests can run headless.
  # For full isolation instead, use afk.sh (docker sandbox).
  claude --permission-mode auto "${INBOUND_ARGS[@]}" \
    --verbose --print --output-format stream-json \
    "$(cat "$PROMPT_FILE")" \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text"

  result=$(jq -r "$final_result" "$tmpfile")
  rm -f "$tmpfile"

  if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* || "$result" == *"<promise>PLAN COMPLETE</promise>"* ]]; then
    echo "Ralph ($MODE) complete after $i iteration(s)."
    log_progress "loop: $MODE complete after $i iteration(s) — $(state)"
    exit 0
  fi
done

log_progress "loop: $MODE stopped at the iteration cap ($ITERATIONS) — $(state)"
