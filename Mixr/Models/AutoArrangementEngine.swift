import CoreGraphics
import Foundation

// MARK: - Auto Scope

enum AutoScope: Equatable {
    case selectedClip(UUID)
    case playheadClips
    case entireProject

    var title: String {
        switch self {
        case .selectedClip: "Selected Clip"
        case .playheadClips: "Playhead Clips"
        case .entireProject: "Entire Project"
        }
    }
}

// MARK: - Auto Arrangement Engine

/// Local, deterministic arrangement engine — no external AI service.
/// Applies festival/pop-EDM DJ arrangement language: risers into drops,
/// impacts on drops, sweeps/downlifters after transitions, transition
/// fades, and tasteful per-clip effect settings. All edits are model
/// mutations on real tracks/clips; the caller wraps the whole run in a
/// single undo snapshot.
enum AutoArrangementEngine {

    /// Region half-width for the playhead scope (spec: 8–16 s total).
    private static let playheadRegionSeconds: Double = 6

    /// Cap on transition moments decorated in a single entire-project run.
    private static let maxProjectTransitions = 4

    // MARK: Entry point

    static func arrange(
        tracks: [MixrTrack],
        scope: AutoScope,
        playheadUnit: CGFloat
    ) -> [MixrTrack] {
        var result = tracks

        switch scope {
        case .selectedClip(let clipID):
            arrangeSelectedClip(clipID, in: &result)
        case .playheadClips:
            arrangePlayheadRegion(around: playheadUnit, in: &result)
        case .entireProject:
            arrangeEntireProject(in: &result)
        }

        return result
    }

    // MARK: Selected Clip

    private static func arrangeSelectedClip(_ clipID: UUID, in tracks: inout [MixrTrack]) {
        guard let (ti, ci) = findClip(clipID, in: tracks) else { return }
        let clip = tracks[ti].clips[ci]
        let clipStart = clip.start
        let clipEnd = clip.start + clip.length

        // Per-clip effect polish — energy without mud.
        var effects = clip.effects
        effects.setLevel(30, for: MixrEffect.reverb.rawValue)
        effects.setLevel(22, for: MixrEffect.echo.rawValue)
        effects.setLevel(18, for: MixrEffect.warmth.rawValue)
        effects.reverbPreset = .hall
        effects.echoPreset = .classic
        tracks[ti].clips[ci].effects = effects

        // Clean entry/exit transitions within the clip's own bounds.
        if clipStart > MixrTimeline.clipEdgeEpsilon {
            tracks[ti].clips[ci].transitionIn = ClipTransition(type: .crossfade, duration: 2)
        }
        let hasFollower = tracks[ti].clips.contains {
            $0.id != clipID && $0.start >= clipEnd - MixrTimeline.clipEdgeEpsilon
        }
        tracks[ti].clips[ci].transitionOut = ClipTransition(
            type: hasFollower ? .echoOut : .fadeOut,
            duration: 2
        )

        // SFX only near this clip's region: riser into its start, impact on
        // the downbeat, sweep-down as it releases.
        addRiser(endingAt: clipStart, in: &tracks)
        addSFX("impact", at: clipStart, in: &tracks)
        addSFX("sweepDown", at: clipEnd, in: &tracks)
    }

    // MARK: Playhead Region

    private static func arrangePlayheadRegion(around playheadUnit: CGFloat, in tracks: inout [MixrTrack]) {
        let halfRegion = MixrTimeline.units(fromSeconds: playheadRegionSeconds)
        let regionStart = max(0, playheadUnit - halfRegion)
        let regionEnd = playheadUnit + halfRegion

        // Nearest clip boundary inside the region becomes the drop point;
        // fall back to the playhead itself.
        let boundaries = songClipBoundaries(in: tracks)
            .filter { $0 >= regionStart && $0 <= regionEnd }
        let dropPoint = boundaries.min {
            abs($0 - playheadUnit) < abs($1 - playheadUnit)
        } ?? playheadUnit

        decorateTransition(at: dropPoint, in: &tracks, intensity: .focused)

        // Polish clips that touch the region — nothing outside it moves.
        for ti in tracks.indices where !tracks[ti].isSFXTrack {
            for ci in tracks[ti].clips.indices {
                let clip = tracks[ti].clips[ci]
                let clipEnd = clip.start + clip.length
                guard clipEnd > regionStart, clip.start < regionEnd else { continue }

                var effects = tracks[ti].clips[ci].effects
                if clipEnd <= dropPoint + MixrTimeline.clipEdgeEpsilon {
                    // Outgoing energy: echo tail out of the transition.
                    effects.setLevel(max(effects.level(for: MixrEffect.echo.rawValue), 35), for: MixrEffect.echo.rawValue)
                    effects.setLevel(max(effects.level(for: MixrEffect.filter.rawValue), 28), for: MixrEffect.filter.rawValue)
                    tracks[ti].clips[ci].transitionOut = ClipTransition(type: .echoOut, duration: 2)
                } else {
                    // Incoming clip: open bright with a touch of space.
                    effects.setLevel(max(effects.level(for: MixrEffect.reverb.rawValue), 24), for: MixrEffect.reverb.rawValue)
                    effects.reverbPreset = .hall
                    if clip.start > MixrTimeline.clipEdgeEpsilon {
                        tracks[ti].clips[ci].transitionIn = ClipTransition(type: .crossfade, duration: 2)
                    }
                }
                tracks[ti].clips[ci].effects = effects
            }
        }
    }

    // MARK: Entire Project

    private static func arrangeEntireProject(in tracks: inout [MixrTrack]) {
        let boundaries = songClipBoundaries(in: tracks)
            .filter { $0 > MixrTimeline.clipEdgeEpsilon }
        // Spread the decorated moments across the project.
        let chosen = pickSpread(from: boundaries, limit: maxProjectTransitions)

        for (index, point) in chosen.enumerated() {
            decorateTransition(
                at: point,
                in: &tracks,
                intensity: index == chosen.count - 1 ? .release : .build
            )
        }

        // Whole-timeline fades: every clip enters/exits cleanly, with
        // volume shaping toward transitions.
        for ti in tracks.indices where !tracks[ti].isSFXTrack {
            let sorted = tracks[ti].clips.sorted { $0.start < $1.start }
            for (order, clip) in sorted.enumerated() {
                guard let ci = tracks[ti].clips.firstIndex(where: { $0.id == clip.id }) else { continue }

                if clip.start > MixrTimeline.clipEdgeEpsilon,
                   tracks[ti].clips[ci].transitionIn.type == .none {
                    tracks[ti].clips[ci].transitionIn = ClipTransition(type: .crossfade, duration: 2)
                }
                let isLast = order == sorted.count - 1
                if tracks[ti].clips[ci].transitionOut.type == .none {
                    tracks[ti].clips[ci].transitionOut = ClipTransition(
                        type: isLast ? .fadeOut : .crossfade,
                        duration: isLast ? 4 : 2
                    )
                }

                // Gentle project-wide tone: warmth on every song clip.
                var effects = tracks[ti].clips[ci].effects
                effects.setLevel(max(effects.level(for: MixrEffect.warmth.rawValue), 15), for: MixrEffect.warmth.rawValue)
                tracks[ti].clips[ci].effects = effects
            }
        }
    }

    // MARK: Transition decoration

    private enum TransitionIntensity {
        case focused   // playhead scope — one strong moment
        case build     // project build: riser + impact + sweep
        case release   // project end: downlifter + crash
    }

    /// Adds the SFX vocabulary around one transition point and applies
    /// outgoing/incoming effect settings on adjacent clips.
    private static func decorateTransition(
        at point: CGFloat,
        in tracks: inout [MixrTrack],
        intensity: TransitionIntensity
    ) {
        switch intensity {
        case .focused:
            addRiser(endingAt: point, in: &tracks)
            addSFX("impact", at: point, in: &tracks)
            addSFX("downlifter", at: point, in: &tracks)
        case .build:
            addRiser(endingAt: point, in: &tracks)
            addSFX("impact", at: point, in: &tracks)
            addSFX("sweepDown", at: point, in: &tracks)
        case .release:
            addSFX("crash", at: point, in: &tracks)
            addSFX("downlifter", at: point, in: &tracks)
        }

        // Outgoing clips ending at the point get echo-out + filter energy;
        // incoming clips starting there get crossfade + reverb air.
        let epsilonZone = MixrTimeline.units(fromSeconds: 1.5)
        for ti in tracks.indices where !tracks[ti].isSFXTrack {
            for ci in tracks[ti].clips.indices {
                let clip = tracks[ti].clips[ci]
                let clipEnd = clip.start + clip.length

                if abs(clipEnd - point) <= epsilonZone {
                    var effects = clip.effects
                    effects.setLevel(max(effects.level(for: MixrEffect.echo.rawValue), 38), for: MixrEffect.echo.rawValue)
                    effects.setLevel(max(effects.level(for: MixrEffect.filter.rawValue), 30), for: MixrEffect.filter.rawValue)
                    effects.echoPreset = .pingPong
                    tracks[ti].clips[ci].effects = effects
                    tracks[ti].clips[ci].transitionOut = ClipTransition(type: .echoOut, duration: 2)
                    // Volume fade-down into the transition.
                    tracks[ti].clips[ci].volume = min(tracks[ti].clips[ci].volume, 0.9)
                } else if abs(clip.start - point) <= epsilonZone {
                    var effects = clip.effects
                    effects.setLevel(max(effects.level(for: MixrEffect.reverb.rawValue), 26), for: MixrEffect.reverb.rawValue)
                    effects.reverbPreset = .hall
                    tracks[ti].clips[ci].effects = effects
                    tracks[ti].clips[ci].transitionIn = ClipTransition(type: .crossfade, duration: 2)
                    tracks[ti].clips[ci].volume = 1.0
                }
            }
        }
    }

    // MARK: SFX placement

    /// Riser ends exactly on the drop point when there is room; skipped when
    /// it would need a negative start.
    private static func addRiser(endingAt point: CGFloat, in tracks: inout [MixrTrack]) {
        guard let riser = SoundEffectLibrary.definition(for: "riser") else { return }
        let start = point - riser.lengthUnits
        guard start >= 0 else { return }
        addSFX("riser", at: start, in: &tracks)
    }

    private static func addSFX(_ id: String, at unit: CGFloat, in tracks: inout [MixrTrack]) {
        guard let definition = SoundEffectLibrary.definition(for: id) else { return }
        let idx = ensureSFXTrack(in: &tracks)
        let start = SoundEffectLibrary.nonOverlappingStart(
            proposedStart: max(0, unit),
            lengthUnits: definition.lengthUnits,
            in: tracks[idx].clips
        )
        tracks[idx].clips.append(
            MixrClip(
                id: UUID(),
                start: start,
                length: definition.lengthUnits,
                soundEffectID: definition.id
            )
        )
        tracks[idx].clips.sort { $0.start < $1.start }
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

    // MARK: Helpers

    private static func findClip(_ id: UUID, in tracks: [MixrTrack]) -> (Int, Int)? {
        for (ti, track) in tracks.enumerated() {
            if let ci = track.clips.firstIndex(where: { $0.id == id }) {
                return (ti, ci)
            }
        }
        return nil
    }

    /// Distinct clip starts/ends across song tracks, sorted ascending.
    private static func songClipBoundaries(in tracks: [MixrTrack]) -> [CGFloat] {
        var points: [CGFloat] = []
        for track in tracks where !track.isSFXTrack {
            for clip in track.clips {
                points.append(clip.start)
                points.append(clip.start + clip.length)
            }
        }
        var distinct: [CGFloat] = []
        for p in points.sorted() {
            if let last = distinct.last, abs(last - p) < MixrTimeline.units(fromSeconds: 1) {
                continue
            }
            distinct.append(p)
        }
        return distinct
    }

    /// Picks up to `limit` points spread evenly across the candidates.
    private static func pickSpread(from points: [CGFloat], limit: Int) -> [CGFloat] {
        guard points.count > limit, limit > 0 else { return points }
        let stride = Double(points.count - 1) / Double(limit - 1)
        var picked: [CGFloat] = []
        for i in 0..<limit {
            let idx = Int((Double(i) * stride).rounded())
            let value = points[min(idx, points.count - 1)]
            if picked.last != value { picked.append(value) }
        }
        return picked
    }
}
