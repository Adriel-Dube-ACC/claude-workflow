---
name: fan-out-issues
description: Run unblocked AFK issues in parallel, one isolated git-worktree agent per issue. Every agent returns a fixed result contract (issues/<id>.result.json — issue id, branch, files touched, checks run with exit codes, open questions) that is verified against git and a re-run of the checks before anything is reported. Use when several independent issues are ready and the user wants them implemented simultaneously.
---

# Fan Out Issues

Parallel implementation of independent issues, each in its own git worktree so edits never collide. Each agent hands back a machine-checkable result, not prose, so a failing check can never be relayed as a pass.

## Process

1. **Build the graph.** Read all open issues in `issues/` and `./ralph/status.sh summary`. An issue is runnable if it is type AFK, every `Blocked by` reference is in `issues/done/`, and each blocker has `passes: true` in `issues/status.json`. On a new project nothing is runnable until the walking skeleton (001) passes.

2. **Propose the wave.** Show the runnable issues and pick a wave of at most 4 — several small waves beat one giant wave, because review is the bottleneck, not the agents. Confirm the selection with the user before launching.

3. **Launch.** Spawn one agent per issue (Agent tool with `isolation: "worktree"`), all in a single message so they run concurrently.

   Before writing the prompts, allocate anything numbered or shared and name the allocation in each prompt: **migration/version numbers** (every agent reading "the highest existing is N" writes N+1, and they all collide at merge), and **sole ownership of any file two issues would both touch**. A conflict found at merge costs a re-run, which is the most expensive thing that can happen to a wave.

   Children see nothing but their prompt, so paste everything they need: the full issue text, its `check` command from `issues/status.json`, the allocations above, and any decision or error text from this conversation that bears on the issue.

   Each agent's prompt:

   > Implement the following issue (full text pasted below). Read `AGENTS.md` for build/test commands, and `docs/research.md` for existing patterns if present. Use TDD: one test → one implementation, testing behavior through public interfaces. Full implementations only — no stubs or placeholders. Run the checks AGENTS.md requires **for the paths you actually touch** — its Checks section says which lanes apply to which paths, and running the whole gate by reflex burns wall clock the entire wave is waiting on. Lint always. Honour any parallelism or resource limit AGENTS.md documents for a shared machine, because your peers are running their own gates at the same time. Every check you run must exit 0, and say which ones you ran and why those. Then run the issue's own check: `<check from status.json>`. Commit on your branch with a descriptive message. Do NOT touch files outside the scope named in the issue, and do NOT edit `issues/status.json`, `issues/progress.md` or move issue files — the orchestrator owns those, and four branches editing them collide at merge.
   >
   > **Return contract — required.** After your last commit, write `issues/<id>.result.json` in your worktree. Do NOT commit it (it names your final commit, so it cannot be inside it). Fill `checks` by pasting the output of `./ralph/checks.sh --json` as-is, plus one entry for the issue's own check with its real exit code — never type exit codes from memory. Then end your reply with exactly the same JSON in a fenced block labelled `ralph-result`, and nothing after it:
   >
   > ```ralph-result
   > {
   >   "issue": "<id>",
   >   "status": "done | partial | blocked",
   >   "branch": "<your branch: git branch --show-current>",
   >   "commit": "<git rev-parse HEAD>",
   >   "files_touched": ["<every path in git diff --name-only <base>...HEAD>"],
   >   "checks": [{"command": "<command>", "exit_code": 0}],
   >   "open_questions": ["<anything the human must decide; required unless status is done>"]
   > }
   > ```
   >
   > `done` means every check exited 0. If anything failed or is unfinished, say `partial` or `blocked` and explain in `open_questions` — a truthful partial is worth more than a false done.

4. **Collect and verify.** For each finished agent, in the main checkout:

   1. Copy `issues/<id>.result.json` from the agent's worktree verbatim. If the file is missing, save the `ralph-result` block from its reply instead, unchanged. Never write or edit a result yourself.
   2. Run `./ralph/result.sh verify issues/<id>.result.json <base-branch> <branch the Agent tool reported for that worktree>` — the third argument binds the result to the work you dispatched. It checks the schema, that the file name matches the reported issue, that `commit` is the tip of `branch` and the worktree is clean, that `files_touched` equals the branch's real diff, that the branch neither edits `issues/status.json` / `progress.md` / `done/` nor drops a Check the base branch has, and re-runs the AGENTS.md Checks plus the issue's check from `issues/status.json` in the agent's worktree, comparing exit codes with the report.
   3. Report per issue from the verified JSON only: branch, status, each check with its exit code, files touched, open questions — and the verify output. A result that fails `verify` is reported as **not verified** with the reason, whatever the agent's prose said.

   List the verified `done` branches for the user to review and merge — do not merge yourself. Leave `partial` and `blocked` issues open with their open questions appended to the issue file.

5. **After the user merges.** On the merged main checkout, for each merged issue run `./ralph/status.sh pass <id>`. Only when it succeeds (Checks + the issue's check green on the merged tree) move the issue file to `issues/done/`. Commit `issues/status.json`, `issues/progress.md`, the moved files and the result files together.

6. **Next wave.** Re-read the graph: newly unblocked issues form the next wave.
