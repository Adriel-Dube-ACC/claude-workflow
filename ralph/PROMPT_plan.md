# PLANNING MODE — NO APPLICATION CODE

You are doing gap analysis, not implementation. You may only modify files in `issues/` (including `issues/status.json` and `issues/progress.md`) and `AGENTS.md`. Do not write or edit application code.

# STUDY

1. `issues/prd.md`, `docs/research.md`, and any `specs/` files
2. All issues — open and in `issues/done/` — plus `./ralph/status.sh summary` and the last ~30 lines of `issues/progress.md`
3. The actual codebase — use parallel subagents. Do NOT assume something is unimplemented; verify by searching.

# GAP ANALYSIS

Compare what the PRD requires against what the code actually does:

1. **Missing work** → create new issue files `issues/NNN-title.md` following the existing issue format (vertical slices, AFK/HITL type, Blocked by field, acceptance criteria)
2. **Stale issues** → an issue describing work that is already done gets moved to `issues/done/` with a note
3. **Wrong issues** → an issue contradicted by the current code or PRD gets rewritten
4. **Priorities** → if the ordering across issues no longer makes sense, renumber or annotate
5. **No walking skeleton** → if nothing yet proves the app runs end to end (deployed, a health route that touches the database, a smoke test in AGENTS.md Checks), create that issue first and make every other open issue blocked by it
6. **Status file** → every issue file has exactly one entry in `issues/status.json` (id, file, title, type, behaviour, check, blockedBy, passes). New issues start `passes: false`. A rewritten issue whose behaviour changed goes back to `passes: false` with its `verified` object removed. Never set `passes: true` by hand — if an issue looks already done, run `./ralph/status.sh pass <id>`; only a green run flips it.

Prefer fewer, sharper issues. If an issue's title needs "and", split it.

# OUTPUT

Run `./ralph/status.sh validate` — it must print `valid`. Append one line with `./ralph/status.sh progress "plan: ..."`. Commit only the issue-file changes, with a message starting `plan:`. Then print a summary: issues created / moved / rewritten, and the single most important open task.

Output <promise>PLAN COMPLETE</promise> when done.
