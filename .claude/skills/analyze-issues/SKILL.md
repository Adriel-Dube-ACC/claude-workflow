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

## Output

A short report, most severe first. For each finding: the file, the problem, and a one-line fix. Offer to apply the fixes; don't apply without confirmation.

If everything passes, say so in one line. Do not invent findings to seem useful.
