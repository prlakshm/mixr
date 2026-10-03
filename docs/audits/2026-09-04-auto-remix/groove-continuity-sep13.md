# Groove continuity correction — September 13

The owner rejected the r3 excerpt: a pause at 0:11 and a quiet ending. The half-second RMS at 11 seconds is about 15 dB below the previous half-second, with almost no low-frequency energy. A nonzero coverage interval did not provide an audible groove. Do not label this intentional or use the silence gate as approval.

## Decision before implementation

Protect the existing complete vocal passages. Evaluate the instrumental source separately from the voice. A busy vocal can conceal an empty backing during selection. Select stable instrumental islands on measured source bars, judging their weakest bars as well as average energy; never move the bed to an arbitrary louder beat. Use a continuous instrumental lead-in into the selected island when the outgoing backing loses its groove. Replace its earlier low-end owner, keeping the source clock continuous into the drop. Do not fill missing music with more risers or limiter gain.

Musical timing and effect density are preferences, subordinate to phrase integrity and musical continuity under the owner's September 13 authorization. The existing numerical acceptance contract remains unchanged. A later handoff is acceptable when it earns its place musically; a mandatory quiet runway is not.

Implement in bounded steps: measure backing stems once per profile; test stable island selection and unavailable-evidence fallbacks; test the prepared bed with independent rhythmic PCM including an outgoing dropout; retain the lyric/pickup controls; render the local reference and additional combinations; compare momentary and short-term loudness across the handoff and following phrase. Keep failed candidates.

## Research and installed guidance

- [Crossfader's worked transition](https://wearecrossfader.co.uk/blog/creative-trick-for-genre-transitions-128bpm-150bpm/) demonstrates introducing musical content before transferring bass ownership. The relevant principle is a continuous low-end handoff; its exact genre trick is not a universal recipe.
- [Transitions DJ's mixing manual](https://www.transitions.dj/manual/pgs/mixing.html) discusses beat phase, phrase placement and choosing compatible passages. Timing and content selection both matter.
- Installed [Audio Mixing and Mastering Direction](https://github.com/calesthio/generative-media-skills/tree/8c85352d5d75d4dcbe58480bd138e37b9742bab1/skills/production/audio-craft/audio-mixing-mastering) at the pinned revision. At review, the repository had 172 stars and the skills directory reported 104 installs. Reviewed its instructions and read-only measurement helper. It supplies general balance/QA guidance, not a DJ engine or listening capability. Its foreground hierarchy must be set to musical performance for Mixr; speech/video presets are not club-mix defaults.
- Rejected REAPER-only and Suno-only workflow skills for this implementation because their required applications/services were unrelated. No cloud audio calls were made.

This is a development correction. Neither metrics nor installed skills establish universal musical quality or headphone/speaker approval.

## Evaluation scope after the compute-budget reminder

Use one reference render per necessary hypothesis, then reuse the compiled renderer for a small representative set: a solo, a tempo-incompatible duo, a three-song mix and a five-song mix. Do not rerun all31 subsets unless these checks expose a reason. One bounded read-only lower-cost subagent was used; no cloud audio calls.

The first complete render selected a backing whose lead-in contained another dropout. It failed the new check and was retained. Joint scoring now evaluates the lead-in plus the following island and can use a four-bar instrumental loop; vocal identity stays remain complete. This is not one-beat grain repetition. Later loops must retain the same backing gain as the first.

The r3 candidate reduced the worst approach deficit from28.45 to5.20LU and brought the following passage change from-2.44 to-1.78LU. Its approach still failed the frozen3LU gate. The next change uses a bounded backing-level rise based on the measured outgoing vocal+instrumental reference. It preserves that gain through the drop so the following passage does not sag again. Optional nonzero fade endpoints express this level ride through the shared live/export envelope; old saved fades retain their original behavior.

## Owner feedback and revised bounded plan

The owner rejected the September13 preview: lyrics are too quiet and the middle sounds like background music or an intro/outro. Interior passages should stay upbeat; removing a numerical trough cannot outweigh vocal presence and musical drive. Retain the rejected candidate as a negative control.

The applied stem map supports the critique. A local voiced-window power comparison puts the incoming vocal about4.54dB below its native vocal/backing relationship; the outgoing retained line loses about4.70dB. These are dry-stem diagnostic estimates, not listening scores. The bounded backing boost omitted a corresponding foreground-balance check.

Next: preserve the measured phrase exit and remove covered duplicate tails before generic overlap repairs; add a synthetic rendered vocal/backing control; restore each foreground phrase's measured native contrast against the selected backing with bounded gain and smooth continuation edges. Missing stem evidence must not trigger a guessed boost. Keep rhythm present, preserve lyric/pickup clocks, and avoid adding effects to simulate energy. Compile once for the final candidate and reuse that renderer for representative checks. Stop tuning against the trough metric alone. No cloud calls and no broad combination sweep.

## September 13 foreground candidate checkpoint

The foreground correction measures voiced windows against that phrase's original backing and compares them with the selected complete instrumental owner. It can raise the lead by at most 6 dB, subject to the existing clip-gain ceiling; continuation edges use the shared smooth gain envelope. Missing, truncated or unequal-stem evidence is skipped. It changes neither lyric clocks nor the rhythmic bed. This is a dry-stem contrast estimate, not a new perceptual approval gate.

Validation: 44 focused assertions pass, including an orthogonal-PCM negative control with a lead buried by 6.02 dB and a corrected contrast within 0.1 dB. Components are measured in the same mastered mix; separately mastered components would invalidate this test. All 13 runner tests pass, and the cached app build succeeds. The earlier broader core run belongs to the earlier source revision and is not claimed as fresh coverage of this checkpoint.

The actual pair render is `Exports/Audit-2026-09-04/foreground-sep13/crate-0-1.m4a`. The incoming gain rises from 2.936 to 4.321 (about 3.36 dB); its source entrance and pickup remain unchanged. The outgoing measured exit remains source73.24, before the next word. The fully covered duplicate tail near mix87.56 is removed.

| Evidence | Owner-rejected r3 | Foreground candidate |
|---|---:|---:|
| Worst approach deficit | 28.45 LU | 3.64 LU — fails 3 LU limit |
| Following-passage change | −2.44 LU | −1.23 LU — passes 2 LU limit |
| Delivered true peak | −1.248 dBTP | −1.259 dBTP |
| Clipped samples | 0 | 0 |

The candidate's remaining trough is mix52.483–52.683, about excerpt0:09.2. The software limiter and mapped internal-silence gates pass. Delivery is −13.97 LUFS. No numerical acceptance limits were changed. Do not boost the backing again merely to erase this residual.

Reused the same compiled renderer for a midtempo solo, three-input and five-input cases. All rendered and passed encoded peak/limiter checks. The larger input cases retain only the compatible pair, so they prove degradation/input handling, not three/five distinct vocal arrangements. Added one 128-BPM solo for a different real arrangement. This bounded set does not establish quality for arbitrary music. No cloud calls, additional agents or full31-subset sweep were used for the foreground correction.

The 26-second listening candidate is `Exports/Audit-2026-09-04/listening-foreground-sep13/revised.wav`, with the handoff at0:12. Comparison excerpts use identical fixed −18 LUFS normalization, without additional compression. The owner rejected the previous groove preview; this new candidate has no headphone/speaker or musical approval yet.

Next decisions, in order: obtain the owner's judgment of vocal prominence and upbeat interior energy; address the short residual only with musical evidence; audit the later supporting copies near mix92 seconds and the full interior energy arc; then broaden held-out musical coverage. Later overlapping support outside this excerpt remains unresolved. Do not call the full algorithm or release complete from the focused results.

Detailed evidence: `implementation/foreground-sep13-source-identity.json`, `implementation/groove-sep13-foreground-tests.log`, `implementation/foreground-sep13-python.log`, `implementation/foreground-sep13-xcode.log`, and the render folders' manifests, decoded metrics and `REVIEW_STATUS.json`.

## Final-pass decision after the second owner review

The owner accepts the brief dip/transition and rejects the prolonged quiet and incoming section choice. Preserve that accepted transition; do not keep raising the backing to chase the trough meter. This is partial listening acceptance, not approval of the complete candidate. The numerical contract remains unchanged.

Source evidence: the previous incoming clip started at59.465; the title word is at60.26, near the chorus ending. The measured vocal section begins at42.6 on an independently measured source downbeat. Its first lyric onset is42.94. The old fallback used a title-word pickup as though it established a complete chorus entrance. A preserved consonant is not proof of a complete phrase.

The selector now prefers the complete measured vocal section containing a selected island or title hint. Weak/unmeasured section evidence cannot override a verified full phrase; the isolated title-word fallback is removed. Measured guest sections determine their slot length, instead of being cut to a fixed eight bars or padded to16 with a quieter verse. Measured hooks are protected from preemptive atmospheric head/tail treatment. One reused low-cost agent reviewed downstream duration and tail handling; no cloud audio calls.

The broader core suite passes all five groups (687 assertions). The focused suite passes47 assertions, including negative controls for a title near the chorus ending. These results precede the final real-audio render, which remains to be checked and heard.

## Final-pass result — September 14

The actual app-DSP render starts the incoming vocal at source42.35 so its pickup reaches the independently measured chorus downbeat42.60 exactly at Drop1. The previous candidate began at59.465, near the60.26 title word. The selected section now covers the measured42.60–65.82 vocal island and completes the line at its exit instead of padding the slot with the quieter following verse. The outgoing retained line still ends at source73.24. The first drop stays at mix55.300; Drop2 moves from129.032 to112.903 because the quiet padding was removed.

The new sustained passage has median short-window loudness −9.93LU versus −11.26LU in the rejected foreground candidate. Its longest run more than3LU below its own passage median is0.30s rather than0.40s. The following-passage change improves to−0.44LU and passes the frozen2LU limit. The brief approach remains3.70LU below reference and fails the frozen3LU numerical limit; the owner explicitly accepted that brief transition, so both facts remain recorded. No threshold was changed.

Delivery measures−13.75LUFS, −1.20dBTP, zero clipped samples, and passes the software-limiter and mapped-source-silence checks. One source-supported0.70s breath near mix1:45 remains in the full arrangement and is documented rather than boosted. The final42s listening excerpt starts12s before Drop1 and continues through the complete incoming chorus.

Verification is fresh for this source:47 focused assertions,687 broader core assertions,44 manifest-integrity assertions, and13 Python runner tests pass. The actual app-DSP render succeeds. Xcode's final application packaging remains inconclusive because `actool` lost its CoreSimulatorService connection while compiling the unchanged asset catalog; a simulator and device build both report that infrastructure error and no Swift source error. The active and proposed remix skills match exactly. No cloud audio requests or broad31-combination sweep were used.

The implementation is the final code pass requested by the owner. Release approval still requires the owner's headphone/speaker audition of `Exports/Audit-2026-09-04/final-section-sep13/listening-final.wav` and live/export parity evidence. The candidate must not be represented as universally good for arbitrary music from this local crate alone.
