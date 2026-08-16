---
name: dj-remix-planning
description: >-
  Plan Auto Remix club rewrites and mashups: phrase-grid arrangement, pulse
  layer, tempo pockets, hook-over-bed roles, and transformation scoring.
  Use when designing remix recipes, selecting cut/transition/SFX/pulse
  opportunities, auditing remix decisions, or implementing Auto Remix planning.
---

> **Policy source of truth:** Mixr root `AGENTS.md`. This skill provides
> planning procedure; if guidance conflicts, AGENTS.md wins.

# DJ Remix Planning

## Product intent

Auto Remix rewrites a song as a **streaming-length club mix**: builds, drops,
breakdowns, and hype—while keeping the song's recognizable identity on the
first drop.

Preservation constrains identity (familiar hook on drop 1), not arrangement.
SFX alone do not count as transformation. Accidental silence is forbidden;
**intentional pre-drop voids are allowed** (hype = subtraction then a downbeat).

Mashups are **hook-over-bed**: one song sings, the other is the club bed.

## Planning hierarchy

1. Analyze musical structure (sections, beats, phrases, drum/bass density).
2. Decide tempo pocket (keep strong pockets; stretch/double-time only within gates).
3. Decide pulse policy (one-kick rule).
4. Build the club phrase-grid recipe (or mashup hook/bed slots).
5. Score and place sections; record structured cut / void / pulse decisions.
6. Validate musical and audio integrity.
7. Render and report every decision.

## Club shape (one song)

Phrase-grid only — drops land on downbeats, never mid-bar:

1. Intro 8–16 — filtered identity / kick tease
2. Groove 8–16 — identity below drop density
3. Build 8–16 — riser / snare; kick+bass out last 4 bars; optional void
4. Drop 1 = 16 — familiar hook, full pulse, one lead idea
5. Breakdown 8–16 — pulse out, breathe
6. Build 2 — denser than build 1
7. Drop 2 = 16 — drop 1 + exactly one extra layer
8. Outro — hook fragment + drums

Recipe flavors (instincts, not sound-alikes): Calvin sparse, Guetta vocal+electronic drop, Avicii 4-bar loop + airy drop 2, Marshmello hummable chops, DJ Snake chant / aggressive low end / half-time OK.

## Club pulse

- Thin source → write kick+bass, duck/high-pass original low end.
- Slamming kit → **no second kick**; only risers / snare / impact / hats.
- Mute kick+bass in build-out, breakdown, and void regions.

## Tempo

- Keep midtempo (~90–100), house (~124–130), festival (~140–150) pockets.
- Double-time only when 2× lands in a pocket; check half/double before stretch.
- Vocal stretch ≤ ~8%; bed/instrumental ≤ ~15%.
- If stretch wrecks the vocal → keep BPM, club-ify with arrangement + energy.

## Mashup

- Highest feature/vocal affinity → hook; highest groove/drums → bed.
- Pitch the bed (≤ ~2 st); never force the star vocal through illegal stretch.
- Prefer Camelot same → ±1 → relative. Refuse pairs that cannot work.
- Minimum stay 8 bars; prefer 16 on choruses. Hook lands on the drop.

## Opportunity evidence

Propose phrase-aligned opportunities when measured:

- repeated or highly similar section
- energy rise or fall
- instrumentation / drum density change
- temporary reduction in vocal activity
- chorus, bridge, breakdown, pre-chorus, intro, or outro boundary
- 8-, 16-, or 32-bar structural completion
- low-information repeated material
- strong novelty event

## Transformation families

### Arrangement
- rebuild onto the club phrase grid
- return to the hook for drop 1 / drop 2
- shorten redundant bars
- compress or replace the outro

### Transition
- filtered build
- echo throw
- intentional pre-drop void
- reverse lead-in
- equal-power overlap
- hard hype cut with anti-click microfade

### Energy shaping
- remove kick/bass before a return (build-out)
- restore the full spectrum on a downbeat
- increase or reduce effect intensity across 4–16 bars
- use contrast rather than continuous loudness automation

### Pulse / SFX
- club kick / bass weight (one at a time)
- riser, snare roll, impact, hats

Pulse and SFX must support an underlying musical transformation.

## High-confidence behavior

With reliable section, beat, and phrase analysis:

- emit the two-wave club shape across intro → drop 2
- include non-SFX arrangement transformations
- land the familiar hook on drop 1
- add exactly one extra idea on drop 2
- keep intentional voids phrase/beat aligned

These are planning targets, not unconditional quotas. Explain fewer edits.

## Low-confidence behavior

When structure, phrase, or beat confidence is low:

- do not invent structural cuts
- still impose filter + pulse + SFX energy curve
- permit edge trimming and intentional pre-drop void when beat grid allows
- degrade handoffs to clean phrase-aligned crossfades in mashups

## Cut rules

- Cuts must land on verified beat and phrase boundaries.
- Do not cut through an active vocal phrase without explicit masking.
- Each cut requires a structured AutoCutRecord.
- Reordering requires stronger evidence than shortening.
- Prefer removing or repeating complete phrase units.
- Mask cuts with overlap, dropout, impact, echo, void, or another justified transition.
- Accidental silence is invalid; intentional pre-drop voids are valid.

## Variation

Do not apply the same flavor to every song.

Choose from measured texture + seed:

- sparse piano/vocal/bass (Calvin-class)
- vocal + electronic drop (Guetta-class)
- four-bar harmonic loop (Avicii-class)
- hummable chop drop (Marshmello-class)
- chant / aggressive low end (Snake-class)

Avoid stacking two dense midrange leads on the drop.

## Decision audit

Before declaring success, report:

- tempo pocket decision and stretch/pitch gates
- pulse policy (wrote kick vs skipped second kick)
- club flavor
- mashup vocal vs bed assignment (or refusal)
- all opportunities considered
- why each selected opportunity was chosen
- why rejected opportunities were rejected
- confidence in each decision
- whether a test passes because an operation was avoided
- which decisions were based on measured evidence versus a heuristic
