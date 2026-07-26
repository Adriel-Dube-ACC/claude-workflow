---
name: ralphify
description: Set up the Ralph loop in any project — `newproj` for a brand-new one, the `ralphify` script for one that already has code. Scaffolds ralph/, issues/, docs/, AGENTS.md, then runs the detected checks and writes only the verified ones into AGENTS.md. Use whenever the user wants to start a new project with the harness, or add Ralph / the harness / the loop to an existing project.
---

# Ralphify — set up the Ralph loop

Two halves. A shell script does the mechanical half. You do the half that
requires judgment: proving the checks actually run.

A check that silently passes lets broken code through every Ralph iteration.
This is the whole reason the skill exists — never skip the verify step.

## 0. Pick the path

Look at the target directory before running anything.

| Situation | Path |
|---|---|
| Directory doesn't exist yet, or is empty | **New** — step 1a |
| Directory has source files, a git history, a package manifest | **Existing** — step 1b |

If the user names a project that doesn't exist yet, that's New. If they say
"add Ralph here" in a repo with code, that's Existing. When genuinely unsure,
ask — the two paths write different files.

## 1a. New project — `newproj`

```bash
newproj my-thing          # creates ~/Claude/my-thing, git init, harness, CLAUDE.md stub
newproj my-thing --here   # scaffold into the current (empty) directory instead
```

Script location: `~/bin/newproj`. It refuses to run if the destination already
exists, and it never overwrites a file that's already there. Set
`CLAUDE_PROJECTS_DIR` to scaffold somewhere other than `~/Claude`, or
`NEWPROJ_VENDOR_SKILLS=1` to copy the skills in for a self-contained repo.

A brand-new project has nothing to detect and nothing to verify. So:

- **Do not invent checks.** An AGENTS.md listing `npm test` for a project with no
  tests is a gate that passes on nothing.
- Get the stack installed and **one trivial test passing** first, then run that
  command and record it. That single real check is what makes an autonomous loop
  safe to start.
- Until a check exists, say plainly that Ralph should be run with
  `./ralph/once.sh` / short `build` runs under supervision, not left unattended.

Then go to step 4 to write AGENTS.md, and step 5 to report.

## 1b. Existing project — `ralphify`

Run from the project root:

```bash
ralphify --dry-run   # review first if the project already has AGENTS.md/CLAUDE.md
ralphify
```

Script location: `~/bin/ralphify`. It never overwrites an existing file, reports
every path as created or kept, and prints:

- **Candidate checks** — detected from package.json / pyproject.toml / go.mod /
  Cargo.toml / Makefile. **Unverified.** The script does not execute them.
- **Notes** — monorepo layout, missing `node_modules`, virtualenv path, dirty
  working tree, missing git repo, leftover `ralph/prompt.md`.

If neither script is on PATH, run `~/bin/<name>` directly. Add `--vendor-skills`
if the project needs to be self-contained for sharing.

Read every note before continuing — a monorepo note means the working directory
for each check is still an open question you have to resolve.

## 2. Handle what `ralphify` found

- `AGENTS.md exists but its Checks section is EMPTY` → you are filling it in step 4.
- `AGENTS.md already has a filled Checks section` → run those existing commands
  anyway to confirm they still pass; report any that don't.
- `ralph/prompt.md` present → superseded by the plan/build split; offer to delete it.
- `not a git repo` → stop and get `git init` + an initial commit done first.
  Ralph checkpoints each iteration with a commit; without git it has no undo.
- `node_modules/ is absent` → install deps before verifying anything.

## 3. Verify the candidates — actually run them

Execute each candidate command and record its exit status. Do not write a command
into AGENTS.md that you have not personally run in this session.

- Failing because of a genuinely broken build → report it; that is a blocker for
  autonomous runs, not something to paper over.
- Failing because the command is wrong (wrong directory, missing script, wrong
  runner) → find the correct one and run that.
- Slow but passing → keep it, and note the runtime in Quirks.
- A check that passes vacuously (no tests collected, empty test suite) is worse
  than no check. Say so explicitly rather than listing it as a gate.

In a monorepo, run each command from the directory it actually belongs to and
write that directory into the check line.

## 4. Write AGENTS.md

Uncomment the survivors under `## Checks`, delete the rest, and delete the
`UNVERIFIED candidates detected by ralphify` comment block once resolved. Fill in
`## Build & run` and `## Quirks` from what you learned while running the checks.

On a new project the Checks section stays empty until a real test exists — leave
a one-line note saying so rather than a placeholder command.

Keep the file under ~60 lines — it loads on every Ralph iteration.

## 5. Report

State plainly:

- which path you took, and files created vs. kept
- each check with its verified exit status
- anything blocking an autonomous run (no tests, broken build, no git)

Then the next command:

- existing project, no map of the codebase yet → `/research`
- no PRD → `/write-a-prd` → `/prd-to-issues` → `/analyze-issues`
- issues ready → `./ralph/loop.sh build 3`
