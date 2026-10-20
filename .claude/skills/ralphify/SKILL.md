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
| New Next.js app | **Existing** — run `create-next-app` first, then step 1b on its output |
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

For a Next.js project, don't use `newproj`: run `npx create-next-app@latest <name>`
first (it writes an `AGENTS.md` with a managed `<!-- BEGIN:nextjs-agent-rules -->`
block that `next dev` keeps current), `git init` + commit, then step 1b in it.
Starting from the framework's scaffold gets version-matched agent docs for free.

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

- **AGENTS.md handling** — if the file exists with no `## Checks` section (the
  create-next-app case) its content is kept byte-for-byte and a harness section
  (Checks / Build & run / Quirks) is appended between
  `<!-- BEGIN:ralph-harness -->` / `<!-- END:ralph-harness -->` markers, after any
  managed blocks. If it already has `## Checks`, nothing in it changes.

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
- `AGENTS.md had no Checks section — appended one` → you are filling the appended
  section in step 4. The managed blocks it lists must still be there afterwards.
- `CLAUDE.md does not import AGENTS.md` → add an `@AGENTS.md` line at the top, so
  interactive sessions load the Checks too.
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

**Append, never replace.** Edit only the harness section (`## Checks`, `## Build &
run`, `## Quirks` — between the `ralph-harness` markers when ralphify appended
them). Never rewrite the file wholesale, and never touch another tool's managed
block (`<!-- BEGIN:nextjs-agent-rules -->` … `<!-- END:… -->` and the like): the
tool that owns it rewrites it, and deleting it only produces a dirty diff later.

Uncomment the survivors under `## Checks`, delete the rest, and delete the
`UNVERIFIED candidates detected by ralphify` comment block once resolved. Fill in
`## Build & run` and `## Quirks` from what you learned while running the checks.

Then prove the file parses the way the loop reads it:

```bash
./ralph/checks.sh --list   # prints exactly the commands you verified
./ralph/checks.sh          # every line PASS, final line "checks: N/N passed"
```

and, if the file had managed blocks, that each `BEGIN:`/`END:` marker pair is
still present (`grep -c 'BEGIN:\|END:' AGENTS.md`).

On a new project the Checks section stays empty until a real test exists — leave
a one-line note saying so rather than a placeholder command.

Keep the file under ~60 lines — it loads on every Ralph iteration.

## 5. Report

State plainly:

- which path you took, and files created vs. kept (and whether AGENTS.md was
  appended to, with its managed blocks intact)
- each check with its verified exit status — the `./ralph/checks.sh` output
- anything blocking an autonomous run (no tests, broken build, no git)

Then the next command:

- existing project, no map of the codebase yet → `/research`
- no PRD → `/write-a-prd` → `/prd-to-issues` → `/analyze-issues`
  (on a new project `/prd-to-issues` makes 001 the walking skeleton and writes
  `issues/status.json`; nothing else runs until the skeleton passes)
- issues ready → `./ralph/loop.sh build 3`
