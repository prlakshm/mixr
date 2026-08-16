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

Auto Remix rewrites a song as a **streaming-length club mix** using a
**two-deck DJ mind**: Deck A is NOW PLAYING, Deck B is COMING NEXT.
Full-volume stacking is illegal except inside a **mix window**.

Preservation constrains identity (familiar hook on drop 1), not arrangement.
SFX alone do not count as transformation. Accidental silence is forbidden;
**intentional pre-drop voids are allowed** (hype = subtraction then a downbeat).

Mashups (2…5 songs) are **hook-replace over one bed**: guest hook IN on the
drop, bed vocal OUT (kick/bass stay). One melody, one kick. Call-and-response
is an optional ≤8-bar island, not the default. Never stack two full-mix kicks/subs.

## Two-deck model

- **Deck A** = current phrase (bed or solo source). **Deck B** = next hook.
- **Mix window** = last ~8 bars of A's phrase + first ~8 bars of the drop.
  Extra layers (second vocal, SFX stacks, pivot wallpaper grains, filter sweeps)
  are legal ONLY there, plus one impact on Drop 1.
- **Verses / grooves** = one deck: the source, maybe light HPF. No wallpaper
  chops, no riser spam, no guest vocal.
- **Xirex pivot wallpaper** (gold standard): Deck A chorus/hook plays COMPLETE
  once; catch only the last 1-beat grain; loop it 8–16× (2–4 bars) with rising
  HPF; hard cut into Deck B's hook on the same word. Not 1/8 stutter spam, not
  tape stops, not verse decoration.
- **Semantic joins**: wait until a phrase finishes. Outro/end of A meets
  intro/hook of B (Mixxx AutoDJ phrase-match behavior; reimplement, don't
  copy GPL). AutoMashUpper still picks WHICH 8–16 bar islands belong together.
- **Drop 2** = a flip (different song's hook or bed chorus back), not the
  same stack louder.
- Diplo / festival energy lives **on the drop**, not on verses.

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

Recipe flavors (instincts, not sound-alikes): Calvin sparse (rare — clear piano ballads only), Guetta vocal+electronic drop, Avicii 4-bar loop + airy drop 2, Marshmello hummable chops, DJ Snake chant / aggressive low end / half-time OK, **Diplo / Major Lazer / Jack Ü** maximalist festival hype (void-then-slam, vocal chops over rolling bed, global-bass DNA, FX as groove). Default Auto Remix toward Diplo/Guetta/Snake — not a polite Calvin radio edit.

## Club pulse

**Only new Auto sound** — thin songs only:

- Four-on-the-floor kick + bass weight; duck/HPF original low end.
- Slamming or moderate kits → **no pulse**. Use existing SFX-row one-shots.
- Mute kick+bass in build-out, breakdown, and void regions.
- Pulse kick/bass are first-class SFX menu items (same library Auto places).

Sound sources: clip effects (reverb/echo/pitch/flanger/blur only) + SFX menu one-shots (including Club Kick / Club Bass) + arrangement.

## Tempo

- Keep midtempo (~90–100), house (~124–130), festival (~140–150) pockets.
- Double-time only when 2× lands in a pocket; check half/double before stretch.
- Vocal stretch ≤ ~8%; bed/instrumental ≤ ~15%.
- If stretch wrecks the vocal → keep BPM, club-ify with arrangement + energy.

## Mashup (2…5 songs)

- ONE club bed (drums / pocket / simple harmony); others = vocal-hook candidates.
- Drop 1 = strongest full hook (**hook-replace**: guest in, bed vocal carved out).
- Drop 2 = a different song’s hook (duo may flip to bed chorus) — not louder stack.
- Dual vocals are NOT the default. Optional call-and-response ≤ 8 bars, then back to one voice.
- Still ONE kick and ONE bass — reject dual full-mix kick/sub stacks.
- Remaining songs: 8–16 bar cameos (verse/breakdown/outro) or short chops if gates fail.
- Pitch the bed (≤ ~2 st); never force a star vocal through illegal stretch.
- Prefer Camelot same → ±1 → relative. Skip or cameo-only when song 4/5 fails.
- Minimum stay 8 bars; prefer 16 on choruses. No 4-bar ping-pong.
- Ballad on a peak-time bed → breakdown runway, not a slam.
- Cap at 5 songs.

Ported heuristics (Swift reimplementations — cite in code):
- **AutoMashUpper (Davies 2014):** mashability is LOCAL per 8–16 bar island (harmonic / rhythmic / spectral); search beat offsets; asymmetric vocal-over-bed.
- **AutoMashup 2025 (BSD-3):** stem *role proxies* from vocalPresence vs bass/drum curves (no Demucs); directional compatibility.
- **Mixxx AutoDJ phrase match:** transition = outro∩intro; delay long intros so endings meet; far BPM → tape-stop, not vocal wreck.

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
- filtered build (mix window only)
- Xirex pivot wallpaper: 1-beat last-word loop 8–16× → hard cut (not echo spam)
- intentional pre-drop void (skipped when pivot wallpaper owns the window)
- reverse lead-in
- equal-power overlap
- hard hype cut with anti-click microfade

### Energy shaping
- remove kick/bass before a return (build-out)
- restore the full spectrum on a downbeat
- increase or reduce effect intensity across 4–16 bars
- use contrast rather than continuous loudness automation

### Pulse / SFX
- thin-song club kick / bass weight (first-class SFX menu items; one at a time)
- existing SFX-row one-shots on extra SFX rows: riser, snare build, impact,
  crash, clap fill, air sweep, reverse cymbal, tape stop, …
- SFX live in the **mix window and on the drop** — not on verses/grooves
- one impact on Drop 1; cymbal punctuation ≤ 2 total; no mid-drop wallpaper
- clip FX in the mix window: pivot HPF sweep, blur/filter, reverb bloom

Pulse and SFX must support an underlying musical transformation. Hype is
the join and the drop, never a second kick or verse wallpaper.

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

Choose from measured texture + seed (hype-biased):

- sparse piano/vocal/bass (Calvin-class) — only clear ballads
- vocal + electronic drop (Guetta-class)
- four-bar harmonic loop (Avicii-class)
- hummable chop drop (Marshmello-class)
- chant / aggressive low end (Snake-class)
- maximalist festival / global-bass (Diplo-class) — default for pop-over-club and dancehall midtempo

Avoid stacking two dense midrange leads on the drop. Hype is density of FX/SFX layers — still one kick and one bass.

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
