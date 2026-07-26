---
name: write-a-spec
description: Interview the user about a feature, then write a self-contained SPEC.md that ends in a verification step. Lighter than write-a-prd — use for features finishable in about a day. For multi-day, multi-slice work use write-a-prd instead.
---

# Write a Spec

For half-day to one-day features. The output is a handoff document: after it's written, implementation happens in a FRESH session with clean context. Do not implement in this session.

## Process

1. If `docs/research.md` exists and is relevant, read it first.

2. **Interview** the user with the AskUserQuestion tool. Ask about technical implementation, UI/UX, edge cases, concerns, and tradeoffs. Don't ask obvious questions — dig into the hard parts they might not have considered. If a question can be answered by exploring the codebase, explore instead of asking. Keep going until there's no ambiguity left.

3. **Write `SPEC.md`** at the project root:

<spec-template>
# Spec: <feature>

## Goal

One paragraph: what and why.

## Files & interfaces involved

The actual files and interfaces to touch — verified against the codebase, not guessed.

## Behavior

Numbered, testable statements of what the feature does, including the edge cases surfaced in the interview.

## Out of scope

Explicit non-goals.

## Acceptance criteria

- [ ] Checkable criteria, one per line

## Verification

The exact commands/steps that prove this works end-to-end (test command, lint, a manual check if unavoidable). Each must produce pass/fail output.
</spec-template>

4. **Hand off.** Tell the user to run `/clear`, then start implementation in the fresh session with:

   ```
   /goal every acceptance criterion in SPEC.md is demonstrated in the transcript and every command in SPEC.md's Verification section passes — or stop after 20 turns
   ```

The spec is the deliverable. Writing precise acceptance criteria pays off more than watching the implementation.
