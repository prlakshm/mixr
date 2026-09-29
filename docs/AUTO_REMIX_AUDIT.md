# Auto Remix quality audit (transitions + "banger" factor)

Date: 2026-09-29 · Branch: `claude/remix-quality-audit-26yyt3`

This audit measured the Auto Remix pipeline on real rendered audio, found the root
causes of weak transitions and flat remixes, and rewrote the analysis → planning →
rendering path. Every claim below comes from a measurement; how to reproduce each
one is listed at the end.

---

## 1. How it was measured

| Tool | What it does |
|---|---|
| **ElevenLabs Music stem separation** (`Scripts/elevenlabs_remix_audit.py`) | Splits a rendered remix into vocals / drums / bass / guitar / piano / other, then measures loudness dips and jumps (BS.1770 short-term), beat-grid breaks and off-grid drum energy on the **drum stem** (trainwrecks / flams), hard vocal cuts on the **vocal stem**, true peak, clipping, clicks, and the per-phrase energy arc. |
| **ElevenLabs Music generation** | A copyright-free corpus of 7 full songs across genres: dance-pop 124, progressive house 126, boom-bap hip-hop 90, R&B 100, pop-punk 140, reggaeton 95, piano ballad 72. |
| **Corpus render harness** (`Scripts/run_corpus_render.sh`) | Runs the real Swift pipeline (analyzer → planner → validator) on decoded audio and renders through `AutoOfflineMixdown`. Songs that get beatmatched are pre-stretched with Rubber Band, so auditions keep their pitch. The **original algorithm** was built from `HEAD` in a separate worktree and rendered on the same inputs. |
| **Join evaluator** | For every join: loudness trough, loudness step, inter-beat anomalies on the percussive part, off-grid onset energy, and beat/downbeat offsets between the two songs inside every overlap. |

Available ElevenLabs scopes on the provided key: music stem separation, audio isolation, and sound generation.
Speech-to-text and forced alignment are **not** enabled (see recommendations).

---

## 2. What was wrong (root causes)

### Analysis
1. **Section identity was guessed from fractions of the song's length.** The "chorus" was the phrase nearest
   28% and 60% of the duration, the bridge 76%. Mashups and remix "drops" were chosen from those guesses, so
   the "bangers" were often verses or breakdowns. On a club-structured fixture the guess had **0% precision**.
2. **The beat grid used an integer BPM, and the first detected beat stood in for beat one.** An integer-BPM
   grid drifts **803 ms** by the end of a 123.4 BPM song. Bar phase (which beat is "1") was never measured.
3. BPM and key came from only the first 90 s of audio.

### Mashup transitions
4. **Every handoff dipped in loudness.** Clips were butt-joined: the outgoing song faded out while the incoming
   one faded in at the same instant. That breaks the repo's own AGENTS.md rules and leaves an audible hole.
   Measured on the corpus, **41 of 48 joins (85%) dipped by more than 3 dB**.
5. **It played like a highlight reel.** Slots were 4–8 bars (≈ 8–15 s), with 7–10 handoffs and 6–7 SFX in
   about 2 minutes, plus automatic pre-drop silences.
6. **Songs weren't beatmatched unless they were close to the anchor.** The target tempo was the anchor's own,
   so 90 + 100 BPM or 124 + 140 BPM left one song unmatched. There was no bass management in overlaps, and
   no loudness matching between songs.
7. **SFX landed off the beat.** Two build SFX were scheduled to end on the same drop. The single-lane SFX track
   then slid the second one to *after* the drop.
8. **Impacts muffled the drop.** A 3 dB duck under every impact softened the very downbeat it was meant to hit.

### One-song remix
9. **There was no real remix.** The song played through almost untouched, with at most one flanger/echo
   segment plus a riser and impact. AGENTS.md asks for 3–5 transformation zones on confident songs.

### Engine consistency
10. **Fades and echo followed each song's native tempo, not the tempo heard.** Live playback and export
    converted fade beats (and the echo delay) at the song's native BPM, while the planner and the offline
    render used the target tempo. On beatmatched clips the fades came out longer or shorter than planned.
11. **Export automation stepped.** Export applied effect changes once per render block with no smoothing,
    while live playback ramped them.

### Your two existing exports (ElevenLabs stem audit)
- **Dua × Weeknd – My Remix (7:03).** The drum stem shows **sustained off-grid drum energy from 4 s to 208 s**
  (off-grid ratio 0.63–0.70; clean songs stay at or below 0.4 and only in short windows). The two songs were
  overlapping without a shared beat grid (≈103 BPM against ≈171/85.5 BPM). There's also a **−11.4 LU loudness
  drop at 3:35**, the true peak reaches **+0.09 dBTP**, and one sample clips.
- **Levitating Remix (2:18).** It ends abruptly: a 13–16 dB hole and a −8.5 LU drop in the last few seconds.

---

## 3. What changed

### Measured structure (`Mixr/Models/SongStructureAnalysis.swift`, new, pure Swift)
- The pipeline:
  - Onsets: FFT spectral flux.
  - Beats: two-pass dynamic-programming tracker, refined to the actual transient (sub-frame accuracy).
  - Tempo: robust constant-tempo fit, reported as a float BPM.
  - Discontinuities: a piecewise grid only when a real discontinuity exists (edits, drift, stitched sections),
    reported as `gridBreaks`.
  - Downbeats: a Viterbi pass over bar positions, using bass-note change, harmonic change, and kick vs backbeat.
  - Sections: bar-level chroma/timbre self-similarity, then phrase-grid segmentation, then repetition groups.
    The chorus or drop is the repeated high-energy group.
- Every value carries a confidence. When downbeat evidence is missing, beat one is never assumed.
- Results on synthetic ground truth:

  | Measure | Result |
  |---|---|
  | Tempo | 123.400 / 118.001 (truth 123.4 / 118.0) |
  | Downbeats | 122 of 128 correct |
  | Grid error at the last bar | 11 ms |
  | Chorus / drop sections | 100% recall and precision on both the pop and the club layouts |

- Heuristic (fraction-of-duration) sections are now **capped below the low-confidence threshold**, so they
  can never drive an edit.

### DJ planner (`AutoRemixPlanner.swift`, rewritten)
- **One song.** Follows AGENTS.md's confidence ladder:
  - **High confidence**, 3–5 zones chosen from:
    - intro trim, hook preview, or a low-pass filtered intro
    - removing a phrase you've already heard, joined at a **bar-matched** jump point (self-similarity ≥ 0.9)
    - a breakdown that opens up through a low-pass sweep
    - an **extended high-pass build**: the build phrase plays a second time with its bass draining, a riser
      ends exactly on the drop downbeat, and an impact lands on it
    - an echo-out ending

    A complete chorus and at least 45 s of continuous song are always kept. Every cut has a masked,
    confident `AutoCutRecord`.
  - **Medium confidence:** the audio stays continuous; only filter automation and edge trims.
  - **Low confidence:** the song is essentially untouched.
- **Mashup (2+ songs):**
  - Even airtime, budgeted in seconds.
  - Each appearance is one continuous run (lead-in phrase into the hook or drop), so the song's own build
    carries into its payoff.
  - Handoffs pick the best recipe that measurement allows:
    - **Beatmatched blend:** 2–8 bars, equal-power, with an **EQ bass swap**. It overlaps the chorus's last
      bars when the material after the chorus is much quieter. The overlap window must not contain a grid
      break in either song.
    - **Filter-build drop:** a high-pass build plus a riser, landing on the incoming song's drop.
    - **Echo slam:** used when tempos can't lock. It lands on the incoming drop when the outgoing song
      ends hot.
    - **Clean 2-bar crossfade:** used for low-confidence songs.
  - The tempo target is the one that lets the most songs lock with the least stretch (90 + 100 meet at 94.9).
  - Each incoming song is locked to the outgoing song's **measured local tempo in the blend window**, the way
    a DJ matches by pitch fader.
  - Songs are loudness-matched, and the groove anchor is picked from drums, bass, and energy (not a piano pulse).

### Shared engine model
- `ClipTransition.filter` adds `bassSwap`, `highPassSweep`, and `lowPassSweep`. It's optional, so saved
  projects decode unchanged.
- The same `AutoTransitionEnvelope` evaluates these filters in live playback, export, and the offline mixdown.
  Both engines gained a second EQ band (high-pass).
- Fade beats and the echo use each clip's **timeline tempo** (native BPM × rate) everywhere.
- Export ramps filters, wet levels, and pitch with the live engine's time constant (50 ms).
- Short echo throws keep full level up to the downbeat. The impact duck is now 1.5 dB.
- SFX that collide on the lane are dropped instead of slid off their downbeat.
- The validator trims an overrunning clip's end instead of sliding its source start, which would break the beat grid.
- A measured BPM is written to tracks that had none, so every engine uses the same tempo.

---

## 4. Evidence: same inputs, old vs new

**Corpus totals (7 one-song remixes + 6 mashups, generated songs):**

| Metric | Old | New |
|---|---|---|
| Joins with a loudness hole > 3 dB | **41 / 48** | **4 / 26** |
| Joins with a loudness jump > 4 LU | 10 | 6 |
| SFX events (all renders) | 45 | 19 |
| Worst true peak | 0.0 dBTP | −0.7 dBTP |
| Worst limiter reduction | 1.9 dB | 0.4 dB |
| Beat offset between songs inside every beatmatched overlap | not phase-aligned (no measured grid) | **0 ms** (beats and downbeats) |

Mashups now run 2:28–3:53 instead of 1:36–2:05, with every appearance lasting 20 s or more.

**Test suites** (`Scripts/run_auto_remix_tests.sh all`): all pass. The new DJ suite has 40+ gates, and each
one is paired with a demonstration that the previous behavior fails it:

| Previous behavior | Result under the new gate |
|---|---|
| Integer-BPM grid | Drifts 803 ms |
| Fraction-of-duration chorus guess | 0% precision on the club fixture |
| Sequential fade join | 17 dB hole |
| Blend without a bass swap | +2 dB of stacked low end |
| Anchor-only tempo target | 100 BPM left unmatched |

### What's still flagged
- **Ballad in a club mashup:** a 72 BPM piano ballad next to 90–95 BPM rap/reggaeton echo-slams with a ≈7 dB
  level change. It's a genuinely incompatible pairing. Better options would be to exclude it or to reserve it
  for a breakdown moment.
- **Hip-hop and R&B downbeats:** confidence is moderate (0.4–0.8) on this corpus. The ladder reduces how
  aggressively those songs get edited, which is what it's for.
- **Filter-build drops read as a dip in metrics.** A high-pass build *is* a deliberate energy dip before a
  drop, so it can register as a hole even when it sounds intended.

---

## 4b. Second round: 16 more generated songs, 20 genres

The pipeline was run end to end on 16 additional generated songs: dance-pop, progressive house,
tech house, drum & bass, dubstep, trap, boom-bap, R&B, afrobeats, reggaeton, pop-punk, indie rock,
synthwave, disco-funk, k-pop and UK garage. That gave 16 one-song remixes and 11 mashups
(8 pairs, 2 trios, 1 four-song mix), 27 renders in all.

**Failures found and fixed**

| Problem found | Fix |
|---|---|
| Trap at 148 BPM read as 98.7 (a 3:2 error) | Among the winning tempo and its 3:2 / 4:3 relatives, pick the one whose rhythm repeats at every beat multiple (1–8 beats). Trap now reads 148.00. |
| A 352 ms off-beat blend (R&B with an ambiguous beat) | Beat confidence now gates every confidence tier and every beatmatched blend. |
| A cut with downbeat confidence 0.06 left a 6 dB hole | Cuts, hook previews and repeated builds require confident downbeats. |
| Echo slams landing on quiet intros (5–8 dB holes) | The incoming song lands on its energy-matched phrase or its drop. |
| Three echo slams in a row | Pairs whose tempos can't lock alternate slams with high-pass build drops (no overlap, so no beatmatch needed). |
| Lopsided airtime (63/37; four-song mix 54/27/11/8) | Landing points are chosen first, then seconds are balanced per song. Hooks must be substantial, and a song heard once gets its strongest hook. |
| Medium-confidence remixes did nothing | Continuous effect zones are now allowed at medium confidence (no cuts). |

**Result on the new batch:** 0 crashes, 0 misaligned blends, loudness holes at 3 of 45 joins,
two-song mashups within 43/57 airtime, four-song mix 35/22/22/22.

**Still open**

| Problem | Details |
|---|---|
| Weak downbeat evidence on trap, afrobeats, k-pop and dubstep (confidence 0.00–0.25) | The confidence ladder correctly holds these songs back. Fixing it needs the drum-stem model. |
| Drum & bass reads 117.3 instead of the requested 176 | The recording itself is ambiguous: librosa also reads 117.5. Needs a listen. |
| Songs shorter than ~2.5 min only get the medium treatment | This is what AGENTS.md asks for. |

**Demucs (official `htdemucs`, checksum-verified) on all 23 songs**
- Speed: about 2 min of CPU per 3.7-min song on this 4-core container.
- **Vocal clashes in mashup blends:** both songs sing at once during only **7%** of 62 s of blended
  overlap. 7 of 8 blends are at 0–4%. The exception (48%) is a tech-house song whose vocals the
  on-device detector misses.
- **On-device vocal detector vs Demucs vocals:** pooled bar-level AUC **0.75** (0.5 = coin flip),
  ranging from 0.17 to 0.96 per song.
- **Small trained vocal models, tested leave-one-song-out:**

  | Model | Pooled AUC |
  |---|---|
  | Existing features | 0.76 |
  | Plus syllable-rate, harmonic-peakiness and midrange-flux cues | 0.76 |
  | 40-band mel spectrum | 0.68 |

  None beats the current detector enough to ship. With 23 songs, reliable vocal detection needs
  the separated vocal track itself (Demucs on the phone) or far more training songs.

## 5. How to make it better (prioritized)

1. **Listen before shipping.** I could not audition anything on headphones or speakers, and the edits to
   `MixrPlaybackEngine` / `MixrExportRenderer` were **not compiled for iOS** here (the Linux toolchain only
   builds the pure-Swift pipeline). Build in Xcode, then export a remix and compare it with the offline render.
   This is steps 4–5 of the AGENTS.md completion standard.
2. **Stems unlock true mashups.** Full-mix mashups can only alternate or blend. A real "10/10" mashup (vocal of
   A over the instrumental of B) needs stems. The ElevenLabs stem separation on this key works (6 stems,
   about a minute per song). Route it through **your own backend proxy**; never ship the API key in the app.
   Then feed three things into `SongSignalFeatures`:
   - the vocal activity curve (the on-device vocal proxy is weak)
   - the drum stem, for downbeats
   - the bass stem, for bass-swap timing

   Uploading user audio to a third party needs an opt-in toggle and a `PRIVACY.md` update.
3. **Enable ElevenLabs speech-to-text** on the key. Word timestamps give lyric-repetition chorus detection (the
   most reliable chorus cue for rap and rock, where energy is flat) and exact vocal-phrase ends for cut points.
4. **Better SFX.** The bundled risers and impacts are procedural noise. ElevenLabs sound generation works on this
   key. Generate candidates, audition them, and replace the assets you like.
5. **Harmonic mixing.** Blends currently shorten to 2–4 bars on key clashes. A ±1–2 semitone correction on the
   incoming song during the blend would allow longer layered blends.
6. **Surface the automation in the UI.** Filter automation isn't visible in the clip editor yet; show a small
   "Bass swap" / "HP build" chip on the edge.
7. **Performance.** Analysis is about 0.6 s per 3.6-minute song in an optimized build. Debug builds of the pure
   Swift FFT will be much slower; consider Accelerate on device.

---

## 6. Reproduce

```bash
# test suites (Linux: swiftc on PATH, or macOS)
Scripts/run_auto_remix_tests.sh all        # pipeline + render + dj

# render a remix / mashup from real audio (job format in DevTests/AutoRemixCorpusRender.swift)
Scripts/run_corpus_render.sh job.json

# stem-based audit of any mix (needs ELEVENLABS_API_KEY with music stem separation)
Scripts/elevenlabs_remix_audit.py mix.m4a --json report.json
```
