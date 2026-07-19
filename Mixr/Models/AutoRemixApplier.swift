#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Auto Remix Applier
//
// Turns a VALIDATED AutoRemixPlan into concrete MixrTrack clip arrays.
// Songs keep their tracks (id, color, mix state); only clips are rebuilt.
// The SFX track's clips are replaced by the plan's coordinated events.
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

        // ── SFX track: replace with the plan's events (skip unknowns) ──
        var placedSFX: [AutoSFXEvent] = []
        if !plan.sfxEvents.isEmpty {
            let idx = ensureSFXTrack(in: &result)
            var clips: [MixrClip] = []
            for event in plan.sfxEvents.sorted(by: { $0.timelineStart < $1.timelineStart }) {
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
                let start = SoundEffectLibrary.nonOverlappingStart(
                    proposedStart: MixrTimeline.units(fromSeconds: max(0, event.timelineStart)),
                    lengthUnits: definition.lengthUnits,
                    in: clips
                )
                clips.append(
                    MixrClip(
                        id: UUID(),
                        start: start,
                        length: definition.lengthUnits,
                        soundEffectID: definition.id
                    )
                )
                placedSFX.append(event)
            }
            result[idx].clips = clips
        } else if let idx = result.firstIndex(where: { $0.isSFXTrack }) {
            result[idx].clips = []
        }

        appliedPlan.sfxEvents = placedSFX
        return Applied(tracks: result, plan: appliedPlan)
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

    private static func ensureSFXTrack(in tracks: inout [MixrTrack]) -> Int {
        if let idx = tracks.firstIndex(where: { $0.isSFXTrack }) { return idx }
        tracks.append(
            MixrTrack(
                id: UUID(),
                title: "Sound Effects",
                artist: "Built-in SFX",
                duration: "",
                durationSeconds: nil,
                bpm: nil,
                key: nil,
                color: .silver,
                volume: 0.85,
                isMuted: false,
                trackType: .soundEffect,
                url: nil,
                artworkData: nil,
                clips: []
            )
        )
        return tracks.count - 1
    }
}
