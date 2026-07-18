import Foundation

// MARK: - Auto Gain Policy
//
// SHARED gain-staging policy for Auto remix output. One place defines the
// loudness targets, SFX gain calibration, ducking behavior, and export
// tail rules used by live playback, offline export, and the portable
// test mixdown. The limiter is a SAFETY layer — this policy is what makes
// the mix fit; sustained heavy limiting is treated as a failed mix.
nonisolated enum AutoGainPolicy {

    // MARK: Targets (measured on pre-encode PCM)

    /// Maximum allowed estimated true peak (4× oversampled), dBTP.
    static let truePeakCeilingDB = -1.0
    /// Integrated loudness target for exported playback.
    static let integratedLoudnessTargetDB = -14.0
    /// Mix-bus headroom reserved BEFORE SFX join the sum, dB.
    static let mixBusHeadroomDB = 6.0
    /// Sustained limiter gain reduction above this is a failed mix, dB.
    static let maxSustainedLimiterReductionDB = 3.0

    // MARK: Export tail

    /// A retained effect tail must stay audible; once the rendered level
    /// remains below this for `silentTailWindowSeconds`, the export ends.
    static let silentTailThresholdDB = -60.0
    static let silentTailWindowSeconds = 0.25
    /// Upper bound on rendered tail length after the last clip (seconds).
    static let maxTailSeconds = 8.0

    // MARK: SFX calibration
    // NOTE: baseline values are the CURRENT uncalibrated behavior (unity);
    // the preservation-first redesign replaces them with per-asset gains.

    /// Calibrated nominal gain for one SFX asset (linear, applied on top
    /// of the SFX track volume).
    static func nominalGain(forSFX id: String) -> Double {
        1.0
    }

    /// Gain applied to the SONG bus while major SFX play (ducking).
    /// Baseline: no ducking.
    static func duckGain(at t: Double, sfxEvents: [AutoSFXEvent]) -> Double {
        1.0
    }

    // MARK: Song placement gain

    /// Placement volume for a one-song remix segment with a 0…1 energy
    /// story value. Baseline replicates the current planner mapping.
    static func songPlacementVolume(energy: Double) -> Double {
        0.82 + 0.18 * min(1, max(0, energy))
    }

    // MARK: Tail trimming

    /// Index one past the last frame to keep: trims a trailing region that
    /// stays below `silentTailThresholdDB` for at least
    /// `silentTailWindowSeconds`. Never trims into `protectedSeconds`
    /// (the musical content); returns `samples.count` when the tail is
    /// audible to the end. Baseline: no trimming (fixed tails), matching
    /// the current exporter.
    static func trimmedTailFrameCount(
        samples: [Float],
        sampleRate: Double,
        protectedSeconds: Double
    ) -> Int {
        samples.count
    }
}
