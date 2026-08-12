# Mixr Audio Engineering Rules

## Product principle

For one-song Auto Remix, preserve the song's identity while creating a clearly edited alternate arrangement. The default result should sound like a polished alternate version of the original—not a shuffled highlight reel.

Preservation is a constraint on identity, not a ban on edits. SFX alone do not count as transformation.

## Confidence ladder (cuts vs preservation)

Apply aggressiveness from measured analysis confidence:

1. **Low confidence** (weak section/beat/phrase evidence): default to zero internal cuts. Permit edge trimming and effects that do not require precise structure. Do not invent cuts to hit transformation quotas.
2. **Medium confidence**: prefer continuous placement; allow a small number of phrase-aligned cuts only with strong local evidence and filled transitions.
3. **High confidence** (song ≳ 2.5 minutes with reliable section/beat/phrase analysis): target 3–5 transformation zones across at least three structural regions, including at least two non-SFX transformations. Prefer arrangement changes when repeat evidence supports them. Preserve at least one complete primary hook and one substantial continuous passage. These are planning targets, not unconditional quotas—explain fewer edits.

Never cut merely to increase variety, handoffs, effect count, or SFX density. When uncertain, keep the audio continuous.

## Structural edits

- Begin with the original source order.
- Trim beginnings and endings only with signal-derived evidence.
- Every internal cut requires:
  - a musical reason;
  - sufficient analysis confidence;
  - phrase/downbeat-aligned boundaries;
  - an explicitly filled or layered transition;
  - passing audio-quality validation.

## Transitions

- A crossfade must contain actual temporal overlap.
- Use equal-power gain curves for music crossfades.
- Never fade both adjacent clips toward silence at the same boundary.
- Hard cuts require downbeat alignment and a short anti-click microfade.
- Do not insert silence automatically.
- A transition must conserve perceived energy unless the creative intent explicitly calls for a drop.

## Analysis

- Editing decisions must come from real audio measurements.
- Do not use seeded guesses for section identity, vocals, bass, energy, or downbeats.
- Track confidence for every derived feature.
- Low confidence must reduce editing aggressiveness.
- Never assume source time zero is beat one without evidence.

## Gain and mastering

- Maintain at least 6 dB of mix-bus headroom before SFX.
- Calibrate SFX gains individually.
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
- Tests must cover clipping, true peak, silence, loudness dips, loudness jumps, clicks, overlap behavior, source continuity, and live/export parity.
- Synthetic audio fixtures must be deterministic and copyright-free.
- Quality tests must demonstrate that the previous behavior fails.
- Never replace listening evaluation with metrics, and never replace metrics with listening alone.

## Completion standard

Do not call an audio change complete until:

1. tests pass;
2. an offline render passes quality gates;
3. transition diagnostics are reviewed;
4. the result is auditioned on headphones and speakers;
5. the agent reports evidence rather than saying it "should sound better."
