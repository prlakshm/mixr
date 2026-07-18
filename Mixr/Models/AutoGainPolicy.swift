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

    /// Assets that hit hard enough to need song ducking underneath.
    static let majorImpactSFX: Set<String> = ["impact", "crash", "bassDrop"]

    /// Calibrated nominal gain for one SFX asset (linear, applied on top
    /// of the SFX track volume). Every asset sits WELL below full scale so
    /// SFX ride on the song instead of fighting it, and stacked events
    /// cannot blow the 6 dB mix-bus headroom on their own.
    static func nominalGain(forSFX id: String) -> Double {
        switch id {
        case "impact", "bassDrop": 0.25          // ≈ −12 dB
        case "crash": 0.30                       // ≈ −10.5 dB
        case "riser", "snareBuild": 0.32         // ≈ −10 dB
        case "reverseCymbal": 0.28               // ≈ −11 dB
        case "downlifter", "tapeStop": 0.25      // ≈ −12 dB
        case "airSweep", "sweepUp", "sweepDown": 0.20  // ≈ −14 dB
        case "clapFill": 0.28
        default: 0.25
        }
    }

    /// Combined nominal gain of events sounding at once must not exceed
    /// this (≈ −6 dB below full scale) — the stacking guard planners and
    /// validators consult before coordinating multiple SFX.
    static let maxSimultaneousSFXGain = 0.5

    // MARK: Ducking

    /// Duck depth under a major impact, dB (smoothly ramped).
    static let duckDepthDB = 3.0
    static let duckAttackSeconds = 0.06
    static let duckHoldSeconds = 0.25
    static let duckReleaseSeconds = 0.30

    /// Gain applied to the SONG bus at time `t` while major SFX play.
    /// Smooth attack/hold/release envelope around each major impact;
    /// overlapping events take the deepest value.
    static func duckGain(at t: Double, sfxEvents: [AutoSFXEvent]) -> Double {
        var gain = 1.0
        let floorGain = pow(10.0, -duckDepthDB / 20.0)
        for event in sfxEvents where majorImpactSFX.contains(event.assetID) {
            let start = event.timelineStart - duckAttackSeconds
            let holdEnd = event.timelineStart + duckHoldSeconds
            let end = holdEnd + duckReleaseSeconds
            guard t >= start, t <= end else { continue }
            let shape: Double
            if t < event.timelineStart {
                shape = (t - start) / duckAttackSeconds            // attack 0→1
            } else if t <= holdEnd {
                shape = 1                                          // hold
            } else {
                shape = 1 - (t - holdEnd) / duckReleaseSeconds     // release 1→0
            }
            // Cosine-smoothed so the ramp itself never steps.
            let smooth = 0.5 - 0.5 * cos(.pi * min(1, max(0, shape)))
            gain = min(gain, 1 - (1 - floorGain) * smooth)
        }
        return gain
    }

    // MARK: Song placement gain

    /// Volume for the continuous one-song remix placement. One value for
    /// the whole song — the song's own dynamics carry the energy story —
    /// leaving ≈ 1 dB of clip headroom before track gain and SFX.
    static let preservationSongVolume = 0.9

    /// Placement volume for an energy-storied slot (mashup path).
    static func songPlacementVolume(energy: Double) -> Double {
        0.82 + 0.18 * min(1, max(0, energy))
    }

    // MARK: Tail trimming

    /// Index one past the last frame to keep: trims a trailing region
    /// that stays below `silentTailThresholdDB`. The export then never
    /// ends with ≥ `silentTailWindowSeconds` of silence — a tail is kept
    /// only while it is audible. Never trims inside `protectedSeconds`
    /// (the musical content).
    static func trimmedTailFrameCount(
        samples: [Float],
        sampleRate: Double,
        protectedSeconds: Double
    ) -> Int {
        guard sampleRate > 0, !samples.isEmpty else { return samples.count }
        let window = max(1, Int(0.02 * sampleRate))
        let threshold = pow(10.0, silentTailThresholdDB / 20.0)
        let protectedFrames = min(samples.count, Int(protectedSeconds * sampleRate))

        // Last 20 ms window whose RMS is audible.
        var lastAudibleEnd = protectedFrames
        var i = samples.count - window
        while i >= protectedFrames {
            var sum = 0.0
            for j in i..<min(samples.count, i + window) {
                let v = Double(samples[j])
                sum += v * v
            }
            if (sum / Double(window)).squareRoot() >= threshold {
                lastAudibleEnd = min(samples.count, i + window)
                break
            }
            i -= window
        }

        let keep = max(protectedFrames, lastAudibleEnd + Int(0.05 * sampleRate))
        return min(samples.count, keep)
    }
}
