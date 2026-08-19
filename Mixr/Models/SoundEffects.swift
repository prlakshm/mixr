#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Synthesis Type

/// Fallback synthesis routine for each SFX — used by SFXSynthesizer when a
/// bundled asset is missing so playback never fails silently.
enum SFXSynthesisType: String, Sendable {
    case riser
    case downlifter
    case impact
    case sweepUp
    case sweepDown
    case reverseCymbal
    case crash
    case snareBuild
    case clapFill
    case bassDrop
    case tapeStop
    case airSweep
    /// Four-on-the-floor kick for thin-song pulse / manual placement.
    case clubKick
    /// Bass/sub weight for thin-song pulse / manual placement.
    case clubBass
}

// MARK: - Sound Effect Definition

/// Built-in V1 sound effects. Audio comes from generated assets in
/// Resources/SFX (see Scripts/generate_sfx_assets.py — reproducible,
/// no copyrighted samples); SFXSynthesizer regenerates any missing asset
/// procedurally at load time.
struct SoundEffectDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: String
    let durationSeconds: Double
    /// Bundled audio file name (in Resources/SFX).
    let assetName: String
    /// Card/clip accent — silver for all V1 effects (the SFX track color).
    var color: MixrWaveformColor = .silver
    let synthesisType: SFXSynthesisType

    var lengthUnits: CGFloat {
        MixrTimeline.units(fromSeconds: durationSeconds)
    }
}

// MARK: - Library

enum SoundEffectLibrary {
    /// Full SFX menu — every built-in one-shot, including the club pulse
    /// kick/bass that Auto Remix places on thin songs. Users can drag these
    /// manually like any other SFX.
    nonisolated static let all: [SoundEffectDefinition] = [
        SoundEffectDefinition(id: "riser",          title: "Riser",          icon: "chart.line.uptrend.xyaxis",   durationSeconds: 4.0, assetName: "riser.wav",          synthesisType: .riser),
        SoundEffectDefinition(id: "downlifter",     title: "Downlifter",     icon: "chart.line.downtrend.xyaxis", durationSeconds: 2.0, assetName: "downlifter.wav",     synthesisType: .downlifter),
        SoundEffectDefinition(id: "impact",         title: "Impact",         icon: "burst.fill",                  durationSeconds: 1.0, assetName: "impact.wav",         synthesisType: .impact),
        SoundEffectDefinition(id: "sweepUp",        title: "Sweep Up",       icon: "arrow.up.right",              durationSeconds: 2.0, assetName: "sweep_up.wav",       synthesisType: .sweepUp),
        SoundEffectDefinition(id: "sweepDown",      title: "Sweep Down",     icon: "arrow.down.right",            durationSeconds: 2.0, assetName: "sweep_down.wav",     synthesisType: .sweepDown),
        SoundEffectDefinition(id: "reverseCymbal",  title: "Reverse Cymbal", icon: "arrow.uturn.backward",        durationSeconds: 1.5, assetName: "reverse_cymbal.wav", synthesisType: .reverseCymbal),
        SoundEffectDefinition(id: "crash",          title: "Crash",          icon: "bolt.fill",                   durationSeconds: 1.0, assetName: "crash.wav",          synthesisType: .crash),
        SoundEffectDefinition(id: "snareBuild",     title: "Snare Build",    icon: "metronome.fill",              durationSeconds: 4.0, assetName: "snare_build.wav",    synthesisType: .snareBuild),
        SoundEffectDefinition(id: "clapFill",       title: "Clap Fill",      icon: "hands.clap.fill",             durationSeconds: 2.0, assetName: "clap_fill.wav",      synthesisType: .clapFill),
        SoundEffectDefinition(id: "bassDrop",       title: "Bass Drop",      icon: "arrow.down.to.line",          durationSeconds: 1.5, assetName: "bass_drop.wav",      synthesisType: .bassDrop),
        SoundEffectDefinition(id: "tapeStop",       title: "Tape Stop",      icon: "recordingtape",               durationSeconds: 1.0, assetName: "tape_stop.wav",      synthesisType: .tapeStop),
        SoundEffectDefinition(id: "airSweep",       title: "Air Sweep",      icon: "wind",                        durationSeconds: 2.0, assetName: "air_sweep.wav",      synthesisType: .airSweep),
        SoundEffectDefinition(id: "clubKick",       title: "Club Kick",      icon: "circle.fill",                 durationSeconds: 0.18, assetName: "club_kick.wav",      synthesisType: .clubKick),
        SoundEffectDefinition(id: "clubBass",       title: "Club Bass",      icon: "waveform.path",               durationSeconds: 0.28, assetName: "club_bass.wav",      synthesisType: .clubBass),
    ]

    /// Pulse-layer ids Auto schedules on a dense beat grid (exact placement,
    /// no collision slide). Same assets appear in `all` for the SFX menu.
    nonisolated static let pulseLayerIDs: Set<String> = ["clubKick", "clubBass"]

    /// nonisolated: looked up by the background export renderer too.
    nonisolated static func definition(for id: String) -> SoundEffectDefinition? {
        all.first { $0.id == id }
    }

    /// True for short pulse hits that must stay on the beat grid when Auto
    /// places them (still first-class menu items for manual use).
    nonisolated static func isPulseLayer(_ id: String) -> Bool {
        pulseLayerIDs.contains(id)
    }

    // MARK: - Collision-free placement (per SFX row)

    /// Resolves a non-overlapping start on ONE SFX track:
    /// starting at `proposedStart`, while the proposed range overlaps an
    /// existing clip, slide the start to the end of that clip and retry.
    /// Never returns a negative start.
    ///
    /// Clips on a single SFX row never overlap. To stack riser + impact +
    /// pulse at the same time, place the colliding hit on an adjacent SFX
    /// row (`placeExact` / Auto Remix extra tracks) — same as a user
    /// dragging a one-shot up or down.
    static func nonOverlappingStart(
        proposedStart: CGFloat,
        lengthUnits: CGFloat,
        in clips: [MixrClip],
        epsilon: CGFloat = MixrTimeline.clipEdgeEpsilon
    ) -> CGFloat {
        var start = max(0, proposedStart)
        let sorted = clips.sorted { $0.start < $1.start }

        var moved = true
        while moved {
            moved = false
            let end = start + lengthUnits
            for clip in sorted {
                let clipEnd = clip.start + clip.length
                let overlaps = start < clipEnd - epsilon && end > clip.start + epsilon
                if overlaps {
                    start = clipEnd
                    moved = true
                    break
                }
            }
        }

        return max(0, start)
    }

    /// True when `proposedStart` can host `lengthUnits` on this row without sliding.
    static func fitsExactly(
        proposedStart: CGFloat,
        lengthUnits: CGFloat,
        in clips: [MixrClip],
        epsilon: CGFloat = MixrTimeline.clipEdgeEpsilon
    ) -> Bool {
        let want = max(0, proposedStart)
        let resolved = nonOverlappingStart(
            proposedStart: want,
            lengthUnits: lengthUnits,
            in: clips,
            epsilon: epsilon
        )
        return abs(resolved - want) <= epsilon
    }

    /// Empty SFX timeline row (primary or spill lane). Extra lanes share the
    /// SFX gradient in the UI but only the top row shows chip/headings.
    static func makeSFXTrack(primary: Bool = true) -> MixrTrack {
        MixrTrack(
            id: UUID(),
            title: primary ? "Sound Effects" : "Sound Effects",
            artist: primary ? "Built-in SFX" : "",
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
    }

    /// Places a one-shot at an exact timeline unit: first SFX row that fits
    /// without sliding, else appends a new SFX row (editor-style stacking).
    /// Returns the track index used.
    @discardableResult
    static func placeExact(
        definition: SoundEffectDefinition,
        atUnit unit: CGFloat,
        into tracks: inout [MixrTrack],
        clipID: UUID = UUID()
    ) -> Int {
        let want = max(0, unit)
        let sfxIndices = tracks.indices.filter { tracks[$0].isSFXTrack }
        for idx in sfxIndices {
            if fitsExactly(
                proposedStart: want,
                lengthUnits: definition.lengthUnits,
                in: tracks[idx].clips
            ) {
                tracks[idx].clips.append(
                    MixrClip(
                        id: clipID,
                        start: want,
                        length: definition.lengthUnits,
                        soundEffectID: definition.id
                    )
                )
                tracks[idx].clips.sort { $0.start < $1.start }
                return idx
            }
        }
        let primary = sfxIndices.isEmpty
        tracks.append(makeSFXTrack(primary: primary))
        let idx = tracks.count - 1
        tracks[idx].clips.append(
            MixrClip(
                id: clipID,
                start: want,
                length: definition.lengthUnits,
                soundEffectID: definition.id
            )
        )
        return idx
    }
}
