import Foundation

/// Master bus for Auto Remix renders: BS.1770-4 integrated loudness,
/// a true-peak-aware lookahead brickwall limiter, and a SIGNED makeup
/// solver that moves the mix toward the club target without turning
/// the limiter into glue.
///
/// Why: raw mixes peak ~10 dB over the ceiling at stacked drops. The
/// old finalize scaled the whole program down to fit (−22 LUFS, a DJ
/// gain-rides it +10 dB), and a plain brickwall at 0 dB makeup crushed
/// the drops with 4–9 dB of sustained reduction. The solver finds the
/// gain — up OR down — whose SUSTAINED reduction over the loudest 10 %
/// of blocks stays under `AutoGainPolicy.maxSustainedLimiterReductionDB`:
/// rare impacts are caught, drops keep their dynamics, and loudness
/// lands as high as the material's own crest factor allows.
enum AutoMasterBus {

    struct Result {
        var channels: [[Float]]
        var companions: [[Float]]
        var measuredLUFS: Double
        var makeupDB: Double
        var sustainedReductionDB: Double
        var reductionP90DB: Double
        var limitedFraction: Double
        var peakReductionDB: Double
        var outputLUFS: Double
    }

    // MARK: - Loudness (ITU-R BS.1770-4, pyloudnorm-matched filters)

    static func integratedLUFS(channels: [[Float]], sampleRate: Double) -> Double {
        guard let n = channels.first?.count, n > 0, sampleRate > 0 else { return -120 }
        let blockLen = max(1, Int(0.4 * sampleRate))
        let hop = max(1, Int(0.1 * sampleRate))
        guard n >= blockLen else { return -120 }
        var blockMS = [Double](repeating: 0, count: (n - blockLen) / hop + 1)
        for ch in channels {
            let w = kWeighted(ch, sampleRate: sampleRate)
            var prefix = [Double](repeating: 0, count: n + 1)
            var acc = 0.0
            for i in 0..<n { acc += w[i] * w[i]; prefix[i + 1] = acc }
            for b in 0..<blockMS.count {
                let s = b * hop
                blockMS[b] += (prefix[s + blockLen] - prefix[s]) / Double(blockLen)
            }
        }
        func loudness(_ ms: Double) -> Double { -0.691 + 10 * log10(max(ms, 1e-20)) }
        let absGated = blockMS.filter { loudness($0) > -70 }
        guard !absGated.isEmpty else { return -120 }
        let relThreshold = loudness(absGated.reduce(0, +) / Double(absGated.count)) - 10
        let gated = absGated.filter { loudness($0) > relThreshold }
        guard !gated.isEmpty else { return -120 }
        return loudness(gated.reduce(0, +) / Double(gated.count))
    }

    /// Stage 1 high shelf (1500 Hz, +4 dB, Q 1/√2) + stage 2 high pass
    /// (38 Hz, Q 0.5) — the same RBJ-form parameters pyloudnorm uses, so
    /// the engine and the Python scoreboard read the same number
    /// (0 dBFS 1 kHz sine → −3.05 LKFS on both).
    private static func kWeighted(_ x: [Float], sampleRate fs: Double) -> [Double] {
        var y = x.map(Double.init)
        do {
            let f0 = 1500.0, g = 4.0, q = 1.0 / 2.0.squareRoot()
            let a = pow(10, g / 40), w0 = 2 * Double.pi * f0 / fs
            let alpha = sin(w0) / (2 * q), cw = cos(w0), sa = 2 * a.squareRoot() * alpha
            let b0 = a * ((a + 1) + (a - 1) * cw + sa)
            let b1 = -2 * a * ((a - 1) + (a + 1) * cw)
            let b2 = a * ((a + 1) + (a - 1) * cw - sa)
            let a0 = (a + 1) - (a - 1) * cw + sa
            let a1 = 2 * ((a - 1) - (a + 1) * cw)
            let a2 = (a + 1) - (a - 1) * cw - sa
            y = biquad(y, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        }
        do {
            let f0 = 38.0, q = 0.5
            let w0 = 2 * Double.pi * f0 / fs
            let alpha = sin(w0) / (2 * q), cw = cos(w0)
            let b0 = (1 + cw) / 2, b1 = -(1 + cw), b2 = (1 + cw) / 2
            let a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha
            y = biquad(y, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        }
        return y
    }

    private static func biquad(_ x: [Double], _ b0: Double, _ b1: Double, _ b2: Double,
                               _ a1: Double, _ a2: Double) -> [Double] {
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }

    // MARK: - True-peak track

    /// Per-sample peak including the three inter-sample phases estimated
    /// with the same 16-tap Hann-windowed sinc `AutoRemixDiagnostics.
    /// truePeakDB` measures with — so a ceiling held on this track is a
    /// ceiling the gate will confirm.
    static func truePeakTrack(channels: [[Float]]) -> [Float] {
        guard let n = channels.first?.count, n > 0 else { return [] }
        let taps = 16, half = taps / 2
        let phases: [Float] = [0.25, 0.5, 0.75]
        let kernels: [[Float]] = phases.map { phase in
            (0..<taps).map { k in
                let x = Float(k - half + 1) - phase
                let sinc = x == 0 ? Float(1) : sin(.pi * x) / (.pi * x)
                let w = 0.5 * (1 + cos(.pi * x / Float(half)))
                return sinc * max(0, w)
            }
        }
        var track = [Float](repeating: 0, count: n)
        for ch in channels {
            ch.withUnsafeBufferPointer { s in
                for i in 0..<n {
                    var p = abs(s[i])
                    if i >= half, i + half < n {
                        for kernel in kernels {
                            var acc: Float = 0
                            for k in 0..<taps { acc += kernel[k] * s[i + k - half + 1] }
                            p = max(p, abs(acc))
                        }
                    }
                    if p > track[i] { track[i] = p }
                }
            }
        }
        return track
    }

    // MARK: - Lookahead brickwall limiter

    /// Gain envelope (≤ 1) keeping `peakTrack × gain` under the ceiling.
    /// Sliding-window minimum of the required gain over the lookahead,
    /// then a moving average over the same window (every averaged term
    /// already contains the sample's own requirement, so the ramp never
    /// overshoots), then a one-pole release toward unity.
    static func limiterEnvelope(
        peakTrack: [Float],
        gainLinear: Float,
        ceilingLinear: Float,
        sampleRate: Double,
        lookaheadSeconds: Double = AutoGainPolicy.masterLimiterLookaheadSeconds,
        releaseSeconds: Double = AutoGainPolicy.masterLimiterReleaseSeconds
    ) -> [Float] {
        let n = peakTrack.count
        guard n > 0 else { return [] }
        let la = max(1, Int(lookaheadSeconds * sampleRate))
        var required = [Float](repeating: 1, count: n)
        for i in 0..<n {
            let p = peakTrack[i] * gainLinear
            if p > ceilingLinear { required[i] = ceilingLinear / p }
        }
        var windowMin = [Float](repeating: 1, count: n)
        var deque = [Int](); deque.reserveCapacity(la + 1)
        var head = 0
        for j in 0..<(n + la) {
            if j < n {
                while deque.count > head, required[deque[deque.count - 1]] >= required[j] {
                    deque.removeLast()
                }
                deque.append(j)
            }
            let i = j - la + 1
            if i >= 0, i < n {
                while head < deque.count, deque[head] < i { head += 1 }
                if head < deque.count { windowMin[i] = required[deque[head]] }
            }
            if head > 4096 { deque.removeFirst(head); head = 0 }
        }
        var env = [Float](repeating: 1, count: n)
        var sum: Float = 0
        for i in 0..<n {
            sum += windowMin[i]
            if i >= la { sum -= windowMin[i - la] }
            env[i] = sum / Float(min(i + 1, la))
        }
        let rel = Float(1 - exp(-1 / (releaseSeconds * sampleRate)))
        var g: Float = 1
        for i in 0..<n {
            if env[i] < g { g = env[i] } else { g += (1 - g) * rel; g = min(g, env[i]) }
            env[i] = g
        }
        return env
    }

    /// Reduction statistics over 100 ms blocks of the loudest 10 % of the
    /// program (by pre-limiter block RMS — the drops, not the handful of
    /// SFX impact blocks a max-referenced window would pick).
    /// `sustainedDB` = median of per-block MEAN reduction: how much the
    /// block's level actually dropped — the glue the policy caps.
    /// `p90DB` = p90 of per-block MAX reduction: the transient shave on
    /// kick hits, reported, not capped (that is what a mastering limiter
    /// is for).
    struct ReductionStats { var sustainedDB: Double; var p90DB: Double; var limitedFraction: Double }

    static func reductionStats(envelope: [Float], peakTrack: [Float],
                               gainLinear: Float, sampleRate: Double) -> ReductionStats {
        let n = envelope.count
        let hop = max(1, Int(0.1 * sampleRate))
        guard n >= hop else { return ReductionStats(sustainedDB: 0, p90DB: 0, limitedFraction: 0) }
        var level: [Float] = [], maxGR: [Double] = [], meanGR: [Double] = []
        var s = 0
        while s + hop <= n {
            var acc: Float = 0, minG: Float = 1, sumDB = 0.0
            for i in s..<(s + hop) {
                let v = peakTrack[i] * gainLinear
                acc += v * v
                minG = min(minG, envelope[i])
                sumDB += -20 * log10(Double(max(envelope[i], 1e-6)))
            }
            level.append((acc / Float(hop)).squareRoot())
            maxGR.append(-20 * log10(Double(max(minG, 1e-6))))
            meanGR.append(sumDB / Double(hop))
            s += hop
        }
        let limited = Double(maxGR.filter { $0 > 1 }.count) / Double(maxGR.count)
        let order = level.indices.sorted { level[$0] > level[$1] }
        let top = Array(order.prefix(max(1, order.count / 10)))
        let topMean = top.map { meanGR[$0] }.sorted()
        let topMax = top.map { maxGR[$0] }.sorted()
        return ReductionStats(
            sustainedDB: topMean[topMean.count / 2],
            p90DB: topMax[min(topMax.count - 1, Int(Double(topMax.count) * 0.9))],
            limitedFraction: limited
        )
    }

    // MARK: - Masterize

    static func masterize(
        channels: [[Float]],
        companions: [[Float]] = [],
        sampleRate: Double,
        targetLUFS: Double = AutoGainPolicy.masterTargetLUFS,
        maxMakeupDB: Double = AutoGainPolicy.masterMaxMakeupDB,
        maxCutDB: Double = AutoGainPolicy.masterMaxCutDB,
        ceilingDB: Double = AutoGainPolicy.truePeakCeilingDB - AutoGainPolicy.masterTruePeakMarginDB,
        maxSustainedDB: Double = AutoGainPolicy.maxSustainedLimiterReductionDB
    ) -> Result {
        guard let n = channels.first?.count, n > 0 else {
            return Result(channels: channels, companions: companions, measuredLUFS: -120,
                          makeupDB: 0, sustainedReductionDB: 0, reductionP90DB: 0,
                          limitedFraction: 0, peakReductionDB: 0, outputLUFS: -120)
        }
        let measured = integratedLUFS(channels: channels, sampleRate: sampleRate)
        let peakTrack = truePeakTrack(channels: channels)
        let ceiling = Float(pow(10.0, ceilingDB / 20.0))
        var gainDB = measured > -100 ? min(max(targetLUFS - measured, -maxCutDB), maxMakeupDB) : 0
        var env: [Float] = []
        var stats = ReductionStats(sustainedDB: 0, p90DB: 0, limitedFraction: 0)
        for _ in 0..<8 {
            let lin = Float(pow(10.0, gainDB / 20.0))
            env = limiterEnvelope(peakTrack: peakTrack, gainLinear: lin,
                                  ceilingLinear: ceiling, sampleRate: sampleRate)
            stats = reductionStats(envelope: env, peakTrack: peakTrack,
                                   gainLinear: lin, sampleRate: sampleRate)
            if stats.sustainedDB <= maxSustainedDB || gainDB <= -maxCutDB { break }
            gainDB = max(gainDB - (stats.sustainedDB - maxSustainedDB) - 0.1, -maxCutDB)
        }
        let lin = Float(pow(10.0, gainDB / 20.0))
        var peakGR: Float = 1
        for g in env { peakGR = min(peakGR, g) }
        func apply(_ x: [Float]) -> [Float] {
            var y = x
            let m = min(x.count, env.count)
            for i in 0..<m { y[i] = x[i] * lin * env[i] }
            if x.count > m { for i in m..<x.count { y[i] = x[i] * lin } }
            return y
        }
        let out = channels.map(apply)
        return Result(
            channels: out,
            companions: companions.map(apply),
            measuredLUFS: measured,
            makeupDB: gainDB,
            sustainedReductionDB: stats.sustainedDB,
            reductionP90DB: stats.p90DB,
            limitedFraction: stats.limitedFraction,
            peakReductionDB: -20 * log10(Double(max(peakGR, 1e-6))),
            outputLUFS: integratedLUFS(channels: out, sampleRate: sampleRate)
        )
    }
}
