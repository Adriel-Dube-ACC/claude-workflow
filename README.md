# Claude AI Engineer Workflow

A portable workflow for building software with Claude Code — from a client brief all the way to autonomous implementation.

## Overview

```
Client Brief
    │
    ▼
/research  →  docs/research.md          (brownfield only — map the existing code first)
    │
    ▼
/write-a-prd  →  issues/prd.md          (interviews you, explores the repo)
    │
    ▼
/prd-to-issues  →  issues/NNN-*.md      (vertical slices, AFK/HITL, dependency graph)
    │
    ▼
/analyze-issues                          (consistency check: PRD ↔ issues)
    │
    ├──▶ /fan-out-issues                 (parallel worktree agents, wave of ≤4)
    │
    └──▶ Ralph loop                      (serial autonomous agent, fresh context per task)
```

For **small features that fit in a day**, skip the PRD chain entirely:

```
/write-a-spec  →  SPEC.md  →  /clear  →  implement with /goal set
```

For **one-sentence fixes**, skip everything: plan mode → implement → commit.

---

## Install

This repository *is* the template. Clone it, install the skills globally, and put the two
scripts on your `PATH`:

```sh
git clone https://github.com/Adriel-Dube-ACC/claude-workflow.git ~/Claude/claude-workflow-export

# skills apply to every project on the machine
mkdir -p ~/.claude/skills
cp -R ~/Claude/claude-workflow-export/.claude/skills/. ~/.claude/skills/

# newproj / ralphify
mkdir -p ~/bin && cp ~/Claude/claude-workflow-export/bin/* ~/bin/ && chmod +x ~/bin/*
export PATH="$HOME/bin:$PATH"        # add to ~/.zshrc
```

Both scripts read the template from `$CLAUDE_WORKFLOW_TEMPLATE`, defaulting to
`~/Claude/claude-workflow-export`. Clone somewhere else and set that variable instead.

## Setup a project

```sh
newproj my-thing        # create ~/Claude/my-thing, scaffolded and git-init'd
newproj --adopt         # add the harness to the project in the current directory
ralphify --dry-run      # existing project: show what would change, write nothing
```

Or from inside Claude Code, in any project: **`/scaffold-workflow`** — same thing, but it also detects and *verifies* the project's real test commands before writing them into `AGENTS.md`.

Manual equivalent:

```sh
cp -r ralph issues docs AGENTS.md /your/new/project/
```

> **Skills are global by default.** Installed to `~/.claude/skills/` they apply to every
> project without copying anything, and a second copy inside a project would show up as a
> duplicate skill competing for selection. Vendor them into a project only to make it
> self-contained for someone else: `ralphify --vendor-skills`, or
> `NEWPROJ_VENDOR_SKILLS=1 newproj <name>`.

Either way, the **Checks** section of `AGENTS.md` must contain the project's real test/typecheck commands. Ralph's quality is gated entirely by these checks — a check that silently passes lets bad code through all night. Run them once by hand before trusting an autonomous loop.

---

## The Workflow Step by Step

### 0. Research (brownfield projects)

```
/research
```

Produces `docs/research.md` — a ≤200-line map of the relevant files, functions, data flows, and constraints, with `file:line` citations. Every later step (PRD, spec, Ralph, worktree agents) reads this instead of re-crawling the repo.

### 1. Write a PRD

```
/write-a-prd
```

Claude interviews you, explores the codebase, and writes `issues/prd.md`.

### 2. Break it into issues

```
/prd-to-issues
```

Vertical slices, tagged **AFK** (autonomous) or **HITL** (needs you), with `Blocked by` dependencies. On a new project issue **001 is a walking skeleton** — deployed hello-world, `/api/health` running a real database query, a Playwright smoke test in the AGENTS.md Checks — and every other issue is blocked by it. Each issue gets one **Check** command, and all of them land in `issues/status.json` with `passes: false`.

### 3. Check consistency

```
/analyze-issues
```

Verifies every user story is covered, nothing contradicts the PRD, and the dependency graph has no cycles or over-serialization. One prompt, catches real gaps.

### 4. Implement — pick one of three modes

**a) Parallel (fastest when ≥2 issues are unblocked):**

```
/fan-out-issues
```

Launches one worktree-isolated agent per unblocked AFK issue (waves of ≤4). Each runs TDD, passes the AGENTS.md checks, commits on its own branch, and returns a fixed result contract (`issues/<id>.result.json`: issue, status, branch, commit, files touched, checks with exit codes, open questions). `ralph/result.sh verify` checks every claim against git and re-runs the checks before anything is reported. You review and merge.

**b) Ralph loop (serial, autonomous, fresh context per task):**

```sh
./ralph/loop.sh plan        # gap analysis: repair/regenerate the issue list
./ralph/loop.sh build 10    # implement up to 10 tasks, one per iteration
```

**c) Supervised single task:**

```sh
./ralph/once.sh             # interactive, you approve as it goes
```

### 5. Review HITL issues

HITL issues need your attention: make the decision, do the external setup, then move them to `issues/done/`.

---

## Ralph Reference

Ralph is a bash loop that feeds a fresh Claude a prompt each iteration. Progress lives in **files and git history**, not the context window — every iteration starts with clean context.

### Two prompts, one loop

- **`ralph/PROMPT_plan.md`** — gap analysis between the PRD and the code. Creates missing issues, retires stale ones, fixes priorities. Only touches `issues/` and `AGENTS.md`. Run when the plan feels stale or Ralph starts circling — regenerating the plan is cheap; following a wrong one isn't.
- **`ralph/PROMPT_build.md`** — picks ONE task, implements with /tdd, runs the AGENTS.md checks, commits, moves the issue to done. Guardrails baked in: search-first (never assume unimplemented), no placeholder code, parallel subagents for reads / exactly one for validation, capture-the-why test comments.

### Scripts

| Script | What | Where |
|---|---|---|
| `loop.sh [plan\|build] [n]` | headless loop, `--permission-mode auto`; `RALPH_INBOUND=accept` opens its inbox to your other sessions | local |
| `once.sh [plan\|build]` | single interactive iteration | local, supervised |
| `afk.sh <n> [plan\|build]` | headless loop | Docker sandbox |
| `checks.sh [--json\|--list]` | runs every AGENTS.md Check; an empty Checks section fails | any |
| `status.sh validate\|summary\|next\|pass <id>\|progress "<text>"` | `issues/status.json` + `issues/progress.md` | any |
| `result.sh validate\|verify <file> <base>` | the fan-out return contract | orchestrator |
| `context-hooks.sh install\|uninstall\|snapshot\|show` | opt-in PreCompact / SessionStart(compact) hooks that carry a state note across compaction | interactive sessions |

All three loop scripts stop early on `<promise>NO MORE TASKS</promise>` (build) or `<promise>PLAN COMPLETE</promise>` (plan).

### State files

- **`issues/status.json`** — one entry per issue: id, file, title, type, behaviour, check command, blockedBy, `passes`. Everything starts failing. Only `./ralph/status.sh pass <id>` flips `passes`, after the AGENTS.md Checks *and* the issue's own check exit 0 with every blocker already passing; it stores the evidence in `verified`, and `validate` rejects a `true` without it.
- **`issues/progress.md`** — append-only log. The loop scripts log each iteration's start (HEAD + passing count), `status.sh pass` logs PASS/FAIL with exit codes, and the build prompt has the agent log what it did and what's next. It's the handoff between fresh contexts.
- **`issues/<id>.result.json`** — one per fan-out agent, verified by `result.sh verify`.
- **`.git/ralph/last-checks.json`, `.git/ralph/context.md`** — per worktree, never committed: the last `checks.sh` run (what is failing), and the state note `context-hooks.sh` writes before a compaction.

Tests for all of this: `tests/harness.test.sh`.

### Context and handoff

Long sessions lose what exists only in the conversation, so the harness keeps state in files and git and makes compaction deliberate. The AGENTS.md "Context & handoff" section says it in five lines: commit at every green `./ralph/checks.sh` run (git is the real checkpoint — `/rewind` misses Bash edits and subagent worktrees), `/compact <focus line>` at a clean boundary before the window fills, research goes to subagents that return summaries, and switching tasks means a `progress` line, a commit, `/clear`, and a fresh start from `issues/progress.md`. Ralph's own passes already start fresh; `PROMPT_build.md` has the agent commit at each green run and log a WIP line when a pass runs long.

Optional hooks, per project and opt-in:

```sh
./ralph/context-hooks.sh install          # .claude/settings.local.json (kept out of git)
./ralph/context-hooks.sh install --shared # .claude/settings.json, for the whole team
./ralph/context-hooks.sh uninstall
```

`PreCompact` writes a short note — branch and HEAD, current issue (from the branch name, the last progress line, or the next runnable issue), the failing checks from the last `checks.sh` run, the last progress line as the next step, and the `/compact` focus line — and `SessionStart` with source `compact` re-injects it. Nothing touches `~/.claude/settings.json`.

### Messages between sessions

When worktree agents run in parallel, the one that changes something the others build on (a schema rename, a shared util) says so: `SendMessage` with what changed, what to do, and a commit or file path — two lines, never a diff. In `/fan-out-issues` children message the orchestrator, which relays to the running siblings; separate `claude -p` / `claude --bg` workers message each other directly after `ListAgents`. Unattended workers need their inbox open — `claude -p --settings '{"crossSessionInbound":"accept"}' …`, or `RALPH_INBOUND=accept ./ralph/loop.sh build N` — because a bypass-permissions receiver holds messages and a held message in `-p` expires after about five minutes. Use `notify_when_idle` instead of polling a long run, and `"permissions": {"deny": ["SendMessage", "ListAgents"]}` in repos where agents should not talk.

### AGENTS.md

The per-project operational guide, loaded every iteration. Checks (test/typecheck commands that must exit 0 before commit), build/run commands, quirks. Keep it under ~60 lines and operational — it's not a changelog. Ralph adds to it when it discovers things the hard way.

---

## Skills Reference

Invoked with `/skill-name`. Defined in `.claude/skills/` (and globally in `~/.claude/skills/`).

| Skill | Use when | Output |
|---|---|---|
| `/scaffold-workflow` | Project is missing the harness, or AGENTS.md has no verified Checks | `ralph/`, `AGENTS.md`, `issues/`, `docs/` |
| `/ralphify` | Add the harness from inside Claude — wraps `newproj` / `ralphify` | same as above |
| `/research` | Before planning on an existing codebase | `docs/research.md` |
| `/grill-me` | Stress-testing a plan or design decision | shared understanding |
| `/write-a-spec` | Feature finishable in ~a day | `SPEC.md` (then `/clear` + `/goal`) |
| `/write-a-prd` | Multi-day, multi-slice work | `issues/prd.md` |
| `/prd-to-issues` | After a PRD | `issues/NNN-*.md` |
| `/analyze-issues` | After prd-to-issues, before building | consistency report, incl. `status.sh validate` |
| `/fan-out-issues` | ≥2 unblocked AFK issues | parallel branches |
| `/tdd` | Any implementation (Ralph uses it automatically) | red → green → refactor |
| `/improve-codebase-architecture` | Weekly, or after a surge of development | refactor RFC in `issues/` |
| `/better-sqlite3-rebuild` | Auto-invoked on native module errors | — |

---

## Issues Directory

```
issues/
├── prd.md               ← the product requirements doc
├── 001-auth-setup.md    ← AFK issue, open
├── 002-user-profile.md  ← HITL issue, open
├── status.json          ← machine-readable status; passes flipped only by ralph/status.sh pass
├── progress.md          ← append-only log, one or more lines per Ralph pass
└── done/
    └── 000-db-schema.md ← completed
docs/
└── research.md          ← the codebase map (brownfield)
```

---

## The one rule under everything

**End every prompt with a check the agent can run.** Tests, a build, a lint, a screenshot diff. Without a runnable check, "looks done" is the only signal, and you become the verification loop. Escalate as runs get longer: in-prompt check → `/goal` (separate evaluator per turn) → Stop hook (deterministic gate) → fresh-context subagent review.
