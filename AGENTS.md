# Mixr Audio Engineering Rules

## Product principle

**Auto Remix produces a club rewrite**, not a polite preservation edit.

For one-song Auto Remix, rebuild the track as a streaming-length club mix in the world of festival / EDM arrangement instincts (builds, drops, breakdowns, crowd hype)—while keeping the song's recognizable identity on the first drop. The default result should sound like a club alternate of the original, not a slightly shuffled original.

Preservation of identity means: the familiar hook lands on drop 1; arrangement, pulse, and energy do the transformation. SFX alone do not count as transformation.

**Mix-window / join grammar (locked):** `.agents/skills/dj-remix-planning/SKILL.md` (continuous sweep, hook-replace, hard cut, festival mix-window SFX, Drop 1 after 16–24 elapsed bars). That skill wins over this file on those topics. Tempo pockets, one-kick pulse, gain/DSP, analysis, testing, and this completion standard remain here.

For mashups (2…5 songs), assign **one club bed** and rotate vocal hooks across the club islands (**hook-replace** on Drop 1: guest vocal in, bed vocal out). Never stack two full mixes with two kicks/subs.

## Confidence ladder (cuts vs energy)

Apply structural aggressiveness from measured analysis confidence:

1. **Low confidence** (weak section/beat/phrase evidence): do **not** invent random structural cuts. Still impose a club **energy curve** (filter, pulse, coordinated SFX, optional pre-drop void). Prefer continuous source order with effect/pulse shaping.
2. **Medium confidence**: phrase-aligned club shape with continuous preference; allow cuts only with strong local evidence and filled transitions.
3. **High confidence** (reliable section/beat/phrase analysis): rebuild onto an 8 / 16 / 32 bar phrase grid with intro → complete hook → continuous sweep → Drop 1 (after 16–24 elapsed bars) → break → Drop 2. Prefer arrangement changes when repeat evidence supports them. Preserve the primary hook on drop 1 and add exactly one extra idea on drop 2.

Never cut merely to increase variety, handoffs, effect count, or SFX density. When uncertain about a cut, keep the audio continuous and club-ify with energy, clip FX, and layered SFX.

Club hype density (one-song Auto Remix / mashup): energy lives on the **drop / mix window**, not on verses. Maximalist flavors stack festival SFX there (riser + snare roll + tape-stop take-out + impact slam) — see `dj-remix-planning`. Verses stay one record. Still one kick and one bass. Flavor instincts bias toward Diplo / Guetta / Snake festival hype over Calvin sparse radio edits. Skip verse filler so Drop 1 hits ~bar **16–24** after one complete Deck A hook + pivot (not a bar-28 runway).

Mashup algorithms (reimplemented in Swift — no Demucs/PyTorch/Mixxx **runtime**): AutoMashUpper local phrase mashability (harmonic/rhythmic/spectral + beat-offset islands); AutoMashup 2025 stem *role proxies* from vocal/bass/drum curves (directional bed≠vocal); Mixxx AutoDJ phrase matching (outro∩intro overlap, delay long intros, tape-stop on far-BPM **non-pivot** joins). Optional offline Demucs **sidecars** (vocals/drums/bass/other) may already exist; if present, sweep material prefers an appropriate isolated stem and kick ownership may read drums. Do not add a Demucs runtime.

## Club arrangement (one song)

Target shape on the phrase grid (all structural cuts on phrase / downbeat boundaries; a drop that lands on bar 3 of a phrase is a fail):

1. Adaptive intro: start with the record’s opening identity; choose its length around a complete hook and legal early drop, rather than fixing it at 16 bars.
2. First complete hook: at least 8 bars of identity; preserve the complete lyrical phrase and pickups.
3. Continuous sweep: normally 2 bars of musical runway into a verified phrase entrance; no repeated one-beat grains. Existing blur is low-pass, not high-pass or vocal isolation.
4. Drop 1: familiar hook at full gain on the verified phrase entrance after 16–24 elapsed bars. The independently annotated early-drop fixture has no timing exception; other late drops require independently reviewed source evidence that every early candidate is illegal.
5. Breakdown 8–16: kick/sub out through stems, arrangement or gain ownership; vocal or piano breathe.
6. Build 2: stronger tension than the first sweep without masking the next hook.
7. Drop 2 = 16: Drop 1 identity plus exactly one distinct musical idea. SFX alone do not count. One-beat void permitted only without a pivot.
8. Short outro: hook fragment + drums.

**Hype is subtraction then a downbeat.** Drop 1 follows the short rising handoff in `dj-remix-planning`; a hard cut is optional and no quiet hole is allowed. A 1-beat pre-drop void is allowed only on **plain** (non-pivot) drops. Accidental silence is still a fail. Details: `dj-remix-planning`.

## Club pulse (one kick rule)

**Only new Auto sound:** a kick/bass pulse layer for **thin** songs (piano ballad, weak drums).

- Four-on-the-floor kick + bass weight.
- **ONE kick and ONE bass at a time.**
- Remove or duck the original low-end owner using available stems, arrangement or gain while the pulse is in. Existing blur is low-pass and cannot prove low-end removal; if isolation is unavailable, skip the pulse when it would create competing low end.
- If drums already slam (strong drum confidence), do **not** add pulse — even when bass density reads low.
- Festival/rock pocket with uncertain analysis: do **not** invent a house kick.
- Thin only when drums are actually weak. Slamming or moderate kits use existing SFX-row one-shots only.
- Two kicks flam and mud the club system — hard fail.

**Sound sources (product lock):**
1. Clip effects panel only: reverb, echo, pitch, flanger, blur (existing presets). No new clip-effect types.
2. SFX row: the built-in one-shots, including **Club Kick** and **Club Bass** (first-class menu items Auto may also place).
3. Arrangement: cuts, tempo/pocket, ducking/HPF, intentional pre-drop void.

## Tempo pockets

Decide per song / pair:

- Default house pocket: 124–128 BPM when the song already sits there, or a small stretch (≤8%) reaches it.
- If the song already sits in **house** (~124–130) or **festival/rock** (~140–150), keep that pocket.
- Midtempo pop (~90–100): **gentle club-lift ≤12%**, pitch preserved (TimePitch.rate / offline WSOLA). Do **not** yank to 126 — that chipmunks the vocal and rushes the record. A slight dance push is enough.
- Prefer double-time only when 2× lands in a pocket; check half-time / double-time before stretching.
- Vocal stretch max ~6–8% on non-lift paths. Gentle midtempo lift may be ~12% (pitch stays).
- If stretch would wreck the vocal and no lift applies, keep source BPM and club-ify with arrangement + energy.

## Mashup (2…5 songs)

N-song club mashups keep the same locked Drop 1 join. More songs mean more hooks to rotate across islands — **hook-replace**, not dual full-mix stacks.

- Pick **ONE club bed** (most mixable drums / already-in-pocket / simplest harmony). Everyone else is a vocal-hook candidate.
- **ONE kick and ONE bass** at any moment. Never stack two full-mix drops with two kicks/subs.
- **Hook-replace is the default** (guest hook in, bed vocal carved). Dual vocals are optional ≤8-bar call-and-response, not the Drop 1 stack. See `dj-remix-planning`.
- For 3–5 song mashups, **rotate** which guest owns Drop 1 vs Drop 2 rather than stacking all of them.
- Phrase grid still 8 / 16 / 32. Minimum identity stay **8 bars**; prefer **16** for a chorus/hook. Do not switch every 4 bars (short supporting chops do not count as identity stays).
- Club shape: intro → one complete A hook → continuous sweep → drop 1 → breakdown → build → drop 2 → outro. Drop 1 ~bar 16–24.
- **Drop 1** = a naturally entered complete familiar hook; do not force its title token as the cut point. **Drop 2** = a different song’s hook (the flip). On a duo, Drop 2 may be the bed’s own chorus flip.
- Remaining songs get fully aligned 8–16-bar hook cameos **after** Drop 1 (breakdown/outro), or are skipped. An incompatible native-speed chop is a separate limited role: at most one mix beat and 0.75 seconds (whichever is shorter), max two per eight bars, non-repeating, only after Drop 1 in breakdown/outro outside another foreground lead. It cannot supply kick/bass or count as a full hook; skip it if isolation or a clean word boundary is unavailable.
- Compatibility is **per added song**: Camelot same / ±1 / relative; vocal stretch ≤ 8% except a gentle midtempo lift ≤12% that actually reaches the selected common tempo; pitch vocal ≤ 2 st; prefer pitching the bed. If any guest fails the gate, skip it or use it only as a bounded short chop — do not force a sour full-vocal overlay.
- Energy matching still applies: a ballad on a peak-time bed needs a breakdown runway, not a slam.
- Cap at 5 songs for a streaming-length club rewrite.
- If key+tempo+energy cannot work without wrecking the vocal, refuse or degrade that guest. Do not force a bad mashup.

## Structural edits

- Begin from measured analysis, not seeded guesses.
- Trim beginnings and endings only with signal-derived evidence.
- Every internal cut requires:
  - a musical reason;
  - sufficient analysis confidence;
  - phrase/downbeat-aligned boundaries;
  - an explicitly filled or layered transition (or an intentional pre-drop void);
  - passing audio-quality validation.

## Transitions

- A crossfade must contain actual temporal overlap.
- Use equal-power gain curves for music **non-pivot** crossfades (verse/groove joins). Different-song non-drop joins **take over** with overlap: outgoing yields while incoming swells quiet → loud.
- Preserve the incoming phrase and pickup. A title token is not a required entrance; use a short rising handoff. A deliberate outgoing continuation may remain; finish it and delay the next song rather than deleting it or cutting it mid-line.
- Never fade both adjacent clips toward silence at the same boundary (unless an intentional void owns the gap).
- Drop 1 uses the phrase-led transition in `dj-remix-planning`. A prepared hard cut or a short blend may work; retain one lead and one low-end owner. The owner audition on September 9 preferred a modest ascension over consecutive lyric cuts.
- The **first clip** of a mashup/remix may fade in over a long intro (duration may exceed the UI 8-beat pill; the selected pill shows 8 as closest). Subsequent hook-replace joins preserve the phrase-led handoff and incoming pickup.
- Do not insert **accidental** silence. Intentional 1-beat pre-drop voids are allowed only on **plain** (non-pivot) drops. Pivot joins must not go quiet.
- A transition must conserve perceived energy unless the creative intent explicitly calls for a drop, pivot filter, or void.

## Analysis

- Editing decisions must come from real audio measurements.
- Do not use seeded guesses for section identity, vocals, bass, energy, or downbeats.
- Track confidence for every derived feature.
- Low confidence must reduce **cut** aggressiveness, not eliminate the club energy curve.
- Never assume source time zero is beat one without evidence.

## Gain and mastering

- Maintain at least 6 dB of mix-bus headroom before SFX.
- Calibrate SFX gains individually (including pulse-layer hits).
- Do not stack multiple major SFX without calculating combined gain.
- Apply smooth ducking when a major SFX competes with the song.
- Target no PCM clipping and a maximum true peak near −1 dBTP.
- Do not use the limiter to conceal bad gain staging.
- Treat sustained heavy limiter reduction as a failed mix.

## DSP automation

- Ramp every audible parameter change.
- Live and offline rendering must share the same automation model.
- Effect transitions may not step abruptly at render-block boundaries.
- Pitch changes require harmonic justification and smooth boundaries.
- Preserve reverb and delay tails without allowing them to overload later material.

## Testing

Numerical acceptance windows, limits and permitted exceptions are frozen in `docs/audits/2026-09-04-auto-remix/acceptance-contract.json`. Missing required evidence is inconclusive, not pass. Changes to that contract require independent reference evidence and baseline/control reruns before retuning.

- A plan-only test is not an audio-quality test.
- Every transition-related change requires rendered-PCM regression tests.
- Tests must cover clipping, true peak, silence, loudness dips, loudness jumps, clicks, overlap behavior, source continuity, live/export parity, phrase-aligned drops, one-kick rule, tempo pockets, mashup roles, and intentional voids.
- Synthetic audio fixtures must be deterministic and copyright-free. Do **not** download Spotify, YouTube rips, or copyrighted commercial tracks.
- Quality tests must demonstrate that the previous behavior fails when asserting a new gate.
- Never replace listening evaluation with metrics, and never replace metrics with listening alone.

## Completion standard

Do not call an audio change complete until:

1. tests pass;
2. an offline render passes quality gates;
3. transition diagnostics are reviewed;
4. the result is auditioned on headphones and speakers;
5. the agent reports evidence rather than saying it "should sound better."
