---
name: prd-to-issues
description: Break a PRD into independently-workable issues and write each as a local markdown file in issues/, plus the machine-readable issues/status.json the Ralph harness gates on. On a new project issue 001 is always a walking skeleton (deployed hello-world, health route through the database, Playwright smoke test in AGENTS.md Checks) that blocks every other issue. Use when the user wants to turn a PRD into a list of concrete tasks.
---

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices (tracer bullets), written as local markdown files, and record them in `issues/status.json` — the state file Ralph reads and only a green checks run may flip.

## Process

### 1. Locate the PRD

Ask the user for the PRD file path (e.g. `issues/prd.md`).

If the PRD is not already in your context window, read it from the file.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code.

### 3. Decide whether the project needs a walking skeleton

A walking skeleton is the thinnest version of the real system that runs end to end: deployed, a route that goes through every layer to the database and back, and an automated smoke test that proves it. Every later issue is one more thin slice through it, so none of them can start until it exists.

Check what is already true. Search before concluding something is missing — a failed grep is not proof of absence:

- Is there a **deployed** environment (e.g. `.vercel/project.json`, `render.yaml`, a deploy URL in README/AGENTS.md)?
- Is there a **health route that touches the database** (not a static `{ ok: true }`)?
- Is there an **end-to-end smoke test** (Playwright) listed in the AGENTS.md Checks?

| Result | Do this |
|---|---|
| None or some are true (any new project, or `newproj` / create-next-app output) | Issue **001 is the walking skeleton**, covering only the missing parts. Every other issue lists it under Blocked by. |
| All three are true | No skeleton issue. Say so in the breakdown and name the evidence (paths, URL, check command). |

Build the skeleton from the PRD's stack. Where the PRD is silent, use the user's default stack: Next.js on Vercel (or Render for long-running workers), Neon Postgres on a dev branch, Clerk for auth. Include only layers the PRD actually uses — no Clerk keys if there is no sign-in.

The skeleton is **HITL** by default: linking the hosting project and putting the database URL and auth keys into env need a human. List those as human prerequisites in the issue. Mark it **AFK** only when they already exist (`.env.local` has the database URL, the hosting project is linked).

### 4. Draft vertical slices

Break the rest of the PRD into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Every slice has ONE check: a shell command that exits 0 only when the slice's behaviour works end to end (usually one Playwright spec). If you cannot write that command, the slice is not concrete enough yet.
</vertical-slice-rules>

### 5. Quiz the user

Present the proposed breakdown as a numbered list, skeleton first. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **Behaviour**: one sentence a user could observe when it works
- **Check**: the command that proves it
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?
- For the skeleton: is the hosting target, database and auth provider right, and do the human prerequisites already exist?

Iterate until the user approves the breakdown.

### 6. Create the issue files

For each approved slice, write a markdown file in `issues/` using the naming pattern `issues/NNN-short-title.md` (e.g. `issues/001-walking-skeleton.md`).

Number issues starting from the next available number (check what files already exist in `issues/` and `issues/done/`). On a new project the skeleton is `001`.

Create files in dependency order (blockers first) so you can reference real filenames in the "Blocked by" field.

Do NOT use `gh issue create` or any GitHub CLI commands. Do NOT reference GitHub issue numbers. Use local filenames for all cross-references.

<walking-skeleton-template>
## Parent PRD

`issues/prd.md`

## Type

HITL (human prerequisites below) — or AFK if they already exist

## What to build

The thinnest deployed version of the app that touches every layer, so every later issue is a slice through something that already runs. No features.

## Human prerequisites

- [ ] Hosting project created and linked (Vercel: `vercel link`; Render: service created from the repo)
- [ ] Database dev branch created (Neon) and its URL in `.env.local` as `DATABASE_URL`, and in the host's env
- [ ] Auth keys in `.env.local` and the host's env (Clerk publishable + secret) — only if the PRD has sign-in
- [ ] Deployed URL recorded in AGENTS.md "Build & run"

## Acceptance criteria

- [ ] The home page renders the app name, locally and at the deployed URL
- [ ] `GET /api/health` runs a real query (`select 1`) against the database and returns `{ "ok": true, "db": "up" }`; with the database unreachable it returns HTTP 503 and `"db": "down"`, never a silent 200
- [ ] A Playwright smoke test (`e2e/smoke.spec.ts`) loads `/` and asserts `/api/health` returns `db: "up"`; it starts the app itself (Playwright `webServer`) and reads `SMOKE_BASE_URL` to run against a deployed URL instead
- [ ] `npm run smoke:deployed` runs the same spec against the deployed URL
- [ ] The local smoke command is added to the AGENTS.md Checks, run once by hand, and exits 0
- [ ] CI (e.g. GitHub Actions) runs the AGENTS.md Checks on every push
- [ ] `.env.example` lists every variable the app reads; real secrets stay out of git

## Check

`npm run test:e2e && npm run smoke:deployed`

## Blocked by

None - can start immediately

## User stories addressed

None directly — this is the path every user story's slice runs on.
</walking-skeleton-template>

<issue-template>
## Parent PRD

`issues/prd.md` (or whichever PRD file was used)

## Type

AFK or HITL

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation. Reference specific sections of the parent PRD rather than duplicating content.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Check

`<one shell command that exits 0 only when this slice works end to end, e.g. npx playwright test e2e/signup.spec.ts>`

## Blocked by

- Blocked by `issues/001-walking-skeleton.md` (on a new project, every issue)
- Blocked by `issues/NNN-title.md` (if any)

Or "None - can start immediately" if no blockers.

## User stories addressed

Reference by number from the parent PRD:

- User story 3
- User story 7

</issue-template>

### 7. Write `issues/status.json`

One entry per issue file, in the same order, every one starting `"passes": false`. If the file already exists, add entries for the new issues and leave existing entries untouched.

```json
{
  "version": 1,
  "prd": "issues/prd.md",
  "issues": [
    {
      "id": "001",
      "file": "001-walking-skeleton.md",
      "title": "Walking skeleton",
      "type": "HITL",
      "behaviour": "The deployed app loads and /api/health reports the database is up",
      "check": "npm run test:e2e && npm run smoke:deployed",
      "blockedBy": [],
      "passes": false
    },
    {
      "id": "002",
      "file": "002-short-title.md",
      "title": "Short title",
      "type": "AFK",
      "behaviour": "One sentence a user could observe",
      "check": "npx playwright test e2e/short-title.spec.ts",
      "blockedBy": ["001"],
      "passes": false
    }
  ]
}
```

- `file` is the bare filename — it stays valid when the issue moves to `issues/done/`.
- `check` and `blockedBy` mirror the issue file's Check and Blocked by sections exactly.
- **Never write `"passes": true`.** Only `./ralph/status.sh pass <id>` may flip it, after the AGENTS.md Checks and the issue's check all exit 0; it records the evidence in a `verified` object, and `validate` rejects a true flag without one. A check that has not been written yet (the spec file doesn't exist) is correct: the issue starts failing.

Then, if the harness is installed (`ralph/status.sh` exists):

```bash
./ralph/status.sh validate     # must print "status: valid — 0/N passing"
./ralph/status.sh progress "prd-to-issues: wrote N issues from issues/prd.md; 001 walking skeleton blocks the rest"
```

The second command creates `issues/progress.md`, the append-only log every Ralph pass adds to. If `ralph/status.sh` is missing, run `/ralphify` first — the status file is useless without the scripts that gate it.

Do NOT close or modify the parent PRD file.
