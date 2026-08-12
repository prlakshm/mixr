---
name: dj-remix-planning
description: >-
  Plan Auto Remix transformations that preserve song identity while creating a
  clearly edited alternate arrangement. Use when designing remix recipes,
  selecting cut/transition/SFX opportunities, scoring transformation zones,
  auditing remix decisions, or implementing Auto Remix planning logic.
---

> **Policy source of truth:** Mixr root `AGENTS.md` confidence ladder. This skill provides planning procedure; if guidance conflicts, AGENTS.md wins.

# DJ Remix Planning

## Product intent

Auto Remix should preserve the song's identity while creating a clearly
transformed alternate arrangement.

Preservation is a constraint, not the objective.

A successful high-confidence remix should feel intentionally edited in
multiple parts of the song. SFX alone do not count as transformation.

## Planning hierarchy

1. Analyze musical structure.
2. Generate transformation opportunities throughout the song.
3. Score each opportunity using measured evidence.
4. Select a varied, distributed recipe.
5. Validate musical and audio integrity.
6. Render and report every decision.

## Opportunity evidence

An opportunity may be proposed at a phrase-aligned boundary when one or
more of these are measured:

- repeated or highly similar section
- energy rise or fall
- instrumentation change
- temporary reduction in vocal activity
- chorus, bridge, breakdown, pre-chorus, intro, or outro boundary
- 8-, 16-, or 32-bar structural completion
- low-information repeated material
- strong novelty event

## Transformation families

### Arrangement
- shorten a repeated section
- remove redundant bars
- repeat a hook
- return to an earlier hook
- create a masked internal cut
- compress or replace the outro

### Transition
- filtered build
- echo throw
- brief dropout
- reverse lead-in
- equal-power overlap
- micro-loop or stutter

### Energy shaping
- remove bass before a return
- restore the full spectrum on a downbeat
- increase or reduce effect intensity across 4–16 bars
- use contrast rather than continuous loudness automation

### SFX
- riser
- impact
- short transitional accent

SFX must support an underlying musical transformation. Adding an SFX
without changing arrangement, spectrum, rhythm, or continuity does not
count as a transformation.

## High-confidence behavior

For a song longer than approximately 2.5 minutes with reliable section,
beat, and phrase analysis:

- target 3–5 transformation zones
- cover at least three structural regions of the song
- include at least two non-SFX transformations
- include arrangement transformation when repeat evidence supports it
- avoid placing every edit around the single largest lift
- maintain sufficient space between major interventions
- preserve at least one complete primary hook
- preserve at least one substantial continuous passage

These are planning targets, not unconditional quotas. Explain any
decision to emit fewer transformations.

## Low-confidence behavior

When structure, phrase, or beat confidence is low:

- preserve continuous placement
- permit edge trimming
- permit only effects that do not require precise section understanding
- do not invent cuts to satisfy transformation targets

## Cut rules

- Cuts must land on verified beat and phrase boundaries.
- Do not cut through an active vocal phrase without explicit masking.
- Each cut requires a structured AutoCutRecord.
- Reordering requires stronger evidence than shortening.
- Prefer removing or repeating complete phrase units.
- Mask cuts with overlap, dropout, impact, echo, or another justified
  transition.
- Do not use silence as a transition unless intentionally requested.

## Variation

Do not apply the same recipe to every song.

Choose a recipe family based on the measured structure:

- progressive build
- hook-forward edit
- condensed club edit
- breakdown-and-return
- rhythmic chop edit
- subtle polished edit

Avoid using the same transformation type twice consecutively unless the
song structure strongly supports it.

## Decision audit

Before declaring success, report:

- all opportunities considered
- why each selected opportunity was chosen
- why rejected opportunities were rejected
- confidence in each decision
- whether a test passes because an operation was avoided
- which decisions were based on measured evidence versus a heuristic
