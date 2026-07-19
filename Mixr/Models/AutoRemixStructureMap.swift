import Foundation

// MARK: - Structure Map
//
// Measured musical structure at phrase resolution: per-phrase feature
// vectors, phrase-to-phrase similarity, removability classes, hook-family
// identification with DIFFERENTIATION (a repeated chorus is only a
// shortening candidate when it is a near-duplicate — intensified or
// structurally distinct hooks are protected), structural regions, and
// local beat-grid stability.
//
// Similarity is NEVER redundancy by itself: vocal-heavy non-hook phrases
// (verses) are classified vocalDistinct and are not removable regardless
// of similarity, because no measured feature can prove lyric identity.

/// Removability class of one phrase.
enum AutoRemixRemovability: String, Sendable, Equatable {
    /// Low vocal presence — arrangement-eligible with repeat evidence.
    case instrumental
    /// Member of the most-repeated high-energy cluster (chorus family).
    case hookFamily
    /// Vocal-heavy, non-hook — NEVER removable; DSP treatment only.
    case vocalDistinct
    /// Leading edge material.
    case intro
    /// Trailing edge material — compressible with decay evidence.
    case outro
}

/// How a later hook instance differs from the protected first instance.
enum AutoHookDifferentiation: String, Sendable, Equatable {
    /// Same energy, vocal activity, and rhythm — normal shortening candidate.
    case nearDuplicate
    /// More energy / vocal activity / rhythm — protected; enhance instead.
    case intensified
    /// Less energy — protected from removal (often a breakdown chorus).
    case reduced
    /// Similar family but different internal structure — protected.
    case structurallyDistinct
}

struct AutoRemixPhrase: Sendable {
    var index: Int
    var startSeconds: Double
    var endSeconds: Double
    var removability: AutoRemixRemovability
    /// Mean normalized values over the phrase.
    var energyMean: Double
    var vocalMean: Double
    var bassMean: Double
    var onsetDensity: Double
    /// Feature vector used for similarity.
    var features: [Double]

    nonisolated var duration: Double { endSeconds - startSeconds }
}

struct AutoRemixHookInstance: Sendable {
    /// Phrase indices covered by this instance.
    var phraseIndices: [Int]
    var startSeconds: Double
    var endSeconds: Double
    var differentiation: AutoHookDifferentiation
    /// The first complete instance is always protected from removal.
    var isProtected: Bool
}

/// Windowed beat-phase measurement for local grid stability.
struct AutoRemixGridWindow: Sendable {
    var centerSeconds: Double
    /// Grid phase (mod beat) measured in this window, seconds.
    var phase: Double
    var confidence: Double
}

struct AutoRemixStructureMap: Sendable {
    var phrases: [AutoRemixPhrase]
    /// similarity[i][j] in 0…1 for phrase pairs (symmetric).
    var similarity: [[Double]]
    var hookInstances: [AutoRemixHookInstance]
    /// Structural regions (source seconds) used for distribution targets.
    var regions: [ClosedRange<Double>]
    var gridWindows: [AutoRemixGridWindow]
    /// Max circular phase deviation across windows, as a fraction of a
    /// beat. Above tuning's tolerance, structural edits are unsafe in the
    /// drifting portion.
    var gridDriftFractionOfBeat: Double
    var usableRange: ClosedRange<Double>

    /// Local beat-grid trust at a source time: window confidence damped
    /// by disagreement with neighboring windows.
    nonisolated func localBeatConfidence(at t: Double) -> Double {
        guard !gridWindows.isEmpty else { return 0 }
        // Nearest window, damped by its agreement with its neighbors.
        var best = gridWindows[0]
        for w in gridWindows where abs(w.centerSeconds - t) < abs(best.centerSeconds - t) {
            best = w
        }
        guard let idx = gridWindows.firstIndex(where: { $0.centerSeconds == best.centerSeconds }) else {
            return best.confidence
        }
        var agreement = 1.0
        let beat = beatSecondsHint
        if beat > 0 {
            for n in [idx - 1, idx + 1] where n >= 0 && n < gridWindows.count {
                let other = gridWindows[n]
                let raw = abs(other.phase - best.phase)
                let circular = min(raw, beat - min(raw, beat))
                agreement = min(agreement, max(0, 1 - (circular / beat) / 0.2))
            }
        }
        return best.confidence * agreement
    }

    /// Beat length used for circular phase comparison.
    var beatSecondsHint: Double = 0

    /// Region index containing a source time.
    nonisolated func regionIndex(of t: Double) -> Int {
        for (i, r) in regions.enumerated() where r.contains(t) { return i }
        return max(0, regions.count - 1)
    }

    /// Phrase containing a source time.
    nonisolated func phrase(at t: Double) -> AutoRemixPhrase? {
        phrases.first { t >= $0.startSeconds && t < $0.endSeconds }
    }

    nonisolated static let empty = AutoRemixStructureMap(
        phrases: [],
        similarity: [],
        hookInstances: [],
        regions: [],
        gridWindows: [],
        gridDriftFractionOfBeat: 1.0,
        usableRange: 0...0
    )
}

// MARK: - Builder (stub — implemented by the transformation layer)

enum AutoRemixStructureMapBuilder {

    /// Builds the measured structure map for one analyzed song.
    /// BASELINE STUB: returns an empty map (no structural knowledge) —
    /// the opportunity layer supplies the real implementation.
    nonisolated static func build(
        analysis: SongAnalysis,
        usableRange: ClosedRange<Double>,
        tuning: AutoTuning = .standard
    ) -> AutoRemixStructureMap {
        var map = AutoRemixStructureMap.empty
        map.usableRange = usableRange
        return map
    }
}
