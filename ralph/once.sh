#!/bin/bash
# One supervised, interactive Ralph iteration in your local terminal.
#   ./ralph/once.sh          # build mode
#   ./ralph/once.sh plan     # planning mode

MODE="${1:-build}"
PROMPT_FILE="ralph/PROMPT_${MODE}.md"
[[ -f "$PROMPT_FILE" ]] || { echo "Missing $PROMPT_FILE — run from the project root."; exit 1; }

# Append to issues/progress.md (no-op if the status helper is missing).
log_progress() { [[ -x ralph/status.sh ]] && ./ralph/status.sh progress "$*" || true; }
state() { echo "HEAD $(git rev-parse --short HEAD 2>/dev/null || echo none), $(./ralph/status.sh summary --line 2>/dev/null || echo 'no status.json')"; }

log_progress "once: $MODE pass started — $(state)"
claude --permission-mode acceptEdits "$(cat "$PROMPT_FILE")"
