# Auto Remix audit and repair plan

Prepared September 4, 2026. Revised September 5, 2026. Status: initial audit performed; rules and acceptance contract revised before implementation; algorithm repair and listening approval remain open.

## Recommendation

Repair tempo alignment, phrase selection, and the release checks before tuning fades or adding effects. Preserve Mixr's club-rewrite identity: a recognizable first hook, purposeful builds and drops, one kick/bass owner, and a different musical idea on Drop 2. Select a transition because the two musical passages support it.

This pass inspected the current working tree, researched DJ practice and audience preferences, measured the eight latest local listening exports, ran the existing five test harnesses, and generated two fresh exports through the app's AVFoundation renderer. It does **not** establish that the remixes sound professional. The available computer-control tool provides interface state and screenshots, not a system-audio feed. Playback was opened in QuickTime; no headphone or speaker listening verdict is claimed.

## Evidence baseline

- Code: `988fd949fbfac87a58ae4b0c67a46e47b7f0ee87`, **plus pre-existing uncommitted changes** in `AutoRemixPlan.swift`, `AutoRemixValidator.swift`, and `AutoJoinEngineTests.swift`. Those changes were preserved. A commit hash alone does not identify this baseline.
- Latest existing listening set found: `/Users/pranavi/Documents/Mixr/Bounces/LISTEN`, eight M4A exports dated August 22. The older repository exports are dated July 18.
- The surrounding Bounces directory's `LAST_SHA` is `01147a1399a750dd347c5cfdbbd99927c1f1ca09`; the eight M4As have no individual manifests, so that marker cannot prove their provenance.
- Fresh working-tree renders: Oops × Baby and Paramore × t.A.T.u., seed `20260815`, real bundled SFX, `MixrExportRenderer`, stereo AAC at 44.1 kHz. The diagnostic harness was copied to an isolated temporary folder and its output path changed; original exports and source audio were preserved.
- Existing tests: **740 PASS assertions, 0 FAIL**, across pipeline 50, rendered-PCM 88, club 547, join 31, golden 24. All five harnesses completed successfully.
- Fresh render harness: `LISTEN_RENDERS_DONE failures=0`.
- Compact measurement evidence: [evidence.json](2026-09-04-auto-remix/evidence.json). Raw logs and playable fresh renders are retained in `/tmp/mixr-audit-20260904/current`; these artifacts are now preserved in the ignored local Exports/Audit-2026-09-04 archive with hashes in baseline-archive.json.

The compiler initially could not write its default module cache; moving that cache to `/tmp` resolved it. The sandboxed AVFoundation decoder failed; the approved retry with macOS audio-service access completed. The legacy smoothness script printed valid JSON before failing to write its hard-coded report destination. Its printed results were retained and its gate function rechecked read-only; fresh-render measurements used an imported analysis function with an explicit temporary report path.

## Playable baseline excerpts

These are fresh current-code excerpts, not repaired versions.

- [Oops × Baby, original 48–88 seconds](/Users/pranavi/Documents/GitHub/mixr/Exports/Audit-2026-09-04/Oops-Baby-current-48s-88s.wav): title dip is approximately 6.45 seconds into this excerpt; Drop 1 is approximately 29.51 seconds in.
- [Paramore × t.A.T.u., original 48–74 seconds](/Users/pranavi/Documents/GitHub/mixr/Exports/Audit-2026-09-04/Paramore-tatu-current-48s-74s.wav): Drop 1 is approximately 8.67 seconds into this excerpt.

## Findings, in repair order

### 1. A tempo exception can approve a vocal that does not match the bed — confirmed logic defect

[`AutoClubTempo.swift:63`](/Users/pranavi/Documents/GitHub/mixr/Mixr/Models/AutoClubTempo.swift:63) clamps a midtempo lift into 1.08–1.12 even when the requested target cannot be reached. [`AutoCompatibility.swift:234`](/Users/pranavi/Documents/GitHub/mixr/Mixr/Models/AutoCompatibility.swift:234) treats a non-null lift as sufficient for full-hook tempo eligibility. The planner also uses the presence of a lift to mark a fit as aligned.

A fresh compiled probe returned `ratio=1.12` for **90 → 144 BPM**. The vocal's resulting tempo is **100.8 BPM**, not 144; neither a half-time nor double-time relationship repairs that mismatch. Separately, the 93/95 BPM pair chooses 105.28 BPM and reports a 1.132043 vocal ratio, exceeding the 12% per-vocal cap. Its later hook gate can clamp that ratio to 1.12, introducing a different tempo inconsistency.

**Repair:** compute the intersection of attainable tempo ranges for the chosen bed and each full-hook guest; use one consistent source-to-mix mapping everywhere. Half/double-time must carry an explicit beat-count mapping and actual corrective rate. A capped rate that misses the target is a rejection, not an aligned result. Re-run eligibility after the final target is selected. An incompatible guest becomes a justified cameo or is skipped.

**Regression:** 90/144 must refuse a sustained overlay; 72/144 may use verified double-time at native playback speed; 93/95 must meet the cap for both tracks and map both to the same realized tempo. Check pulse phase over 16 bars of rendered PCM, not only ratio fields. This defect strongly suggests rhythmic mismatch; it was not diagnosed by hearing the output.

### 2. Drop 1 still waits 34 bars — confirmed on fresh output plans

| Fresh case | Target tempo | Drop 1 | Bars elapsed before Drop 1 | First Deck A title probe |
|---|---:|---:|---:|---:|
| Oops × Baby | 105.28 BPM | 77.508 s | 34 | 54.71 s |
| Paramore × t.A.T.u. | 144 BPM | 56.667 s | 34 | 26.67 s |

These are **34 completed bars**, i.e. the entrance to bar 35 with one-based numbering. That exceeds the skill's 16–24-bar target. The golden tier does not impose that target on these rendered cases. A downbeat is also not sufficient evidence of an eight-bar phrase boundary; source phrase annotations must establish the appropriate origin.

**Repair:** work backward from the earliest viable complete hook and incoming phrase. Allocate intro + complete A hook + transition before committing the timeline. Protect real pickup syllables and sustained endings. If reliable musical evidence makes the target impossible, report a specific exception rather than silently adding runway or shortening the hook. Do not solve the timing constraint by chopping the lyric.

### 3. The fresh Oops title entrance contains a measurable dip that a broad exemption can hide

The fresh Oops × Baby render has a **0.40-second deep-hole flag at 54.45 s**, with a minimum 29.5 dB below its reference and 26.9 dB below local context. Its title probe starts at 54.71 s. This is a metered candidate for audition, not yet a declaration that a natural breath is defective.

[`AutoListenLoop.swift:124`](/Users/pranavi/Documents/GitHub/mixr/Mixr/Models/AutoListenLoop.swift:124) exempts entire labeled join windows and the first five seconds of long dominant vocal stems from a hole rule. The title exemption begins 0.3 seconds before its placement, covering this event. Both fresh manifests show clean pre-apply contract scores.

**Repair:** compare a suspected gap against the source passage and actual audible overlap. Exempt only a bounded, explicitly justified breath, breakdown, or permitted void. A label must not excuse arbitrary silence inside its span. Evaluate every song handoff, including title entrances and Drop 2.

The existing smoothness checker also flags several terminal effect tails as dead air. Keep these separate from internal transition defects: the five older-export failures all occur near the ending, while intermediate dips around 27–34 s, 74–80 s, and 96 s remain audition candidates. Do not lower the global threshold to silence these reports.

### 4. The golden and release checks can pass without testing the important musical behavior

- [`AutoRemixGoldenTests.swift:115`](../../DevTests/AutoRemixGoldenTests.swift) generates amplitude-shaped **440 Hz sine waves**. They test some gain/timing math but contain no sung syllables, independent drum patterns, chord clashes, or recognizability.
- The portable renderer explicitly omits the real TimePitch and effect chain. The app's pre-apply loop uses that approximation. It cannot certify the real sweep, delay tail, or vocal stretch quality.
- A vocal ride-in assertion at line 467 is conditional on finding one-beat supporting placements (still named `grains`). With no matching placements it can disappear rather than fail. Replace optional test execution with required case construction and explicit presence checks.
- `join_auditor.py` audits sweep troughs and the first expected token. The manifest writer does not populate `expectedTokens` or `vocalSidecar` on this render path. **Both fresh cases returned `PASS ... whisper=inconclusive`.** This was reproduced, not inferred.
- `verify_all.sh` checks for printed `FAIL` lines rather than reliably preserving the Swift process's exit status; its transition, smoothness, and Whisper sections do not all feed the final failure accumulator. It does not invoke the newer JoinAuditor. A compile failure or failed optional stage can therefore be omitted from the final verdict.
- The plan fingerprint excludes source starts, song identity, tempo ratios, effects, fade details, and stem identities. Different-sounding plans can share a fingerprint.

**Repair:** three explicit outcomes per required gate: pass, fail, inconclusive. Only pass satisfies release readiness. Check process exits and expected case counts; assert every required gate actually ran. Canonicalize the complete rendered plan and hash the working-tree patch, source audio, stems, sidecars, settings, renderer, and final audio. Include token timestamps and annotation provenance. These verification scripts currently live outside the repository; bring maintained versions under `Scripts/` so the algorithm and its judges evolve together.

### 5. Transition shape is fragmented across planning, repair, and DSP — confirmed architecture risk

The sweep in `AutoJoinEngine.appendPivotWallpaperLoop` uses per-bar segments with blur targets around 30 then 46 and different gains. `ClipEffectDSP` implements blur as a **low-pass**, despite repeated high-pass/kick-removal language in the skill. `MixrExportRenderer` updates parameters once per 1,024-frame block (about 23 ms). The application code assigns filter and several effect targets directly; it does not establish a sample-continuous trajectory for all parameters.

The existing uncommitted lyric repair extends phrases and layers tails over later material. That can preserve a final word while introducing competing vocals or lows; it needs stem-aware PCM coverage, not only a placement-length assertion. Later repair passes can also change earlier overlap decisions.

**Repair:** retain one transition contract containing source phrase boundaries, pickup and tail spans, tempo mapping, vocal/kick/bass ownership, real overlap, gain/filter trajectories, SFX, and valid exceptions. Choose a legal contract before arranging clips. Validate the final applied result after every repair round. Share the automation representation across live and export paths and verify actual rendered behavior. Preserve delay/reverb state across continuous segments.

This evidence identifies risks, not proof of audible clicks. Measure seam transients against source transients and audition the excerpts before choosing ramp lengths.

### 6. The remix skill gives contradictory taste and engineering guidance

The August 20 sweep replacement is followed by multiple active-looking commands to restore the retired repeated grain. Tempo guidance demands midtempo → 126 even though the root rules and current implementation require a gentle lift. Other passages disagree about incoming versus outgoing tokens, low-pass versus high-pass, and how the outgoing lead should leave.

**Repair:** replace the historical accumulation with one current specification. Keep retired techniques in a separate history file, outside active instructions. The reviewable replacement is [dj-remix-planning.proposed.md](2026-09-04-auto-remix/dj-remix-planning.proposed.md). The revised copy is now installed as the governing specification before Phase B; it is not listening approval.

## What online research supports

1. **Placement and phrase alignment matter more than a universally smooth fade.** Native Instruments describes matching musical phrases, appropriate transition types, and bass swaps; its live-remix guidance also preserves the source's signature identity. Apply that as phrase completion, one low-end owner, and a recognizable hook. This is practitioner guidance, not a numerical listener-preference study. [Native Instruments, Sara Simms](https://blog.native-instruments.com/dj-tips/).
2. **Transition choice depends on arrangement.** Digital DJ Tips emphasizes understanding sections and finishing blends before competing bass, vocals, or melodies arrive. That supports choosing a transition from the passages' roles rather than assigning the same effect package everywhere. [Digital DJ Tips](https://www.digitaldjtips.com/how-pro-djs-know-where-to-transition-plus-a-big-cheat/).
3. **Audience taste is divided.** One DJ discussion criticizes constant short switches and repetitive effects; another includes both enthusiasm for mashups and disappointment when familiar instrumentals cue an expected lyric that never comes. Treat these as qualitative anecdotes. They support testing groove duration, expectation/payoff, and hook clarity; they do not prove that all audiences want fewer effects or long tracks. [DJ discussion: overuse](https://www.reddit.com/r/DJs/comments/1beo2on), [DJ discussion: mashups](https://www.reddit.com/r/DJs/comments/1cjk7c7).
4. **Automatic transitions need listening evaluation.** Research on learning DJ transitions uses EQ and fader control and reports a listening test against baselines. The useful lesson here is to compare actual audio, not to replace Mixr with that research model. [Chen et al., ICASSP 2022](https://arxiv.org/abs/2110.06525).

The synthesis for Mixr is **familiar hook + new club context + a convincing buildup and release**. The audience should be able to follow and dance through the change. Festival energy remains the product direction; effect count alone is not evidence of quality.

## Execution plan

### Phase 0 — Freeze governing behavior and baseline

- [x] Install the reconciled remix skill and root instructions before algorithm edits: continuous sweep, no retired repeated grains, blur correctly identified as low-pass, adaptable intro and Drop 1 after 16–24 elapsed bars.
- [x] Freeze [acceptance-contract.json](2026-09-04-auto-remix/acceptance-contract.json): beat drift, live/export timing, local loudness, limiter reduction, peak/headroom and bounded silence exceptions. These are explicit engineering criteria, not retrospective fits to a candidate.
- [x] Separate sustained aligned hooks from bounded native-speed chops.
- [x] Specify independently annotated mandatory early-drop and separate legitimate late-drop cases; planner explanations cannot satisfy the mandatory early-drop case.
- [x] Add high-confidence transformation, Drop 2 idea, guest rotation, and low-confidence continuity/energy controls. Fixtures remain to be implemented.
- [x] Archive baseline audio privately with hashes and retain original working-tree patch; never commit commercial audio.

### Phase A — Repair the test runner and judges

- [ ] Version the current baseline, complete manifests, meters, and generated excerpts without committing copyrighted music.
- [ ] Add failing harness tests for missing manifests/tokens, skipped assertions, unavailable decoders, empty case sets, and nonzero subprocess exits.
- [ ] Add negative controls: clipped lyric, beat drift, an internal silence, double-kick overlap, filter step, buried first syllable. Judges must detect deliberately broken audio before their success verdict is trusted.
- [ ] Separate structural, signal, model-critique, and human-listening outcomes. Never convert unavailable listening into pass.

### Phase B — Correct timing and musical eligibility

- [ ] Fix the tempo intersection and all consumers of `clubHouseLiftRatio`; prove 90/144 rejection and 93/95 cap/alignment behavior in both plan and PCM tests.
- [ ] Replace the two song-name-driven positive goldens with content-based cases. Keep the same real songs as local regressions, including incompatible-pair expectations.
- [ ] Add independently annotated phrase starts/ends and vocal pickups. Build the earliest legal complete-hook path to Drop 1; mandatory independent early-drop fixture must meet 16–24 bars without exceptions. Test independently supported long-hook exceptions separately.
- [ ] Preserve the final words by choosing a better join point; permit a bounded tail only where lead and low-end ownership remain valid.

Tempo rendering regressions precede phrase-selection changes. Finish and inspect each failing-control/repaired-PCM pair before proceeding.

### Phase C — Address demonstrated rendering defects

- [ ] Consolidate transition ownership and trajectories in `AutoJoinEngine`/plan contracts; audit `AutoRemixApplier`, `AutoTransitionEnvelope`, `ClipEffectDSP`, live playback, and `MixrExportRenderer` together.
- [ ] Replace blanket quiet-window exemptions with source-aware, bounded exceptions. Reproduce and resolve the 54.45-second title-entrance candidate before declaring it fixed.
- [ ] Test 128/256/1,024-frame rendering and live/export event alignment. Require no parameter steps caused by the block size, real temporal overlap where requested, clean pickup attacks, and preserved tails.
- [ ] Measure unmastered song/SFX buses, limiter reduction distribution, stereo and mono behavior, encoded true peak, and local loudness through every transition. Keep the existing 6 dB headroom and approximately −1 dBTP rules; do not cure errors with heavier limiting.

### Phase D — Calibrate musical judgment and lock the new golden set

- [ ] Use [golden-regression-proposal.json](2026-09-04-auto-remix/golden-regression-proposal.json) as the case inventory. Build deterministic copyright-free fixtures with independent drum, bass, harmony, and vocal-like event tracks; keep real user-owned audio local.
- [ ] Run all five solos and all 26 combinations of 2–5 songs in the existing five-song crate. Include missing/partial stems, uncertain structure, drift, off-zero downbeats, long sustained syllables, and key/tempo rejection cases. Add held-out tracks outside the original five before claiming generalization.
- [ ] Compare baseline and candidate in randomized order with loudness-matched excerpts, then hear the full unnormalized mix for energy progression. Evaluate one change at a time.
- [ ] Score phrase placement, beat lock, hook integrity, low-end clarity, transition continuity, buildup/payoff, and musical novelty on 1–5 anchored scales. Record reviewer, playback device, timestamps, and reasons. Proposed acceptance: all critical dimensions at least 4, no hard failures, and a clear preference for the candidate on the changed joins; calibrate these criteria with the owner before freezing them.
- [ ] Audition on headphones and speakers. Inspect source and isolated stems whenever a meter or reviewer flags a passage. A musical breath can pass with evidence; an unexplained hole cannot.
- [ ] Promote executable golden results only after evidence supports them; governing rules were frozen in Phase 0. Run each new test against the old behavior to prove it fails for the intended reason, then verify the repair. Broad listening remains the final release check.

## Requested audio-understanding MCP

An MCP is a tool connection, not hearing by itself. A small connector can read a selected export/excerpt, send it to an audio-capable model, and return timestamped observations and uncertainty. Codex supports local and remote MCP servers. Gemini documents audio questions, music-related emotion analysis, and timestamped segment analysis; OpenAI also documents audio-input models. Neither documentation establishes professional DJ judging accuracy. [MCP support](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Gemini audio](https://ai.google.dev/gemini-api/docs/audio), [OpenAI audio](https://developers.openai.com/api/docs/guides/audio).

Installed tool: `critique_transition(audio_path, start_seconds, end_seconds, upload_authorized=false)`, with a fixed neutral DJ rubric; evaluate anonymous references through separate calls. Its response should contain the exact audio hash, model/version, timestamped observation, confidence and uncertainty, and an explicit inconclusive state. Use one excerpt containing roughly eight bars before and after the join plus a whole-mix pass for arrangement. Give the model audio and a neutral rubric before revealing which version is the candidate. Validate timing claims against signal/lyric annotations.

Before relying on it, test repeated evaluations and blinded positive/negative controls. Compare its preferences with the owner's ratings. Reject inconsistent or ungrounded recommendations. Local meters remain deterministic; model critique is advisory; headphone/speaker sign-off stays human. A cloud connector needs a chosen provider, API credentials, and explicit scope for transmitting excerpts. The requested connector is now installed; its local checks and live API requests passed. Two authorized audio excerpts were evaluated on September 8, but the blinded dropout control failed: the model misclassified a verified injected hole as intentional. Model critique remains advisory. See [installation and remaining setup](2026-09-04-auto-remix/audio-connector-installation.md).

[Audio Sonic MCP](https://github.com/ripunjay-kashyap/audio-sonic-mcp) is an existing project focused on tempo/key/vocal features and sound descriptors. Its local-file CLI could be evaluated as additional analysis; it has not been installed or verified here as a perceptual DJ judge.

## Alternatives and completion boundary

- **Recommended: repair contracts and evaluation, then tune a small transition repertoire.** Fits the existing Swift engine and yields testable fixes with clear causes.
- **Tune fades and levels only.** Smallest patch, but cannot fix incompatible tempos, wrong musical placement, or false-pass tests.
- **Replace planning with a learned DJ model.** Larger data, licensing, integration, latency, and evaluation project; not justified before fixing demonstrated correctness defects.

The intended next implementation can be done as one coordinated effort, but a promise of a one-shot professional result would be unsupported. Completion requires passing tests, actual export quality gates, reviewed transition diagnostics, and headphone/speaker audition. This revision freezes the rules and regression specification before production changes. The case inventory is still a specification, not executable or passing golden tests. Installation verification is recorded separately; no professional-sounding algorithm or human audition is claimed.
