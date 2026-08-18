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
            let floor = isHookEchoThrow(p) ? echoMinLen : minLen
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
            let floor = isHookEchoThrow(p) ? echoMinLen : minLen
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
                abs(($0 - beatSec) - event.timelineEnd) < 0.55
                    || abs($0 - event.timelineEnd) < 0.45
            }
            if takeOut { return true }
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

            // Xirex pivot hard cut — never soften Drop 1 into an equal-power fade-in.
            let beatSec = plan.beatSeconds
            let barSec = plan.barSeconds
            let pivotBefore = plan.placements.contains { g in
                g.role == .supporting
                    && abs(g.timelineDuration - beatSec) < beatSec * 0.4
                    && g.timelineStart >= next.timelineStart - tuning.pivotLookbackSeconds(barSec: barSec)
                    && g.timelineStart < next.timelineStart - 0.02
                    && g.timelineEnd <= next.timelineStart + 0.08
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

            // Title-hook island (intro/verse → first complete chorus, or 8+8 hold):
            // hard cut. Equal-power fade-in eats the opening title word.
            let titleHookJoin = prev.songID == next.songID
                && next.timelineDuration >= plan.barSeconds * 7.5
                && (
                    (next.sourceStart > prev.sourceEnd + plan.barSeconds * 0.25
                        && prev.timelineStart <= plan.barSeconds * 10)
                    || (next.sourceStart < prev.sourceEnd - 0.05
                        && abs(next.sourceStart - prev.sourceStart) < plan.barSeconds * 0.75)
                )
            if titleHookJoin {
                if plan.placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - plan.placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        plan.placements[prevIdx].timelineDuration = trimmed
                    }
                }
                plan.placements[prevIdx].fadeOut = .hardCut
                plan.placements[nextIdx].fadeIn = .hardCut
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

            // Different songs: never extend two dominants into each other.
            // Switch by hard cut at full clip volume — no fade-in from silence.
            if prev.songID != next.songID {
                if plan.placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - plan.placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        plan.placements[prevIdx].timelineDuration = trimmed
                    }
                }
                plan.placements[prevIdx].fadeOut = .hardCut
                plan.placements[nextIdx].fadeIn = .hardCut
                plan.placements[nextIdx].volume = max(
                    plan.placements[nextIdx].volume,
                    AutoGainPolicy.incomingDropVolume
                )
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
