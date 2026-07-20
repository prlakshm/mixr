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

// MARK: - Builder

enum AutoRemixStructureMapBuilder {

    /// Phrase unit: 4 bars (finer boundaries; 8/16/32-bar completions
    /// are every 2nd/4th/8th unit from the anchor).
    nonisolated static let phraseBars = 4.0
    /// Similarity at or above this marks a repeat of earlier material.
    nonisolated static let repeatSimilarity = 0.85
    /// Similarity above this keeps two phrases in one section family.
    nonisolated static let familySimilarity = 0.6
    /// Normalized vocal presence above this marks vocal-heavy material.
    nonisolated static let vocalThreshold = 0.45
    /// Instance-level deltas beyond these mark a differentiated hook.
    nonisolated static let differentiationDelta = 0.08

    /// Builds the measured structure map for one analyzed song.
    /// Requires trusted signal features — a song without measurements has
    /// no structural knowledge and gets an empty map (conservative path).
    nonisolated static func build(
        analysis: SongAnalysis,
        usableRange: ClosedRange<Double>,
        tuning: AutoTuning = .standard
    ) -> AutoRemixStructureMap {
        var map = AutoRemixStructureMap.empty
        map.usableRange = usableRange
        map.beatSecondsHint = analysis.beatSeconds

        guard let signal = analysis.signal,
              signal.overallConfidence >= 0.4,
              signal.beatConfidence > 0.4
        else { return map }

        map.gridWindows = signal.beatPhaseWindows
        map.gridDriftFractionOfBeat = signal.gridDriftFractionOfBeat

        let bar = analysis.barSeconds
        let unit = bar * phraseBars
        guard unit > 0.5, usableRange.upperBound - usableRange.lowerBound > unit * 4 else {
            return map
        }

        // Anchor the phrase grid to the first measured downbeat inside
        // the usable range.
        let anchor = analysis.downbeats.first { $0 >= usableRange.lowerBound - 0.05 }
            ?? usableRange.lowerBound

        // ── Per-phrase feature vectors ──
        var phrases: [AutoRemixPhrase] = []
        var start = anchor
        var index = 0
        let hop = signal.hopSeconds
        let onsetMedian = median(signal.onsetStrength.filter { $0 > 0 }) ?? 0

        while start + unit <= usableRange.upperBound + 0.5 {
            let end = min(start + unit, usableRange.upperBound)
            let energy = meanCurve(signal.energyCurve, hop: hop, from: start, to: end)
            let vocal = meanCurve(signal.vocalPresenceCurve, hop: hop, from: start, to: end)
            let bass = meanCurve(signal.bassEnergyCurve, hop: hop, from: start, to: end)
            let density = onsetDensity(
                signal.onsetStrength, hop: hop, from: start, to: end, median: onsetMedian
            )
            let energySlope = meanCurve(signal.energyCurve, hop: hop, from: (start + end) / 2, to: end)
                - meanCurve(signal.energyCurve, hop: hop, from: start, to: (start + end) / 2)
            let vocalSlope = meanCurve(signal.vocalPresenceCurve, hop: hop, from: (start + end) / 2, to: end)
                - meanCurve(signal.vocalPresenceCurve, hop: hop, from: start, to: (start + end) / 2)

            phrases.append(
                AutoRemixPhrase(
                    index: index,
                    startSeconds: start,
                    endSeconds: end,
                    removability: .instrumental,   // assigned below
                    energyMean: energy,
                    vocalMean: vocal,
                    bassMean: bass,
                    onsetDensity: density,
                    features: [energy, bass, vocal, density, energySlope * 0.5, vocalSlope * 0.5]
                )
            )
            index += 1
            start += unit
        }
        guard phrases.count >= 6 else { return map }

        // ── Similarity matrix ──
        let n = phrases.count
        var similarity = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            similarity[i][i] = 1
            for j in (i + 1)..<n {
                let s = phraseSimilarity(phrases[i].features, phrases[j].features)
                similarity[i][j] = s
                similarity[j][i] = s
            }
        }

        // ── Hook family: the most-repeated high-energy family ──
        let maxEnergy = phrases.map(\.energyMean).max() ?? 1
        let highEnergy = phrases.indices.filter { phrases[$0].energyMean >= maxEnergy * 0.75 }
        var bestFamily: [Int] = []
        for seedIdx in highEnergy {
            let family = highEnergy.filter { similarity[seedIdx][$0] >= familySimilarity }
            if family.count > bestFamily.count { bestFamily = family }
        }
        let hookPhrases = Set(bestFamily)

        // ── Removability classes ──
        for i in phrases.indices {
            if hookPhrases.contains(i) {
                phrases[i].removability = .hookFamily
            } else if phrases[i].startSeconds < anchor + unit * 2,
                      phrases[i].energyMean < maxEnergy * 0.6 {
                phrases[i].removability = .intro
            } else if phrases[i].endSeconds > usableRange.upperBound - unit * 3 - 0.5,
                      phrases[i].energyMean < maxEnergy * 0.6 {
                phrases[i].removability = .outro
            } else if phrases[i].vocalMean >= vocalThreshold {
                phrases[i].removability = .vocalDistinct
            } else {
                phrases[i].removability = .instrumental
            }
        }

        // ── Hook instances (contiguous runs) with differentiation ──
        var instances: [AutoRemixHookInstance] = []
        var run: [Int] = []
        func closeRun() {
            guard !run.isEmpty else { return }
            instances.append(
                AutoRemixHookInstance(
                    phraseIndices: run,
                    startSeconds: phrases[run.first!].startSeconds,
                    endSeconds: phrases[run.last!].endSeconds,
                    differentiation: .nearDuplicate,   // classified below
                    isProtected: instances.isEmpty
                )
            )
            run = []
        }
        for i in phrases.indices {
            if hookPhrases.contains(i) {
                run.append(i)
            } else {
                closeRun()
            }
        }
        closeRun()

        if let first = instances.first {
            func instanceMean(_ inst: AutoRemixHookInstance, _ key: (AutoRemixPhrase) -> Double) -> Double {
                let values = inst.phraseIndices.map { key(phrases[$0]) }
                return values.reduce(0, +) / Double(max(values.count, 1))
            }
            let refEnergy = instanceMean(first, \.energyMean)
            let refVocal = instanceMean(first, \.vocalMean)
            let refDensity = instanceMean(first, \.onsetDensity)

            for k in instances.indices.dropFirst() {
                let inst = instances[k]
                var pairSim = 0.0
                var pairs = 0
                for (a, b) in zip(first.phraseIndices, inst.phraseIndices) {
                    pairSim += similarity[a][b]
                    pairs += 1
                }
                pairSim = pairs > 0 ? pairSim / Double(pairs) : 0

                let dEnergy = instanceMean(inst, \.energyMean) - refEnergy
                let dVocal = instanceMean(inst, \.vocalMean) - refVocal
                let dDensity = instanceMean(inst, \.onsetDensity) - refDensity

                let differentiation: AutoHookDifferentiation
                if dEnergy >= differentiationDelta || dVocal >= differentiationDelta
                    || dDensity >= 0.15 {
                    differentiation = .intensified
                } else if dEnergy <= -differentiationDelta {
                    differentiation = .reduced
                } else if pairSim >= 0.8 {
                    differentiation = .nearDuplicate
                } else {
                    differentiation = .structurallyDistinct
                }
                instances[k].differentiation = differentiation
                // Only a near-duplicate may lose its protection.
                instances[k].isProtected = differentiation != .nearDuplicate
            }
        }

        // ── Regions: thirds of the usable range ──
        let span = usableRange.upperBound - usableRange.lowerBound
        let third = span / 3
        map.regions = [
            usableRange.lowerBound...(usableRange.lowerBound + third),
            (usableRange.lowerBound + third)...(usableRange.lowerBound + 2 * third),
            (usableRange.lowerBound + 2 * third)...usableRange.upperBound,
        ]

        map.phrases = phrases
        map.similarity = similarity
        map.hookInstances = instances
        return map
    }

    // MARK: Internals

    nonisolated private static func meanCurve(
        _ curve: [Double],
        hop: Double,
        from start: Double,
        to end: Double
    ) -> Double {
        guard hop > 0, !curve.isEmpty, end > start else { return 0 }
        let lo = max(0, Int(start / hop))
        let hi = min(curve.count - 1, Int(end / hop))
        guard hi >= lo else { return 0 }
        var sum = 0.0
        for i in lo...hi { sum += curve[i] }
        return sum / Double(hi - lo + 1)
    }

    /// Fraction of hops whose onset exceeds twice the median — a 0…1
    /// transient-density proxy.
    nonisolated private static func onsetDensity(
        _ onset: [Double],
        hop: Double,
        from start: Double,
        to end: Double,
        median: Double
    ) -> Double {
        guard hop > 0, !onset.isEmpty, end > start, median > 0 else { return 0 }
        let lo = max(0, Int(start / hop))
        let hi = min(onset.count - 1, Int(end / hop))
        guard hi >= lo else { return 0 }
        var hits = 0
        for i in lo...hi where onset[i] > median * 2 { hits += 1 }
        return Double(hits) / Double(hi - lo + 1)
    }

    nonisolated private static func phraseSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0.0
        for i in a.indices {
            let d = a[i] - b[i]
            sum += d * d
        }
        let distance = (sum / Double(a.count)).squareRoot()
        return max(0, 1 - distance * 2.5)
    }

    nonisolated private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}
