#!/bin/bash
set -eo pipefail

# Fully sandboxed Ralph loop (Docker). Same as loop.sh but each iteration runs
# in the Claude Code Docker sandbox instead of your local environment.
#   ./ralph/afk.sh 10          # build mode, up to 10 iterations
#   ./ralph/afk.sh 1 plan      # one planning pass

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> [plan|build]"
  exit 1
fi

ITERATIONS="$1"
MODE="${2:-build}"
PROMPT_FILE="ralph/PROMPT_${MODE}.md"
[[ -f "$PROMPT_FILE" ]] || { echo "Missing $PROMPT_FILE — run from the project root."; exit 1; }

# jq filter to extract streaming text from assistant messages
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'

# jq filter to extract final result
final_result='select(.type == "result").result // empty'

for ((i=1; i<=ITERATIONS; i++)); do
  echo "=== ralph $MODE (sandboxed) — iteration $i/$ITERATIONS ==="
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  docker sandbox run claude . -- \
    --verbose \
    --print \
    --output-format stream-json \
    "$(cat "$PROMPT_FILE")" \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text"

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* || "$result" == *"<promise>PLAN COMPLETE</promise>"* ]]; then
    echo "Ralph ($MODE) complete after $i iteration(s)."
    exit 0
  fi
done
