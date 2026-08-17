import Foundation

// MARK: - Rendered-Audio Diagnostics
//
// Objective measurements over pre-encode PCM: short-term loudness,
// sample/true peak, silence runs, click detection, and per-transition
// before/center/after loudness. Pure Swift over [Float] so the exact same
// meters run in the on-device debug report and in the portable test
// harness. These meters are the quality gates — a transition-related
// change that cannot pass them is not done.
nonisolated enum AutoRemixDiagnostics {

    // MARK: Loudness

    /// Mean RMS level over [start, end) seconds, dBFS (power-averaged).
    static func meanLoudnessDB(
        samples: [Float],
        sampleRate: Double,
        from start: Double,
        to end: Double
    ) -> Double {
        let lo = max(0, Int(start * sampleRate))
        let hi = min(samples.count, Int(end * sampleRate))
        guard hi > lo else { return -120 }
        var sum = 0.0
        for i in lo..<hi {
            let v = Double(samples[i])
            sum += v * v
        }
        let rms = (sum / Double(hi - lo)).squareRoot()
        return 20 * log10(max(rms, 1e-12))
    }

    /// Short-term loudness curve: RMS over `windowSeconds`, advancing by
    /// `hopSeconds`. Returns (windowStartSeconds, dBFS) pairs.
    static func shortTermLoudnessDB(
        samples: [Float],
        sampleRate: Double,
        windowSeconds: Double = 0.4,
        hopSeconds: Double = 0.1
    ) -> [(time: Double, db: Double)] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        let window = max(1, Int(windowSeconds * sampleRate))
        let hop = max(1, Int(hopSeconds * sampleRate))
        var out: [(Double, Double)] = []
        var start = 0
        // Running sum of squares over the hop-aligned window.
        while start < samples.count {
            let end = min(samples.count, start + window)
            var sum = 0.0
            for i in start..<end {
                let v = Double(samples[i])
                sum += v * v
            }
            let rms = (sum / Double(end - start)).squareRoot()
            out.append((Double(start) / sampleRate, 20 * log10(max(rms, 1e-12))))
            start += hop
        }
        return out
    }

    /// Simple integrated loudness estimate: power mean of 400 ms windows
    /// above an absolute −70 dB gate. An RMS approximation (not full
    /// BS.1770 K-weighting) — used for relative targets and regression,
    /// documented as approximate.
    static func integratedLoudnessApproxDB(
        samples: [Float],
        sampleRate: Double
    ) -> Double {
        let curve = shortTermLoudnessDB(samples: samples, sampleRate: sampleRate)
        let gated = curve.filter { $0.db > -70 }
        guard !gated.isEmpty else { return -120 }
        let meanPower = gated.map { pow(10, $0.db / 10) }.reduce(0, +) / Double(gated.count)
        return 10 * log10(max(meanPower, 1e-12))
    }

    // MARK: Peaks

    /// Largest absolute sample value.
    static func samplePeak(_ samples: [Float]) -> Float {
        var peak: Float = 0
        for v in samples { peak = max(peak, abs(v)) }
        return peak
    }

    /// Count of samples at or above full scale.
    static func clippedSampleCount(_ samples: [Float]) -> Int {
        var n = 0
        for v in samples where abs(v) >= 1.0 { n += 1 }
        return n
    }

    /// Estimated true peak from 4× oversampling (windowed-sinc
    /// interpolation at phases 1/4, 1/2, 3/4), dBTP.
    static func truePeakDB(
        samples: [Float],
        sampleRate: Double
    ) -> Double {
        guard !samples.isEmpty else { return -120 }
        // 16-tap Hann-windowed sinc per fractional phase.
        let taps = 16
        let half = taps / 2
        let phases: [Double] = [0.25, 0.5, 0.75]
        let kernels: [[Double]] = phases.map { phase in
            (0..<taps).map { k in
                let x = Double(k - half + 1) - phase
                let sinc = x == 0 ? 1.0 : sin(.pi * x) / (.pi * x)
                let w = 0.5 * (1 + cos(.pi * (Double(k - half + 1) - phase) / Double(half)))
                return sinc * max(0, w)
            }
        }
        var peak = Double(samplePeak(samples))
        let n = samples.count
        for i in 0..<n {
            for kernel in kernels {
                var acc = 0.0
                for k in 0..<taps {
                    let idx = i + k - half + 1
                    guard idx >= 0, idx < n else { continue }
                    acc += Double(samples[idx]) * kernel[k]
                }
                peak = max(peak, abs(acc))
            }
        }
        return 20 * log10(max(peak, 1e-12))
    }

    // MARK: Silence

    /// Contiguous regions whose 20 ms RMS stays below `thresholdDB` for at
    /// least `minSeconds`.
    static func silenceRuns(
        samples: [Float],
        sampleRate: Double,
        thresholdDB: Double = -45,
        minSeconds: Double = 0.1
    ) -> [SignalRegion] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        let window = max(1, Int(0.02 * sampleRate))
        var regions: [SignalRegion] = []
        var runStart: Int?
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + window)
            var sum = 0.0
            for j in i..<end {
                let v = Double(samples[j])
                sum += v * v
            }
            let db = 10 * log10(max(sum / Double(end - i), 1e-24))
            if db < thresholdDB {
                if runStart == nil { runStart = i }
            } else if let s = runStart {
                let dur = Double(i - s) / sampleRate
                if dur >= minSeconds {
                    regions.append(SignalRegion(start: Double(s) / sampleRate, end: Double(i) / sampleRate))
                }
                runStart = nil
            }
            i += window
        }
        if let s = runStart {
            let dur = Double(samples.count - s) / sampleRate
            if dur >= minSeconds {
                regions.append(
                    SignalRegion(start: Double(s) / sampleRate, end: Double(samples.count) / sampleRate)
                )
            }
        }
        return regions
    }

    // MARK: Clicks

    /// Largest absolute sample-to-sample jump and where it happens.
    /// Full-scale program material stays well below ~0.5; an instantaneous
    /// jump near 1.0 is an audible click/discontinuity.
    static func maxAdjacentSampleJump(
        samples: [Float],
        sampleRate: Double
    ) -> (jump: Double, atSeconds: Double) {
        var maxJump = 0.0
        var at = 0.0
        for i in 1..<max(1, samples.count) {
            let jump = Double(abs(samples[i] - samples[i - 1]))
            if jump > maxJump {
                maxJump = jump
                at = Double(i) / sampleRate
            }
        }
        return (maxJump, at)
    }

    // MARK: Transitions

    struct BoundaryLoudness {
        var boundarySeconds: Double
        var beforeDB: Double
        var centerDB: Double
        var afterDB: Double

        /// Center dip below the QUIETER surrounding side, dB (≥ 0).
        nonisolated var centerTroughDB: Double {
            max(0, min(beforeDB, afterDB) - centerDB)
        }
        /// Absolute before→after level change, dB.
        nonisolated var jumpDB: Double { abs(afterDB - beforeDB) }
    }

    /// Mix-window energy immediately before an incoming song attacks.
    struct MixWindowPreIncoming {
        var incomingStart: Double
        var establishedDB: Double
        var preIncomingDB: Double
        var incomingAttackDB: Double

        /// How far RMS dropped in the last half-second before incoming, dB.
        nonisolated var holeDB: Double { max(0, establishedDB - preIncomingDB) }

        /// Dead air / fade-to-silence / both-sides duck before the new song.
        /// Spectral thinning at full clip volume is not this — the mix must
        /// actually collapse relative to the audio that was already playing.
        nonisolated var isEnergyHole: Bool { holeDB >= 8.0 }
    }

    /// RMS in the mix window before `incomingStart` vs the established
    /// level just earlier. A hole here is a failed song-switch join.
    static func mixWindowPreIncoming(
        samples: [Float],
        sampleRate: Double,
        incomingStart t: Double
    ) -> MixWindowPreIncoming {
        MixWindowPreIncoming(
            incomingStart: t,
            establishedDB: meanLoudnessDB(
                samples: samples, sampleRate: sampleRate, from: t - 1.35, to: t - 0.55
            ),
            preIncomingDB: meanLoudnessDB(
                samples: samples, sampleRate: sampleRate, from: t - 0.45, to: t - 0.02
            ),
            incomingAttackDB: meanLoudnessDB(
                samples: samples, sampleRate: sampleRate, from: t + 0.02, to: t + 0.45
            )
        )
    }

    /// Timeline starts where a dominant clip of a *different* song takes over.
    static func songSwitchIncomingStarts(placements: [AutoClipPlacement]) -> [Double] {
        let dominants = placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        var starts: [Double] = []
        for (prev, next) in zip(dominants, dominants.dropFirst()) where prev.songID != next.songID {
            if starts.last.map({ abs($0 - next.timelineStart) < 0.05 }) == true { continue }
            starts.append(next.timelineStart)
        }
        return starts
    }

    /// Short-term loudness immediately before / across / after a
    /// transition boundary.
    static func boundaryLoudness(
        samples: [Float],
        sampleRate: Double,
        boundarySeconds t: Double
    ) -> BoundaryLoudness {
        BoundaryLoudness(
            boundarySeconds: t,
            beforeDB: meanLoudnessDB(samples: samples, sampleRate: sampleRate, from: t - 1.0, to: t - 0.15),
            centerDB: meanLoudnessDB(samples: samples, sampleRate: sampleRate, from: t - 0.15, to: t + 0.15),
            afterDB: meanLoudnessDB(samples: samples, sampleRate: sampleRate, from: t + 0.15, to: t + 1.0)
        )
    }

    // MARK: Quality report (debug-only)

    struct CutReportEntry {
        var timelineAt: Double
        var reason: String
        var masking: String
        var confidence: Double
        var expectedEnergyDeltaDB: Double
    }

    /// Objective per-render report: what was kept, what was cut and why,
    /// how every transition measures, and where the levels landed.
    /// Debug/diagnostic surface only — never shown in the normal UI.
    struct QualityReport {
        var usableSourceRange: ClosedRange<Double>?
        var internalCuts: [CutReportEntry]
        var transitions: [BoundaryLoudness]
        var integratedLoudnessDB: Double
        var samplePeakDB: Double
        var truePeakDB: Double
        var limiterGainReductionDB: Double
        var detectedSilences: [SignalRegion]
        var analysisConfidence: Double
        var repairsAndWarnings: [String]

        nonisolated var text: String {
            var lines: [String] = ["── Auto Remix quality report ──"]
            if let range = usableSourceRange {
                lines.append(String(format: "usable source: %.2fs – %.2fs", range.lowerBound, range.upperBound))
            }
            lines.append("internal cuts: \(internalCuts.count)")
            for cut in internalCuts {
                lines.append(String(
                    format: "  cut @%.2fs  reason=%@ masking=%@ conf=%.2f Δ=%.1f dB",
                    cut.timelineAt, cut.reason, cut.masking, cut.confidence, cut.expectedEnergyDeltaDB
                ))
            }
            for b in transitions {
                lines.append(String(
                    format: "  boundary @%.2fs  before=%.1f center=%.1f after=%.1f dBFS (trough %.1f, jump %.1f)",
                    b.boundarySeconds, b.beforeDB, b.centerDB, b.afterDB, b.centerTroughDB, b.jumpDB
                ))
            }
            lines.append(String(format: "integrated ≈ %.1f dB   sample peak %.2f dBFS   true peak %.2f dBTP",
                                integratedLoudnessDB, samplePeakDB, truePeakDB))
            lines.append(String(format: "limiter reduction %.1f dB", limiterGainReductionDB))
            for s in detectedSilences {
                lines.append(String(format: "  silence %.2f–%.2fs", s.start, s.end))
            }
            lines.append(String(format: "analysis confidence %.2f", analysisConfidence))
            for r in repairsAndWarnings { lines.append("  note: \(r)") }
            return lines.joined(separator: "\n")
        }
    }

    static func maskingDescription(_ masking: AutoCutMasking) -> String {
        switch masking {
        case .equalPowerCrossfade(let seconds):
            String(format: "equal-power crossfade %.2fs", seconds)
        case .sfx(let assetID):
            "sfx:\(assetID)"
        case .effectTail:
            "effect tail"
        case .alignedHardCut:
            "aligned hard cut"
        }
    }

    /// Builds the report for a plan and its rendered PCM.
    static func qualityReport(
        plan: AutoRemixPlan,
        pcm: [Float],
        sampleRate: Double,
        limiterGainReductionDB: Double = 0
    ) -> QualityReport {
        let boundaries = internalCutBoundaries(placements: plan.placements)
        let contentStart = plan.placements.map(\.timelineStart).min() ?? 0
        let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        return QualityReport(
            usableSourceRange: plan.usableSourceRange,
            internalCuts: plan.cutRecords.map {
                CutReportEntry(
                    timelineAt: $0.timelineAt,
                    reason: $0.reason.rawValue,
                    masking: maskingDescription($0.masking),
                    confidence: $0.confidence,
                    expectedEnergyDeltaDB: $0.expectedEnergyDeltaDB
                )
            },
            transitions: boundaries.map {
                boundaryLoudness(samples: pcm, sampleRate: sampleRate, boundarySeconds: $0)
            },
            integratedLoudnessDB: integratedLoudnessApproxDB(samples: pcm, sampleRate: sampleRate),
            samplePeakDB: 20 * log10(max(Double(samplePeak(pcm)), 1e-12)),
            truePeakDB: truePeakDB(samples: pcm, sampleRate: sampleRate),
            limiterGainReductionDB: limiterGainReductionDB,
            detectedSilences: silenceRuns(samples: pcm, sampleRate: sampleRate)
                .filter { $0.start > contentStart + 0.5 && $0.end < contentEnd - 0.5 },
            analysisConfidence: plan.confidence,
            repairsAndWarnings: plan.warnings
        )
    }

    // MARK: Source-order checks (plan-level)

    /// Timeline boundaries between consecutive DOMINANT placements of the
    /// same song where the source jumps (discontinuity = internal cut).
    /// `toleranceSeconds` forgives sample-rounding; a placement flagged
    /// `continuesPrevious` is a segment split, not a cut.
    static func internalCutBoundaries(
        placements: [AutoClipPlacement],
        toleranceSeconds: Double = 0.05
    ) -> [Double] {
        let dominants = placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        var cuts: [Double] = []
        for pair in zip(dominants, dominants.dropFirst()) {
            guard pair.0.songID == pair.1.songID else { continue }
            if pair.1.continuesPrevious { continue }
            let expected = pair.0.sourceEnd
            if abs(pair.1.sourceStart - expected) > toleranceSeconds {
                cuts.append(pair.1.timelineStart)
            }
        }
        return cuts
    }

    /// True when dominant placements consume the source in strictly
    /// non-decreasing order (no rewinds), ignoring placements listed in
    /// `justifiedReturnStarts` (timeline seconds of an explicit hook return).
    static func sourceOrderIsMonotonic(
        placements: [AutoClipPlacement],
        justifiedReturnStarts: [Double] = [],
        toleranceSeconds: Double = 0.05
    ) -> Bool {
        let dominants = placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        for pair in zip(dominants, dominants.dropFirst()) {
            guard pair.0.songID == pair.1.songID else { continue }
            let isJustified = justifiedReturnStarts.contains {
                abs($0 - pair.1.timelineStart) < 0.05
            }
            if isJustified { continue }
            if pair.1.sourceStart < pair.0.sourceStart - toleranceSeconds {
                return false
            }
        }
        return true
    }
}
