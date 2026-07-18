import Foundation

// MARK: - Auto Remix Validator
//
// Validates and REPAIRS a plan before it ever touches the timeline:
// clamps source ranges, enforces clip minimums, removes same-song
// overlaps, closes accidental gaps, caps simultaneous sources at two,
// guarantees every riser has a payoff, and snaps impacts to downbeats.
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

        // ── 1. Source ranges must live inside each song ──
        plan.placements = plan.placements.compactMap { p in
            var p = p
            p.effects = AutoSupportedEffects.sanitize(p.effects)
            guard let duration = profiles[p.songID]?.analysis.durationSeconds else { return p }
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
            guard p.timelineDuration >= minLen else {
                if p.role == .dominant {
                    warnings.append("Dropped a section that no longer had enough source material.")
                }
                return nil
            }
            return p
        }

        // ── 2. Same-song placements may overlap ONLY for a declared
        // equal-power crossfade (true temporal overlap). Undeclared
        // overlap is trimmed away as before.
        var bySong: [UUID: [Int]] = [:]
        for (i, p) in plan.placements.enumerated() {
            bySong[p.songID, default: []].append(i)
        }
        for (_, idxs) in bySong {
            let sorted = idxs.sorted {
                plan.placements[$0].timelineStart < plan.placements[$1].timelineStart
            }
            for pair in zip(sorted, sorted.dropFirst()) {
                let overlap = plan.placements[pair.0].timelineEnd - plan.placements[pair.1].timelineStart
                let declared = plan.placements[pair.1].overlapsPreviousSeconds
                if overlap > 0.005 {
                    if declared > 0.005, overlap <= declared + 0.05 {
                        continue   // sanctioned crossfade overlap
                    }
                    let excess = overlap - max(0, declared)
                    plan.placements[pair.0].timelineDuration -= excess
                    if plan.placements[pair.0].timelineDuration < minLen {
                        plan.placements[pair.0].timelineDuration = 0
                        warnings.append(
                            "Removed a clip segment that collided with the same song's next section."
                        )
                    }
                }
            }
        }
        plan.placements.removeAll { $0.timelineDuration < minLen }

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

        // ── 3. No more than two full-song sources at once ──
        let dominants = plan.placements.filter { $0.role == .dominant }
        plan.placements.removeAll { p in
            guard p.role == .supporting else { return false }
            let concurrent = dominants.filter {
                $0.timelineStart < p.timelineEnd - 0.01 && $0.timelineEnd > p.timelineStart + 0.01
            }
            let distinctSongs = Set(concurrent.map(\.songID) + [p.songID])
            if distinctSongs.count > 2 {
                warnings.append("Removed an overlap that would have stacked three songs at once.")
                return true
            }
            return false
        }

        // ── 4. Close accidental gaps (> one eighth note of silence) ──
        // Coverage includes song clips AND SFX so transition tails / hits
        // don't look like empty stretches. Intentional micro-pauses and
        // pre-drop pauses are preserved.
        let maxGap = plan.eighthNoteSeconds
        let intentional = plan.intentionalGaps
        var coverage = mergedCoverage(
            placements: plan.placements,
            sfxEvents: plan.sfxEvents
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
                sfxEvents: plan.sfxEvents
            )
        }

        // ── 5. Every riser/build SFX must lead to a payoff ──
        let payoffStarts = plan.placements.filter { $0.role == .dominant }.map(\.timelineStart)
        let beforeSFX = plan.sfxEvents.count
        plan.sfxEvents.removeAll { event in
            guard ["riser", "snareBuild", "reverseCymbal", "airSweep"].contains(event.assetID) else {
                return false
            }
            let lands = payoffStarts.contains { abs($0 - event.timelineEnd) < 0.35 }
            if !lands {
                decisions.append(
                    AutoDecision(
                        kind: .removedInvalidSFX,
                        songTitle: nil,
                        detail: "\(event.assetID) without payoff"
                    )
                )
                return true
            }
            return false
        }
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

    private static func isCrossfadeMasking(_ masking: AutoCutMasking) -> Bool {
        if case .equalPowerCrossfade = masking { return true }
        return false
    }

    private static func fadesTowardSilence(_ t: ClipTransition) -> Bool {
        [.fadeOut, .crossfade, .auto].contains(t.type) && t.duration > 0.5
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
