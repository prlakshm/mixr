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

        // ── 2. Same-song (same-track) placements must never overlap ──
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
                if overlap > 0.005 {
                    plan.placements[pair.0].timelineDuration -= overlap
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
        for g in intentional {
            let overlap = min(gap.end, g.end) - max(gap.start, g.start)
            if overlap > gap.length * 0.5, gap.length <= maxPause + 0.02 {
                return true
            }
        }
        // Hard-cut micro-pauses ≤ quarter beat are treated as intentional
        // even without an explicit marker (applier / planner may omit them).
        return gap.length <= maxPause + 0.005
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
