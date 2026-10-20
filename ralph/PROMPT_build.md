# STUDY THE CONTEXT

Study (don't skim) before doing anything:

1. `AGENTS.md` — operational guide: commands, checks, quirks
2. `issues/prd.md` and `docs/research.md`, if present
3. All open issues: `issues/*.md` (ignore `issues/done/`)
4. Issue status: `./ralph/status.sh summary` (reads `issues/status.json` — which issues pass, which are blocked, the next runnable one)
5. The handoff from earlier passes: the last ~30 lines of `issues/progress.md`
6. Recent work: `git log -n 10 --oneline`, plus the most recent full commit message

# PROVE THE TREE IS GREEN

Run `./ralph/checks.sh` before changing anything. It runs every command in the "Checks" section of `AGENTS.md`. If any check fails on the untouched tree, fixing that IS this pass's task (priority 1 below) — do not build on a red tree.

# TASK SELECTION

Work on AFK issues only — never HITL. An issue is only workable if everything in its "Blocked by" list is already in `issues/done/` and marked `passes: true` in `issues/status.json`. On a new project that means nothing is workable until the walking skeleton (issue 001) passes.

No `issues/status.json` (a project set up before it existed)? Fall back to `issues/done/` alone, skip the `status.sh pass` step below, and say in your commit message that a `./ralph/loop.sh plan` pass should create it.

Pick exactly ONE task — the most important one, prioritized:

1. Critical bugfixes
2. Development infrastructure (tests, types, dev scripts — precursors to features)
3. Tracer bullets: thin end-to-end slices of new features through all layers
4. Polish and quick wins
5. Refactors

If all AFK tasks are complete, output <promise>NO MORE TASKS</promise> and stop.

# TRACER BULLETS

The walking skeleton (deployed app, health route through the database, smoke test in Checks) is the first slice; every later issue is one more thin end-to-end slice through it — UI, API, data and test together, demoable on its own. Never build a whole horizontal layer (all the tables, all the endpoints) ahead of the features that use it. If the issue you picked can't be finished end to end in one pass, finish a thinner slice of it, note the rest in the issue file, and leave `passes` false.

# EXPLORATION

Before making any changes, search the codebase using parallel subagents. Do NOT assume something is not implemented — a failed grep is not proof of absence. Verify what exists first.

# CONTEXT

Your context window is a budget; files and git are the memory, not the conversation. You cannot run /compact or /clear yourself — the loop gives every pass a fresh window, and a long pass may be compacted automatically, which loses anything that exists only in the conversation.

- Research-heavy steps (repo sweeps, reading docs or long logs, comparing many files) go to a subagent told to return a summary of at most ~20 lines. Only the summary enters your window.
- Commit at every green `./ralph/checks.sh` run — a small `wip(<id>): …` commit is fine. Git is the real save point: checkpoints and /rewind do not see Bash edits or subagent worktrees.
- If the pass is running long (several failed attempts, big logs), write the state down before going on: `./ralph/status.sh progress "<id>: WIP — tried …; failing: …; next: …"`. If `ralph/context-hooks.sh` is installed, that line, the failing check and the current issue are re-injected after a compaction.

# IMPLEMENTATION

Use /tdd: one test → one implementation, testing behavior through public interfaces.

- FULL implementations only. DO NOT write placeholders, stubs, or TODO-later code.
- Use parallel subagents for searches and reads.
- Use exactly ONE subagent for builds and tests — never parallelize validation.
- When you write a test, add a comment capturing WHY it matters. Future iterations have no memory of your reasoning and will otherwise mangle or delete it.

# FEEDBACK LOOPS

Run `./ralph/checks.sh`. Every check must exit 0 before you commit.

If `AGENTS.md` is missing or its Checks section is empty, discover the project's test and typecheck commands, run them, and record them in `AGENTS.md`.

If you changed the Checks section of `AGENTS.md` (e.g. the walking skeleton adds its smoke test), commit that change first, on its own — `pass` only accepts the committed gate. Then run `./ralph/status.sh pass <issue id>`. It re-runs the Checks plus the issue's own `check` command from `issues/status.json`, and flips `passes` to true only if every one exits 0. NEVER edit `passes` or `verified` by hand — `./ralph/status.sh validate` rejects a hand-flipped flag. If `pass` fails, the issue is not done.

# PROGRESS

Append one line for the next pass: `./ralph/status.sh progress "<id>: what you did; what is left or blocking; what the next pass should pick up"`. The log is the handoff between fresh contexts — write what you would want to read with no memory of this session.

# COMMIT

You have been committing at every green checks run. Finish with a git commit that includes `issues/status.json` and `issues/progress.md` with the code (the loop may have appended a line to progress.md before you started — commit it too). The message must include:

1. Key decisions made
2. Files changed
3. Blockers or notes for the next iteration

# THE ISSUE

- Task complete (`./ralph/status.sh pass <id>` succeeded) → move the issue file to `issues/done/`.
- Task incomplete → append a note to the issue file: what was done, what remains, what's blocking.

# SELF-IMPROVEMENT

If you discovered an operational fact not in `AGENTS.md` (a command, a quirk, a gotcha), add it. Keep AGENTS.md operational and under ~60 lines — it is not a changelog.

# FINAL RULES

ONLY WORK ON A SINGLE TASK. When it is committed and its issue file updated, stop.
