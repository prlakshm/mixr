import Foundation

// MARK: - Auto Remix Validator
//
// Validates and REPAIRS a plan before it ever touches the timeline:
// clamps source ranges, enforces clip minimums, removes same-song
// overlaps, closes accidental gaps, caps simultaneous sources
// (2 for remix, 3 for mashup vocal stacks), guarantees every riser
// has a payoff, and snaps impacts to downbeats.
// A knowingly invalid plan is never returned — offending elements are
// repaired or dropped with a warning.

nonisolated enum AutoRemixValidator {

    static func validate(
        _ plan: AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        tuning: AutoTuning
    ) -> AutoRemixPlan {
        var plan = plan
        var warnings = plan.warnings
        var decisions = plan.decisions
        let minLen = tuning.minSegmentSeconds - 0.1
        let barSec = plan.barSeconds
        let beatSec = plan.beatSeconds
        let echoMinLen = max(0.12, beatSec * 0.4)

        // Short supporting DJ echo throws OR 1-beat pivot wallpaper grains
        // may sit below the global clip minimum.
        func isHookEchoThrow(_ p: AutoClipPlacement) -> Bool {
            guard p.role == .supporting else { return false }
            let shortGrain = p.timelineDuration <= barSec + 0.05
                && p.timelineDuration >= echoMinLen
            let pivotBeat = abs(p.timelineDuration - beatSec) < beatSec * 0.4
            guard shortGrain || pivotBeat else { return false }
            return p.overlapsPreviousSeconds > 0.05
                || p.effects.level(for: MixrEffect.echo.rawValue) >= 8
                || p.effects.level(for: MixrEffect.blur.rawValue) >= 36
                || p.fadeOut.type == .echoOut
        }

        // ── 1. Source ranges must live inside each song ──
        var step1: [AutoClipPlacement] = []
        step1.reserveCapacity(plan.placements.count)
        for var p in plan.placements {
            p.effects = AutoSupportedEffects.sanitize(p.effects)
            guard let duration = profiles[p.songID]?.analysis.durationSeconds else {
                step1.append(p)
                continue
            }
            if p.sourceStart < 0 { p.sourceStart = 0 }
            let overrun = p.sourceEnd - (duration - 0.05)
            if overrun > 0 {
                let slide = min(overrun, p.sourceStart)
                p.sourceStart -= slide
                let remaining = overrun - slide
                if remaining > 0 {
                    p.timelineDuration -= remaining / max(p.tempoRatio, 0.0001)
                }
            }
            // Sample-continuous segment splits (filter ramps) are not
            // musical cuts — the audio underneath is continuous, so the
            // musical minimum-length rule does not apply to them.
            let floor = (isHookEchoThrow(p) || p.continuesPrevious) ? echoMinLen : minLen
            if p.timelineDuration < floor {
                if p.role == .dominant {
                    warnings.append("Dropped a section that no longer had enough source material.")
                }
                continue
            }
            step1.append(p)
        }
        plan.placements = step1

        // ── 2. Same-song placements may overlap ONLY for a declared
        // equal-power crossfade (true temporal overlap), or when a
        // supporting hook-echo / stutter layer sits under the lead.
        var bySong: [UUID: [Int]] = [:]
        for (i, p) in plan.placements.enumerated() {
            bySong[p.songID, default: []].append(i)
        }
        for (_, idxs) in bySong {
            let sorted = idxs.sorted {
                plan.placements[$0].timelineStart < plan.placements[$1].timelineStart
            }
            for pair in zip(sorted, sorted.dropFirst()) {
                let a = plan.placements[pair.0]
                let b = plan.placements[pair.1]
                // Different Demucs sidecars are different files (vocal over
                // drums+bass+other). They may share a song ID and timeline.
                if a.stemKind != b.stemKind { continue }
                let overlap = a.timelineEnd - b.timelineStart
                let declared = max(a.overlapsPreviousSeconds, b.overlapsPreviousSeconds)
                if overlap > 0.005 {
                    // Intentional same-song supporting echo / stutter layer.
                    if (a.role == .supporting || b.role == .supporting),
                       declared > 0.005 || isHookEchoThrow(a) || isHookEchoThrow(b) {
                        continue
                    }
                    if declared > 0.005, overlap <= declared + 0.05 {
                        continue   // sanctioned crossfade overlap
                    }
                    let excess = overlap - max(0, min(declared, overlap))
                    let floor = isHookEchoThrow(a) ? echoMinLen : minLen
                    plan.placements[pair.0].timelineDuration -= excess
                    if plan.placements[pair.0].timelineDuration < floor {
                        plan.placements[pair.0].timelineDuration = 0
                        warnings.append(
                            "Removed a clip segment that collided with the same song's next section."
                        )
                    }
                }
            }
        }
        plan.placements.removeAll { p in
            let floor = (isHookEchoThrow(p) || p.continuesPrevious) ? echoMinLen : minLen
            return p.timelineDuration < floor
        }

        // ── 2b. One-song remix: every internal cut must be reasoned,
        // confident, and masked; source order must stay monotonic unless
        // an explicit hook return justifies the rewind; and no boundary
        // may fade BOTH neighbors toward silence (level hole).
        if plan.mode == .remix {
            repairRemixCuts(
                &plan,
                profiles: profiles,
                warnings: &warnings,
                decisions: &decisions,
                minLen: minLen
            )
        }

        // ── 3. Cap simultaneous full-song sources ──
        // Remix: at most two. Mashup: bed + lead vocal + optional second
        // vocal overlay may reach three complementary layers.
        let maxConcurrentSongs = plan.mode == .mashup ? 3 : 2
        let dominants = plan.placements.filter { $0.role == .dominant }
        let snapshot = plan.placements
        plan.placements.removeAll { p in
            guard p.role == .supporting else { return false }
            let concurrent = dominants.filter {
                $0.timelineStart < p.timelineEnd - 0.01 && $0.timelineEnd > p.timelineStart + 0.01
            }
            let otherSupports = snapshot.filter { s in
                s.role == .supporting
                    && s.songID != p.songID
                    && s.timelineStart < p.timelineEnd - 0.01
                    && s.timelineEnd > p.timelineStart + 0.01
            }
            let distinctSongs = Set(concurrent.map(\.songID) + otherSupports.map(\.songID) + [p.songID])
            if distinctSongs.count > maxConcurrentSongs {
                warnings.append("Removed an overlap that would have stacked too many songs at once.")
                return true
            }
            return false
        }

        // Close accidental gaps on SONG coverage only. SFX glitter must not
        // hide a hole in the arrangement (busy beds, not whooshes over silence).
        let maxGap = plan.eighthNoteSeconds
        let intentional = plan.intentionalGaps
        var coverage = mergedCoverage(
            placements: plan.placements,
            sfxEvents: []
        )

        // Iterate until stable — pulling later content can create new adjacencies.
        for _ in 0..<8 {
            let currentGaps = gaps(in: coverage).filter { gap in
                guard gap.length > maxGap + 0.001 else { return false }
                if isIntentional(gap, in: intentional, maxPause: tuning.maxIntentionalPauseBeats * plan.beatSeconds) {
                    return false
                }
                return true
            }
            guard let gap = currentGaps.first else { break }

            var repaired = false
            // Extend the placement that ends at the gap when its source allows.
            if let idx = plan.placements.indices.min(by: { a, b in
                abs(plan.placements[a].timelineEnd - gap.start)
                    < abs(plan.placements[b].timelineEnd - gap.start)
            }), abs(plan.placements[idx].timelineEnd - gap.start) < 0.05 {
                let p = plan.placements[idx]
                let songDuration = profiles[p.songID]?.analysis.durationSeconds ?? .infinity
                let sourceRoom = (songDuration - 0.05 - p.sourceEnd) / max(p.tempoRatio, 0.0001)
                if sourceRoom >= gap.length {
                    plan.placements[idx].timelineDuration += gap.length
                    repaired = true
                    decisions.append(
                        AutoDecision(
                            kind: .repairedTimelineGap,
                            songTitle: nil,
                            detail: "extended previous phrase"
                        )
                    )
                }
            }

            if !repaired {
                // Pull everything after the gap earlier — never stretch beyond source.
                for i in plan.placements.indices where plan.placements[i].timelineStart >= gap.end - 0.01 {
                    plan.placements[i].timelineStart -= gap.length
                }
                for i in plan.sfxEvents.indices where plan.sfxEvents[i].timelineStart >= gap.end - 0.01 {
                    plan.sfxEvents[i].timelineStart -= gap.length
                }
                for i in plan.intentionalGaps.indices
                where plan.intentionalGaps[i].start >= gap.end - 0.01 {
                    plan.intentionalGaps[i].start -= gap.length
                    plan.intentionalGaps[i].end -= gap.length
                }
                for i in plan.cutRecords.indices where plan.cutRecords[i].timelineAt >= gap.end - 0.01 {
                    plan.cutRecords[i].timelineAt -= gap.length
                }
                for i in plan.pulseRegions.indices where plan.pulseRegions[i].timelineStart >= gap.end - 0.01 {
                    plan.pulseRegions[i].timelineStart -= gap.length
                    plan.pulseRegions[i].timelineEnd -= gap.length
                }
                decisions.append(
                    AutoDecision(
                        kind: .repairedTimelineGap,
                        songTitle: nil,
                        detail: "pulled next section earlier"
                    )
                )
                warnings.append("Closed an accidental gap by pulling the next section earlier.")
            }

            coverage = mergedCoverage(
                placements: plan.placements,
                sfxEvents: []
            )
        }

        // ── 4b. Handoffs must overlap (except the intentional pre-drop void).
        // A join with no overlap and no SFX cover is a defect — extend the
        // previous dominant for an equal-power crossfade when source allows.
        ensureHandoffOverlaps(
            &plan,
            profiles: profiles,
            tuning: tuning,
            warnings: &warnings,
            decisions: &decisions
        )

        // ── 4b-ii. The pivot wallpaper ENTRY must be masked.
        // Every non-grain clip is trimmed at loopStart, so the mix steps
        // from full band to one isolated high-passed vocal in a single
        // sample. Measured on rendered PCM that is a 4-sigma timbre outlier
        // against the mix's own bar-to-bar distribution — heard as "the
        // switch comes from nowhere". Take-out hits are placed by their own
        // duration before the drop, so a 4.0s riser cannot reach a 2-bar
        // (4.56s @105bpm) wallpaper; the seam is left bare.
        //
        // Masking a cut with a broadband swell is the same rule the cut
        // policy already requires elsewhere. It does NOT soften Drop 1 —
        // that stays a hard cut at full clip volume, and rendered PCM shows
        // the drop boundary was never the outlier.
        if ProcessInfo.processInfo.environment["MIXR_NO_INVARIANTS"] != "1" {
            enforceArrangementInvariants(&plan, profiles: profiles, warnings: &warnings, decisions: &decisions)
        }
        addIncomingVocalRideIn(&plan, decisions: &decisions)
        addPivotBlendFloor(&plan, decisions: &decisions)
        coverPivotWallpaperSeam(&plan, decisions: &decisions)

        // ── 4c. No placement may WALK its source into near-silence: a long
        // groove/build/drop clip whose source tail collapses (bridge, spoken
        // break, instrumental drop-out) is rewound to its own strong head on
        // a bar boundary. Dead air mid-mix is a defect, not the record.
        repairQuietSourceTails(&plan, profiles: profiles, decisions: &decisions)
        repairPreDropDip(&plan, profiles: profiles, decisions: &decisions)
        if ProcessInfo.processInfo.environment["MIXR_NO_LOUDMATCH"] != "1" {
            matchSectionLoudness(&plan, profiles: profiles, decisions: &decisions)
        }
        keepGuestFirstLineClear(&plan, profiles: profiles, decisions: &decisions)
        transformVerbatimRepeats(&plan, decisions: &decisions)
        rampContinuousVolumeSteps(&plan, decisions: &decisions)
        shapeTrailingOutro(&plan, profiles: profiles, decisions: &decisions)

        // Intentional silence is ONLY the pre-drop void (hype = subtraction).
        plan.intentionalGaps.removeAll { gap in
            !gap.reason.localizedCaseInsensitiveContains("void")
        }

        // ── 5. Build SFX must resolve into a drop take-out or ride the drop.
        // Title-hook / groove dominant starts are NOT payoffs — a riser
        // aimed at 15.3s would bury the opening title line.
        let dropRegions = plan.pulseRegions.filter { $0.role == .drop }
        let dropStarts = dropRegions.map(\.timelineStart)
        let beforeSFX = plan.sfxEvents.count
        let keptSFX = plan.sfxEvents.filter { event in
            guard ["riser", "snareBuild", "reverseCymbal", "airSweep"].contains(event.assetID) else {
                return true
            }
            let riding = dropRegions.contains { drop in
                event.timelineStart >= drop.timelineStart + beatSec - 0.05
                    && event.timelineStart < drop.timelineEnd - 0.05
            }
            if riding { return true }
            let takeOut = dropStarts.contains {
                abs($0 - event.timelineEnd) < max(0.55, beatSec + 0.2)
                    || abs(($0 - beatSec) - event.timelineEnd) < max(0.55, beatSec + 0.2)
            }
                || plan.pulseRegions.contains { r in
                    r.role == .buildOut
                        && abs(r.timelineEnd - event.timelineEnd) < max(0.55, beatSec + 0.2)
                }
            if takeOut { return true }
            // A swell that OPENS a build/buildOut window is a payoff too:
            // it masks the wallpaper seam, where every non-grain clip is
            // trimmed at once. Judging sweeps only by where they END drops
            // exactly the hit that covers the hardest cut in the mix.
            let opensBuild = plan.pulseRegions.contains { r in
                (r.role == .buildOut || r.role == .build)
                    && event.timelineStart >= r.timelineStart - 0.05
                    && event.timelineStart < r.timelineStart + beatSec * 0.5
            }
            if opensBuild { return true }
            decisions.append(
                AutoDecision(
                    kind: .removedInvalidSFX,
                    songTitle: nil,
                    detail: "\(event.assetID) without payoff"
                )
            )
            return false
        }
        plan.sfxEvents = keptSFX
        if plan.sfxEvents.count < beforeSFX {
            warnings.append("Removed build SFX that had no clear payoff.")
        }

        // ── 6. Impacts align to downbeats of the target grid ──
        for i in plan.sfxEvents.indices where plan.sfxEvents[i].assetID == "impact" {
            let t = plan.sfxEvents[i].timelineStart
            let snapped = (t / plan.barSeconds).rounded() * plan.barSeconds
            if abs(snapped - t) <= plan.beatSeconds * 0.5 {
                plan.sfxEvents[i].timelineStart = max(0, snapped)
            }
        }

        // ── 7. SFX events must not start before zero or after the content ──
        let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        plan.sfxEvents.removeAll { event in
            let invalid = event.timelineStart < -0.01 || event.timelineStart > contentEnd + 0.5
            if invalid {
                decisions.append(
                    AutoDecision(
                        kind: .removedInvalidSFX,
                        songTitle: nil,
                        detail: event.assetID
                    )
                )
            }
            return invalid
        }
        plan.sfxEvents.sort { $0.timelineStart < $1.timelineStart }

        // ── 8. Structural expectations (warn-only) ──
        let songCount = Set(plan.placements.map(\.songID)).count
        if plan.mode == .mashup, songCount >= 2, plan.handoffCount < 3 {
            if !decisions.contains(where: { $0.kind == .duoAlternationFallback }) {
                decisions.append(
                    AutoDecision(
                        kind: .duoAlternationFallback,
                        songTitle: nil,
                        detail: "Fewer song handoffs than intended — some sections were skipped for lack of material."
                    )
                )
            }
            warnings.append(
                "Fewer song handoffs than intended — some sections were skipped for lack of material."
            )
        }

        // ── 9. Timeline budget ──
        if contentEnd > tuning.maxTimelineSeconds + 10 {
            warnings.append("Arrangement runs long; consider removing a song.")
        }

        // ── 10. Recompute handoff count from dominant slot sequence ──
        plan.handoffCount = recomputedHandoffs(plan.placements)

        plan.warnings = warnings
        plan.decisions = decisions
        plan.targetDuration = plan.placements.map(\.timelineEnd).max() ?? plan.targetDuration
        return plan
    }

    // MARK: - Coverage helpers

    private struct Gap {
        var start: Double
        var end: Double
        var length: Double { end - start }
    }

    private static func mergedCoverage(
        placements: [AutoClipPlacement],
        sfxEvents: [AutoSFXEvent]
    ) -> [(Double, Double)] {
        var ranges = placements.map { ($0.timelineStart, $0.timelineEnd) }
        ranges.append(contentsOf: sfxEvents.map { ($0.timelineStart, $0.timelineEnd) })
        let sorted = ranges.sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for range in sorted {
            if var last = merged.last, range.0 <= last.1 + 0.001 {
                last.1 = max(last.1, range.1)
                merged[merged.count - 1] = last
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func gaps(in coverage: [(Double, Double)]) -> [Gap] {
        var result: [Gap] = []
        for pair in zip(coverage, coverage.dropFirst()) where pair.1.0 - pair.0.1 > 0.001 {
            result.append(Gap(start: pair.0.1, end: pair.1.0))
        }
        return result
    }

    private static func isIntentional(
        _ gap: Gap,
        in intentional: [AutoIntentionalGap],
        maxPause: Double
    ) -> Bool {
        // Silence is intentional ONLY when an explicit marker covers it —
        // unmarked gaps are defects to close, never blessed by size.
        for g in intentional {
            let overlap = min(gap.end, g.end) - max(gap.start, g.start)
            if overlap > gap.length * 0.5, gap.length <= maxPause + 0.02 {
                return true
            }
        }
        return false
    }

    // MARK: - Remix cut integrity

    /// One-song preservation rules:
    ///  • a source discontinuity between timeline-adjacent placements is
    ///    an internal cut and must carry a confident AutoCutRecord;
    ///    unreasoned cuts are repaired back to source continuity (or the
    ///    offending placement is dropped when the source has no room);
    ///  • a cut masked by an equal-power crossfade must actually OVERLAP;
    ///  • source-continuous splits get their inner fades cleared so no
    ///    boundary fades both neighbors toward silence;
    ///  • source order stays monotonic unless a hookReturn record
    ///    justifies the rewind.
    private static func repairRemixCuts(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        warnings: inout [String],
        decisions: inout [AutoDecision],
        minLen: Double
    ) {
        // ── Monotonic source order ──
        var toRemove = Set<UUID>()
        var lastStartBySong: [UUID: Double] = [:]
        let timelineOrder = plan.placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        for p in timelineOrder {
            if let last = lastStartBySong[p.songID], p.sourceStart < last - 0.05 {
                let justified = plan.cutRecords.contains {
                    $0.reason == .hookReturn && abs($0.timelineAt - p.timelineStart) < 0.1
                }
                if !justified {
                    toRemove.insert(idFor(p))
                    warnings.append(
                        "Removed a section that rewound the song without a justified hook return."
                    )
                    continue
                }
            }
            lastStartBySong[p.songID] = max(lastStartBySong[p.songID] ?? -1, p.sourceStart)
        }
        if !toRemove.isEmpty {
            plan.placements.removeAll { toRemove.contains(idFor($0)) }
        }

        // ── Cut integrity on timeline-adjacent same-song pairs ──
        let order = plan.placements.indices
            .filter { plan.placements[$0].role == .dominant }
            .sorted { plan.placements[$0].timelineStart < plan.placements[$1].timelineStart }
        var dropAfterRepair = Set<Int>()

        for pair in zip(order, order.dropFirst()) {
            let prev = plan.placements[pair.0]
            let next = plan.placements[pair.1]
            guard prev.songID == next.songID else { continue }
            let overlapping = next.timelineStart < prev.timelineEnd - 0.005
            let sequential = abs(next.timelineStart - prev.timelineEnd) <= 0.05
            guard overlapping || sequential else { continue }
            let songDuration = profiles[next.songID]?.analysis.durationSeconds ?? .infinity

            if next.continuesPrevious {
                // Declared continuity must be sample-true.
                if abs(next.sourceStart - prev.sourceEnd) > 0.05 {
                    plan.placements[pair.1].sourceStart = prev.sourceEnd
                }
                continue
            }

            let discontinuity = abs(next.sourceStart - prev.sourceEnd) > 0.05
            if !discontinuity {
                if sequential {
                    // Contiguous source split — continuity, no fades.
                    plan.placements[pair.1].continuesPrevious = true
                    plan.placements[pair.0].fadeOut = .none
                    plan.placements[pair.1].fadeIn = .none
                }
                continue
            }

            let record = plan.cutRecords.first {
                abs($0.timelineAt - next.timelineStart) < 0.1
            }

            if let record, record.confidence >= 0.5 {
                // A crossfade-masked cut requires REAL temporal overlap.
                if case .equalPowerCrossfade(let seconds) = record.masking,
                   next.overlapsPreviousSeconds <= 0.005,
                   sequential,
                   seconds > 0.01,
                   prev.sourceEnd + seconds * prev.tempoRatio <= songDuration - 0.05 {
                    let beats = seconds / max(plan.beatSeconds, 0.001)
                    plan.placements[pair.0].timelineDuration += seconds
                    plan.placements[pair.0].fadeOut = ClipTransition(
                        type: .crossfade,
                        duration: beats,
                        curve: AutoTransitionEnvelope.equalPowerCurveName
                    )
                    plan.placements[pair.1].overlapsPreviousSeconds = seconds
                    plan.placements[pair.1].fadeIn = ClipTransition(
                        type: .crossfade,
                        duration: beats,
                        curve: AutoTransitionEnvelope.equalPowerCurveName
                    )
                } else if !isCrossfadeMasking(record.masking), sequential {
                    // Hard/SFX/tail-masked cut: never fade both sides to
                    // silence — the masking layer carries the join.
                    if fadesTowardSilence(prev.fadeOut), fadesIn(next.fadeIn) {
                        plan.placements[pair.0].fadeOut = .none
                        plan.placements[pair.1].fadeIn = .none
                    }
                }
            } else {
                // Unreasoned / low-confidence cut → keep the song
                // continuous when the source allows, else drop the tail.
                if prev.sourceEnd + next.sourceDuration <= songDuration - 0.05 {
                    plan.placements[pair.1].sourceStart = prev.sourceEnd
                    plan.placements[pair.1].continuesPrevious = true
                    plan.placements[pair.0].fadeOut = .none
                    plan.placements[pair.1].fadeIn = .none
                    warnings.append(
                        "Removed an unjustified internal cut — kept the song continuous."
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .repairedTimelineGap,
                            songTitle: nil,
                            detail: "removed an unjustified cut"
                        )
                    )
                } else {
                    dropAfterRepair.insert(pair.1)
                    warnings.append(
                        "Dropped a section whose cut had no reason and no masking."
                    )
                }
            }
        }

        if !dropAfterRepair.isEmpty {
            let ids = dropAfterRepair.map { idFor(plan.placements[$0]) }
            plan.placements.removeAll { ids.contains(idFor($0)) }
        }
    }

    /// Stable identity for a placement (no stored id on the struct).
    private static func idFor(_ p: AutoClipPlacement) -> UUID {
        // Derive a deterministic pseudo-identity from immutable fields.
        // Placements are unique by (song, slot, timelineStart) in practice.
        var hasher = Hasher()
        hasher.combine(p.songID)
        hasher.combine(p.slotIndex)
        hasher.combine(Int((p.timelineStart * 1000).rounded()))
        let h = hasher.finalize()
        return UUID(
            uuid: (
                UInt8(truncatingIfNeeded: h >> 56), UInt8(truncatingIfNeeded: h >> 48),
                UInt8(truncatingIfNeeded: h >> 40), UInt8(truncatingIfNeeded: h >> 32),
                UInt8(truncatingIfNeeded: h >> 24), UInt8(truncatingIfNeeded: h >> 16),
                UInt8(truncatingIfNeeded: h >> 8), UInt8(truncatingIfNeeded: h),
                0, 0, 0, 0, 0, 0, 0, 0
            )
        )
    }

    /// Whole-plan musical invariants, enforced BEFORE render:
    ///
    ///  • NOVELTY BUDGET — no source region plays more than twice across the
    ///    mix. A third verbatim appearance retargets to an unused chorus
    ///    island of the same song when one exists; otherwise it is surfaced
    ///    as a warning (never silently deleted — a hole is worse).
    ///  • LYRIC-LINE INTEGRITY — a dominant cut may not land inside a word:
    ///    when the sidecar has word onsets, a clip whose source end falls
    ///    mid-word is extended to the word's end (bounded, collision-checked).
    private static func enforceArrangementInvariants(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        warnings: inout [String],
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return }

        // ── Novelty budget ──
        struct Appearance { var index: Int; var start: Double }
        var seen: [UUID: [Appearance]] = [:]
        let idxs = plan.placements.indices
            .filter { plan.placements[$0].role == .dominant
                && plan.placements[$0].timelineDuration >= barSec * 4 }
            .sorted { plan.placements[$0].timelineStart < plan.placements[$1].timelineStart }
        for i in idxs {
            let p = plan.placements[i]
            let priors = seen[p.songID, default: []].filter {
                abs($0.start - p.sourceStart) < barSec * 1.5
            }
            if priors.count >= 2 {
                // Third appearance: retarget to an unused island if possible.
                let used = seen[p.songID, default: []].map(\.start)
                let candidate = profiles[p.songID]?.candidates
                    .filter { c in
                        c.label == .chorus
                            && Double(c.barCount) * barSec >= p.timelineDuration - 0.5
                            && used.allSatisfy { abs($0 - c.startSeconds) > barSec * 2 }
                    }
                    .max(by: { $0.hook < $1.hook })
                if let candidate {
                    plan.placements[i].sourceStart = candidate.startSeconds
                    decisions.append(
                        AutoDecision(
                            kind: .returnedToHook,
                            songTitle: profiles[p.songID]?.title,
                            detail: String(
                                format: "novelty budget: 3rd replay of src=%.1f retargeted to unused island @%.1f",
                                p.sourceStart, candidate.startSeconds
                            )
                        )
                    )
                } else {
                    warnings.append(
                        String(format: "Source region %.1fs plays a 3rd time at %.1fs (no unused island to swap in).",
                               p.sourceStart, p.timelineStart)
                    )
                }
            }
            seen[p.songID, default: []].append(
                Appearance(index: i, start: plan.placements[i].sourceStart)
            )
        }

        // ── Lyric-line integrity ──
        let sortedIdx = plan.placements.indices.sorted {
            plan.placements[$0].timelineStart < plan.placements[$1].timelineStart
        }
        for i in plan.placements.indices {
            let p = plan.placements[i]
            guard p.role == .dominant, p.timelineDuration >= barSec * 2 else { continue }
            guard let words = profiles[p.songID]?.analysis.signal?.lyricWords,
                  !words.isEmpty else { continue }
            // Next placement on the timeline (for collision checks).
            let nextStart = sortedIdx
                .compactMap { plan.placements[$0].timelineStart > p.timelineStart + 0.05
                    ? plan.placements[$0].timelineStart : nil }
                .min() ?? .infinity
            let srcEnd = p.sourceEnd
            guard let word = words.first(where: {
                srcEnd > $0.t + 0.06 && srcEnd < $0.t + 0.34
            }) else { continue }
            let extendSrc = (word.t + 0.38) - srcEnd
            let extendTimeline = extendSrc / max(p.tempoRatio, 0.001)
            guard extendTimeline > 0.02, extendTimeline < 0.6 else { continue }
            guard p.timelineEnd + extendTimeline < nextStart + 0.25 else { continue }
            plan.placements[i].timelineDuration += extendTimeline
            decisions.append(
                AutoDecision(
                    kind: .shortenedForMaterial,
                    songTitle: profiles[p.songID]?.title,
                    detail: String(
                        format: "cut nudged off mid-word “%@” (+%.2fs so the line finishes)",
                        word.word, extendTimeline
                    )
                )
            )
        }
    }

    /// Sample-continuous neighbors may not STEP in volume ("jumps louder,
    /// isn't a smooth blend" — the title-duck release went 0.18→0.62 in one
    /// sample). Any continuous same-stem step over ~4 dB gets a staircase:
    /// the first bar of the louder side splits into two sub-segments at
    /// interpolated volumes, turning the step into a ramp. Generic — also
    /// smooths loudness-matching and makeup steps mid-line.
    private static func rampContinuousVolumeSteps(
        _ plan: inout AutoRemixPlan,
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return }
        var extra: [AutoClipPlacement] = []
        var ramped = 0
        let order = plan.placements.indices.sorted {
            plan.placements[$0].timelineStart < plan.placements[$1].timelineStart
        }
        for (ai, bi) in zip(order, order.dropFirst()) {
            let a = plan.placements[ai]
            let b = plan.placements[bi]
            guard b.continuesPrevious,
                  a.songID == b.songID, a.stemKind == b.stemKind,
                  abs(a.timelineEnd - b.timelineStart) < 0.05,
                  a.volume > 0.01, b.volume > 0.01,
                  b.timelineDuration > barSec * 0.9
            else { continue }
            let stepDB = 20 * log10(b.volume / a.volume)
            guard abs(stepDB) > 4.0 else { continue }
            let rampLen = min(barSec, b.timelineDuration * 0.5)
            let half = rampLen / 2
            let v1 = a.volume * pow(b.volume / a.volume, 1.0 / 3.0)
            let v2 = a.volume * pow(b.volume / a.volume, 2.0 / 3.0)
            var s1 = b
            s1.timelineDuration = half
            s1.volume = v1
            var s2 = b
            s2.timelineStart = b.timelineStart + half
            s2.timelineDuration = half
            s2.sourceStart = b.sourceStart + half * b.tempoRatio
            s2.volume = v2
            s2.continuesPrevious = true
            plan.placements[bi].timelineStart = b.timelineStart + rampLen
            plan.placements[bi].timelineDuration = b.timelineDuration - rampLen
            plan.placements[bi].sourceStart = b.sourceStart + rampLen * b.tempoRatio
            extra.append(s1)
            extra.append(s2)
            ramped += 1
        }
        guard ramped > 0 else { return }
        plan.placements.append(contentsOf: extra)
        decisions.append(
            AutoDecision(
                kind: .imposedClubEnergyCurve,
                songTitle: nil,
                detail: "ramped \(ramped) continuous volume steps (>4 dB) into staircases"
            )
        )
    }

    /// The mix TRAILS OFF ("make ending more trailing off"): the last
    /// dominant material decays progressively over its final bars — volume
    /// steps down and the low-pass closes — instead of holding a shelf and
    /// collapsing. SFX (the ending cymbals) ride on top unaffected.
    private static func shapeTrailingOutro(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return }
        let endT = plan.placements.map(\.timelineEnd).max() ?? 0
        guard endT > 30 else { return }
        var extra: [AutoClipPlacement] = []
        var shaped = 0
        let trailBars = 6.0
        for i in plan.placements.indices {
            let p = plan.placements[i]
            guard p.timelineEnd > endT - 0.5,
                  p.timelineDuration >= barSec * (trailBars + 1),
                  p.stemKind == nil || p.role == .dominant || p.role == .supporting
            else { continue }
            let trailStart = p.timelineEnd - trailBars * barSec
            let src = p
            plan.placements[i].timelineDuration = trailStart - p.timelineStart
            plan.placements[i].fadeOut = ClipTransition(type: .none, duration: 0)
            let stages = 3
            let stageDur = trailBars * barSec / Double(stages)
            var prevEffectiveDB = -120.0
            if let signal = profiles[src.songID]?.analysis.signal {
                let headSrcDB = signal.meanRMSDB(
                    from: max(0, src.sourceStart + (trailStart - src.timelineStart) * src.tempoRatio - 2 * barSec * src.tempoRatio),
                    to: src.sourceStart + (trailStart - src.timelineStart) * src.tempoRatio
                )
                if headSrcDB > -60 {
                    prevEffectiveDB = headSrcDB + 20 * log10(max(src.volume, 0.01))
                }
            }
            for k in 0..<stages {
                var seg = src
                seg.timelineStart = trailStart + Double(k) * stageDur
                seg.timelineDuration = stageDur
                seg.sourceStart = src.sourceStart + (seg.timelineStart - src.timelineStart) * src.tempoRatio
                seg.continuesPrevious = true
                seg.fadeIn = ClipTransition(type: .none, duration: 0)
                let ramp = Double(k + 1) / Double(stages)
                // Recursive −4 dB chain: each stage sits exactly 4 dB under
                // the PREVIOUS stage's effective level. Monotonic by
                // construction, ≤4 dB steps (the continuous-volume gate's
                // bound), and self-compensating: quiet source raises the
                // knob to hold the slope instead of multiplying into −47 dB.
                var stageVol = src.volume * (1.0 - 0.5 * ramp)
                if let signal = profiles[src.songID]?.analysis.signal {
                    let stageSrcDB = signal.meanRMSDB(
                        from: seg.sourceStart,
                        to: seg.sourceStart + seg.timelineDuration * seg.tempoRatio
                    )
                    if prevEffectiveDB > -70, stageSrcDB > -60 {
                        stageVol = pow(10.0, ((prevEffectiveDB - 4.0) - stageSrcDB) / 20.0)
                        stageVol = min(stageVol, 2.0)
                        stageVol = max(stageVol, 0.05)
                        prevEffectiveDB = stageSrcDB + 20 * log10(stageVol)
                    } else {
                        prevEffectiveDB = -120
                    }
                }
                seg.volume = stageVol
                var fx = seg.effects
                fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 26 * ramp),
                            for: MixrEffect.blur.rawValue)
                seg.effects = AutoSupportedEffects.sanitize(fx)
                seg.fadeOut = k == stages - 1
                    ? ClipTransition(type: .crossfade, duration: 8,
                                     curve: AutoTransitionEnvelope.equalPowerCurveName)
                    : ClipTransition(type: .none, duration: 0)
                extra.append(seg)
            }
            shaped += 1
        }
        guard shaped > 0 else { return }
        plan.placements.append(contentsOf: extra)
        decisions.append(
            AutoDecision(
                kind: .shortenedLowEnergySection,
                songTitle: nil,
                detail: String(format: "trailing outro: %d layer(s) decay over %.0f bars into the fade", shaped, trailBars)
            )
        )
    }

    /// Repetition may only appear TRANSFORMED (product decision 2026-08-20:
    /// "they sound like a broken record"). Adjacent dominant passes playing
    /// the same source slice verbatim get a direction-aware treatment:
    ///
    ///  • BEFORE the first drop (the title hold): pass 1 is the STRIPPED
    ///    pass — its backing stems thinned — so the repeat reads as
    ///    verse-into-lift instead of déjà vu. The vocal is never touched
    ///    (ASR owns the first 4 s).
    ///  • AT/AFTER a drop (the Drop 2 hook ride): pass 2 SWEEPS DOWN —
    ///    per-bar rising low-pass into the outro, the closing-the-club move.
    private static func transformVerbatimRepeats(
        _ plan: inout AutoRemixPlan,
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return }
        let firstDrop = plan.pulseRegions.filter { $0.role == .drop }
            .map(\.timelineStart).min() ?? .infinity

        let doms = plan.placements.indices
            .filter { plan.placements[$0].role == .dominant
                && plan.placements[$0].timelineDuration >= barSec * 4 }
            .sorted { plan.placements[$0].timelineStart < plan.placements[$1].timelineStart }

        var tailSegments: [AutoClipPlacement] = []
        for (ai, bi) in zip(doms, doms.dropFirst()) {
            let a = plan.placements[ai]
            let b = plan.placements[bi]
            guard a.songID == b.songID,
                  abs(a.sourceStart - b.sourceStart) < 0.1,
                  abs(a.timelineDuration - b.timelineDuration) < barSec * 0.5,
                  b.timelineStart - a.timelineEnd < barSec
            else { continue }
            let sameVol = abs(a.volume - b.volume) < 0.05
            let sameBlur = abs(a.effects.level(for: MixrEffect.blur.rawValue)
                - b.effects.level(for: MixrEffect.blur.rawValue)) < 6
            guard sameVol && sameBlur else { continue }

            if b.timelineEnd <= firstDrop + 0.5 {
                // Title hold: thin pass 1's BACKING (supporting, non-vocal)
                // so the full pass 2 lands as the lift.
                var thinned = 0
                for i in plan.placements.indices {
                    let s = plan.placements[i]
                    guard s.role == .supporting, s.stemKind != nil, s.stemKind != .vocals else { continue }
                    let overlap = min(s.timelineEnd, a.timelineEnd) - max(s.timelineStart, a.timelineStart)
                    guard overlap > s.timelineDuration * 0.5 else { continue }
                    plan.placements[i].volume = s.volume * 0.55
                    var fx = plan.placements[i].effects
                    fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 22),
                                for: MixrEffect.blur.rawValue)
                    plan.placements[i].effects = AutoSupportedEffects.sanitize(fx)
                    thinned += 1
                }
                // Full-mix pass (no stems): thin pass 1 itself, mildly.
                if thinned == 0, a.stemKind == nil {
                    plan.placements[ai].volume = a.volume * 0.8
                    var fx = plan.placements[ai].effects
                    fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 18),
                                for: MixrEffect.blur.rawValue)
                    plan.placements[ai].effects = AutoSupportedEffects.sanitize(fx)
                }
                decisions.append(
                    AutoDecision(
                        kind: .returnedToHook,
                        songTitle: nil,
                        detail: String(format: "hold varied: pass 1 stripped @%.1fs, pass 2 full @%.1fs (no verbatim repeat)", a.timelineStart, b.timelineStart)
                    )
                )
            } else {
                // Drop ride: pass 2 sweeps down into what follows.
                let bars = max(2, Int((b.timelineDuration / barSec).rounded()))
                let segDur = b.timelineDuration / Double(bars)
                let src = plan.placements[bi]
                plan.placements[bi].timelineDuration = segDur
                for k in 1..<bars {
                    var seg = src
                    seg.timelineStart = src.timelineStart + Double(k) * segDur
                    seg.timelineDuration = segDur
                    seg.sourceStart = src.sourceStart + Double(k) * segDur * src.tempoRatio
                    seg.continuesPrevious = true
                    seg.fadeIn = ClipTransition(type: .none, duration: 0)
                    seg.fadeOut = k == bars - 1 ? src.fadeOut : ClipTransition(type: .none, duration: 0)
                    let ramp = Double(k) / Double(max(bars - 1, 1))
                    var fx = seg.effects
                    fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 34 * ramp),
                                for: MixrEffect.blur.rawValue)
                    seg.effects = AutoSupportedEffects.sanitize(fx)
                    seg.volume = src.volume * (1.0 - 0.12 * ramp)
                    tailSegments.append(seg)
                }
                plan.placements[bi].fadeOut = ClipTransition(type: .none, duration: 0)
                decisions.append(
                    AutoDecision(
                        kind: .returnedToHook,
                        songTitle: nil,
                        detail: String(format: "hold varied: drop ride pass 2 sweeps down @%.1fs (no verbatim repeat)", b.timelineStart)
                    )
                )
            }
        }
        plan.placements.append(contentsOf: tailSegments)
    }

    /// The guest's FIRST LINE owns the drop — ride SFX wait for it to land.
    ///
    /// The drop-ride stack fired an air sweep one beat in and a bass-drop at
    /// the half bar; the bass-drop also triggers the 4.5 dB song duck. On
    /// rendered PCM that carved an 8 dB hole exactly through "hit me baby" —
    /// the words the whole join exists to deliver. The grammar already says
    /// title-hook onsets stay uncovered; this extends the same rule to the
    /// incoming drop vocal's first lyric line, measured from the sidecar
    /// when present (fallback: one bar). The downbeat impact itself is the
    /// slam and stays; rides resume after the line.
    private static func keepGuestFirstLineClear(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        let beatSec = plan.beatSeconds
        guard barSec > 0.05 else { return }
        let rideIDs: Set<String> = ["airSweep", "bassDrop", "impact", "crash"]
        let dropStarts = plan.pulseRegions.filter { $0.role == .drop }.map(\.timelineStart)

        var removed: [String] = []
        for drop in dropStarts.sorted() {
            guard let lead = plan.placements.first(where: {
                $0.role == .dominant && abs($0.timelineStart - drop) < beatSec * 0.75
            }) else { continue }
            var lineEnd = drop + barSec   // fallback: protect the first bar
            if let words = profiles[lead.songID]?.analysis.signal?.lyricWords, !words.isEmpty {
                let ratio = max(lead.tempoRatio, 0.0001)
                let srcLo = lead.sourceStart - 0.05
                let srcHi = lead.sourceStart + 6.0 * ratio
                let lineWords = words.filter { $0.t >= srcLo && $0.t <= srcHi }
                    .sorted { $0.t < $1.t }
                var lastT: Double? = nil
                for w in lineWords {
                    if let prev = lastT, w.t - prev > 0.7 { break }
                    lastT = w.t
                }
                if let lastT {
                    let srcEnd = lastT + 0.5
                    lineEnd = lead.timelineStart + (srcEnd - lead.sourceStart) / ratio
                }
            }
            lineEnd = min(lineEnd, drop + 2 * barSec)
            let hi = lineEnd + AutoGainPolicy.duckAttackSeconds
            // SLIDE, don't delete — festival density is a locked flavor;
            // this rule is about WHEN the rides land, not whether.
            for i in plan.sfxEvents.indices {
                let e = plan.sfxEvents[i]
                guard rideIDs.contains(e.assetID) else { continue }
                guard e.timelineStart > drop + 0.02, e.timelineStart < hi else { continue }
                let beatsPast = ((hi - drop) / beatSec).rounded(.up)
                var newT = drop + beatsPast * beatSec
                // Stagger multiple slid events onto successive beats.
                while plan.sfxEvents.contains(where: {
                    $0.assetID == plan.sfxEvents[i].assetID
                        && abs($0.timelineStart - newT) < 0.15
                        && $0.timelineStart != e.timelineStart
                }) {
                    newT += beatSec
                }
                removed.append(String(
                    format: "%@ %.2f→%.2f", e.assetID, e.timelineStart, newT
                ))
                plan.sfxEvents[i].timelineStart = newT
            }
        }
        guard !removed.isEmpty else { return }
        decisions.append(
            AutoDecision(
                kind: .removedInvalidSFX,
                songTitle: nil,
                detail: "slid rides off the drop vocal's first line: " + removed.joined(separator: ", ")
            )
        )
    }

    /// Make the volume knob mean the same thing in every section.
    ///
    /// `songPlacementVolume(energy:)` writes a level from an ENERGY STORY,
    /// with no idea how loud the underlying record is there. Two sections set
    /// to the same volume therefore render at different loudness whenever the
    /// source differs, and the mix lurches as it moves between them — measured
    /// as a +7.6 LU step into the Paramore title hook, and 13–19 LU of overall
    /// range on several mixes. The peak limiter cannot correct this; it only
    /// catches transients, not programme level.
    ///
    /// So: measure each plain song section's own source level, and scale its
    /// clip volume by the difference from the mix's reference. Rendered level
    /// then tracks the energy story instead of the record's mastering. The
    /// correction is bounded, so a genuinely quiet section stays relatively
    /// quiet and this never becomes a compressor.
    ///
    /// Full-mix sections only — stems carry their own measured makeup, and
    /// join staging (pivot grains, drop leads, title copies) is applied after
    /// this and deliberately overrides it.
    private static func matchSectionLoudness(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return }

        struct Section { var index: Int; var db: Double; var weight: Double }
        var sections: [Section] = []
        for i in plan.placements.indices {
            let p = plan.placements[i]
            guard p.role == .dominant, p.stemKind == nil else { continue }
            guard p.timelineDuration >= barSec * 2 else { continue }
            guard let signal = profiles[p.songID]?.analysis.signal else { continue }
            let src = signal.meanRMSDB(from: p.sourceStart, to: p.sourceEnd)
            guard src > -60 else { continue }
            // EFFECTIVE level (source × current clip volume), so matching is
            // a FIXED POINT: re-running converges instead of double-scaling.
            // The listen loop re-validates plans, and the source-only delta
            // scaled already-matched sections a second time.
            let db = src + 20 * log10(max(p.volume, 0.01))
            sections.append(Section(index: i, db: db, weight: p.timelineDuration))
        }
        guard sections.count >= 2 else { return }

        // Duration-weighted median: the level the mix actually sits at, not
        // an average a single long quiet section could drag down.
        let sorted = sections.sorted { $0.db < $1.db }
        let totalWeight = sorted.reduce(0) { $0 + $1.weight }
        var cumulative = 0.0
        var reference = sorted[sorted.count / 2].db
        for s in sorted {
            cumulative += s.weight
            if cumulative >= totalWeight / 2 {
                reference = s.db
                break
            }
        }

        var adjusted = 0
        var worst = 0.0
        for s in sections {
            let delta = min(
                AutoGainPolicy.loudnessMatchMaxBoostDB,
                max(-AutoGainPolicy.loudnessMatchMaxCutDB, reference - s.db)
            )
            guard abs(delta) > 0.25 else { continue }
            let scale = pow(10.0, delta / 20.0)
            let old = plan.placements[s.index].volume
            plan.placements[s.index].volume = min(
                AutoGainPolicy.maxClipVolume,
                max(0.02, old * scale)
            )
            // Supporting stems riding this section move WITH it. Their
            // levels were staged relative to the title vocal; when the
            // sections around them rise to reference and they do not, the
            // title window turns into a relative pit (measured: a −34 dB
            // "dead air" hole at every title entrance in the crates whose
            // sections got boosted).
            let span = (plan.placements[s.index].timelineStart,
                        plan.placements[s.index].timelineEnd)
            for j in plan.placements.indices {
                let q = plan.placements[j]
                guard q.role == .supporting, q.stemKind != nil, q.stemKind != .vocals else { continue }
                let mid = q.timelineStart + q.timelineDuration / 2
                guard mid > span.0, mid < span.1 else { continue }
                plan.placements[j].volume = min(
                    AutoGainPolicy.maxClipVolume,
                    max(0.02, q.volume * scale)
                )
            }
            adjusted += 1
            if abs(delta) > abs(worst) { worst = delta }
        }
        guard adjusted > 0 else { return }
        decisions.append(
            AutoDecision(
                kind: .imposedClubEnergyCurve,
                songTitle: nil,
                detail: String(
                    format: "loudness-matched %d sections to %.1f dB reference (largest %+.1f dB)",
                    adjusted, reference, worst
                )
            )
        )
    }

    /// The approach to a drop must BUILD, not fall into a hole.
    ///
    /// A build clip that walks its source forward can wander into the song's
    /// own quiet bridge right where tension should peak. Drop 2 did exactly
    /// that — its last two bars fell 7 dB and then the drop slammed +11 dB,
    /// while Drop 1's approach holds within 1 dB. Riser and snare underneath
    /// cannot hold a level the music itself has abandoned.
    ///
    /// Fix at the arrangement, not with gain: rewind the last bars to the
    /// clip's own strong head, so the build keeps its energy into the
    /// downbeat. `repairQuietSourceTails` uses a 15 dB "dead air" threshold
    /// that a merely-weak passage never trips; immediately before a drop a
    /// much smaller dip is already audible, hence the tighter bar here.
    private static func repairPreDropDip(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return }
        let dropStarts = plan.pulseRegions.filter { $0.role == .drop }.map(\.timelineStart)
        guard !dropStarts.isEmpty else { return }
        let dipThresholdDB = 8.0
        let tailBars = 2.0
        var tails: [AutoClipPlacement] = []

        for drop in dropStarts.sorted() {
            // The dominant material running INTO this drop.
            guard let idx = plan.placements.indices.first(where: {
                let p = plan.placements[$0]
                return p.role == .dominant
                    && abs(p.timelineEnd - drop) < barSec * 0.3
                    && p.timelineDuration >= barSec * 4
                    && p.stemKind != .vocals
            }) else { continue }
            let p = plan.placements[idx]
            guard let signal = profiles[p.songID]?.analysis.signal else { continue }

            let tailDur = min(tailBars * barSec, p.timelineDuration * 0.5)
            guard tailDur >= barSec * 0.9 else { continue }
            let tailSrcStart = p.sourceStart + (p.timelineDuration - tailDur) * p.tempoRatio
            let tailDB = signal.meanRMSDB(from: tailSrcStart, to: p.sourceEnd)
            let headDB = signal.meanRMSDB(
                from: p.sourceStart,
                to: p.sourceStart + min(4 * barSec * p.tempoRatio, p.sourceEnd - p.sourceStart)
            )
            guard headDB > -80, tailDB > -120 else { continue }
            guard headDB - tailDB > dipThresholdDB else { continue }

            let splitAt = p.timelineEnd - tailDur
            var tail = p
            tail.timelineStart = splitAt
            tail.timelineDuration = tailDur
            tail.sourceStart = p.sourceStart   // replay the strong head
            tail.continuesPrevious = false
            tail.fadeIn = .hardCut
            tails.append(tail)

            plan.placements[idx].timelineDuration = splitAt - p.timelineStart
            plan.placements[idx].fadeOut = .none
            decisions.append(
                AutoDecision(
                    kind: .shortenedLowEnergySection,
                    songTitle: profiles[p.songID]?.title,
                    detail: String(
                        format: "pre-drop dip repaired @%.1fs (build tail was %.1f dB under its head)",
                        splitAt, headDB - tailDB
                    )
                )
            )
        }
        plan.placements.append(contentsOf: tails)
    }

    /// Ride the INCOMING voice in over the outgoing track's music, before the
    /// switch.
    ///
    /// Even with level and filter made continuous, Drop 1 still changed the
    /// lead VOICE and the energy in the same sample — the ear meets a new
    /// singer and a new arrangement at once, which is what still read as
    /// jarring. Previewing Deck B's run-up phrase over Deck A's instrumental
    /// means only the energy changes at the drop; the voice is already
    /// accepted. This is the standard DJ vocal ride-in, and it is only
    /// possible because the Demucs vocal stem lets us take the voice without
    /// its band.
    ///
    /// Stays a tease, not a duet: `incomingVocalPreviewScale` keeps it under
    /// Deck A's lead, it is `supporting`, and it ENDS at `loopStart` so the
    /// chop and the drop still each own their moment. Two bars sits well
    /// inside the call-and-response allowance.
    private static func addIncomingVocalRideIn(
        _ plan: inout AutoRemixPlan,
        decisions: inout [AutoDecision]
    ) {
        let beatSec = plan.beatSeconds
        let barSec = plan.barSeconds
        guard beatSec > 0.01, barSec > 0.05 else { return }
        let dropStarts = plan.pulseRegions.filter { $0.role == .drop }.map(\.timelineStart)
        guard let drop = dropStarts.min() else { return }

        // The join CONTRACT is the authority on window geometry; the
        // buildOut region is the pre-contract fallback.
        let loopStart: Double
        if let c = plan.joinContracts.first(where: {
            $0.kind == .sweepJoin && abs($0.cutAt - drop) < beatSec * 0.5
        }) {
            loopStart = c.windowStart
        } else if let window = plan.pulseRegions.first(where: {
            $0.role == .buildOut && abs($0.timelineEnd - drop) < beatSec * 0.75
        }) {
            loopStart = window.timelineStart
        } else { return }

        // The incoming lead: the vocal that owns Drop 1.
        guard let incoming = plan.placements.first(where: {
            $0.role == .dominant && $0.stemKind == .vocals
                && abs($0.timelineStart - drop) < beatSec * 0.75
        }) else { return }
        // Only a genuine song switch needs a voice introduced.
        guard incoming.songID != plan.mashupBedSongID else { return }

        let rideDur = min(
            AutoGainPolicy.incomingVocalPreviewBars * barSec,
            max(0, loopStart - 0.05)
        )
        guard rideDur >= barSec * 0.9 else { return }
        let rideStart = loopStart - rideDur
        // Its own run-up material, so the hook still lands fresh on the drop.
        let rideSource = incoming.sourceStart - rideDur * incoming.tempoRatio
        guard rideSource >= 0.05 else { return }

        // Don't stack on an existing preview.
        let already = plan.placements.contains {
            $0.songID == incoming.songID && $0.stemKind == .vocals
                && $0.timelineStart < loopStart - 0.05
                && $0.timelineEnd > rideStart + 0.05
        }
        if already { return }

        // Must stay under whatever Deck A's lead is doing there.
        let deckALead = plan.placements
            .filter {
                $0.role == .dominant && $0.songID != incoming.songID
                    && $0.timelineStart < loopStart && $0.timelineEnd > rideStart
            }
            .map(\.volume)
            .max() ?? AutoGainPolicy.vocalStemMakeupDefault

        var fx = ClipEffectSettings()
        // Sits behind the lead rather than competing with it.
        fx.setLevel(26, for: MixrEffect.blur.rawValue)
        fx = AutoSupportedEffects.sanitize(fx)

        var ride = incoming
        ride.timelineStart = rideStart
        ride.timelineDuration = rideDur
        ride.sourceStart = rideSource
        ride.role = .supporting
        ride.volume = min(
            AutoGainPolicy.maxClipVolume,
            deckALead * AutoGainPolicy.incomingVocalPreviewScale
        )
        ride.effects = fx
        ride.continuesPrevious = false
        // Swells in so the new voice arrives rather than appearing.
        ride.fadeIn = ClipTransition(
            type: .crossfade,
            duration: 4,
            curve: AutoTransitionEnvelope.equalPowerCurveName
        )
        ride.fadeOut = ClipTransition(type: .none, duration: 0)
        ride.overlapsPreviousSeconds = rideDur
        plan.placements.append(ride)

        decisions.append(
            AutoDecision(
                kind: .hookReplace,
                songTitle: nil,
                detail: String(
                    format: "incoming vocal ride-in %.1f bars @%.2fs (src=%.2f vol=%.2f under lead %.2f)",
                    rideDur / barSec, rideStart, rideSource, ride.volume, deckALead
                )
            )
        )
    }

    /// Carry the bed's harmonic layer under the sweep window so the two
    /// decks genuinely OVERLAP. Authority is `joinContracts.kind == .sweepJoin`
    /// plus `coverage` — never a grain-count signature.
    ///
    /// `.bedOther` / `.duckedFullMix` require a floor spanning the window.
    /// `.noneRequired` does not invent one.
    private static func addPivotBlendFloor(
        _ plan: inout AutoRemixPlan,
        decisions: inout [AutoDecision]
    ) {
        let beatSec = plan.beatSeconds
        guard beatSec > 0.01 else { return }
        var floors: [AutoClipPlacement] = []

        for contract in plan.joinContracts where contract.kind == .sweepJoin {
            let loopStart = contract.windowStart
            let drop = contract.cutAt
            let bedID = contract.outgoingSongID ?? plan.mashupBedSongID
            switch contract.coverage {
            case .noneRequired:
                continue
            case .bedOther, .duckedFullMix:
                break
            }
            guard let bedID else { continue }

            let wantOther = contract.coverage == .bedOther
            let covered = plan.placements.contains {
                $0.songID == bedID
                    && (wantOther ? $0.stemKind == .other : $0.stemKind == nil)
                    && $0.timelineStart < loopStart + 0.05 && $0.timelineEnd > drop - 0.08
            }
            if covered { continue }

            let source = plan.placements
                .filter({
                    $0.songID == bedID
                        && (wantOther ? $0.stemKind == .other : ($0.stemKind == nil || $0.stemKind == .other))
                        && $0.role == .supporting
                        && $0.timelineStart < loopStart - 0.01
                        && $0.timelineEnd > loopStart - beatSec * 4
                        && $0.timelineEnd < drop - 0.01
                })
                .max(by: { $0.timelineEnd < $1.timelineEnd })
                ?? plan.placements
                    .filter({
                        $0.songID == bedID
                            && $0.timelineStart < loopStart - 0.01
                            && $0.timelineEnd > loopStart - beatSec * 8
                    })
                    .max(by: { $0.timelineEnd < $1.timelineEnd })
            guard let source else { continue }

            var floor = source
            floor.timelineStart = loopStart
            floor.timelineDuration = drop - loopStart
            floor.sourceStart = source.sourceStart
                + (loopStart - source.timelineStart) * source.tempoRatio
            floor.volume = min(source.volume, AutoGainPolicy.pivotBedFloorVolume)
            floor.role = .supporting
            if wantOther { floor.stemKind = .other }
            floor.continuesPrevious = false
            floor.fadeIn = .hardCut
            floor.fadeOut = ClipTransition(
                type: .crossfade,
                duration: 4,
                curve: AutoTransitionEnvelope.equalPowerCurveName
            )
            floor.overlapsPreviousSeconds = 0
            floors.append(floor)
            decisions.append(
                AutoDecision(
                    kind: .hookReplace,
                    songTitle: nil,
                    detail: String(format: "pivot blend floor (%@ @%.2f vol=%.2f)",
                                   wantOther ? "bed other" : "ducked full-mix",
                                   loopStart, floor.volume)
                )
            )
        }
        plan.placements.append(contentsOf: floors)
    }

    /// Place a broadband swell covering the last beat into the hard cut when
    /// nothing already covers that seam. Reads `joinContracts.kind == .sweepJoin`.
    private static func coverPivotWallpaperSeam(
        _ plan: inout AutoRemixPlan,
        decisions: inout [AutoDecision]
    ) {
        let beatSec = plan.beatSeconds
        guard beatSec > 0.01 else { return }

        for contract in plan.joinContracts where contract.kind == .sweepJoin {
            let drop = contract.cutAt
            let lastBeatStart = drop - beatSec
            let covered = plan.sfxEvents.contains {
                $0.timelineEnd > lastBeatStart + 0.02 && $0.timelineStart < drop - 0.02
            }
            if covered { continue }

            for id in ["airSweep", "reverseCymbal", "sweepUp"] {
                guard let def = SoundEffectLibrary.definition(for: id) else { continue }
                let start = drop - def.durationSeconds
                guard start < drop - beatSec * 0.5 else { continue }
                plan.sfxEvents.append(
                    AutoSFXEvent(
                        assetID: id,
                        timelineStart: start,
                        purpose: "sweep seam cover on the last beat before the cut"
                    )
                )
                decisions.append(
                    AutoDecision(
                        kind: .addedRiserIntoDrop,
                        songTitle: nil,
                        detail: String(format: "seam cover %@ @%.2fs (last beat into cut)", id, start)
                    )
                )
                break
            }
        }
    }

    /// Rewind quiet source tails: a long dominant clip whose source decays
    /// into near-silence (spoken bridge, instrumental drop-out, breakdown
    /// tail) keeps playing dead air on the timeline. Split at the last loud
    /// bar boundary and loop the clip's own strong head under the remainder.
    /// Vocal stems keep their natural rests; the final (outro) placement may
    /// decay by design.
    private static func repairQuietSourceTails(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        decisions: inout [AutoDecision]
    ) {
        let barSec = plan.barSeconds
        let dbgRepair = ProcessInfo.processInfo.environment["MIXR_DEBUG_REPAIR"] == "1"
        if dbgRepair { print("REPAIR enter barSec=\(barSec) bed=\(plan.mashupBedSongID?.uuidString.prefix(8) ?? "nil") placements=\(plan.placements.count)") }
        guard barSec > 0.1 else { return }
        let lastDominantStart = plan.placements
            .filter { $0.role == .dominant }
            .map(\.timelineStart)
            .max() ?? .infinity
        var tails: [AutoClipPlacement] = []
        for i in plan.placements.indices {
            let p = plan.placements[i]
            // Dominant clips AND supporting instrumental stems (bed loops
            // under a drop): a quiet source tail in either leaves dead air.
            let eligibleRole = p.role == .dominant
                || (p.role == .supporting && p.stemKind != nil)
            guard eligibleRole, p.stemKind != .vocals else { continue }
            let isFinal = p.role == .dominant
                && p.timelineStart >= lastDominantStart - 0.05
            guard p.timelineDuration >= barSec * 4 else { continue }
            guard let signal = profiles[p.songID]?.analysis.signal else { continue }
            if isFinal {
                // End the song when the SONG ends: the outro may decay by
                // design, but if its source dies mid-clip the shaped trail
                // multiplies silence — 4.7 s of −47 dB before the fade even
                // starts. Trim to the last alive source moment; the trail
                // shaping then decays real material.
                var alive = p.sourceEnd
                var t = p.sourceEnd - 0.5
                let headDB = signal.meanRMSDB(
                    from: p.sourceStart,
                    to: p.sourceStart + min(4 * barSec * p.tempoRatio, p.sourceDuration)
                )
                while t > p.sourceStart + barSec * p.tempoRatio {
                    if signal.meanRMSDB(from: t, to: t + 0.5) > headDB - 18 { alive = t + 0.5; break }
                    t -= 0.5
                }
                let deadTail = (p.sourceEnd - alive) / max(p.tempoRatio, 0.001)
                if deadTail > 1.5 {
                    plan.placements[i].timelineDuration -= deadTail
                    decisions.append(
                        AutoDecision(
                            kind: .shortenedLowEnergySection,
                            songTitle: profiles[p.songID]?.title,
                            detail: String(format: "outro trimmed %.1fs of dead source tail (end when the song ends)", deadTail)
                        )
                    )
                }
                continue
            }

            let step = 0.5
            var head = -160.0
            let headEnd = min(p.sourceEnd, p.sourceStart + barSec * 8 * p.tempoRatio)
            var t = p.sourceStart
            while t < headEnd - step {
                head = max(head, signal.meanRMSDB(from: t, to: t + step))
                t += step
            }
            guard head > -60 else { continue }
            if dbgRepair {
                var tailMin = 0.0
                var tt = p.sourceStart + (p.sourceEnd - p.sourceStart) * 0.4
                while tt < p.sourceEnd - 0.5 {
                    tailMin = min(tailMin, signal.meanRMSDB(from: tt, to: tt + 0.5) - head)
                    tt += 0.5
                }
                print(String(format: "REPAIR tail? t=%.1f-%.1f src=%.1f ratio=%.2f head=%.1f tailMinRel=%.1f", p.timelineStart, p.timelineEnd, p.sourceStart, p.tempoRatio, head, tailMin))
            }

            // Longest quiet run in the clip's back half (>15 dB below the
            // head). The run need not reach the clip edge — dead air often
            // ends in one loud flick before the next section.
            let halfway = p.sourceStart + (p.sourceEnd - p.sourceStart) * 0.4
            var quietFrom: Double? = nil
            var runStart: Double? = nil
            t = halfway
            while t < p.sourceEnd - step {
                let quiet = signal.meanRMSDB(from: t, to: t + step) < head - 15
                if quiet {
                    if runStart == nil { runStart = t }
                    let runDur = (t + step - (runStart ?? t)) / max(p.tempoRatio, 0.001)
                    if runDur >= 1.2 { quietFrom = runStart; break }
                } else {
                    runStart = nil
                }
                t += step
            }
            guard let quietFrom else { continue }

            let quietTimeline = p.timelineStart
                + (quietFrom - p.sourceStart) / max(p.tempoRatio, 0.001)
            let keepBars = ((quietTimeline - p.timelineStart) / barSec).rounded(.down)
            guard keepBars >= 1 else { continue }
            let splitAt = p.timelineStart + keepBars * barSec
            let tailDur = p.timelineEnd - splitAt
            guard tailDur >= barSec * 0.9 else { continue }

            var tail = p
            tail.timelineStart = splitAt
            tail.timelineDuration = tailDur
            tail.sourceStart = p.sourceStart   // loop back to the strong head
            tail.continuesPrevious = false
            tail.fadeIn = .hardCut
            tails.append(tail)

            plan.placements[i].timelineDuration = splitAt - p.timelineStart
            plan.placements[i].fadeOut = .none
            decisions.append(
                AutoDecision(
                    kind: .shortenedLowEnergySection,
                    songTitle: profiles[p.songID]?.title,
                    detail: String(
                        format: "rewound quiet source tail @%.1fs to clip head (%.1fs of dead air)",
                        splitAt, tailDur
                    )
                )
            )
        }
        plan.placements.append(contentsOf: tails)

        // Whole-clip-quiet cameos (sparse verse of a guest over nothing):
        // rewinding their own head cannot help — keep the BED's drums+bass
        // looping underneath instead, like a DJ holding the groove under a
        // sparse vocal cameo. Reuse the drop's validated bed-stem island.
        guard let bedID = plan.mashupBedSongID else { return }
        let bedStemRefs = plan.placements.filter {
            $0.songID == bedID && $0.role == .supporting
                && ($0.stemKind == .drums || $0.stemKind == .bass)
        }
        guard !bedStemRefs.isEmpty else { return }
        var mixRef = -160.0
        for p in plan.placements where p.role == .dominant && p.stemKind == nil {
            if let signal = profiles[p.songID]?.analysis.signal {
                mixRef = max(mixRef, signal.meanRMSDB(from: p.sourceStart, to: p.sourceStart + 4))
            }
        }
        guard mixRef > -60 else { return }
        var backing: [AutoClipPlacement] = []
        for p in plan.placements {
            guard p.role == .dominant, p.stemKind == nil, p.songID != bedID else { continue }
            guard p.timelineStart < lastDominantStart - 0.05 else { continue }
            guard p.timelineDuration >= barSec * 4 else { continue }
            guard let signal = profiles[p.songID]?.analysis.signal else { continue }
            var clipMax = -160.0
            var t = p.sourceStart
            while t < p.sourceEnd - 0.5 {
                clipMax = max(clipMax, signal.meanRMSDB(from: t, to: t + 0.5))
                t += 0.5
            }
            if dbgRepair {
                print(String(format: "REPAIR cameo? t=%.1f-%.1f src=%.1f clipMax=%.1f mixRef=%.1f", p.timelineStart, p.timelineEnd, p.sourceStart, clipMax, mixRef))
            }
            guard clipMax < mixRef - 8 else { continue }
            // Already covered by bed stems (e.g. hook-replace)? Skip.
            let covered = bedStemRefs.contains {
                min($0.timelineEnd, p.timelineEnd) - max($0.timelineStart, p.timelineStart)
                    > p.timelineDuration * 0.5
            }
            guard !covered else { continue }
            let loopSec = barSec * 8
            for kind in [AutoStemKind.drums, AutoStemKind.bass] {
                guard let ref = bedStemRefs.first(where: { $0.stemKind == kind }) else { continue }
                var offset = 0.0
                while offset < p.timelineDuration - 0.05 {
                    let segDur = min(loopSec, p.timelineDuration - offset)
                    var seg = ref
                    seg.timelineStart = p.timelineStart + offset
                    seg.timelineDuration = segDur
                    seg.sourceStart = ref.sourceStart
                    seg.volume = 0.7
                    seg.fadeIn = .hardCut
                    seg.fadeOut = .none
                    seg.continuesPrevious = false
                    seg.overlapsPreviousSeconds = segDur
                    seg.slotIndex = p.slotIndex
                    backing.append(seg)
                    offset += segDur
                }
            }
            decisions.append(
                AutoDecision(
                    kind: .shortenedLowEnergySection,
                    songTitle: profiles[p.songID]?.title,
                    detail: String(
                        format: "bed drums+bass loop under quiet cameo @%.1fs (%.1f dB below mix)",
                        p.timelineStart, clipMax - mixRef
                    )
                )
            )
        }
        plan.placements.append(contentsOf: backing)
    }

    /// Dominant joins need real temporal overlap + equal-power fades, unless
    /// they are a club drop hard cut (pivot / hook-return slam) or already
    /// SFX-covered butts.
    private static func ensureHandoffOverlaps(
        _ plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        tuning: AutoTuning,
        warnings: inout [String],
        decisions: inout [AutoDecision]
    ) {
        let equalPower = AutoTransitionEnvelope.equalPowerCurveName
        let overlapSec = max(tuning.minSegmentSeconds, min(plan.barSeconds, plan.beatSeconds * 4))
        let overlapBeats = overlapSec / max(plan.beatSeconds, 0.001)

        let idxs = plan.placements.indices
            .filter { plan.placements[$0].role == .dominant }
            .sorted { plan.placements[$0].timelineStart < plan.placements[$1].timelineStart }

        for (prevIdx, nextIdx) in zip(idxs, idxs.dropFirst()) {
            let prev = plan.placements[prevIdx]
            let next = plan.placements[nextIdx]

            let voidBefore = plan.intentionalGaps.contains {
                $0.reason.localizedCaseInsensitiveContains("void")
                    && abs($0.end - next.timelineStart) < 0.05
            }
            if voidBefore { continue }

            // A sample-continuous segment split is not a join — never stage
            // handoff machinery against one (the old grain-signature check
            // matched the sweep's echo throw and re-floored mid-window
            // segments to full volume, undoing the lead taper).
            if next.continuesPrevious { continue }

            // Sweep-join pivot hard cut — never soften Drop 1 into an
            // equal-power fade-in. The pivot marker is the buildOut window
            // ending on this entrance (same key as the planner).
            let beatSec = plan.beatSeconds
            let barSec = plan.barSeconds
            _ = barSec
            // Contract is the authority; buildOut region and decision text
            // remain as fallback for plans built before contracts existed.
            let pivotBefore = plan.joinContracts.contains {
                $0.kind == .sweepJoin && abs($0.cutAt - next.timelineStart) < beatSec * 0.5
            } || plan.pulseRegions.contains { r in
                r.role == .buildOut && abs(r.timelineEnd - next.timelineStart) < beatSec * 0.75
            } || plan.decisions.contains {
                $0.kind == .pivotWallpaperLoop
                    && ($0.detail ?? "").contains(String(format: "%.1f", next.timelineStart))
            }
            if pivotBefore {
                plan.placements[nextIdx].fadeIn = .none
                plan.placements[nextIdx].volume = max(
                    plan.placements[nextIdx].volume,
                    AutoGainPolicy.incomingDropVolume
                )
                continue
            }

            // Club Drop 1 / Drop 2: hard cut + impact, not equal-power fade-in.
            if AutoRemixDiagnostics.incomingIsClubDrop(
                pulseRegions: plan.pulseRegions,
                timelineStart: next.timelineStart
            ) {
                if plan.placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - plan.placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        plan.placements[prevIdx].timelineDuration = trimmed
                    }
                }
                plan.placements[prevIdx].fadeOut = .none
                plan.placements[nextIdx].fadeIn = .none
                plan.placements[nextIdx].volume = max(
                    plan.placements[nextIdx].volume,
                    AutoGainPolicy.incomingDropVolume
                )
                continue
            }

            // Isolated title vocal / intro → title hook: outgoing yields
            // (quiet); incoming stays at full so the title token is not eaten.
            if next.stemKind == .vocals, prev.stemKind != .vocals,
               next.timelineDuration > beatSec * 8 {
                var prevP = plan.placements[prevIdx]
                var nextP = plan.placements[nextIdx]
                // One-beat overhang + 2-beat fade: mid-slope at the entrance
                // (same geometry as title-window staging, so re-validate
                // converges instead of re-trimming the tail flush).
                AutoJoinEngine.applyYieldJoin(
                    prev: &prevP, next: &nextP,
                    beats: 2, overhangSeconds: beatSec
                )
                plan.placements[prevIdx] = prevP
                plan.placements[nextIdx] = nextP
                continue
            }

            let titleHookJoin = prev.songID == next.songID
                && next.timelineDuration >= plan.barSeconds * 7.5
                && (
                    (next.sourceStart > prev.sourceEnd + plan.barSeconds * 0.25
                        && prev.timelineStart <= plan.barSeconds * 10)
                    || (next.sourceStart < prev.sourceEnd - 0.05
                        && abs(next.sourceStart - prev.sourceStart) < plan.barSeconds * 0.75)
                )
            // A hook-island rewind INSIDE a drop (8+8 final-peak repeat) is a
            // hard splice — a yield fade to zero there dips the drop.
            func inDropRegion(_ t: Double) -> Bool {
                plan.pulseRegions.contains {
                    $0.role == .drop && t > $0.timelineStart + 0.1 && t < $0.timelineEnd - 0.1
                }
            }
            // A same-source rewind next to the timeline head is the pre-drop
            // title hold (yield fade OK). The same rewind deep in the mix is
            // a Drop 2 hook repeat — hard splice, never a fade toward zero.
            let sourceRewind = prev.songID == next.songID
                && abs(next.sourceStart - prev.sourceStart) < plan.barSeconds * 0.75
            let joinInsideDrop = (inDropRegion(prev.timelineStart + prev.timelineDuration / 2)
                && inDropRegion(next.timelineStart + next.timelineDuration / 2))
                || (sourceRewind && prev.timelineStart > plan.barSeconds * 12)
            if titleHookJoin, !joinInsideDrop {
                var prevP = plan.placements[prevIdx]
                var nextP = plan.placements[nextIdx]
                AutoJoinEngine.applyYieldJoin(
                    prev: &prevP, next: &nextP,
                    beats: 2, overhangSeconds: plan.beatSeconds
                )
                plan.placements[prevIdx] = prevP
                plan.placements[nextIdx] = nextP
                continue
            }
            if titleHookJoin, joinInsideDrop {
                plan.placements[prevIdx].fadeOut = .none
                plan.placements[nextIdx].fadeIn = .none
                continue
            }

            // Continuous source (energy-curve / no-cut path) — never invent an overlap cut.
            let prevSourceEnd = prev.sourceStart + prev.timelineDuration * prev.tempoRatio
            if next.continuesPrevious || abs(next.sourceStart - prevSourceEnd) < 0.05 {
                continue
            }
            // Low-confidence club curve: no structural handoff surgery.
            if plan.decisions.contains(where: {
                $0.kind == .imposedClubEnergyCurve || $0.kind == .usedLowConfidenceFallback
            }), plan.mode == .remix {
                continue
            }

            // Different songs: incoming swells in and takes over (overlap).
            // Pivot Drop 1 stays a hard cut (handled above).
            if prev.songID != next.songID {
                var prevP = plan.placements[prevIdx]
                var nextP = plan.placements[nextIdx]
                AutoJoinEngine.applyTakeoverJoin(prev: &prevP, next: &nextP, beatSec: beatSec)
                nextP.volume = max(nextP.volume, AutoGainPolicy.incomingDropVolume)
                plan.placements[prevIdx] = prevP
                plan.placements[nextIdx] = nextP
                continue
            }

            let overlap = prev.timelineEnd - next.timelineStart
            if overlap >= overlapSec * 0.45 {
                if plan.placements[nextIdx].overlapsPreviousSeconds < 0.01 {
                    plan.placements[nextIdx].overlapsPreviousSeconds = overlap
                }
                plan.placements[prevIdx].fadeOut = ClipTransition(
                    type: .crossfade, duration: overlap / max(plan.beatSeconds, 0.001), curve: equalPower
                )
                plan.placements[nextIdx].fadeIn = ClipTransition(
                    type: .crossfade, duration: overlap / max(plan.beatSeconds, 0.001), curve: equalPower
                )
                continue
            }

            let joinLo = min(prev.timelineEnd, next.timelineStart)
            let joinHi = max(prev.timelineEnd, next.timelineStart)
            let sfxCover = plan.sfxEvents.contains { event in
                event.timelineEnd > joinLo - 0.02 && event.timelineStart < joinHi + 0.02
            }

            let songDuration = profiles[prev.songID]?.analysis.durationSeconds ?? .infinity
            let needEnd = next.timelineStart + overlapSec
            let extraTimeline = needEnd - prev.timelineEnd
            let extraSource = max(0, extraTimeline) * prev.tempoRatio
            if extraTimeline > 0.01,
               prev.sourceEnd + extraSource <= songDuration - 0.05 {
                plan.placements[prevIdx].timelineDuration = needEnd - prev.timelineStart
                plan.placements[prevIdx].fadeOut = ClipTransition(
                    type: .crossfade, duration: overlapBeats, curve: equalPower
                )
                plan.placements[nextIdx].fadeIn = ClipTransition(
                    type: .crossfade, duration: overlapBeats, curve: equalPower
                )
                plan.placements[nextIdx].overlapsPreviousSeconds = overlapSec
                decisions.append(
                    AutoDecision(
                        kind: .repairedTimelineGap,
                        songTitle: nil,
                        detail: "equal-power handoff overlap"
                    )
                )
            } else if abs(prev.timelineEnd - next.timelineStart) < 0.05, sfxCover {
                // Butt join with SFX cover — acceptable masking, no silence hole.
                continue
            } else if overlap > 0.05 {
                plan.placements[nextIdx].overlapsPreviousSeconds = max(
                    plan.placements[nextIdx].overlapsPreviousSeconds, overlap
                )
                plan.placements[prevIdx].fadeOut = ClipTransition(
                    type: .crossfade,
                    duration: overlap / max(plan.beatSeconds, 0.001),
                    curve: equalPower
                )
                plan.placements[nextIdx].fadeIn = ClipTransition(
                    type: .crossfade,
                    duration: overlap / max(plan.beatSeconds, 0.001),
                    curve: equalPower
                )
            } else if !sfxCover {
                warnings.append(
                    "A section join had no overlap and no SFX cover — kept continuous when possible."
                )
            }
        }
    }

    private static func isCrossfadeMasking(_ masking: AutoCutMasking) -> Bool {
        if case .equalPowerCrossfade = masking { return true }
        return false
    }

    private static func fadesTowardSilence(_ t: ClipTransition) -> Bool {
        switch t.type {
        case .fadeOut, .echoOut:
            return t.duration > 0
        case .crossfade, .auto:
            // Equal-power conserves energy; other curves can dig a hole.
            return t.curve != AutoTransitionEnvelope.equalPowerCurveName && t.duration > 0.5
        case .none:
            return false
        }
    }

    private static func fadesIn(_ t: ClipTransition) -> Bool {
        [.crossfade, .auto].contains(t.type) && t.duration > 0.5
    }

    private static func recomputedHandoffs(_ placements: [AutoClipPlacement]) -> Int {
        let dominants = placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        // Collapse head/body/tail of the same slot into one appearance.
        var slotSong: [(slot: Int, song: UUID)] = []
        for p in dominants {
            if let last = slotSong.last, last.slot == p.slotIndex {
                continue
            }
            slotSong.append((p.slotIndex, p.songID))
        }
        var n = 0
        for i in 1..<slotSong.count where slotSong[i].song != slotSong[i - 1].song {
            n += 1
        }
        return n
    }
}
