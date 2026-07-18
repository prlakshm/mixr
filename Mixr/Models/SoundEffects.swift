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
    ]

    /// nonisolated: looked up by the background export renderer too.
    nonisolated static func definition(for id: String) -> SoundEffectDefinition? {
        all.first { $0.id == id }
    }

    // MARK: - Collision-free placement

    /// Resolves a non-overlapping start on the SFX track:
    /// starting at `proposedStart`, while the proposed range overlaps an
    /// existing clip, slide the start to the end of that clip and retry.
    /// Never returns a negative start.
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
}
