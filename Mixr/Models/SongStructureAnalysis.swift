import Foundation

// MARK: - Measured Song Structure
//
// Beat, bar, phrase, and section structure MEASURED from decoded PCM —
// the evidence base the Auto planner edits from. Pure Swift over [Float]
// so it runs identically on-device (fed by MixrAudioAnalyzer's reader)
// and in the portable Linux test harness (fed by fixtures / corpus).
//
// Pipeline:
//   1. anti-aliased decimation to ≈ 11 kHz
//   2. STFT (1024 / hop 256) → 24 log bands → spectral-flux onset envelope
//      (+ a kick-band flux and a snare-band flux)
//   3. tempo: onset autocorrelation (octave-resolved by the BPM hint or a
//      log-normal prior) → dynamic-programming beat tracker (Ellis 2007)
//   4. constant-tempo fit (float BPM, never rounded) + 5 ms phase refinement
//      against the time-domain transient envelope; tempo stability measured
//   5. downbeat phase: harmonic change + kick-vs-backbeat at each beat
//   6. bar-synchronous chroma + timbre → self-similarity matrix
//   7. checkerboard + energy novelty → phrase-grid (4-bar) boundaries
//   8. repetition groups → chorus = repeated high-energy group; intro /
//      build / verse / bridge / breakdown / outro from position + energy
//
// Every derived value carries a confidence. Nothing here is seeded or
// derived from fractions of the song's duration.

nonisolated struct BarFeatures: Sendable {
    var start: Double
    var end: Double
    /// Mean power of the bar, dBFS.
    var rmsDB: Double
    /// 0…1 loudness normalized across the song (p5 → 0, p95 → 1).
    var energy: Double
    /// 0…1 low-band (< 120 Hz) share, normalized across the song.
    var bass: Double
    /// 0…1 vocal-band presence proxy, normalized across the song.
    var vocal: Double
    /// 0…1 onset density, normalized across the song.
    var onset: Double
    /// 12-bin chroma, L2-normalized.
    var chroma: [Double]
    /// Coarse log band energies (sub, low, low-mid, mid, high), dB.
    var bands: [Double]
}

nonisolated struct MeasuredSection: Sendable, Equatable {
    enum Label: String, Sendable {
        case intro, verse, build, chorus, bridge, breakdown, outro
    }

    var label: Label
    /// Bar indices into `SongStructure.bars`, end exclusive.
    var startBar: Int
    var endBar: Int
    var start: Double
    var end: Double
    /// Repetition group id (sections sharing material); −1 = unique.
    var group: Int
    var energy: Double
    var vocal: Double
    var bass: Double
    var confidence: Double

    var barCount: Int { endBar - startBar }
    var duration: Double { end - start }
}

nonisolated struct SongStructure: Sendable {
    var bpm: Double
    /// Beat times (seconds). Ideal constant grid when tempo is stable,
    /// tracked beats otherwise.
    var beatTimes: [Double]
    /// Bar start times (downbeats), seconds.
    var downbeats: [Double]
    var beatConfidence: Double
    var downbeatConfidence: Double
    /// 0…1 — share of beats in the longest constant-tempo run.
    var tempoStability: Double
    /// Source times where the beat grid is discontinuous (a new constant-
    /// tempo run starts: tempo drift, an edit, or a stitched section).
    /// Beatmatched overlaps must not span one.
    var gridBreaks: [Double] = []
    /// Phrase grid phase: phrases start at bars ≡ offset (mod 4).
    var phraseOffsetBars: Int
    var bars: [BarFeatures]
    var sections: [MeasuredSection]
    /// 0…1 trust in the section map (boundary prominence × repetition).
    var structureConfidence: Double
    var key: String?
    var keyConfidence: Double
    /// Loudness of the song body: mean power of the loudest 60% of bars, dBFS.
    var bodyLoudnessDB: Double

    var barSeconds: Double { 240.0 / max(bpm, 1) }

    /// Downbeat nearest to `t`.
    func nearestDownbeat(to t: Double) -> Double? {
        downbeats.min { abs($0 - t) < abs($1 - t) }
    }

    /// Index of the bar containing `t` (nil before the first downbeat).
    func barIndex(at t: Double) -> Int? {
        guard let first = downbeats.first, t >= first - 1e-6 else { return nil }
        var lo = 0, hi = downbeats.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if downbeats[mid] <= t + 1e-6 { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Time of bar `i` (extrapolated on the grid past the tracked bars).
    func barTime(_ i: Int) -> Double {
        if i >= 0, i < downbeats.count { return downbeats[i] }
        guard let first = downbeats.first else { return Double(i) * barSeconds }
        if i < 0 { return first + Double(i) * barSeconds }
        let last = downbeats[downbeats.count - 1]
        return last + Double(i - downbeats.count + 1) * barSeconds
    }

    func sections(_ label: MeasuredSection.Label) -> [MeasuredSection] {
        sections.filter { $0.label == label }
    }
}

// MARK: - Analyzer

nonisolated enum SongStructureAnalyzer {

    static let analysisRate = 11_025.0
    static let fftSize = 1024
    static let hop = 256
    static let chromaFFTSize = 4096
    static let chromaHop = 1024

    /// Full structure analysis. `bpmHint` (metadata) only resolves the
    /// tempo octave — the tempo itself is always measured.
    static func analyze(
        samples: [Float],
        sampleRate: Double,
        bpmHint: Double? = nil
    ) -> SongStructure? {
        guard sampleRate > 0, Double(samples.count) / sampleRate > 12 else { return nil }

        // ── 1. Decimate ──
        let factor = max(1, Int((sampleRate / analysisRate).rounded()))
        let x = decimate(samples, factor: factor)
        let sr = sampleRate / Double(factor)
        let duration = Double(samples.count) / sampleRate

        // ── 2. STFT features ──
        let stft = spectralFeatures(x, sampleRate: sr)
        let frameRate = sr / Double(hop)
        let frameOffset = Double(fftSize) / 2 / sr   // frame t ↔ time t/frameRate + offset
        func frameTime(_ f: Double) -> Double { f / frameRate + frameOffset }

        let onset = normalizedOnset(stft.flux, frameRate: frameRate)
        guard onset.count > Int(frameRate * 8) else { return nil }

        // ── 3. Tempo + DP beats ──
        guard let period = estimatePeriod(onset, frameRate: frameRate, bpmHint: bpmHint) else { return nil }
        var beatFrames = trackBeats(onset, period: period)
        guard beatFrames.count >= 16 else { return nil }
        // Second pass with the period the first pass actually measured —
        // the autocorrelation lag is coarse (≈ ±0.3%), and a DP tracker
        // held to a slightly wrong period drifts 50–100 ms between strong
        // onsets.
        let ibi = zip(beatFrames.dropFirst(), beatFrames).map { Double($0 - $1) }.sorted()
        let medianIBI = ibi[ibi.count / 2]
        let refinedPeriod = linearFit(beatFrames.map(Double.init)).slope
        if abs(refinedPeriod - medianIBI) < medianIBI * 0.05, abs(refinedPeriod - period) < period * 0.03 {
            let second = trackBeats(onset, period: refinedPeriod)
            if second.count >= 16 { beatFrames = second }
        }
        var beats = beatFrames.map { frameTime(Double($0)) }

        // ── 4. Piecewise constant-tempo grid + fine phase ──
        // Quantized productions give one run; live drift or edited
        // material splits into several locally-linear runs. Each run is
        // replaced by its ideal grid, phase-refined in 2 ms steps against
        // the time-domain transients.
        let transient = transientEnvelope(samples, sampleRate: sampleRate)
        // Sub-frame refinement: DP beats are quantized to 23 ms frames;
        // snap each to the strongest transient within ±30 ms so frame
        // jitter never reads as a tempo change.
        let beatPeriod = linearFit(beats).slope
        let refineWindow = min(0.08, 0.15 * beatPeriod)     // < a 16th note at any tempo
        beats = beats.map { refineBeat($0, transient: transient.values, hop: transient.hop, window: refineWindow) }
        // Quantized productions: one robust constant-tempo line explains
        // (almost) every beat. Only when it doesn't are runs split.
        let global = robustLinearFit(beats)
        let inliers = beats.enumerated().filter {
            abs($0.element - (global.intercept + global.slope * Double($0.offset))) < 0.04
        }.count
        let runs = Double(inliers) / Double(beats.count) >= 0.85 ? [0..<beats.count] : gridRuns(beats)
        var gridBeats: [Double] = []
        var runStarts: [Int] = []
        for run in runs {
            let slice = Array(beats[run])
            runStarts.append(gridBeats.count)
            guard slice.count >= 8 else { gridBeats += slice; continue }
            let fit = robustLinearFit(slice)
            let shift = refinePhase(transient: transient.values, hop: transient.hop,
                                    t0: fit.intercept, period: fit.slope, count: slice.count)
            gridBeats += (0..<slice.count).map { fit.intercept + shift + fit.slope * Double($0) }
        }
        beats = gridBeats
        let longest = runs.map(\.count).max() ?? 0
        let stability = Double(longest) / Double(max(beats.count, 1))
        let ibis = zip(beats.dropFirst(), beats).map { $0 - $1 }.sorted()
        let bpm = 60.0 / ibis[ibis.count / 2]
        let gridBreaks = runStarts.dropFirst().filter { $0 < beats.count }.map { beats[$0] }

        let beatConfidence = beatStrengthConfidence(onset: onset, beats: beats, frameRate: frameRate,
                                                    frameOffset: frameOffset) * (0.6 + 0.4 * stability)

        // ── 5. Downbeats: Viterbi over bar positions (phase may re-lock
        // only at grid discontinuities) ──
        let chromaFrames = chromagram(x, sampleRate: sr)
        let bassChroma = chromagram(x, sampleRate: sr, minHz: 38, maxHz: 260)
        let chromaRate = sr / Double(chromaHop)
        let chromaOffset = Double(chromaFFTSize) / 2 / sr
        let downbeat = downbeatPositions(
            beats: beats, runStarts: Set(runStarts),
            kick: stft.kickFlux, snare: stft.snareFlux, frameRate: frameRate, frameOffset: frameOffset,
            chroma: chromaFrames, bassChroma: bassChroma, chromaRate: chromaRate, chromaOffset: chromaOffset
        )
        var downbeats = downbeat.indices.map { beats[$0] }
        // Extend the bar grid backwards over audible material before the
        // first tracked downbeat (pickups / soft intros).
        if let first = downbeats.first {
            let barLen = 240.0 / bpm
            var t = first - barLen
            while t >= -0.02 {
                downbeats.insert(max(0, t), at: 0)
                t -= barLen
            }
        }
        guard downbeats.count >= 8 else { return nil }

        // ── 6. Bar features ──
        let bars = barFeatures(
            downbeats: downbeats, duration: duration,
            stft: stft, onset: onset, frameRate: frameRate, frameOffset: frameOffset,
            chroma: chromaFrames, chromaRate: chromaRate, chromaOffset: chromaOffset
        )

        // ── 7. SSM + novelty + phrase grid ──
        let ssm = selfSimilarity(bars)
        let novelty = combinedNovelty(ssm: ssm, bars: bars)
        let phraseOffset = bestPhraseOffset(novelty)
        let boundaries = pickBoundaries(novelty: novelty, offset: phraseOffset, barCount: bars.count)

        // ── 8. Sections ──
        var sections = labelSections(boundaries: boundaries, bars: bars, ssm: ssm)
        let prominence = boundaryProminence(novelty: novelty, boundaries: boundaries)
        let repeated = sections.contains { $0.label == .chorus && $0.group >= 0 }
        let structureConfidence = min(1, max(0,
            0.35 * beatConfidence + 0.25 * downbeat.confidence + 0.25 * prominence + (repeated ? 0.15 : 0.0)))
        for i in sections.indices {
            sections[i].confidence = min(sections[i].confidence, structureConfidence + 0.2)
        }

        let key = estimateKey(chromaFrames)
        let sortedPower = bars.map { pow(10, $0.rmsDB / 10) }.sorted(by: >)
        let loudCount = max(1, Int(Double(sortedPower.count) * 0.6))
        let body = 10 * log10(max(sortedPower.prefix(loudCount).reduce(0, +) / Double(loudCount), 1e-12))

        return SongStructure(
            bpm: bpm,
            beatTimes: beats,
            downbeats: downbeats,
            beatConfidence: beatConfidence,
            downbeatConfidence: downbeat.confidence,
            tempoStability: stability,
            gridBreaks: gridBreaks,
            phraseOffsetBars: phraseOffset,
            bars: bars,
            sections: sections,
            structureConfidence: structureConfidence,
            key: key?.name,
            keyConfidence: key?.confidence ?? 0,
            bodyLoudnessDB: body
        )
    }

    // MARK: 1. Decimation (windowed-sinc FIR, only kept outputs computed)

    static func decimate(_ x: [Float], factor: Int) -> [Float] {
        guard factor > 1 else { return x }
        let half = 8 * factor
        let cutoff = 0.45 / Double(factor)
        var h = [Float](repeating: 0, count: 2 * half + 1)
        var sum: Float = 0
        for k in -half...half {
            let n = Double(k)
            let sinc = k == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * n) / (.pi * n)
            let w = 0.42 + 0.5 * cos(.pi * n / Double(half)) + 0.08 * cos(2 * .pi * n / Double(half))
            h[k + half] = Float(sinc * w)
            sum += h[k + half]
        }
        for i in h.indices { h[i] /= sum }
        let outCount = x.count / factor
        var y = [Float](repeating: 0, count: outCount)
        x.withUnsafeBufferPointer { xp in
            h.withUnsafeBufferPointer { hp in
                for m in 0..<outCount {
                    let c = m * factor
                    var acc: Float = 0
                    let lo = max(0, c - half), hi = min(x.count - 1, c + half)
                    var k = lo
                    while k <= hi {
                        acc += xp[k] * hp[k - c + half]
                        k += 1
                    }
                    y[m] = acc
                }
            }
        }
        return y
    }

    // MARK: 2. STFT features

    struct SpectralFeatures {
        var flux: [Double]
        var kickFlux: [Double]
        var snareFlux: [Double]
        /// Per frame: power in coarse bands (sub <120, low 120–400,
        /// low-mid 400–1k, mid 1k–2.5k, high 2.5k+), and vocal band 300–3.4k.
        var bandPower: [[Double]]
        var vocalPower: [Double]
        var totalPower: [Double]
    }

    static func spectralFeatures(_ x: [Float], sampleRate sr: Double) -> SpectralFeatures {
        let n = fftSize
        let frames = max(0, (x.count - n) / hop + 1)
        let fft = FFT(size: n)
        let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n))) }
        let binHz = sr / Double(n)

        // 24 log bands 40 Hz … 5 kHz for flux.
        let edges = (0...24).map { 40.0 * pow(5000.0 / 40.0, Double($0) / 24.0) }
        var bandOfBin = [Int](repeating: -1, count: n / 2 + 1)
        for b in 0..<(n / 2 + 1) {
            let f = Double(b) * binHz
            if let idx = (0..<24).first(where: { f >= edges[$0] && f < edges[$0 + 1] }) { bandOfBin[b] = idx }
        }
        let coarseEdges = [20.0, 120, 400, 1000, 2500, sr / 2]
        func coarse(_ f: Double) -> Int { (0..<5).first { f >= coarseEdges[$0] && f < coarseEdges[$0 + 1] } ?? -1 }
        let coarseOfBin = (0..<(n / 2 + 1)).map { coarse(Double($0) * binHz) }

        var bandLog = [[Double]](repeating: [Double](repeating: 0, count: 24), count: frames)
        var bandPower = [[Double]](repeating: [Double](repeating: 0, count: 5), count: frames)
        var vocal = [Double](repeating: 0, count: frames)
        var total = [Double](repeating: 0, count: frames)
        var re = [Float](repeating: 0, count: n)
        var im = [Float](repeating: 0, count: n)
        var bands24 = [Double](repeating: 0, count: 24)

        for f in 0..<frames {
            let base = f * hop
            for i in 0..<n {
                re[i] = x[base + i] * window[i]
                im[i] = 0
            }
            fft.forward(&re, &im)
            for i in 0..<24 { bands24[i] = 0 }
            var coarseP = [Double](repeating: 0, count: 5)
            var v = 0.0, tot = 0.0
            for b in 1...(n / 2) {
                let p = Double(re[b] * re[b] + im[b] * im[b])
                tot += p
                let bi = bandOfBin[b]
                if bi >= 0 { bands24[bi] += p }
                let ci = coarseOfBin[b]
                if ci >= 0 { coarseP[ci] += p }
                let hz = Double(b) * binHz
                if hz >= 300, hz <= 3400 { v += p }
            }
            for i in 0..<24 { bandLog[f][i] = bands24[i] }
            bandPower[f] = coarseP
            vocal[f] = v
            total[f] = tot
        }

        // Log compression with a floor relative to the loudest band energy.
        var peak = 1e-12
        for row in bandLog { for v in row { peak = max(peak, v) } }
        let floor = peak * 1e-7
        for f in 0..<frames {
            for i in 0..<24 { bandLog[f][i] = 10 * log10(bandLog[f][i] + floor) }
        }
        var flux = [Double](repeating: 0, count: frames)
        var kick = [Double](repeating: 0, count: frames)
        var snare = [Double](repeating: 0, count: frames)
        let kickBands = (0..<24).filter { edges[$0 + 1] <= 150 }
        let snareBands = (0..<24).filter { edges[$0] >= 1500 }
        if frames > 1 {
            for f in 1..<frames {
                var s = 0.0, k = 0.0, sn = 0.0
                for i in 0..<24 {
                    let d = max(0, bandLog[f][i] - bandLog[f - 1][i])
                    s += d
                    if kickBands.contains(i) { k += d }
                    if snareBands.contains(i) { sn += d }
                }
                flux[f] = s
                kick[f] = k
                snare[f] = sn
            }
        }
        return SpectralFeatures(flux: flux, kickFlux: kick, snareFlux: snare,
                                bandPower: bandPower, vocalPower: vocal, totalPower: total)
    }

    /// Detrended (1 s moving mean removed), half-wave rectified,
    /// unit-std onset envelope.
    static func normalizedOnset(_ flux: [Double], frameRate: Double) -> [Double] {
        let w = max(1, Int(frameRate * 0.5))
        var prefix = [0.0]
        prefix.reserveCapacity(flux.count + 1)
        for v in flux { prefix.append(prefix.last! + v) }
        var out = [Double](repeating: 0, count: flux.count)
        for i in flux.indices {
            let lo = max(0, i - w), hi = min(flux.count, i + w + 1)
            let mean = (prefix[hi] - prefix[lo]) / Double(hi - lo)
            out[i] = max(0, flux[i] - mean)
        }
        let mean = out.reduce(0, +) / Double(max(out.count, 1))
        let variance = out.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(out.count, 1))
        let sd = max(sqrt(variance), 1e-9)
        return out.map { $0 / sd }
    }

    // MARK: 3. Tempo + DP beat tracking

    /// Beat period in FRAMES. Autocorrelation over 55–215 BPM with
    /// harmonic reinforcement; the octave is resolved toward the hint
    /// (metadata BPM) or a log-normal prior centered on 115 BPM.
    static func estimatePeriod(_ onset: [Double], frameRate: Double, bpmHint: Double?) -> Double? {
        let minLag = Int(frameRate * 60 / 215)
        let maxLag = Int(frameRate * 60 / 55) + 1
        guard onset.count > maxLag * 16 else { return nil }
        var ac = [Double](repeating: 0, count: 12 * maxLag + 8)
        onset.withUnsafeBufferPointer { o in
            for lag in 1..<ac.count {
                var s = 0.0
                var i = 0
                let n = o.count - lag
                while i < n { s += o[i] * o[i + lag]; i += 1 }
                ac[lag] = s / Double(n)
            }
        }
        func acAt(_ l: Double) -> Double {
            let i = Int(l)
            guard i >= 1, i + 1 < ac.count else { return 0 }
            let f = l - Double(i)
            return ac[i] * (1 - f) + ac[i + 1] * f
        }
        var best: (lag: Double, score: Double)?
        var lag = Double(minLag)
        while lag <= Double(maxLag) {
            let bpm = 60 * frameRate / lag
            // Metrical consistency: a true beat period also repeats at the
            // half-bar and bar (2×, 4×); syncopated sub-patterns (dembow
            // 3+3+2) do not.
            let harmonic = acAt(lag) + 0.6 * acAt(lag * 2) + 0.6 * acAt(lag * 4)
            let prior: Double
            if let hint = bpmHint, hint > 30 {
                let octaves = abs(log2(bpm / hint))
                prior = octaves < 0.08 ? 1.0 : exp(-0.5 * pow(octaves / 0.25, 2))
            } else {
                prior = exp(-0.5 * pow(log2(bpm / 115) / 0.9, 2))
            }
            let score = harmonic * prior
            if best == nil || score > best!.score { best = (lag, score) }
            lag += 0.05
        }
        guard let best, best.score > 0 else { return nil }
        guard bpmHint == nil else { return best.lag }

        // Metrical disambiguation: a syncopated pattern (breakbeat kicks
        // every 1½ beats, trap bounce, dembow 3+3+2) can out-score the real
        // pulse. Among the winner and its 3:2 / 4:3 relatives, the TRUE
        // beat is the one whose 1-bar and 2-bar lengths repeat — music
        // loops by the bar, not by 1½ bars.
        // Comb over beat multiples 1…8: the true beat lines up with pattern
        // repeats at EVERY multiple; a 1½-beat pseudo-pulse lands on
        // half-beats at every other multiple.
        func barScore(_ l: Double) -> Double { (1...8).reduce(0.0) { $0 + acAt(Double($1) * l) } / 8 }
        let minBPMLag = Double(minLag), maxBPMLag = Double(maxLag)
        var chosen = best.lag
        var chosenScore = barScore(best.lag)
        for ratio in [2.0 / 3.0, 3.0 / 4.0, 4.0 / 3.0, 3.0 / 2.0] {
            let l = best.lag * ratio
            guard l >= minBPMLag, l <= maxBPMLag, 8 * l + 1 < Double(ac.count) else { continue }
            let score = barScore(l)
            if score > chosenScore * 1.1 { chosen = l; chosenScore = score }
        }
        return chosen
    }

    /// Ellis (2007) dynamic-programming beat tracker. Returns beat frames.
    static func trackBeats(_ onset: [Double], period: Double, tightness: Double = 250) -> [Int] {
        let n = onset.count
        var cum = [Double](repeating: 0, count: n)
        var back = [Int](repeating: -1, count: n)
        let lo = Int((period / 2).rounded()), hi = Int((period * 2).rounded())
        // Precompute transition penalties per offset.
        var penalty = [Double](repeating: 0, count: hi + 1)
        for d in max(1, lo)...hi { penalty[d] = -tightness * pow(log(Double(d) / period), 2) }
        for t in 0..<n {
            var bestScore = -Double.infinity
            var bestPrev = -1
            let start = max(0, t - hi), end = t - lo
            if end >= start {
                for p in start...end {
                    let s = cum[p] + penalty[t - p]
                    if s > bestScore { bestScore = s; bestPrev = p }
                }
            }
            if bestPrev >= 0, bestScore > 0 {
                cum[t] = onset[t] + bestScore
                back[t] = bestPrev
            } else {
                cum[t] = onset[t]
            }
        }
        // Last beat: the best-scoring local maximum in the final period.
        let tailStart = max(0, n - Int(period * 1.5))
        guard var t = (tailStart..<n).max(by: { cum[$0] < cum[$1] }) else { return [] }
        var beats: [Int] = []
        while t >= 0 {
            beats.append(t)
            t = back[t]
        }
        beats.reverse()
        // Trim beats in silence at either edge (onset far below typical).
        let strengths = beats.map { onset[$0] }
        let typical = strengths.sorted()[strengths.count / 2]
        var first = 0, last = beats.count - 1
        func weak(_ i: Int) -> Bool {
            let w = beats[max(0, i - 2)...min(beats.count - 1, i + 2)].map { onset[$0] }
            return w.reduce(0, +) / Double(w.count) < typical * 0.08
        }
        while first < last, weak(first) { first += 1 }
        while last > first, weak(last) { last -= 1 }
        return Array(beats[first...last])
    }

    static func linearFit(_ ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(ys.count)
        let xs = (0..<ys.count).map(Double.init)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for i in ys.indices {
            sxy += (xs[i] - mx) * (ys[i] - my)
            sxx += (xs[i] - mx) * (xs[i] - mx)
        }
        let slope = sxx > 0 ? sxy / sxx : 0.5
        return (slope, my - slope * mx)
    }

    /// Iteratively reweighted (Huber, 20 ms) line fit — outlier beats from
    /// fills or breaks do not tilt the tempo.
    static func robustLinearFit(_ ys: [Double]) -> (slope: Double, intercept: Double) {
        var fit = linearFit(ys)
        for _ in 0..<6 {
            var sw = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
            for (i, y) in ys.enumerated() {
                let x = Double(i)
                let r = abs(y - (fit.intercept + fit.slope * x))
                let w = r <= 0.02 ? 1.0 : 0.02 / r
                sw += w; sx += w * x; sy += w * y; sxx += w * x * x; sxy += w * x * y
            }
            let d = sw * sxx - sx * sx
            guard abs(d) > 1e-12 else { break }
            let slope = (sw * sxy - sx * sy) / d
            fit = (slope, (sy - slope * sx) / sw)
        }
        return fit
    }

    /// Time-domain transient envelope (first-difference RMS, 2 ms hop).
    static func transientEnvelope(_ x: [Float], sampleRate: Double) -> (values: [Double], hop: Double) {
        let h = max(1, Int(sampleRate * 0.002))
        let count = x.count / h
        var env = [Double](repeating: 0, count: count)
        var prev: Float = 0
        x.withUnsafeBufferPointer { p in
            for i in 0..<count {
                var s: Float = 0
                let base = i * h
                for j in 0..<h {
                    let v = p[base + j]
                    let d = v - prev
                    s += d * d
                    prev = v
                }
                env[i] = Double(s / Float(h)).squareRoot()
            }
        }
        // Half-wave rectified rise → onset-like.
        var onset = [Double](repeating: 0, count: count)
        for i in 1..<max(1, count) { onset[i] = max(0, env[i] - env[i - 1]) }
        return (onset, Double(h) / sampleRate)
    }

    /// Shift (seconds, ±60 ms) maximizing transient energy on the grid.
    static func refinePhase(transient: [Double], hop: Double, t0: Double, period: Double, count: Int) -> Double {
        var bestShift = 0.0, bestScore = -1.0
        var shift = -0.06
        while shift <= 0.06 + 1e-9 {
            var s = 0.0
            for k in 0..<count {
                let idx = Int(((t0 + shift + period * Double(k)) / hop).rounded())
                guard idx >= 1, idx + 1 < transient.count else { continue }
                s += max(transient[idx - 1], transient[idx], transient[idx + 1])
            }
            if s > bestScore { bestScore = s; bestShift = shift }
            shift += 0.002
        }
        return bestShift
    }

    /// Mean onset at beats vs. at off-beat midpoints → 0…1.
    static func beatStrengthConfidence(onset: [Double], beats: [Double], frameRate: Double, frameOffset: Double) -> Double {
        func at(_ t: Double) -> Double {
            let i = Int(((t - frameOffset) * frameRate).rounded())
            guard i >= 1, i + 1 < onset.count else { return 0 }
            return max(onset[i - 1], onset[i], onset[i + 1])
        }
        var on = 0.0, off = 0.0
        for i in 0..<(beats.count - 1) {
            on += at(beats[i])
            off += at((beats[i] + beats[i + 1]) / 2)
        }
        guard on > 0 else { return 0 }
        let ratio = on / max(off, 1e-9)
        return min(1, max(0, (ratio - 1.0) / 1.5))
    }

    // MARK: 5. Chroma + downbeats

    static func chromagram(_ x: [Float], sampleRate sr: Double, minHz: Double = 100, maxHz: Double = 2200) -> [[Double]] {
        let n = chromaFFTSize
        let frames = max(0, (x.count - n) / chromaHop + 1)
        let fft = FFT(size: n)
        let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n))) }
        let binHz = sr / Double(n)
        let pcOfBin: [Int] = (0...(n / 2)).map { b in
            let f = Double(b) * binHz
            guard f >= minHz, f <= maxHz else { return -1 }
            let midi = 69 + 12 * log2(f / 440)
            return ((Int(midi.rounded()) % 12) + 12) % 12
        }
        var out = [[Double]](repeating: [Double](repeating: 0, count: 12), count: frames)
        var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
        for f in 0..<frames {
            let base = f * chromaHop
            for i in 0..<n { re[i] = x[base + i] * window[i]; im[i] = 0 }
            fft.forward(&re, &im)
            var c = [Double](repeating: 0, count: 12)
            for b in 1...(n / 2) where pcOfBin[b] >= 0 {
                c[pcOfBin[b]] += Double(re[b] * re[b] + im[b] * im[b]).squareRoot()
            }
            out[f] = c
        }
        return out
    }

    static func meanChroma(_ chroma: [[Double]], from t0: Double, to t1: Double, rate: Double, offset: Double) -> [Double] {
        var c = [Double](repeating: 0, count: 12)
        let a = max(0, Int(((t0 - offset) * rate).rounded(.down)))
        let b = min(chroma.count, max(a + 1, Int(((t1 - offset) * rate).rounded(.up))))
        guard a < b else { return c }
        for i in a..<b { for k in 0..<12 { c[k] += chroma[i][k] } }
        let norm = sqrt(c.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? c.map { $0 / norm } : c
    }

    /// Strongest transient within ±`window` of `t` (parabolic sub-hop peak).
    static func refineBeat(_ t: Double, transient: [Double], hop: Double, window: Double = 0.035) -> Double {
        let c = Int((t / hop).rounded())
        let w = Int(window / hop)
        let lo = max(1, c - w), hi = min(transient.count - 2, c + w)
        guard hi > lo else { return t }
        var best = lo
        for i in lo...hi where transient[i] > transient[best] { best = i }
        guard transient[best] > 0 else { return t }
        let a = transient[best - 1], b = transient[best], d = transient[best + 1]
        let denom = a - 2 * b + d
        let offset = abs(denom) > 1e-12 ? 0.5 * (a - d) / denom : 0
        return (Double(best) + max(-0.5, min(0.5, offset))) * hop
    }

    /// Splits tracked beats into locally-linear runs: a run breaks only
    /// where ≥ 4 consecutive beats leave a ≥ 16-beat fit by > 45 ms (a
    /// real discontinuity or drift), then neighbouring runs that one line
    /// explains (RMS residual < 20 ms) are merged back.
    static func gridRuns(_ beats: [Double]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start = 0
        var i = 0
        while i < beats.count {
            if i - start >= 16 {
                let fit = linearFit(Array(beats[start..<i]))
                func dev(_ k: Int) -> Double { abs(beats[k] - (fit.intercept + fit.slope * Double(k - start))) }
                if dev(i) > 0.045, (i..<min(beats.count, i + 4)).allSatisfy({ dev($0) > 0.045 }) {
                    runs.append(start..<i)
                    start = i
                }
            }
            i += 1
        }
        runs.append(start..<beats.count)
        func rms(_ r: Range<Int>) -> Double {
            let slice = Array(beats[r])
            guard slice.count >= 3 else { return 0 }
            let fit = linearFit(slice)
            let ss = slice.enumerated().reduce(0.0) { $0 + pow($1.element - (fit.intercept + fit.slope * Double($1.offset)), 2) }
            return (ss / Double(slice.count)).squareRoot()
        }
        var merged: [Range<Int>] = []
        for r in runs {
            if let last = merged.last, rms(last.lowerBound..<r.upperBound) < 0.02 {
                merged[merged.count - 1] = last.lowerBound..<r.upperBound
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    /// Per-beat downbeat evidence → Viterbi over bar positions 0…3.
    /// Position advances by one each beat; a phase reset is only cheap at
    /// a grid-run start (a real discontinuity), never mid-run.
    static func downbeatPositions(
        beats: [Double], runStarts: Set<Int>,
        kick: [Double], snare: [Double], frameRate: Double, frameOffset: Double,
        chroma: [[Double]], bassChroma: [[Double]], chromaRate: Double, chromaOffset: Double
    ) -> (indices: [Int], confidence: Double) {
        let n = beats.count
        guard n >= 12 else { return (Array(stride(from: 0, to: n, by: 4)), 0) }
        func peak(_ curve: [Double], _ t: Double) -> Double {
            let i = Int(((t - frameOffset) * frameRate).rounded())
            guard i >= 1, i + 1 < curve.count else { return 0 }
            return max(curve[i - 1], curve[i], curve[i + 1])
        }
        var harm = [Double](repeating: 0, count: n)
        var bassChange = [Double](repeating: 0, count: n)
        var kickVsSnare = [Double](repeating: 0, count: n)
        func change(_ c: [[Double]], _ a: Double, _ b: Double, _ e: Double) -> Double {
            let before = meanChroma(c, from: a, to: b, rate: chromaRate, offset: chromaOffset)
            let after = meanChroma(c, from: b, to: e, rate: chromaRate, offset: chromaOffset)
            var dot = 0.0
            for k in 0..<12 { dot += before[k] * after[k] }
            return 1 - dot
        }
        for i in 0..<n {
            if i >= 2, i + 2 < n {
                harm[i] = change(chroma, beats[i - 2], beats[i], beats[i + 2])
                // Bass notes usually move on beat 1 — the steadiest bar-line
                // cue when melodies move every beat.
                bassChange[i] = change(bassChroma, beats[i - 1], beats[i], beats[i + 1])
            }
            kickVsSnare[i] = peak(kick, beats[i]) - peak(snare, beats[i])
        }
        func z(_ v: [Double]) -> [Double] {
            let m = v.reduce(0, +) / Double(v.count)
            let sd = max(1e-9, sqrt(v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)))
            return v.map { ($0 - m) / sd }
        }
        let zk = z(kickVsSnare)
        let zhRaw = z(harm), zb = z(bassChange)
        let zh = (0..<n).map { 0.5 * zhRaw[$0] + 0.7 * zb[$0] }
        // Emission: log-score of "this beat is bar position p".
        // Beat 1: harmonic change + kick; beat 3: kick; beats 2/4: no kick
        // (backbeat). Kick alternation is the most reliable cue across
        // genres; harmonic change separates beat 1 from beat 3.
        let zkick = z((0..<n).map { peak(kick, beats[$0]) })
        func emission(_ i: Int, _ p: Int) -> Double {
            switch p {
            case 0: return 0.6 * zh[i] + 0.7 * zkick[i] + 0.2 * zk[i]
            case 2: return -0.3 * zh[i] + 0.5 * zkick[i]
            default: return -0.15 * zh[i] - 0.6 * zkick[i] - 0.2 * zk[i]
            }
        }
        let resetCost = 6.0
        var score = (0..<4).map { emission(0, $0) }
        var back = [[Int]](repeating: [0, 1, 2, 3], count: n)
        for i in 1..<n {
            var next = [Double](repeating: -.infinity, count: 4)
            let reset = runStarts.contains(i) ? 2.0 : resetCost
            for p in 0..<4 {
                for q in 0..<4 {
                    let cost = (q + 1) % 4 == p ? 0 : reset
                    let v = score[q] - cost
                    if v > next[p] { next[p] = v; back[i][p] = q }
                }
                next[p] += emission(i, p)
            }
            score = next
        }
        var p = (0..<4).max { score[$0] < score[$1] }!
        var positions = [Int](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            positions[i] = p
            p = back[i][p]
        }
        let indices = (0..<n).filter { positions[$0] == 0 }
        // Confidence: how much beat-1 evidence beats the best alternative
        // phase on average per bar.
        var chosen = 0.0, alt = 0.0
        for i in indices { chosen += emission(i, 0) }
        for shift in 1..<4 {
            var s = 0.0
            for i in indices where i + shift < n { s += emission(i + shift, 0) }
            alt = max(alt, s)
        }
        let bars = Double(max(indices.count, 1))
        let margin = (chosen - alt) / bars
        return (indices, min(1, max(0, margin / 0.8)))
    }

    // MARK: 6. Bar features

    static func barFeatures(
        downbeats: [Double], duration: Double,
        stft: SpectralFeatures, onset: [Double], frameRate: Double, frameOffset: Double,
        chroma: [[Double]], chromaRate: Double, chromaOffset: Double
    ) -> [BarFeatures] {
        let barLen = downbeats.count > 1 ? (downbeats[downbeats.count - 1] - downbeats[0]) / Double(downbeats.count - 1) : 2
        var raw: [(start: Double, end: Double, power: Double, bassShare: Double, vocalShare: Double,
                   onset: Double, bands: [Double], chroma: [Double])] = []
        for (i, s) in downbeats.enumerated() {
            let e = i + 1 < downbeats.count ? downbeats[i + 1] : min(duration, s + barLen)
            guard e - s > barLen * 0.5 else { continue }
            let a = max(0, Int(((s - frameOffset) * frameRate).rounded()))
            let b = min(stft.totalPower.count, Int(((e - frameOffset) * frameRate).rounded()))
            guard b > a else { continue }
            var p = 0.0, v = 0.0, o = 0.0
            var bands = [Double](repeating: 0, count: 5)
            for f in a..<b {
                p += stft.totalPower[f]
                v += stft.vocalPower[f]
                o += onset[f]
                for k in 0..<5 { bands[k] += stft.bandPower[f][k] }
            }
            let count = Double(b - a)
            raw.append((s, e, p / count, bands[0] / max(p, 1e-12), v / max(p, 1e-12), o / count,
                        bands.map { 10 * log10($0 / count + 1e-12) },
                        meanChroma(chroma, from: s, to: e, rate: chromaRate, offset: chromaOffset)))
        }
        guard !raw.isEmpty else { return [] }
        // Power is in FFT units; convert to relative dBFS-like scale via the
        // loudest bar (absolute level only matters relatively here).
        let db = raw.map { 10 * log10($0.power + 1e-12) }
        func norm(_ v: [Double]) -> [Double] {
            let s = v.sorted()
            let lo = s[Int(Double(s.count - 1) * 0.05)], hi = s[Int(Double(s.count - 1) * 0.95)]
            return v.map { hi - lo > 1e-9 ? min(1, max(0, ($0 - lo) / (hi - lo))) : 0.5 }
        }
        let energy = norm(db)
        // Vocal proxy: mid-band share weighted by loudness — a bar that is
        // quiet cannot carry a lead vocal.
        let vocal = norm(zip(raw.map(\.vocalShare), energy).map { $0 * (0.4 + 0.6 * $1) })
        let bass = norm(zip(raw.map(\.bassShare), energy).map { $0 * (0.3 + 0.7 * $1) })
        let onsetN = norm(raw.map(\.onset))
        let maxDB = db.max() ?? 0
        return raw.indices.map { i in
            BarFeatures(
                start: raw[i].start, end: raw[i].end,
                rmsDB: db[i] - maxDB,
                energy: energy[i], bass: bass[i], vocal: vocal[i], onset: onsetN[i],
                chroma: raw[i].chroma, bands: raw[i].bands
            )
        }
    }

    // MARK: 7. Self-similarity, novelty, phrase grid

    static func selfSimilarity(_ bars: [BarFeatures]) -> [[Double]] {
        let n = bars.count
        // z-score timbre (bands + onset + energy) across the song.
        var timbre = bars.map { $0.bands + [$0.onset * 10, $0.energy * 10] }
        let dims = timbre.first?.count ?? 0
        for d in 0..<dims {
            let col = timbre.map { $0[d] }
            let m = col.reduce(0, +) / Double(n)
            let sd = max(1e-9, sqrt(col.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n)))
            for i in 0..<n { timbre[i][d] = (timbre[i][d] - m) / sd }
        }
        var s = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var dists: [Double] = []
        for i in 0..<n { for j in (i + 1)..<n where j < n {
            var d = 0.0
            for k in 0..<dims { d += (timbre[i][k] - timbre[j][k]) * (timbre[i][k] - timbre[j][k]) }
            dists.append(d)
        } }
        let sigma2 = max(1e-6, dists.isEmpty ? 1 : dists.sorted()[dists.count / 2])
        for i in 0..<n {
            s[i][i] = 1
            for j in (i + 1)..<max(i + 1, n) {
                var c = 0.0
                for k in 0..<12 { c += bars[i].chroma[k] * bars[j].chroma[k] }
                var d = 0.0
                for k in 0..<dims { d += (timbre[i][k] - timbre[j][k]) * (timbre[i][k] - timbre[j][k]) }
                let t = exp(-d / sigma2)
                let v = 0.6 * c + 0.4 * t
                s[i][j] = v
                s[j][i] = v
            }
        }
        return s
    }

    /// Novelty at each bar boundary i (between bar i−1 and bar i),
    /// 0…1: checkerboard kernel (4 bars each side) + energy step.
    static func combinedNovelty(ssm: [[Double]], bars: [BarFeatures]) -> [Double] {
        let n = bars.count
        let w = 4
        var nov = [Double](repeating: 0, count: n + 1)
        var en = [Double](repeating: 0, count: n + 1)
        for i in 1..<n {
            var same = 0.0, cross = 0.0, cs = 0.0, cc = 0.0
            for a in -w..<w { for b in -w..<w {
                let p = i + a, q = i + b
                guard p >= 0, q >= 0, p < n, q < n, p != q else { continue }
                let g = exp(-Double(a * a + b * b) / Double(2 * w * w))
                if (a < 0) == (b < 0) { same += ssm[p][q] * g; cs += g } else { cross += ssm[p][q] * g; cc += g }
            } }
            if cs > 0, cc > 0 { nov[i] = max(0, same / cs - cross / cc) }
            let before = bars[max(0, i - 4)..<i].map(\.energy)
            let after = bars[i..<min(n, i + 4)].map(\.energy)
            en[i] = abs(after.reduce(0, +) / Double(after.count) - before.reduce(0, +) / Double(before.count))
        }
        let nm = max(nov.max() ?? 1, 1e-9), em = max(en.max() ?? 1, 1e-9)
        return (0...n).map { min(1, 0.6 * nov[$0] / nm + 0.4 * en[$0] / em) }
    }

    /// Phrase offset o ∈ 0…3: phrases start at bars ≡ o (mod 4).
    static func bestPhraseOffset(_ novelty: [Double]) -> Int {
        var best = 0, bestScore = -1.0
        for o in 0..<4 {
            var s = 0.0
            var i = o
            while i < novelty.count {
                // 8-bar lines weigh more than 4-bar lines.
                s += novelty[i] * ((i - o) % 8 == 0 ? 1.0 : 0.7)
                i += 4
            }
            if s > bestScore { bestScore = s; best = o }
        }
        return best
    }

    static func pickBoundaries(novelty: [Double], offset: Int, barCount n: Int) -> [Int] {
        var grid = Array(stride(from: offset, through: n, by: 4)).filter { $0 > 0 && $0 < n }
        if grid.isEmpty { grid = [n / 2] }
        let values = grid.map { novelty[$0] }
        let mean = values.reduce(0, +) / Double(values.count)
        let sd = sqrt(values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count))
        var chosen = grid.filter { g in
            let v = novelty[g]
            let prev = g - 4 > 0 ? novelty[g - 4] : 0
            let next = g + 4 < n ? novelty[g + 4] : 0
            return v >= mean + 0.25 * sd && v >= prev * 0.9 && v >= next * 0.9
        }
        var bounds = [0] + chosen + [n]
        // A leading pickup shorter than a phrase merges into the first section.
        if offset > 0, offset < 4, bounds.count > 2, bounds[1] > offset { bounds.insert(offset, at: 1) }
        bounds = Array(Set(bounds)).sorted()
        // Split sections longer than 16 bars at their strongest grid line.
        var changed = true
        while changed {
            changed = false
            for k in 0..<(bounds.count - 1) where bounds[k + 1] - bounds[k] > 16 {
                let inner = grid.filter { $0 > bounds[k] + 3 && $0 < bounds[k + 1] - 3 }
                if let split = inner.max(by: { novelty[$0] < novelty[$1] }) {
                    bounds.insert(split, at: k + 1)
                    changed = true
                    break
                }
            }
        }
        // Merge sections shorter than 4 bars (except a leading pickup).
        chosen = bounds
        var merged: [Int] = [chosen[0]]
        for b in chosen.dropFirst() {
            if b - merged.last! < 4, b != n, merged.count > 1 { continue }
            merged.append(b)
        }
        if merged.last != n { merged.append(n) }
        if merged.count > 2, n - merged[merged.count - 2] < 4 { merged.remove(at: merged.count - 2) }
        return merged
    }

    static func boundaryProminence(novelty: [Double], boundaries: [Int]) -> Double {
        let inner = boundaries.dropFirst().dropLast()
        guard !inner.isEmpty else { return 0 }
        let chosen = inner.map { novelty[$0] }.reduce(0, +) / Double(inner.count)
        let all = novelty.reduce(0, +) / Double(max(novelty.count, 1))
        return min(1, max(0, (chosen - all) / max(all, 1e-9) / 1.5))
    }

    // MARK: 8. Section labeling

    static func labelSections(boundaries: [Int], bars: [BarFeatures], ssm: [[Double]]) -> [MeasuredSection] {
        struct Seg { var a: Int; var b: Int; var energy: Double; var vocal: Double; var bass: Double; var group = -1 }
        var segs: [Seg] = []
        for k in 0..<(boundaries.count - 1) {
            let a = boundaries[k], b = boundaries[k + 1]
            guard b > a else { continue }
            let slice = bars[a..<b]
            let count = Double(slice.count)
            segs.append(Seg(a: a, b: b,
                            energy: slice.map(\.energy).reduce(0, +) / count,
                            vocal: slice.map(\.vocal).reduce(0, +) / count,
                            bass: slice.map(\.bass).reduce(0, +) / count))
        }
        guard !segs.isEmpty else { return [] }
        let n = bars.count

        // Repetition threshold from the song's own similarity distribution.
        var off: [Double] = []
        for i in 0..<n { for j in (i + 4)..<max(i + 4, n) where j < n { off.append(ssm[i][j]) } }
        off.sort()
        let p80 = off.isEmpty ? 0.8 : off[Int(Double(off.count - 1) * 0.80)]
        let p99 = off.isEmpty ? 0.95 : off[Int(Double(off.count - 1) * 0.99)]
        let threshold = p80 + 0.3 * (p99 - p80)

        func similarity(_ x: Seg, _ y: Seg) -> Double {
            let len = min(x.b - x.a, y.b - y.a)
            guard len >= 2 else { return 0 }
            var best = 0.0
            for sx in [0, (x.b - x.a) - len] { for sy in [0, (y.b - y.a) - len] {
                var s = 0.0
                for k in 0..<len { s += ssm[x.a + sx + k][y.a + sy + k] }
                best = max(best, s / Double(len))
            } }
            return best
        }
        // Union-find grouping.
        var parent = Array(segs.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { i = parent[i] }; return i }
        for i in segs.indices { for j in (i + 1)..<segs.count where j < segs.count {
            if similarity(segs[i], segs[j]) >= threshold { parent[find(j)] = find(i) }
        } }
        var groupIDs: [Int: Int] = [:]
        for i in segs.indices {
            let r = find(i)
            let members = segs.indices.filter { find($0) == r }
            if members.count >= 2 {
                if groupIDs[r] == nil { groupIDs[r] = groupIDs.count }
                segs[i].group = groupIDs[r]!
            }
        }

        let energies = segs.map(\.energy).sorted()
        let medianE = energies[energies.count / 2]
        var labels = [MeasuredSection.Label](repeating: .verse, count: segs.count)
        var conf = [Double](repeating: 0.5, count: segs.count)

        // Chorus: the repeated group with the highest energy (+ vocal / count).
        var chorusGroup: Int?
        var bestScore = -1.0
        for g in Set(segs.map(\.group)) where g >= 0 {
            let members = segs.filter { $0.group == g }
            let e = members.map(\.energy).reduce(0, +) / Double(members.count)
            let v = members.map(\.vocal).reduce(0, +) / Double(members.count)
            guard e >= medianE - 0.02 else { continue }
            let score = e + 0.1 * v + 0.08 * Double(min(members.count, 4))
            if score > bestScore { bestScore = score; chorusGroup = g }
        }
        let topE = energies.last ?? 1
        for i in segs.indices {
            if let g = chorusGroup, segs[i].group == g, segs[i].energy >= medianE - 0.05 {
                labels[i] = .chorus; conf[i] = 0.8
            } else if segs[i].energy >= max(0.72, topE - 0.08), segs[i].b - segs[i].a >= 4 {
                // Unrepeated peak material (EDM drops that vary) still pays off.
                labels[i] = .chorus; conf[i] = chorusGroup == nil ? 0.55 : 0.45
            }
        }
        let chorusIdx = segs.indices.filter { labels[$0] == .chorus }
        let firstChorus = chorusIdx.first ?? segs.count
        let lastChorus = chorusIdx.last ?? -1

        // Intro: leading low-energy material before the first payoff.
        var i = 0
        while i < min(firstChorus, 2), segs[i].energy < max(medianE, 0.45), segs[i].a < 17 {
            labels[i] = .intro; conf[i] = 0.7; i += 1
        }
        if labels[0] == .verse, segs[0].b - segs[0].a <= 8, segs[0].vocal < 0.35 {
            labels[0] = .intro; conf[0] = 0.55
        }
        // Outro: trailing lower-energy material after the last payoff.
        var j = segs.count - 1
        while j > lastChorus, j > 0, labels[j] == .verse, segs[j].energy < max(medianE, 0.5) || j == segs.count - 1 {
            labels[j] = .outro; conf[j] = 0.65
            j -= 1
            if segs.count - 1 - j >= 2 { break }
        }
        // Builds: short non-payoff sections right before a payoff whose
        // energy is below it.
        for c in chorusIdx where c > 0 {
            let p = c - 1
            if labels[p] == .verse, segs[p].b - segs[p].a <= 8, segs[p].energy < segs[c].energy - 0.05 {
                labels[p] = .build; conf[p] = 0.6
            }
        }
        // Bridge / breakdown: low-energy, unrepeated material after the
        // first payoff and before the ending.
        for k in segs.indices where labels[k] == .verse && k > firstChorus && k < lastChorus {
            if segs[k].energy < medianE - 0.1 || (segs[k].group < 0 && segs[k].energy < medianE) {
                labels[k] = segs[k].vocal < 0.35 ? .breakdown : .bridge
                conf[k] = 0.55
            }
        }

        // Merge contiguous chorus segments into one payoff section.
        var out: [MeasuredSection] = []
        for k in segs.indices {
            let s = segs[k]
            let section = MeasuredSection(
                label: labels[k], startBar: s.a, endBar: s.b,
                start: bars[s.a].start, end: bars[s.b - 1].end,
                group: s.group, energy: s.energy, vocal: s.vocal, bass: s.bass, confidence: conf[k]
            )
            if var last = out.last, last.label == .chorus, section.label == .chorus, last.barCount < 16 {
                let total = Double(last.barCount + section.barCount)
                last.energy = (last.energy * Double(last.barCount) + section.energy * Double(section.barCount)) / total
                last.vocal = (last.vocal * Double(last.barCount) + section.vocal * Double(section.barCount)) / total
                last.bass = (last.bass * Double(last.barCount) + section.bass * Double(section.barCount)) / total
                last.endBar = section.endBar
                last.end = section.end
                last.group = last.group >= 0 ? last.group : section.group
                out[out.count - 1] = last
            } else {
                out.append(section)
            }
        }
        return out
    }

    // MARK: Key (Krumhansl–Schmuckler over the whole-song chroma)

    static func estimateKey(_ chroma: [[Double]]) -> (name: String, confidence: Double)? {
        var total = [Double](repeating: 0, count: 12)
        for frame in chroma { for k in 0..<12 { total[k] += frame[k] } }
        guard total.reduce(0, +) > 0 else { return nil }
        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        func pearson(_ a: [Double], _ b: [Double]) -> Double {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            var num = 0.0, da = 0.0, db = 0.0
            for i in 0..<12 { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb) }
            return da > 0 && db > 0 ? num / sqrt(da * db) : 0
        }
        var scored: [(String, Double)] = []
        for root in 0..<12 {
            let rot = { (p: [Double]) in (0..<12).map { p[($0 - root + 12) % 12] } }
            scored.append((names[root], pearson(rot(major), total)))
            scored.append((names[root] + "m", pearson(rot(minor), total)))
        }
        scored.sort { $0.1 > $1.1 }
        return (scored[0].0, min(1, max(0, (scored[0].1 - scored[1].1) * 4)))
    }
}

// MARK: - Minimal radix-2 FFT (pure Swift, no Accelerate — portable)

nonisolated struct FFT {
    let size: Int
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let bitReverse: [Int]

    init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        cosTable = (0..<(size / 2)).map { Float(cos(-2 * Double.pi * Double($0) / Double(size))) }
        sinTable = (0..<(size / 2)).map { Float(sin(-2 * Double.pi * Double($0) / Double(size))) }
        let bits = Int(log2(Double(size)))
        bitReverse = (0..<size).map { i in
            var r = 0, x = i
            for _ in 0..<bits { r = (r << 1) | (x & 1); x >>= 1 }
            return r
        }
    }

    /// In-place forward transform.
    func forward(_ re: inout [Float], _ im: inout [Float]) {
        let n = size
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { m in
                for i in 0..<n {
                    let j = bitReverse[i]
                    if j > i { r.swapAt(i, j); m.swapAt(i, j) }
                }
                cosTable.withUnsafeBufferPointer { ct in
                    sinTable.withUnsafeBufferPointer { st in
                        var len = 2
                        while len <= n {
                            let half = len / 2
                            let step = n / len
                            var start = 0
                            while start < n {
                                var k = 0
                                for j in start..<(start + half) {
                                    let wr = ct[k], wi = st[k]
                                    let xr = r[j + half], xi = m[j + half]
                                    let tr = xr * wr - xi * wi
                                    let ti = xr * wi + xi * wr
                                    r[j + half] = r[j] - tr
                                    m[j + half] = m[j] - ti
                                    r[j] += tr
                                    m[j] += ti
                                    k += step
                                }
                                start += len
                            }
                            len <<= 1
                        }
                    }
                }
            }
        }
    }
}
