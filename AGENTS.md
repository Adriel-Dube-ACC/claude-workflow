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

## Build & run

<!-- How to build / start the app -->

## Quirks

<!-- Environment gotchas, non-obvious behaviors -->
