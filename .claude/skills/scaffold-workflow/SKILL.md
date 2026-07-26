---
name: scaffold-workflow
description: Add the Ralph workflow harness (ralph/, AGENTS.md with real detected checks, issues/, docs/) to the current project, new or existing. Use when a project is missing the harness, when the user wants to set up Ralph here, or when AGENTS.md has no Checks filled in.
---

# Scaffold Workflow

Install the workflow harness into the current project and — the part that matters — fill `AGENTS.md` with checks that have been **verified to actually run**.

## Process

### 1. Check what already exists

Look for `ralph/`, `AGENTS.md`, `issues/`, `docs/`, `CLAUDE.md`. Never overwrite an existing file without asking. Report what's present and what's missing before doing anything.

### 2. Copy the harness

If `~/bin/ralphify` exists, run it instead of copying by hand — it does this step
plus stack detection, and never overwrites anything. Then continue from step 3.

Otherwise, the template lives at `~/Claude/claude-workflow-export/`. Copy only what's missing:

- `ralph/PROMPT_build.md`, `ralph/PROMPT_plan.md`, `ralph/loop.sh`, `ralph/once.sh`, `ralph/afk.sh` (chmod +x the scripts)
- `AGENTS.md` (template)
- `issues/done/`, `docs/`

If `ralph/prompt.md` (the old single-prompt version) exists, tell the user it's superseded by the plan/build split and offer to delete it.

The skills are global in `~/.claude/skills/` and already work here — only vendor them into `.claude/skills/` if the user wants the project self-contained for sharing.

### 3. Detect the real checks — then RUN them

This is the step that determines whether Ralph works at all. A check that silently passes lets broken code through every iteration.

Inspect the project to find its actual commands:

- Python: `pytest`, `ruff check`, `mypy` — note whether a venv must be activated first
- Node/TS: read `package.json` scripts — `test`, `typecheck`, `build`, `lint`
- Monorepos: **the command's working directory matters.** Check whether a root `package.json` exists before writing any root-level npm command.

Then actually execute each candidate command and confirm it exits 0. Do not write a command into `AGENTS.md` that you have not run.

If a project has no tests at all, say so plainly — Ralph should not run autonomously without a gate. Recommend getting one trivial test passing first.

### 4. Write AGENTS.md

Keep it under ~60 lines; it loads on every Ralph iteration.

```markdown
## Checks (must all exit 0 before any commit)
- `<verified command>`

## Build & run
- <how to start the app, required env vars, migrations>

## Quirks
- <non-obvious gotchas: monorepo layout, env setup, things that bite>
```

### 5. Report

State: files created, the checks you verified (with their exit status), and anything that blocks an autonomous run. Then give the next command — `/write-a-prd` if there's no PRD, `./ralph/loop.sh plan` if there is one but the issue list is stale, or `./ralph/loop.sh build 3` if issues are ready.
