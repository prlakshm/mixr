import Foundation

// MARK: - Portable Offline Mixdown
//
// Deterministic reference renderer for AutoRemixPlan placements + SFX.
// Pure Swift over [Float] — no AVFoundation — so rendered-PCM quality
// gates run in the standalone harness on any platform.
//
// It mirrors the REAL engines' scheduling math (trim/offset/speed,
// per-clip volume, transition envelopes via AutoTransitionEnvelope, SFX
// gains and ducking via AutoGainPolicy), the DJ filter automation (the
// engines' 12 dB/oct EQ high-/low-pass bands, driven by the same envelope
// model), and the tempo-synced echo (AVAudioUnitDelay wet/dry semantics,
// so echo-outs keep their tails). Reverb and flanger are not modeled —
// they add color, not transition gain structure.
nonisolated enum AutoOfflineMixdown {

    struct Source {
        var samples: [Float]
        var sampleRate: Double

        nonisolated init(samples: [Float], sampleRate: Double) {
            self.samples = samples
            self.sampleRate = sampleRate
        }
    }

    struct Result {
        /// Full mix (songs + SFX) after the gain policy.
        var mix: [Float]
        /// Song bus only (pre-SFX), for headroom checks.
        var songBus: [Float]
        /// Peak gain reduction a ceiling-limiter would have applied, dB.
        var limiterGainReductionDB: Double
        var sampleRate: Double
    }

    /// Renders a plan against per-song sources. `trackVolume` mirrors the
    /// song tracks' mixer volume; `sfxTrackVolume` mirrors the SFX track.
    static func render(
        plan: AutoRemixPlan,
        sources: [UUID: Source],
        sampleRate: Double = 44_100,
        trackVolume: Double = 1.0,
        sfxTrackVolume: Double = 0.85,
        includeTail: Bool = true,
        sfxSamples: [String: [Float]] = [:]
    ) -> Result {
        let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        let sfxEnd = plan.sfxEvents.map(\.timelineEnd).max() ?? 0
        let tail = includeTail ? exportTailSeconds(plan: plan) : 0
        let totalSeconds = max(contentEnd, sfxEnd) + tail
        let frames = Int(totalSeconds * sampleRate)
        guard frames > 0 else {
            return Result(mix: [], songBus: [], limiterGainReductionDB: 0, sampleRate: sampleRate)
        }

        var songBus = [Float](repeating: 0, count: frames)

        // ── Song placements (dry) + per-song echo send ──
        let bySong = Dictionary(grouping: plan.placements) { $0.songID }
        for (songID, placements) in bySong {
            guard let source = sources[songID] else { continue }
            let ordered = placements.sorted { $0.timelineStart < $1.timelineStart }
            var send = [Float](repeating: 0, count: frames)
            var usesEcho = false
            for (idx, p) in ordered.enumerated() {
                let continuity = AutoTransitionEnvelope.Continuity(
                    previous: p.continuesPrevious,
                    next: idx + 1 < ordered.count && ordered[idx + 1].continuesPrevious
                )
                usesEcho = renderPlacement(
                    p,
                    continuity: continuity,
                    source: source,
                    bpm: p.envelopeBPM > 0 ? p.envelopeBPM : plan.targetBPM,
                    trackVolume: trackVolume,
                    sampleRate: sampleRate,
                    into: &songBus,
                    echoSend: &send
                ) || usesEcho
            }
            if usesEcho {
                let bpm = ordered.first.map { $0.envelopeBPM > 0 ? $0.envelopeBPM : plan.targetBPM } ?? plan.targetBPM
                applyEcho(send: send, beatSeconds: 60 / max(bpm, 1), sampleRate: sampleRate, into: &songBus)
            }
        }

        // ── Ducking under major SFX (policy-driven; baseline = none) ──
        if !plan.sfxEvents.isEmpty {
            for i in 0..<frames {
                let t = Double(i) / sampleRate
                let duck = AutoGainPolicy.duckGain(at: t, sfxEvents: plan.sfxEvents)
                if duck < 0.9999 {
                    songBus[i] *= Float(duck)
                }
            }
        }

        // ── SFX bus ──
        var mix = songBus
        for event in plan.sfxEvents {
            guard let def = SoundEffectLibrary.definition(for: event.assetID) else { continue }
            // Real asset PCM when supplied (audition renders); otherwise the
            // deterministic copyright-free stand-in (tests).
            let buffer = sfxSamples[event.assetID] ?? syntheticSFX(
                type: def.synthesisType,
                durationSeconds: def.durationSeconds,
                sampleRate: sampleRate
            )
            let gain = Float(sfxTrackVolume * AutoGainPolicy.nominalGain(forSFX: event.assetID))
            let startFrame = Int(event.timelineStart * sampleRate)
            for (j, v) in buffer.enumerated() {
                let idx = startFrame + j
                guard idx >= 0, idx < frames else { continue }
                mix[idx] += v * gain
            }
        }

        // ── Ceiling limiter model: measure how much reduction the master
        // limiter would need; apply a hard ceiling so downstream metrics
        // see post-limiter PCM. The policy treats sustained reduction
        // beyond its threshold as a failed mix — tests read this value.
        let ceiling = Float(pow(10.0, AutoGainPolicy.truePeakCeilingDB / 20.0))
        var peak: Float = 0
        for v in mix { peak = max(peak, abs(v)) }
        var reductionDB = 0.0
        if peak > ceiling {
            reductionDB = Double(20 * log10(peak / ceiling))
            let scale = ceiling / peak
            for i in 0..<frames { mix[i] *= scale }
            for i in 0..<frames { songBus[i] *= scale }
        }

        // ── Tail policy (baseline: keep everything) ──
        let keep = AutoGainPolicy.trimmedTailFrameCount(
            samples: mix,
            sampleRate: sampleRate,
            protectedSeconds: contentEnd
        )
        if keep < mix.count {
            mix.removeLast(mix.count - keep)
            if keep < songBus.count { songBus.removeLast(songBus.count - keep) }
        }

        return Result(
            mix: mix,
            songBus: songBus,
            limiterGainReductionDB: reductionDB,
            sampleRate: sampleRate
        )
    }

    // MARK: Placement rendering

    /// Renders one placement's dry signal into `bus` and its echo send
    /// (pre-delay wet input) into `echoSend`. Returns true when echo is used.
    @discardableResult
    private static func renderPlacement(
        _ p: AutoClipPlacement,
        continuity: AutoTransitionEnvelope.Continuity,
        source: Source,
        bpm: Double,
        trackVolume: Double,
        sampleRate: Double,
        into bus: inout [Float],
        echoSend: inout [Float]
    ) -> Bool {
        let startFrame = Int(p.timelineStart * sampleRate)
        let frameCount = Int(p.timelineDuration * sampleRate)
        guard frameCount > 0 else { return false }
        let srcRate = source.sampleRate
        let echoLevel = p.effects.level(for: "echo") / 100.0
        let blurLP = ClipEffectMapping.blurLowPassHz(level: p.effects.level(for: "blur"))
        var hp = Biquad(), lp = Biquad()
        var usesEcho = false
        var envelope = AutoTransitionEnvelope.Value(gain: 1, echoBoost: 0)
        let controlStride = 32

        for j in 0..<frameCount {
            let outIdx = startFrame + j
            guard outIdx >= 0, outIdx < bus.count else { continue }
            let t = Double(outIdx) / sampleRate
            let sourceSeconds = p.sourceStart + (Double(j) / sampleRate) * p.tempoRatio
            let srcPos = sourceSeconds * srcRate
            let i0 = Int(srcPos)
            guard i0 >= 0, i0 + 1 < source.samples.count else { continue }
            let frac = Float(srcPos - Double(i0))
            var sample = source.samples[i0] * (1 - frac) + source.samples[i0 + 1] * frac

            if j % controlStride == 0 {
                envelope = AutoTransitionEnvelope.envelope(
                    transitionIn: p.fadeIn,
                    transitionOut: p.fadeOut,
                    clipStart: p.timelineStart,
                    clipEnd: p.timelineEnd,
                    at: t,
                    bpm: bpm,
                    continuity: continuity
                )
                hp.setHighPass(envelope.highPassHz, sampleRate: sampleRate)
                lp.setLowPass(min(envelope.lowPassHz, blurLP), sampleRate: sampleRate)
            } else if j % controlStride == controlStride / 2 {
                // Gain tracks at half the control stride (sub-ms), so
                // anti-click microfades stay exact.
                let g = AutoTransitionEnvelope.envelope(
                    transitionIn: p.fadeIn, transitionOut: p.fadeOut,
                    clipStart: p.timelineStart, clipEnd: p.timelineEnd,
                    at: t, bpm: bpm, continuity: continuity
                )
                envelope.gain = g.gain
            }
            if envelope.highPassHz > AutoTransitionEnvelope.openHighPassHz + 1 { sample = hp.process(sample) }
            if min(envelope.lowPassHz, blurLP) < AutoTransitionEnvelope.openLowPassHz - 1 { sample = lp.process(sample) }

            let g = Float(trackVolume * p.volume * envelope.gain)
            // AVAudioUnitDelay semantics: output = dry·(1 − mix) + wet·mix.
            let wetMix = Float(min(70, ClipEffectMapping.echoWetPercent(amount: echoLevel) + envelope.echoBoost) / 100)
            bus[outIdx] += sample * g * (1 - wetMix)
            if wetMix > 0.001 {
                echoSend[outIdx] += sample * g * wetMix
                usesEcho = true
            }
        }
        return usesEcho
    }

    /// Tempo-synced feedback delay (1 beat, ~45% feedback, 9 kHz damping)
    /// over a song's echo send — its tail rings past the clip like the
    /// engines' AVAudioUnitDelay.
    private static func applyEcho(send: [Float], beatSeconds: Double, sampleRate: Double, into bus: inout [Float]) {
        let delay = max(1, Int(beatSeconds * sampleRate))
        var line = [Float](repeating: 0, count: delay)
        var idx = 0
        let feedback: Float = 0.45
        let damp = Float(1 - exp(-2 * Double.pi * 9000 / sampleRate))
        var lpState: Float = 0
        for i in 0..<min(send.count, bus.count) {
            let out = line[idx]
            lpState += (out - lpState) * damp
            line[idx] = send[i] + lpState * feedback
            bus[i] += out
            idx += 1
            if idx == delay { idx = 0 }
        }
    }

    /// RBJ-cookbook 2nd-order section (12 dB/oct, Q = 0.707) — the shape
    /// of AVAudioUnitEQ's high-/low-pass bands.
    struct Biquad {
        var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var z1: Float = 0, z2: Float = 0
        var lastHz = -1.0

        mutating func setHighPass(_ hz: Double, sampleRate: Double) {
            guard abs(hz - lastHz) > 0.5 else { return }
            lastHz = hz
            let w = 2 * Double.pi * min(hz, sampleRate * 0.45) / sampleRate
            let alpha = sin(w) / (2 * 0.7071), c = cos(w), a0 = 1 + alpha
            b0 = Float((1 + c) / 2 / a0); b1 = Float(-(1 + c) / a0); b2 = b0
            a1 = Float(-2 * c / a0); a2 = Float((1 - alpha) / a0)
        }

        mutating func setLowPass(_ hz: Double, sampleRate: Double) {
            guard abs(hz - lastHz) > 0.5 else { return }
            lastHz = hz
            let w = 2 * Double.pi * min(hz, sampleRate * 0.45) / sampleRate
            let alpha = sin(w) / (2 * 0.7071), c = cos(w), a0 = 1 + alpha
            b0 = Float((1 - c) / 2 / a0); b1 = Float((1 - c) / a0); b2 = b0
            a1 = Float(-2 * c / a0); a2 = Float((1 - alpha) / a0)
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    // MARK: Export tail (portable mirror of the exporter's rule)

    /// Fixed decay allowance after the last clip, from the plan's effect
    /// use — mirrors ClipEffectDSP.exportTailSeconds. The tail POLICY
    /// (never ship silence) is enforced by AutoGainPolicy tail trimming.
    static func exportTailSeconds(plan: AutoRemixPlan) -> Double {
        var tail = 0.3
        let beat = plan.beatSeconds
        for p in plan.placements {
            let fx = p.effects
            if fx.level(for: "reverb") > 0.5 {
                switch fx.reverbPreset {
                case .smallRoom: tail = max(tail, 1.2)
                case .hall: tail = max(tail, 3.5)
                case .ambient: tail = max(tail, 6.0)
                }
            }
            if fx.level(for: "echo") > 0.5 { tail = max(tail, min(6.0, beat * 8.0)) }
            if p.fadeOut.type == .echoOut { tail = max(tail, min(6.0, beat * 8.0)) }
        }
        return min(tail, AutoGainPolicy.maxTailSeconds)
    }

    // MARK: Deterministic synthetic SFX (copyright-free, no I/O)

    /// Portable stand-ins for the bundled SFX assets: same duration and
    /// broad energy shape, fully deterministic.
    static func syntheticSFX(
        type: SFXSynthesisType,
        durationSeconds: Double,
        sampleRate: Double
    ) -> [Float] {
        let n = Int(durationSeconds * sampleRate)
        guard n > 0 else { return [] }
        var rng = SplitMix64(seed: 0x5F3C_9A17)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let x = Double(i) / Double(n)         // 0…1 progress
            let noise = Float(rng.nextUniform() * 2 - 1)
            let value: Float
            switch type {
            case .riser, .sweepUp, .airSweep, .snareBuild, .clapFill:
                // Rising energy into the payoff.
                value = noise * Float(0.05 + 0.85 * x * x)
            case .downlifter, .sweepDown, .tapeStop:
                value = noise * Float(0.9 * (1 - x) * (1 - x))
            case .impact, .crash, .bassDrop:
                // Front-loaded hit with exponential decay.
                value = noise * Float(exp(-6 * x))
            case .reverseCymbal:
                value = noise * Float(0.05 + 0.9 * x * x * x)
            }
            out[i] = value
        }
        return out
    }

    // MARK: Deterministic RNG (fixture use only — never for decisions)

    struct SplitMix64 {
        private var state: UInt64

        nonisolated init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }

        nonisolated mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        nonisolated mutating func nextUniform() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
    }
}
