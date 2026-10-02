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

    /// Measured beat / bar / phrase / section structure (nil when the
    /// audio was too short or had no trackable pulse).
    var structure: SongStructure? = nil

    /// Short-time K-weighted (ITU-R BS.1770 pre-filter) power in dB, one
    /// value per `hopSeconds` — what listeners hear as loudness: a bright
    /// mix reads louder, a bass-heavy one quieter, than its raw RMS.
    var loudnessCurveDB: [Double] = []

    /// Loudness of the song body, dBFS: mean power of the loudest 60% of
    /// 100 ms hops (edge silence and quiet passages excluded). Used for
    /// loudness matching between songs.
    nonisolated var bodyLoudnessDB: Double {
        let powers = rmsCurveDB.map { pow(10, $0 / 10) }.sorted(by: >)
        guard !powers.isEmpty else { return -120 }
        let n = max(1, Int(Double(powers.count) * 0.6))
        return 10 * log10(max(powers.prefix(n).reduce(0, +) / Double(n), 1e-12))
    }

    nonisolated var hopCount: Int { rmsCurveDB.count }

    /// Mean K-weighted loudness over a source range (power domain, dB);
    /// falls back to raw RMS when the curve is unavailable.
    nonisolated func meanLoudnessDB(from start: Double, to end: Double) -> Double {
        guard hopSeconds > 0, !loudnessCurveDB.isEmpty else { return meanRMSDB(from: start, to: end) }
        let lo = max(0, Int(start / hopSeconds))
        let hi = min(loudnessCurveDB.count - 1, Int(end / hopSeconds))
        guard hi >= lo else { return -120 }
        var power = 0.0
        for i in lo...hi { power += pow(10, loudnessCurveDB[i] / 10) }
        return 10 * log10(max(power / Double(hi - lo + 1), 1e-12))
    }

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

    /// Fine hop used for onset/beat-phase work (10 ms).
    nonisolated static let onsetHopSeconds = 0.01
    /// Edge silence threshold, dBFS (20 ms windows).
    nonisolated static let silenceThresholdDB = -50.0

    /// Extracts signal features from mono PCM.
    /// `bpmHint` (from metadata/estimation) anchors beat-phase search;
    /// without a hint the period is estimated by onset autocorrelation.
    /// Every value here is MEASURED — no seeds, no fractions-of-duration.
    nonisolated static func extract(
        samples: [Float],
        sampleRate: Double,
        bpmHint: Double? = nil
    ) -> SongSignalFeatures {
        let duration = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        guard sampleRate > 0, duration > 1.0 else {
            return emptyFeatures(sampleRate: sampleRate, duration: duration)
        }

        // ── Band-filtered streams (one-pole cascades, single pass) ──
        // bass ≈ < 150 Hz, mid ≈ 300 Hz – 3 kHz (vocal-presence proxy).
        let aBass = onePoleCoefficient(cutoff: 150, sampleRate: sampleRate)
        let aMidLo = onePoleCoefficient(cutoff: 300, sampleRate: sampleRate)
        let aMidHi = onePoleCoefficient(cutoff: 3000, sampleRate: sampleRate)

        let hop = max(1, Int(hopSeconds * sampleRate))
        let hopCount = max(1, samples.count / hop)
        var rmsDB = [Double](repeating: -120, count: hopCount)
        var bassRMS = [Double](repeating: 0, count: hopCount)
        var midRMS = [Double](repeating: 0, count: hopCount)
        var totalRMS = [Double](repeating: 0, count: hopCount)

        let fineHop = max(1, Int(onsetHopSeconds * sampleRate))
        let fineCount = max(1, samples.count / fineHop)
        var fineRMS = [Double](repeating: 0, count: fineCount)

        var lpBass: Double = 0
        var lpMidLo: Double = 0
        var lpMidHi: Double = 0
        var sumSq = 0.0, sumSqBass = 0.0, sumSqMid = 0.0
        var hopIdx = 0, hopFill = 0
        var fineSumSq = 0.0
        var fineIdx = 0, fineFill = 0
        var prevSample = 0.0

        for sample in samples {
            let v = Double(sample)
            lpBass += (v - lpBass) * aBass
            lpMidLo += (v - lpMidLo) * aMidLo
            lpMidHi += (v - lpMidHi) * aMidHi
            let mid = lpMidHi - lpMidLo
            // Transient emphasis for the beat tracker: first difference
            // (6 dB/oct high-pass) so steady tonal content cannot bias
            // the onset grid — only true transients score.
            let transient = v - prevSample
            prevSample = v

            sumSq += v * v
            sumSqBass += lpBass * lpBass
            sumSqMid += mid * mid
            hopFill += 1
            if hopFill == hop, hopIdx < hopCount {
                let n = Double(hop)
                let rms = (sumSq / n).squareRoot()
                rmsDB[hopIdx] = 20 * log10(max(rms, 1e-12))
                totalRMS[hopIdx] = rms
                bassRMS[hopIdx] = (sumSqBass / n).squareRoot()
                midRMS[hopIdx] = (sumSqMid / n).squareRoot()
                hopIdx += 1
                hopFill = 0
                sumSq = 0; sumSqBass = 0; sumSqMid = 0
            }

            fineSumSq += transient * transient
            fineFill += 1
            if fineFill == fineHop, fineIdx < fineCount {
                fineRMS[fineIdx] = (fineSumSq / Double(fineHop)).squareRoot()
                fineIdx += 1
                fineFill = 0
                fineSumSq = 0
            }
        }

        // ── Onset strength (half-wave rectified RMS difference) ──
        var fineOnset = [Double](repeating: 0, count: fineCount)
        for i in 1..<fineCount {
            fineOnset[i] = max(0, fineRMS[i] - fineRMS[i - 1])
        }
        var hopOnset = [Double](repeating: 0, count: hopCount)
        for i in 1..<hopCount {
            hopOnset[i] = max(0, totalRMS[i] - totalRMS[i - 1])
        }

        // ── Edge silence (20 ms windows against an absolute floor) ──
        let edgeWindow = max(1, Int(0.02 * sampleRate))
        let silenceLin = pow(10, silenceThresholdDB / 20)
        var leadingSilence = 0.0
        var i = 0
        while i + edgeWindow <= samples.count {
            var s = 0.0
            for j in i..<(i + edgeWindow) { s += Double(samples[j]) * Double(samples[j]) }
            if (s / Double(edgeWindow)).squareRoot() > silenceLin { break }
            i += edgeWindow
            leadingSilence = Double(i) / sampleRate
        }
        var trailingSilence = 0.0
        var k = samples.count
        while k - edgeWindow >= 0 {
            var s = 0.0
            for j in (k - edgeWindow)..<k { s += Double(samples[j]) * Double(samples[j]) }
            if (s / Double(edgeWindow)).squareRoot() > silenceLin { break }
            k -= edgeWindow
            trailingSilence = Double(samples.count - k) / sampleRate
        }
        // A fully silent buffer: report it all as leading silence.
        if leadingSilence >= duration - 0.05 { trailingSilence = 0 }

        // ── Normalized curves (95th percentile as reference) ──
        func normalized(_ values: [Double]) -> [Double] {
            let sorted = values.sorted()
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            guard p95 > 1e-9 else { return values.map { _ in 0 } }
            return values.map { min(1, $0 / p95) }
        }
        let energyCurve = normalized(totalRMS)
        let bassCurve = normalized(bassRMS)
        let vocalCurve = normalized(midRMS)

        var novelty = [Double](repeating: 0, count: hopCount)
        for idx in 1..<hopCount {
            novelty[idx] = abs(energyCurve[idx] - energyCurve[idx - 1])
                + abs(bassCurve[idx] - bassCurve[idx - 1])
                + abs(vocalCurve[idx] - vocalCurve[idx - 1])
        }
        let noveltyCurve = normalized(novelty)

        // ── Interior quiet regions (≥ 1 s well below the body level) ──
        let bodyHops = rmsDB.enumerated().filter {
            let t = Double($0.offset) * hopSeconds
            return t >= leadingSilence && t < duration - trailingSilence
        }.map(\.element)
        let medianDB = median(bodyHops) ?? -120
        let quietFloorDB = max(-45.0, medianDB - 18.0)
        var quietRegions: [SignalRegion] = []
        var runStart: Double?
        for idx in 0..<hopCount {
            let t = Double(idx) * hopSeconds
            let inBody = t >= leadingSilence && t < duration - trailingSilence
            let quiet = inBody && rmsDB[idx] < quietFloorDB
            if quiet {
                if runStart == nil { runStart = t }
            } else if let s = runStart {
                if t - s >= 1.0 { quietRegions.append(SignalRegion(start: s, end: t)) }
                runStart = nil
            }
        }
        if let s = runStart, duration - trailingSilence - s >= 1.0 {
            quietRegions.append(SignalRegion(start: s, end: duration - trailingSilence))
        }

        // ── Beat period + phase ──
        let period: Double?
        if let bpmHint, bpmHint >= 40, bpmHint <= 220 {
            period = 60.0 / bpmHint
        } else {
            period = estimatePeriod(onset: fineOnset, hop: onsetHopSeconds)
        }

        var downbeatOffset: Double?
        var beatConfidence = 0.0
        var drumConfidence = 0.0
        if let period {
            let search = beatPhase(
                onset: fineOnset,
                hop: onsetHopSeconds,
                period: period,
                searchStart: leadingSilence,
                searchSeconds: min(30, duration - leadingSilence - trailingSilence)
            )
            beatConfidence = search.confidence
            drumConfidence = search.drumConfidence
            if search.confidence > 0.2 {
                // First grid time at/after the music starts with real onset
                // energy — never assume the source begins on beat one.
                downbeatOffset = search.firstBeatSeconds
            }
        }

        let durationFactor = min(1.0, duration / 30.0)
        var overall = min(1.0, max(0.0, 0.25 + 0.55 * beatConfidence + 0.2 * durationFactor))

        // ── Measured structure (beats, bars, phrases, sections) ──
        // When it succeeds it supersedes the coarse phase search above:
        // float tempo, real downbeats, and section evidence.
        let structure = SongStructureAnalyzer.analyze(samples: samples, sampleRate: sampleRate, bpmHint: bpmHint)
        if let structure {
            beatConfidence = max(beatConfidence * 0.5, structure.beatConfidence)
            // Only a CONFIDENT bar phase may replace the first-beat estimate;
            // with no bar-level evidence (identical beats) "beat one" is unknown.
            if structure.downbeatConfidence >= 0.3,
               let first = structure.downbeats.first(where: { $0 >= leadingSilence - 0.05 }) {
                downbeatOffset = first
            }
            overall = min(1.0, max(0.0,
                0.15 + 0.4 * structure.structureConfidence
                    + 0.3 * min(1, structure.beatConfidence * 1.5)
                    + 0.15 * structure.downbeatConfidence))
        }

        return SongSignalFeatures(
            sampleRate: sampleRate,
            durationSeconds: duration,
            rmsCurveDB: rmsDB,
            onsetStrength: hopOnset,
            hopSeconds: hopSeconds,
            downbeatOffsetSeconds: downbeatOffset,
            beatConfidence: beatConfidence,
            leadingSilenceSeconds: leadingSilence,
            trailingSilenceSeconds: trailingSilence,
            quietRegions: quietRegions,
            energyCurve: energyCurve,
            bassEnergyCurve: bassCurve,
            vocalPresenceCurve: vocalCurve,
            noveltyCurve: noveltyCurve,
            drumConfidence: drumConfidence,
            overallConfidence: overall,
            structure: structure,
            loudnessCurveDB: kWeightedCurveDB(samples, sampleRate: sampleRate, hop: hop, count: hopCount)
        )
    }

    /// BS.1770 K-weighting (high shelf +4 dB above ≈1.7 kHz, then a 38 Hz
    /// high-pass; coefficients derived for any sample rate), mean power
    /// per hop in dB.
    nonisolated static func kWeightedCurveDB(_ x: [Float], sampleRate fs: Double, hop: Int, count: Int) -> [Double] {
        // De Man's bilinear form of the BS.1770 shelf (reproduces the
        // spec's published 48 kHz coefficients exactly).
        func shelf() -> [Double] {
            let g = 3.999843853973347, q = 0.7071752369554196, fc = 1681.974450955533
            let k = tan(Double.pi * fc / fs), vh = pow(10, g / 20), vb = pow(vh, 0.4996667741545416)
            let a0 = 1 + k / q + k * k
            return [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
                    2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        }
        func highPass() -> [Double] {
            let q = 0.5003270373238773, fc = 38.13547087602444
            let k = tan(Double.pi * fc / fs), a0 = 1 + k / q + k * k
            return [1, -2, 1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        }
        let stages = [shelf(), highPass()]
        var z = [[Double]](repeating: [0, 0], count: 2)   // transposed direct form II state
        var out = [Double](repeating: -120, count: count)
        var sum = 0.0, fill = 0, idx = 0
        for sample in x {
            var v = Double(sample)
            for (k, h) in stages.enumerated() {
                let y = h[0] * v + z[k][0]
                z[k][0] = h[1] * v - h[3] * y + z[k][1]
                z[k][1] = h[2] * v - h[4] * y
                v = y
            }
            sum += v * v; fill += 1
            if fill == hop {
                if idx < count { out[idx] = 10 * log10(max(sum / Double(hop), 1e-12)) }
                idx += 1; sum = 0; fill = 0
            }
        }
        return out
    }

    // MARK: Internals

    nonisolated private static func emptyFeatures(
        sampleRate: Double,
        duration: Double
    ) -> SongSignalFeatures {
        SongSignalFeatures(
            sampleRate: sampleRate,
            durationSeconds: duration,
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

    nonisolated private static func onePoleCoefficient(
        cutoff: Double,
        sampleRate: Double
    ) -> Double {
        1.0 - exp(-2.0 * .pi * cutoff / sampleRate)
    }

    nonisolated private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Onset autocorrelation over the 60–200 BPM lag range.
    nonisolated private static func estimatePeriod(
        onset: [Double],
        hop: Double
    ) -> Double? {
        let minLag = max(2, Int(60.0 / 200.0 / hop))
        let maxLag = min(onset.count - 1, Int(60.0 / 60.0 / hop))
        guard minLag < maxLag else { return nil }
        var bestLag = 0
        var bestScore = 0.0
        for lag in minLag...maxLag {
            var score = 0.0
            for i in 0..<(onset.count - lag) {
                score += onset[i] * onset[i + lag]
            }
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0, bestScore > 0 else { return nil }
        return Double(bestLag) * hop
    }

    /// Grid-phase search: which offset φ ∈ [0, period) lines the beat grid
    /// up with the measured onsets. Returns the first REAL beat time (grid
    /// time whose local onset is strong), a 0…1 phase confidence, and the
    /// fraction of grid points landing on strong onsets (drum confidence).
    nonisolated private static func beatPhase(
        onset: [Double],
        hop: Double,
        period: Double,
        searchStart: Double,
        searchSeconds: Double
    ) -> (firstBeatSeconds: Double?, confidence: Double, drumConfidence: Double) {
        guard period > 0.1, searchSeconds > period * 4 else { return (nil, 0, 0) }
        let phaseSteps = max(8, Int(period / 0.005))
        let searchEnd = searchStart + searchSeconds

        func onsetAt(_ t: Double) -> Double {
            let idx = Int(t / hop)
            guard idx >= 1, idx < onset.count - 1 else { return 0 }
            // Small neighborhood max — forgives ±1 hop of grid error.
            return max(onset[idx - 1], onset[idx], onset[idx + 1])
        }

        let overallMean = onset.isEmpty
            ? 0.0
            : onset.reduce(0, +) / Double(onset.count)

        var bestPhase = 0.0
        var bestScore = -1.0
        for step in 0..<phaseSteps {
            let phi = Double(step) / Double(phaseSteps) * period
            var score = 0.0
            var count = 0
            var t = searchStart + phi
            while t < searchEnd {
                score += onsetAt(t)
                count += 1
                t += period
            }
            guard count > 0 else { continue }
            score /= Double(count)
            if score > bestScore {
                bestScore = score
                bestPhase = phi
            }
        }
        guard bestScore > 0, overallMean > 0 else { return (nil, 0, 0) }

        // Confidence: how much the best grid stands out over the average.
        let ratio = bestScore / (overallMean + 1e-12)
        let confidence = min(1.0, max(0.0, (ratio - 1.0) / 6.0))

        // First grid time with real onset energy = first audible beat.
        let strongLevel = bestScore * 0.3
        var firstBeat: Double?
        var t = searchStart + bestPhase
        while t < searchEnd {
            if onsetAt(t) >= strongLevel {
                firstBeat = t
                break
            }
            t += period
        }

        // Drum confidence: fraction of grid points with a clear transient.
        var strongHits = 0
        var gridPoints = 0
        var g = firstBeat ?? (searchStart + bestPhase)
        while g < searchEnd {
            gridPoints += 1
            if onsetAt(g) > overallMean * 2 { strongHits += 1 }
            g += period
        }
        let drum = gridPoints > 0 ? Double(strongHits) / Double(gridPoints) : 0

        return (firstBeat, confidence, drum)
    }
}
