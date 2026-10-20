# AGENTS.md — operational guide

Keep this file under ~60 lines. Operational facts only — commands, quirks, gotchas discovered the hard way. It is loaded on every Ralph iteration, so every line costs context on every run. It is NOT a changelog.

## Checks (must all exit 0 before any commit)

Run them all with `./ralph/checks.sh`. On a new project the walking skeleton
(issue 001) adds the Playwright smoke test here.

<!-- Replace with this project's real commands, e.g.:
- `npm test`
- `npm run typecheck`
- `pytest`
- `ruff check .`
- `npx playwright test e2e/smoke.spec.ts`
-->

## Context & handoff

- Commit at every green `./ralph/checks.sh` run. Git is the real checkpoint: /rewind misses Bash edits and subagent worktrees.
- Before the window fills (`/context` shows it), `/compact` at a clean boundary with a focus line, e.g. `/compact keep issue 003, the failing auth test, the session-table plan` — don't wait for auto-compact.
- Research-heavy steps (repo sweeps, docs, long logs) go to a subagent that returns a short summary.
- Switching tasks: `./ralph/status.sh progress "<id>: done; left; next"`, commit, `/clear`, then start from `issues/progress.md`.
- Optional: `./ralph/context-hooks.sh install` saves a state note (issue, failing check, next step) before each compaction and re-injects it after.

## Build & run

<!-- How to build / start the app -->

## Quirks

<!-- Environment gotchas, non-obvious behaviors -->
