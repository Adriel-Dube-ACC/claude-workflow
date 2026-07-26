#!/bin/bash
# One supervised, interactive Ralph iteration in your local terminal.
#   ./ralph/once.sh          # build mode
#   ./ralph/once.sh plan     # planning mode

MODE="${1:-build}"
PROMPT_FILE="ralph/PROMPT_${MODE}.md"
[[ -f "$PROMPT_FILE" ]] || { echo "Missing $PROMPT_FILE — run from the project root."; exit 1; }

claude --permission-mode acceptEdits "$(cat "$PROMPT_FILE")"
