# Mixr Audio Engineering Rules

## Product principle

**Auto Remix produces a club rewrite**, not a polite preservation edit.

For one-song Auto Remix, rebuild the track as a streaming-length club mix in the world of festival / EDM arrangement instincts (builds, drops, breakdowns, crowd hype)—while keeping the song's recognizable identity on the first drop. The default result should sound like a club alternate of the original, not a slightly shuffled original.

Preservation of identity means: the familiar hook lands on drop 1; arrangement, pulse, and energy do the transformation. SFX alone do not count as transformation.

For mashups, assign **hook-over-bed** roles (one song sings, the other is the club bed). Never force two full mixes to fight drop-on-drop.

## Confidence ladder (cuts vs energy)

Apply structural aggressiveness from measured analysis confidence:

1. **Low confidence** (weak section/beat/phrase evidence): do **not** invent random structural cuts. Still impose a club **energy curve** (filter, pulse, coordinated SFX, optional pre-drop void). Prefer continuous source order with effect/pulse shaping.
2. **Medium confidence**: phrase-aligned club shape with continuous preference; allow cuts only with strong local evidence and filled transitions.
3. **High confidence** (reliable section/beat/phrase analysis): rebuild onto an 8 / 16 / 32 bar phrase grid with a two-wave club arrangement (build → drop → break → build → drop 2). Prefer arrangement changes when repeat evidence supports them. Preserve the primary hook on drop 1 and add exactly one extra idea on drop 2.

Never cut merely to increase variety, handoffs, effect count, or SFX density. When uncertain about a cut, keep the audio continuous and club-ify with energy.

## Club arrangement (one song)

Target shape on the phrase grid (all structural cuts on phrase / downbeat boundaries; a drop that lands on bar 3 of a phrase is a fail):

1. Intro 8–16: filtered identity / kick tease
2. Groove or verse 8–16: song identity, density below the drop
3. Build 8–16: riser, snare roll; kick+bass OUT in the last 4 bars; optional half-bar or 1-beat void
4. Drop 1 = 16: familiar hook on bar 1, full kick/sub, ONE lead idea
5. Breakdown 8–16: kick/sub out, vocal or piano breathe
6. Build 2: denser than build 1
7. Drop 2 = 16: drop 1 + exactly one extra layer (wider / harmony / vocal chop / perc)
8. Short outro: hook fragment + drums

**Hype is subtraction then a downbeat.** Intentional pre-drop voids are allowed and required when confidence supports them. The ban on *accidental* silence still applies.

## Club pulse (one kick rule)

**Only new Auto sound:** a kick/bass pulse layer for **thin** songs (piano ballad, weak drums).

- Four-on-the-floor kick + bass weight.
- **ONE kick and ONE bass at a time.**
- Duck or high-pass the original low end (existing blur / gain) while the pulse is in.
- If the source already slams (or has a moderate kit): do **not** add this pulse. Use existing SFX-row one-shots (riser, snare build, impact, …) only.
- Two kicks flam and mud the club system — hard fail.

**Sound sources (product lock):**
1. Clip effects panel only: reverb, echo, pitch, flanger, blur (existing presets). No new clip-effect types.
2. SFX row only: the twelve bundled one-shots. Pulse kick/bass are Auto-only and not SFX-row cards.
3. Arrangement: cuts, tempo/pocket, ducking/HPF, intentional pre-drop void.

## Tempo pockets

Decide per song / pair:

- Default house pocket: 124–128 BPM when nothing else fits.
- If the song already shares a strong pocket, **keep it** (midtempo pop ~90–100, festival/rock ~140–150, house ~124–130).
- Prefer double-time only when 2× lands in a pocket; check half-time / double-time before stretching.
- Vocal stretch max ~6–8%; instrumental / bed stretch prefer ≤15%.
- If stretch would wreck the vocal, keep source BPM and club-ify with arrangement + energy.

## Mashup (two songs)

- One song = vocal hook; the other = club bed. Not equal ping-pong every 4 bars.
- Prefer same Camelot, then ±1, then relative major/minor.
- Pitch the **bed**, not the star vocal. Vocal pitch shift ≤ ~2 semitones.
- Stretch the instrumental first. Vocal stretch ≤ 8%.
- Switch only on phrase boundaries. Minimum stay 8 bars; prefer 16 for choruses.
- One kick, one bass, one lead vocal at a time.
- Land the familiar hook **on the drop**.
- If key+tempo+energy cannot work without wrecking the vocal, refuse the pair or pick a safer architecture. Do not force a bad mashup.
- Drop-on-drop of two full mixes is a fail.

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
- Use equal-power gain curves for music crossfades.
- Never fade both adjacent clips toward silence at the same boundary (unless an intentional void owns the gap).
- Hard cuts require downbeat alignment and a short anti-click microfade.
- Do not insert **accidental** silence. Intentional pre-drop voids are allowed.
- A transition must conserve perceived energy unless the creative intent explicitly calls for a drop or void.

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
