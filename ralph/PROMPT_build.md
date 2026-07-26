# STUDY THE CONTEXT

Study (don't skim) before doing anything:

1. `AGENTS.md` — operational guide: commands, checks, quirks
2. `issues/prd.md` and `docs/research.md`, if present
3. All open issues: `issues/*.md` (ignore `issues/done/`)
4. Recent work: `git log -n 10 --oneline`, plus the most recent full commit message

# TASK SELECTION

Work on AFK issues only — never HITL. An issue is only workable if everything in its "Blocked by" list is already in `issues/done/`.

Pick exactly ONE task — the most important one, prioritized:

1. Critical bugfixes
2. Development infrastructure (tests, types, dev scripts — precursors to features)
3. Tracer bullets: thin end-to-end slices of new features through all layers
4. Polish and quick wins
5. Refactors

If all AFK tasks are complete, output <promise>NO MORE TASKS</promise> and stop.

# EXPLORATION

Before making any changes, search the codebase using parallel subagents. Do NOT assume something is not implemented — a failed grep is not proof of absence. Verify what exists first.

# IMPLEMENTATION

Use /tdd: one test → one implementation, testing behavior through public interfaces.

- FULL implementations only. DO NOT write placeholders, stubs, or TODO-later code.
- Use parallel subagents for searches and reads.
- Use exactly ONE subagent for builds and tests — never parallelize validation.
- When you write a test, add a comment capturing WHY it matters. Future iterations have no memory of your reasoning and will otherwise mangle or delete it.

# FEEDBACK LOOPS

Run every command in the "Checks" section of `AGENTS.md`. All must exit 0 before you commit.

If `AGENTS.md` is missing or its Checks section is empty, discover the project's test and typecheck commands, run them, and record them in `AGENTS.md`.

# COMMIT

Make a git commit. The message must include:

1. Key decisions made
2. Files changed
3. Blockers or notes for the next iteration

# THE ISSUE

- Task complete → move the issue file to `issues/done/`.
- Task incomplete → append a note to the issue file: what was done, what remains, what's blocking.

# SELF-IMPROVEMENT

If you discovered an operational fact not in `AGENTS.md` (a command, a quirk, a gotcha), add it. Keep AGENTS.md operational and under ~60 lines — it is not a changelog.

# FINAL RULES

ONLY WORK ON A SINGLE TASK. When it is committed and its issue file updated, stop.
