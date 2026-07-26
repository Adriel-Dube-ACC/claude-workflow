---
name: fan-out-issues
description: Run unblocked AFK issues in parallel, one isolated git-worktree agent per issue. Use when several independent issues are ready and the user wants them implemented simultaneously.
---

# Fan Out Issues

Parallel implementation of independent issues, each in its own git worktree so edits never collide.

## Process

1. **Build the graph.** Read all open issues in `issues/`. An issue is runnable if it is type AFK and every `Blocked by` reference is in `issues/done/`.

2. **Propose the wave.** Show the runnable issues and pick a wave of at most 4 — several small waves beat one giant wave, because review is the bottleneck, not the agents. Confirm the selection with the user before launching.

3. **Launch.** Spawn one agent per issue (Agent tool with `isolation: "worktree"`), all in a single message so they run concurrently. Each agent's prompt:

   > Implement the following issue (full text pasted below). Read `AGENTS.md` for build/test commands, and `docs/research.md` for existing patterns if present. Use TDD: one test → one implementation, testing behavior through public interfaces. Full implementations only — no stubs or placeholders. Run every check in AGENTS.md; all must exit 0. Commit on your branch with a descriptive message. Do NOT touch files outside the scope named in the issue. Report back: what you built, the check output, files changed, and anything blocking.

4. **Collect.** As agents finish, report per issue: branch name, pass/fail evidence, files touched. Move completed issues to `issues/done/`. List the branches for the user to review and merge — do not merge yourself.

5. **Next wave.** After the user merges, re-read the graph: newly unblocked issues form the next wave.
