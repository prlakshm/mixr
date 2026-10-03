# General deterministic remix implementation

**Goal:** A measured, repeatable club arrangement for one song or a compatible set of two to five songs, with defined input validation and explicit degradation when evidence or isolation is insufficient.

**Current status (September 12):** Local implementation and technical regression work continue. The owner rejected the latest rendered candidate because it shortened lyrics and rushed the following handoff. No professional-quality, headphone, or speaker approval has been earned.

**Authority:** The September 12 owner feedback supersedes any interpretation of September 9 that deletes the deliberate outgoing continuation. Preserve it, delay the following song, and retain its first consonant. The numerical acceptance contract is unchanged. The active remix skill and its companion proposal now contain this clarification.

## Design

Keep the Swift analysis → candidate selection → arrangement → validation → shared render pipeline. Musical decisions use measured evidence and remain deterministic. Display titles cannot privilege a reference pair. Structural confidence, actual tempo compatibility, and isolation are independent gates. Unknown structure preserves continuous source order with an energy curve. Incompatible guests are skipped or restricted rather than forced into full overlays.

The applied timeline must preserve the validated decision. It must not add an effects package or manufacture a diagnostic claim. Source time, timeline time, tempo ratio and downstream events must remain synchronized when a handoff changes.

## Implemented and exercised before the latest listening correction

- Defined malformed-input, duplicate-track, unknown-tempo and large-timeline outcomes: 31 input checks.
- Removed named-song role privilege and tested metadata invariance, common tempo, guest rotation, 5-song cap and confidence degradation: 35 generalization checks.
- Removed automatic incoming vocal preview and future-lyric echo throw; simplified the first different-song handoff to one rise.
- Removed the fixed incoming gain multiplication and preserved actual applied effects/diagnostics.
- Reconciled tempo scheduling with the real renderer: six synthetic fixtures completed, including a deliberately drifting negative control.
- Prevented pulse underneath a full mix, missing isolation or conflicting strong drums: five checks, including a rendered low-end control.
- Checked decoded AAC delivery. All 31 local-song subsets rendered and passed decoded peak and software-limiter checks. These results precede the latest phrase correction and do not override the owner's musical rejection.

Evidence is retained in `implementation/sept12-*`, `implementation/pulse-ownership-*`, and `Exports/Audit-2026-09-04/ownership-sep12`. Earlier failing controls remain available.

## September 12 listening correction

The rejected heuristic ended the outgoing vocal at source 67.700 seconds, between the onsets of “I'm” and “not.” An RMS valley was incorrectly treated as a complete lyric ending. That shortening has been removed.

The subsequent fixed two-bar extension was also insufficient: a longer synthetic continuation remained active at its new boundary. The revised candidate searches beyond the continuation's minimum dwell for a measured isolated-vocal pause with a corroborating word gap, retires the vocal there, and carries the instrumental to a later bar. Incoming placements and downstream events move together. It does not infer semantic completeness from this pause; affected plans explicitly retain a phrase-review warning.

The incoming vocal can retain a bounded continuous pickup before the drum downbeat. Its word clock and phrase endpoint stay fixed. Revalidation cannot grow this pickup. A copyright-free rendered high-frequency consonant control rejects the old trim and retains the new pickup. This verifies source trimming/scheduling, not the actual Audio Unit's consonant audibility.

A single lower-cost subagent performed a narrow, read-only review. It found the fixed-delay issue, a stretched-pickup idempotence issue and an assertion that confused a real pickup with a repeated preview. The parent handled implementation and all local checks. No new cloud audio calls were made.

## Remaining evidence and risks

- The pause heuristic is provisional. Read-only source measurements show quiet windows inside longer lyric lines, so pause plus word-onset gaps cannot prove a complete phrase. Independent phrase-end evidence and another owner audition remain necessary.
- This correction targets the first different-song sweep. Shifting downstream joins preserves their relative source mapping; it does not independently approve their musical phrasing.
- Generic lyric-tail repairs can still extend or duplicate supporting passages. Complete-hook boundaries, non-pivot low-end handoffs and every later lyric cut require further review.
- Missing or corrupt stem runtime fallback, automatic thin-song source carving, high-confidence solo transformation/Drop 2 negative controls, held-out material, live/export capture parity, pre-SFX headroom and upstream Audio Unit limiter telemetry remain open.
- The earlier audio-service approval block cleared after the stated account reset time. Fresh renders ran through normal approval review; no workaround was used.
- The protected active skill was updated after the stated account reset time, through normal approval review. It matches `dj-remix-planning.proposed.md`.

Do not relabel the September 12 rejected export as a corrected listening candidate. Technical passes and portable PCM controls are necessary evidence, not a substitute for the missing rendered-audio and human approval.

## Follow-up after the real render

The first new render failed review even though delivery peaks passed: Drop 1 reached bar 27, the outgoing pause was inside another line, and a later repair demoted the incoming vocal to a 0.254-second lead fragment. The repair had mistaken backing drums for a new vocal owner. The corrected next-lead search now considers foreground vocals/full records only.

The next candidate uses the measured outgoing source downbeat at 73.24 seconds, corroborated by the following word entrance, instead of the later quiet valley. Its instrumental opening can shorten on a verified quiet bar, reserving the extra continuation time while keeping Drop 1 at elapsed bar 24. This rule requires real bar and vocal evidence; it cannot manufacture an early-cut exception.

Revision 2 preserved the incoming lead and measured −1.248 dBTP with no clipped samples or internal sub-60 dB silence. It still carried a 75-millisecond old outgoing tail to the new drop. Revision 3 absorbs that already-covered tail rather than replaying it. A failing synthetic regression records this defect. Revision 3 completed: 22 focused checks, 88 rendered-quality checks and the app build passed. The broader 687-check suite passed immediately before the final covered-tail removal; 13 runner checks also passed. The fresh pair export keeps Drop 1 at bar 24, has no old outgoing tail at the drop, measures −1.248 dBTP with zero clipped samples, and passes software-limiter and internal-silence checks. The matched excerpt is in `Exports/Audit-2026-09-04/listening-owner-sep12-r3/revised.wav`; owner audition is pending.

The source-bar/word alignment is stronger timing evidence than a word gap alone, but it does not certify semantic lyric completeness across arbitrary songs. Human audition, held-out material and the wider open acceptance requirements above remain necessary.
