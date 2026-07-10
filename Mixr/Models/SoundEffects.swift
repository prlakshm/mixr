import CoreGraphics
import Foundation

// MARK: - Sound Effect Definition

/// Built-in V1 sound effects. Local definitions only — no bundled audio yet.
/// AVAudioEngine integration point: attach a synthesized or bundled buffer per
/// definition and schedule it in MixrPlaybackEngine when SFX playback lands.
struct SoundEffectDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: String
    let durationSeconds: Double

    var lengthUnits: CGFloat {
        MixrTimeline.units(fromSeconds: durationSeconds)
    }
}

// MARK: - Library

enum SoundEffectLibrary {
    static let all: [SoundEffectDefinition] = [
        SoundEffectDefinition(id: "riser",          title: "Riser",          icon: "chart.line.uptrend.xyaxis",   durationSeconds: 4.0),
        SoundEffectDefinition(id: "downlifter",     title: "Downlifter",     icon: "chart.line.downtrend.xyaxis", durationSeconds: 2.0),
        SoundEffectDefinition(id: "impact",         title: "Impact",         icon: "burst.fill",                  durationSeconds: 1.0),
        SoundEffectDefinition(id: "sweepUp",        title: "Sweep Up",       icon: "arrow.up.right",              durationSeconds: 2.0),
        SoundEffectDefinition(id: "sweepDown",      title: "Sweep Down",     icon: "arrow.down.right",            durationSeconds: 2.0),
        SoundEffectDefinition(id: "reverseCymbal",  title: "Reverse Cymbal", icon: "arrow.uturn.backward",        durationSeconds: 1.5),
        SoundEffectDefinition(id: "crash",          title: "Crash",          icon: "bolt.fill",                   durationSeconds: 1.0),
        SoundEffectDefinition(id: "snareBuild",     title: "Snare Build",    icon: "metronome.fill",              durationSeconds: 4.0),
        SoundEffectDefinition(id: "clapFill",       title: "Clap Fill",      icon: "hands.clap.fill",             durationSeconds: 2.0),
        SoundEffectDefinition(id: "bassDrop",       title: "Bass Drop",      icon: "arrow.down.to.line",          durationSeconds: 1.5),
        SoundEffectDefinition(id: "tapeStop",       title: "Tape Stop",      icon: "recordingtape",               durationSeconds: 1.0),
        SoundEffectDefinition(id: "airSweep",       title: "Air Sweep",      icon: "wind",                        durationSeconds: 2.0),
    ]

    static func definition(for id: String) -> SoundEffectDefinition? {
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
