# PLANNING MODE — NO APPLICATION CODE

You are doing gap analysis, not implementation. You may only modify files in `issues/` and `AGENTS.md`. Do not write or edit application code.

# STUDY

1. `issues/prd.md`, `docs/research.md`, and any `specs/` files
2. All issues — open and in `issues/done/`
3. The actual codebase — use parallel subagents. Do NOT assume something is unimplemented; verify by searching.

# GAP ANALYSIS

Compare what the PRD requires against what the code actually does:

1. **Missing work** → create new issue files `issues/NNN-title.md` following the existing issue format (vertical slices, AFK/HITL type, Blocked by field, acceptance criteria)
2. **Stale issues** → an issue describing work that is already done gets moved to `issues/done/` with a note
3. **Wrong issues** → an issue contradicted by the current code or PRD gets rewritten
4. **Priorities** → if the ordering across issues no longer makes sense, renumber or annotate

Prefer fewer, sharper issues. If an issue's title needs "and", split it.

# OUTPUT

Commit only the issue-file changes, with a message starting `plan:`. Then print a summary: issues created / moved / rewritten, and the single most important open task.

Output <promise>PLAN COMPLETE</promise> when done.
