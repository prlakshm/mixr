#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Auto Remix Applier
//
// Turns a VALIDATED AutoRemixPlan into concrete MixrTrack clip arrays.
// Songs keep their tracks (id, color, mix state); only clips are rebuilt.
// SFX: clips are packed onto one or more SFX rows with per-row
// nonOverlappingStart. Simultaneous hits (riser + impact + pulse) land on
// adjacent SFX rows — same as a user dragging a one-shot up/down.
// Returns the applied plan so the summary reflects skipped SFX / repairs.
// The caller wraps the whole apply in one undo snapshot.

nonisolated enum AutoRemixApplier {

    struct Applied: Sendable {
        var tracks: [MixrTrack]
        /// Plan reflecting what was actually placed (SFX list may shrink).
        var plan: AutoRemixPlan
    }

    static func apply(_ plan: AutoRemixPlan, to tracks: [MixrTrack]) -> Applied {
        var result = tracks
        var appliedPlan = plan
        let placementsBySong = Dictionary(grouping: plan.placements, by: \.songID)
        let arrangedSongIDs = Set(plan.placements.map(\.songID))

        for ti in result.indices where !result[ti].isSFXTrack {
            let trackID = result[ti].id
            if let placements = placementsBySong[trackID] {
                result[ti].clips = placements
                    .sorted { $0.timelineStart < $1.timelineStart }
                    .map(makeClip)
            } else if !result[ti].clips.isEmpty, !arrangedSongIDs.isEmpty {
                // Song excluded by the planner (reported in warnings).
                result[ti].clips = []
            }
        }

        // Expand pulse regions into on-grid hits, then merge with musical SFX.
        let pulseHits: [AutoSFXEvent]
        if let policy = plan.pulsePolicy, !plan.pulseRegions.isEmpty {
            pulseHits = AutoClubPulse.scheduleHits(
                regions: plan.pulseRegions,
                policy: policy,
                beatSeconds: plan.beatSeconds,
                barSeconds: plan.barSeconds
            ).map {
                AutoSFXEvent(assetID: $0.assetID, timelineStart: $0.timelineStart, purpose: $0.purpose)
            }
        } else {
            pulseHits = []
        }
        let allSFX = (plan.sfxEvents + pulseHits).sorted { $0.timelineStart < $1.timelineStart }

        // Reset every SFX row, then pack exact-time hits across rows.
        for ti in result.indices where result[ti].isSFXTrack {
            result[ti].clips = []
        }

        var placedSFX: [AutoSFXEvent] = []
        if !allSFX.isEmpty {
            if !result.contains(where: { $0.isSFXTrack }) {
                result.append(SoundEffectLibrary.makeSFXTrack(primary: true))
            }
            for event in allSFX {
                guard let definition = SoundEffectLibrary.definition(for: event.assetID) else {
                    appliedPlan.decisions.append(
                        AutoDecision(
                            kind: .removedInvalidSFX,
                            songTitle: nil,
                            detail: event.assetID
                        )
                    )
                    appliedPlan.warnings.append(
                        "Skipped unknown SFX asset '\(event.assetID)'."
                    )
                    continue
                }
                let unit = MixrTimeline.units(fromSeconds: max(0, event.timelineStart))
                SoundEffectLibrary.placeExact(
                    definition: definition,
                    atUnit: unit,
                    into: &result
                )
                if !SoundEffectLibrary.isPulseLayer(definition.id) {
                    placedSFX.append(event)
                }
            }
            // Drop unused empty spill lanes (keep the primary / top SFX row).
            pruneEmptySecondarySFXTracks(&result)
        } else {
            pruneEmptySecondarySFXTracks(&result)
        }

        appliedPlan.sfxEvents = placedSFX
        return Applied(tracks: result, plan: appliedPlan)
    }

    /// Removes empty SFX spill lanes; keeps the first (top) SFX row even if empty.
    private static func pruneEmptySecondarySFXTracks(_ tracks: inout [MixrTrack]) {
        var seenPrimary = false
        tracks.removeAll { track in
            guard track.isSFXTrack else { return false }
            if !seenPrimary {
                seenPrimary = true
                return false
            }
            return track.clips.isEmpty
        }
    }

    // MARK: - Clip construction

    private static func makeClip(_ p: AutoClipPlacement) -> MixrClip {
        MixrClip(
            id: UUID(),
            start: MixrTimeline.units(fromSeconds: p.timelineStart),
            length: max(
                MixrTimeline.minClipLengthUnits,
                MixrTimeline.units(fromSeconds: p.timelineDuration)
            ),
            playbackSpeed: p.tempoRatio,
            transitionIn: p.fadeIn,
            transitionOut: p.fadeOut,
            volume: min(1, max(0, p.volume)),
            effects: AutoSupportedEffects.sanitize(p.effects),
            soundEffectID: nil,
            sourceOffsetSeconds: max(0, p.sourceStart)
        )
    }
}
