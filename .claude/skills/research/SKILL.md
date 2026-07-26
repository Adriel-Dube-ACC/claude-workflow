---
name: research
description: Map an existing codebase before planning — produces docs/research.md covering relevant files, functions, data flows, patterns, and constraints. Use before write-a-prd or write-a-spec on an existing (brownfield) project, or when the user asks to research a subsystem.
---

# Research

Produce a compact, durable map of the code relevant to an upcoming change. This file is the context handoff for every later session — PRD writing, spec writing, and implementation agents read it instead of re-crawling the repo.

## Process

1. **Scope.** Ask the user one question: what change or feature is this research for? One sentence is enough. If they've already said, skip this.

2. **Explore with subagents.** Spawn parallel Explore subagents so file reads don't pollute this context. Split by concern (e.g. data layer / API surface / UI / tests). Instruct each: "Do not assume something is not implemented — verify by searching."

3. **Write `docs/research.md`** (create `docs/` if needed):

<research-template>
# Research: <topic>

Date: <date> | Commit: <git short sha>

## Relevant files

What each file is responsible for. One line each, with path.

## Key functions & interfaces

Signatures and responsibilities, cited as `path/to/file.py:123`.

## Data flow

How data moves through the system for the paths this change touches.

## Patterns to follow

Existing conventions new code should match, each with an example location.

## Constraints

Things any change must respect: invariants, backwards compatibility, auth, performance.

## Open questions

Things the code couldn't answer.
</research-template>

## Rules

- Cite `file:line` for every claim. The next reader must be able to jump straight there.
- Under 200 lines. This is a map, not a tour.
- Describe what IS. Never propose solutions — no "we should", no design opinions.
- If a research file already exists for this area, update it (and refresh the commit stamp) instead of writing a second one.
