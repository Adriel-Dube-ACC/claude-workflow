---
name: analyze-issues
description: Consistency check between a PRD and its issue files — verifies every user story is covered, no issue contradicts the PRD, and the dependency graph is sound. Use after prd-to-issues, before implementation starts.
---

# Analyze Issues

Cross-artifact consistency check. Read the PRD (default `issues/prd.md`) and every open issue in `issues/`, then check:

1. **Coverage** — every PRD user story maps to at least one issue. List uncovered stories.
2. **Traceability** — every issue references real user stories. Flag issues that cover nothing in the PRD (scope creep).
3. **Contradictions** — issues whose acceptance criteria conflict with the PRD's implementation or testing decisions.
4. **Dependency graph** — every `Blocked by` reference points at a file that exists; no cycles; flag issues marked blocked that could actually start now (over-serialization).
5. **Slice quality** — issues that look like horizontal layers rather than vertical slices, or that bundle two concerns (the title needs an "and").
6. **AFK/HITL sanity** — AFK issues that secretly require a human decision, and HITL issues that could be AFK.
7. **Status file** — `issues/status.json` must agree with the issue files, because Ralph and `/fan-out-issues` read only the JSON. Run `./ralph/status.sh validate` and report every `status:` line it prints as a finding. It checks the schema; that every issue file has an entry and every entry's file exists (in `issues/` or `issues/done/`); that each file name starts with its id; that each file's `## Type`, `## Check` command and `## Blocked by` references equal the entry's `type`, `check` and `blockedBy`; that no `passes: true` lacks the evidence only `./ralph/status.sh pass` writes; and that no passing issue has a failing blocker. Then compare what the script cannot judge: the entry's `title` against the file's heading, and its `behaviour` sentence against the file's "What to build". No `issues/status.json` → one finding: create it (`/prd-to-issues` step 7, or `./ralph/loop.sh plan`). No `ralph/status.sh` (a project set up before it existed) → do the same comparisons by reading both.

## Output

A short report, most severe first. For each finding: the file, the problem, and a one-line fix. Include the `./ralph/status.sh validate` output as run. Offer to apply the fixes; don't apply without confirmation, and never fix a `passes` flag by hand — re-run `./ralph/status.sh pass <id>` instead.

If everything passes, say so in one line. Do not invent findings to seem useful.
