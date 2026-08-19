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
        var stemTracksByParent: [UUID: [MixrTrack]] = [:]

        for ti in result.indices where !result[ti].isSFXTrack {
            let trackID = result[ti].id
            if let placements = placementsBySong[trackID] {
                let resolvedStems = plan.stemsBySongID[trackID]
                    ?? AutoStemResolver.resolve(songURL: result[ti].url)
                func stemURL(_ kind: AutoStemKind) -> URL? { resolvedStems.url(for: kind) }

                let fullMix = placements.filter { p in
                    guard let kind = p.stemKind else { return true }
                    return stemURL(kind) == nil
                }
                result[ti].clips = fullMix
                    .sorted { $0.timelineStart < $1.timelineStart }
                    .map(makeClip)

                var extras: [MixrTrack] = []
                for kind in AutoStemKind.allCases {
                    let kindPlacements = placements.filter { $0.stemKind == kind }
                    guard !kindPlacements.isEmpty, let url = stemURL(kind) else { continue }
                    let parent = result[ti]
                    extras.append(
                        MixrTrack(
                            id: UUID(),
                            title: "\(parent.title) · \(kind.rawValue)",
                            artist: parent.artist,
                            duration: parent.duration,
                            durationSeconds: parent.durationSeconds,
                            bpm: parent.bpm,
                            key: parent.key,
                            color: parent.color,
                            volume: parent.volume,
                            isMuted: false,
                            url: url,
                            artworkData: nil,
                            clips: kindPlacements
                                .sorted { $0.timelineStart < $1.timelineStart }
                                .map(makeClip)
                        )
                    )
                }
                if !extras.isEmpty {
                    stemTracksByParent[trackID] = extras
                }
            } else if !result[ti].clips.isEmpty, !arrangedSongIDs.isEmpty {
                // Song excluded by the planner (reported in warnings).
                result[ti].clips = []
            }
        }

        let parentIDs = result.filter { !$0.isSFXTrack }.map(\.id)
        for parentID in parentIDs.reversed() {
            guard let extras = stemTracksByParent[parentID],
                  let idx = result.firstIndex(where: { $0.id == parentID }) else { continue }
            for (offset, extra) in extras.enumerated() {
                result.insert(extra, at: idx + 1 + offset)
            }
        }

        // Expand pulse regions into on-grid hits, then merge with musical SFX.
        let pulseHits: [AutoSFXEvent]
        if let policy = plan.pulsePolicy, !plan.pulseRegions.isEmpty {
            pulseHits = AutoClubPulse.scheduleHits(
                regions: plan.pulseRegions,
                policy: policy,
                beatSeconds: plan.beatSeconds,
                barSeconds: plan.barSeconds,
                halfTimeDrop: plan.clubFlavor?.bias.halfTimeDrop ?? false
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
        if appliedPlan.mode == .mashup {
            let ids = Set(placedSFX.map(\.assetID))
            let hasTakeOut = ids.contains("riser") || ids.contains("snareBuild") || ids.contains("tapeStop")
            let hasRide = ids.contains("airSweep") || ids.contains("clapFill") || ids.contains("impact")
            let hasFestival = appliedPlan.decisions.contains {
                $0.kind == .addedRiserIntoDrop
                    && ($0.detail ?? "").localizedCaseInsensitiveContains("festival")
            }
            if (hasTakeOut || hasRide), !hasFestival {
                appliedPlan.decisions.append(
                    AutoDecision(
                        kind: .addedRiserIntoDrop,
                        songTitle: nil,
                        detail: "festival take-out + drop-ride (riser/snare/tape then air/clap/impact)"
                    )
                )
            }
            if !appliedPlan.decisions.contains(where: {
                ($0.detail ?? "").localizedCaseInsensitiveContains("addedRiserIntoDrop")
                    && ($0.detail ?? "").localizedCaseInsensitiveContains("festival")
            }) {
                appliedPlan.decisions.append(
                    AutoDecision(
                        kind: .selectedAnchor,
                        songTitle: nil,
                        detail: "addedRiserIntoDrop — festival take-out + drop-ride on Drop 1 mix window"
                    )
                )
            }
        }
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
        let units = MixrTimeline.units(fromSeconds: max(0.05, p.timelineDuration))
        // Short supporting echo / stutter chops may sit below the global
        // clip minimum so bounce WAVs hear the literal duplicate.
        let isShortEcho = p.role == .supporting
            && units < MixrTimeline.minClipLengthUnits
            && (
                p.overlapsPreviousSeconds > 0.05
                    || p.effects.level(for: MixrEffect.echo.rawValue) >= 8
                    || p.effects.level(for: MixrEffect.blur.rawValue) >= 36
                    || p.fadeOut.type == .echoOut
            )
        let minUnits: CGFloat = isShortEcho
            ? max(0.12, units)
            : MixrTimeline.minClipLengthUnits
        return MixrClip(
            id: UUID(),
            start: MixrTimeline.units(fromSeconds: p.timelineStart),
            length: max(minUnits, units),
            playbackSpeed: p.tempoRatio,
            transitionIn: p.fadeIn,
            transitionOut: p.fadeOut,
            volume: min(AutoGainPolicy.maxClipVolume, max(0, p.volume)),
            effects: AutoSupportedEffects.sanitize(p.effects),
            soundEffectID: nil,
            sourceOffsetSeconds: max(0, p.sourceStart)
        )
    }
}
