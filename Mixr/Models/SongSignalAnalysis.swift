import Foundation

// MARK: - Signal-Derived Song Features
//
// Real short-time measurements extracted from decoded PCM. This is the
// evidence base for every Auto editing decision: seeded pseudo-random
// values must never decide structure. Pure Swift over [Float] so the
// extractor runs identically on-device (fed by MixrAudioAnalyzer's file
// reader) and in the portable test harness (fed by synthetic fixtures).
//
// Every derived feature carries a confidence; consumers must reduce
// editing aggressiveness as confidence drops.

/// One contiguous time region inside the source, seconds.
struct SignalRegion: Equatable, Sendable {
    var start: Double
    var end: Double

    nonisolated var duration: Double { end - start }

    nonisolated func contains(_ t: Double) -> Bool { t >= start && t < end }
}

struct SongSignalFeatures: Sendable {
    var sampleRate: Double
    var durationSeconds: Double

    /// Short-time RMS in dBFS, one value per `hopSeconds`.
    var rmsCurveDB: [Double]
    /// Half-wave-rectified energy difference (onset strength), per hop.
    var onsetStrength: [Double]
    var hopSeconds: Double

    /// Seconds into the source of the first confident DOWNBEAT.
    /// nil when beat tracking was inconclusive — never assume 0.
    var downbeatOffsetSeconds: Double?
    /// 0…1 trust in the beat grid / downbeat phase.
    var beatConfidence: Double

    /// Sustained near-silence at the edges (seconds).
    var leadingSilenceSeconds: Double
    var trailingSilenceSeconds: Double
    /// Interior sustained near-silent or low-information regions.
    var quietRegions: [SignalRegion]

    /// Normalized 0…1 energy per hop (from rmsCurveDB).
    var energyCurve: [Double]
    /// Low-band (~<150 Hz) energy per hop, normalized 0…1.
    var bassEnergyCurve: [Double]
    /// Mid-band (~300 Hz–3 kHz) presence per hop, normalized 0…1 —
    /// vocal-presence proxy without a separation model.
    var vocalPresenceCurve: [Double]
    /// Spectral-novelty proxy per hop (band-energy change), normalized.
    var noveltyCurve: [Double]

    /// 0…1 transient/drum reliability from onset regularity.
    var drumConfidence: Double
    /// 0…1 overall trust in these measurements.
    var overallConfidence: Double

    nonisolated var hopCount: Int { rmsCurveDB.count }

    /// Mean short-time RMS (power domain) over a source range, dBFS.
    nonisolated func meanRMSDB(from start: Double, to end: Double) -> Double {
        guard hopSeconds > 0, !rmsCurveDB.isEmpty else { return -120 }
        let lo = max(0, Int(start / hopSeconds))
        let hi = min(rmsCurveDB.count - 1, Int(end / hopSeconds))
        guard hi >= lo else { return -120 }
        var power = 0.0
        for i in lo...hi { power += pow(10, rmsCurveDB[i] / 10) }
        return 10 * log10(max(power / Double(hi - lo + 1), 1e-12))
    }
}

// MARK: - Extractor

enum SongSignalAnalyzer {

    /// Hop used for all short-time curves (100 ms).
    nonisolated static let hopSeconds = 0.1

    /// Extracts signal features from mono PCM.
    /// `bpmHint` (from metadata/estimation) anchors beat-phase search.
    ///
    /// BASELINE STUB: returns an empty, zero-confidence feature set —
    /// the preservation-first redesign supplies the real measurements.
    nonisolated static func extract(
        samples: [Float],
        sampleRate: Double,
        bpmHint: Double? = nil
    ) -> SongSignalFeatures {
        SongSignalFeatures(
            sampleRate: sampleRate,
            durationSeconds: sampleRate > 0 ? Double(samples.count) / sampleRate : 0,
            rmsCurveDB: [],
            onsetStrength: [],
            hopSeconds: hopSeconds,
            downbeatOffsetSeconds: nil,
            beatConfidence: 0,
            leadingSilenceSeconds: 0,
            trailingSilenceSeconds: 0,
            quietRegions: [],
            energyCurve: [],
            bassEnergyCurve: [],
            vocalPresenceCurve: [],
            noveltyCurve: [],
            drumConfidence: 0,
            overallConfidence: 0
        )
    }
}
