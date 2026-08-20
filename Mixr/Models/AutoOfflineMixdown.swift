import Foundation

// MARK: - Portable Offline Mixdown
//
// Deterministic reference renderer for AutoRemixPlan placements + SFX.
// Pure Swift over [Float] — no AVFoundation — so rendered-PCM quality
// gates run in the standalone harness on any platform.
//
// Stretch parity: live/export use AVAudioUnitTimePitch (overlap-aware when
// stretch > 8%). This offline renderer uses linear resample only — it models
// gain envelopes, ducking, and transition math faithfully, but NOT TimePitch
// smear/settle. Plan-level mixLead gates cover title-token timing; golden
// bounce sign-off still requires Mac AVFoundation listen.
//
// It mirrors the REAL engines' scheduling math (trim/offset/speed,
// per-clip volume, transition envelopes via AutoTransitionEnvelope, SFX
// gains and ducking via AutoGainPolicy) without the effect DSP chain
// (reverb/echo/flanger add tails but do not change transition gain
// structure, which is what these gates measure).
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
    /// `stemSources[songID][kind]` is used when a placement has `stemKind`;
    /// missing stem PCM falls back to the full-mix `sources` entry.
    static func render(
        plan: AutoRemixPlan,
        sources: [UUID: Source],
        stemSources: [UUID: [AutoStemKind: Source]] = [:],
        sampleRate: Double = 44_100,
        trackVolume: Double = 1.0,
        sfxTrackVolume: Double = 0.85,
        includeTail: Bool = true
    ) -> Result {
        let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        var sfxEnd = plan.sfxEvents.map(\.timelineEnd).max() ?? 0
        if let policy = plan.pulsePolicy, !plan.pulseRegions.isEmpty {
            let pulseEnd = AutoClubPulse.scheduleHits(
                regions: plan.pulseRegions,
                policy: policy,
                beatSeconds: plan.beatSeconds,
                barSeconds: plan.barSeconds,
                halfTimeDrop: plan.clubFlavor?.bias.halfTimeDrop ?? false
            ).map { $0.timelineStart + 0.3 }.max() ?? 0
            sfxEnd = max(sfxEnd, pulseEnd)
        }
        let tail = includeTail ? exportTailSeconds(plan: plan) : 0
        let totalSeconds = max(contentEnd, sfxEnd) + tail
        let frames = Int(totalSeconds * sampleRate)
        guard frames > 0 else {
            return Result(mix: [], songBus: [], limiterGainReductionDB: 0, sampleRate: sampleRate)
        }

        var songBus = [Float](repeating: 0, count: frames)

        // ── Song placements ──
        let bySong = Dictionary(grouping: plan.placements) { $0.songID }
        for (songID, placements) in bySong {
            let stems = stemSources[songID] ?? [:]
            let ordered = placements.sorted { $0.timelineStart < $1.timelineStart }
            for (idx, p) in ordered.enumerated() {
                let source: Source
                if let kind = p.stemKind, let stem = stems[kind] {
                    source = stem
                } else if let full = sources[songID] {
                    source = full
                } else {
                    continue
                }
                let continuity = AutoTransitionEnvelope.Continuity(
                    previous: p.continuesPrevious,
                    next: idx + 1 < ordered.count && ordered[idx + 1].continuesPrevious
                )
                renderPlacement(
                    p,
                    continuity: continuity,
                    source: source,
                    bpm: plan.targetBPM,
                    trackVolume: trackVolume,
                    sampleRate: sampleRate,
                    into: &songBus
                )
            }
        }

        // ── Ducking under major SFX (policy-driven; baseline = none) ──
        let duckEvents = plan.sfxEvents
        if !duckEvents.isEmpty {
            for i in 0..<frames {
                let t = Double(i) / sampleRate
                let duck = AutoGainPolicy.duckGain(at: t, sfxEvents: duckEvents)
                if duck < 0.9999 {
                    songBus[i] *= Float(duck)
                }
            }
        }

        // Reserve mix-bus headroom before SFX join — density is layers/FX,
        // not slamming the song bus into the ceiling.
        let headroom = Float(pow(10.0, -AutoGainPolicy.mixBusHeadroomDB / 20.0))
        for i in 0..<frames { songBus[i] *= headroom }

        // ── SFX bus (musical accents + expanded club pulse) ──
        var mix = songBus
        var renderSFX = plan.sfxEvents
        if let policy = plan.pulsePolicy, !plan.pulseRegions.isEmpty {
            let pulseHits = AutoClubPulse.scheduleHits(
                regions: plan.pulseRegions,
                policy: policy,
                beatSeconds: plan.beatSeconds,
                barSeconds: plan.barSeconds,
                halfTimeDrop: plan.clubFlavor?.bias.halfTimeDrop ?? false
            )
            renderSFX += pulseHits.map {
                AutoSFXEvent(assetID: $0.assetID, timelineStart: $0.timelineStart, purpose: $0.purpose)
            }
        }

        // Precompute per-frame stacked SFX gain so coordinated club hits
        // (riser+snare+impact+crash) honor maxSimultaneousSFXGain.
        var sfxGainAtFrame = [Float](repeating: 0, count: frames)
        struct PreparedSFX {
            var startFrame: Int
            var buffer: [Float]
            var gain: Float
        }
        var prepared: [PreparedSFX] = []
        prepared.reserveCapacity(renderSFX.count)
        for event in renderSFX {
            guard let def = SoundEffectLibrary.definition(for: event.assetID) else { continue }
            var buffer = syntheticSFX(
                type: def.synthesisType,
                durationSeconds: def.durationSeconds,
                sampleRate: sampleRate
            )
            // Edge fades on every one-shot so dense stacks never click.
            let fade = max(1, Int(0.004 * sampleRate))
            for i in 0..<min(fade, buffer.count) {
                let g = Float(i) / Float(fade)
                buffer[i] *= g
                let j = buffer.count - 1 - i
                if j >= 0 { buffer[j] *= g }
            }
            let gain = Float(sfxTrackVolume * AutoGainPolicy.nominalGain(forSFX: event.assetID))
            let startFrame = Int(event.timelineStart * sampleRate)
            for j in 0..<buffer.count {
                let idx = startFrame + j
                guard idx >= 0, idx < frames else { continue }
                sfxGainAtFrame[idx] += abs(buffer[j]) * gain
            }
            prepared.append(PreparedSFX(startFrame: startFrame, buffer: buffer, gain: gain))
        }
        let stackCeiling = Float(AutoGainPolicy.maxSimultaneousSFXGain)
        for event in prepared {
            for (j, v) in event.buffer.enumerated() {
                let idx = event.startFrame + j
                guard idx >= 0, idx < frames else { continue }
                var g = event.gain
                let stacked = sfxGainAtFrame[idx]
                if stacked > stackCeiling, stacked > 1e-6 {
                    g *= stackCeiling / stacked
                }
                mix[idx] += v * g
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

    private static func renderPlacement(
        _ p: AutoClipPlacement,
        continuity: AutoTransitionEnvelope.Continuity,
        source: Source,
        bpm: Double,
        trackVolume: Double,
        sampleRate: Double,
        into bus: inout [Float]
    ) {
        let startFrame = Int(p.timelineStart * sampleRate)
        let frameCount = Int(p.timelineDuration * sampleRate)
        guard frameCount > 0 else { return }
        let srcRate = source.sampleRate

        // Cheap wet-bus approximation so offline WAV bounces aren't bone-dry
        // when the plan fires clip FX (real engines use ClipEffectDSP).
        let blurAmt = p.effects.level(for: "blur") / 100.0
        let echoAmt = p.effects.level(for: "echo") / 100.0
        let reverbAmt = p.effects.level(for: "reverb") / 100.0
        let flangerAmt = p.effects.flangerAmount
        let beat = 60.0 / max(bpm, 40)
        let echoDelayFrames = max(1, Int(beat * sampleRate))
        // Prime-spaced taps spread to ~230 ms so the tail reads as diffuse
        // room, not a metallic slapback comb cluster.
        let reverbDelays = [
            max(1, Int(0.031 * sampleRate)),
            max(1, Int(0.047 * sampleRate)),
            max(1, Int(0.071 * sampleRate)),
            max(1, Int(0.103 * sampleRate)),
            max(1, Int(0.149 * sampleRate)),
            max(1, Int(0.191 * sampleRate)),
            max(1, Int(0.229 * sampleRate)),
        ]
        var lpf: Float = 0
        let lpfCoeff = Float(0.15 + (1.0 - min(1, blurAmt)) * 0.75)

        for j in 0..<frameCount {
            let outIdx = startFrame + j
            guard outIdx >= 0, outIdx < bus.count else { continue }
            let t = Double(outIdx) / sampleRate
            var sample: Float
            if abs(p.tempoRatio - 1) < 0.02 {
                let sourceSeconds = p.sourceStart + (Double(j) / sampleRate) * p.tempoRatio
                let srcPos = sourceSeconds * srcRate
                let i0 = Int(srcPos)
                guard i0 >= 0, i0 + 1 < source.samples.count else { continue }
                let frac = Float(srcPos - Double(i0))
                sample = source.samples[i0] * (1 - frac) + source.samples[i0 + 1] * frac
            } else {
                sample = wsolaSample(
                    samples: source.samples,
                    sourceStart: p.sourceStart,
                    tempoRatio: p.tempoRatio,
                    outputIndex: j,
                    outputRate: sampleRate,
                    sourceRate: srcRate
                )
            }

            // Blur ≈ low-pass (filter sweep / build-out).
            if blurAmt > 0.02 {
                lpf += (sample - lpf) * lpfCoeff
                sample = sample * Float(1 - blurAmt * 0.85) + lpf * Float(blurAmt * 0.85)
            }
            // Flanger ≈ light modulated comb (cheap). Slow, shallow, and a
            // low wet mix — a 5.5 Hz 0.45-mix comb reads as metal, not motion.
            if flangerAmt > 0.02 {
                let mod = 1.0 + 0.003 * sin(t * 0.9 * .pi * 2)
                let delay = Int(mod * 0.004 * sampleRate)
                let approxI0 = Int(p.sourceStart * srcRate + Double(j) * p.tempoRatio * (srcRate / sampleRate))
                let di = approxI0 - delay
                if di >= 0, di < source.samples.count {
                    sample += source.samples[di] * Float(flangerAmt * 0.22)
                }
            }

            let envelope = AutoTransitionEnvelope.envelope(
                transitionIn: p.fadeIn,
                transitionOut: p.fadeOut,
                clipStart: p.timelineStart,
                clipEnd: p.timelineEnd,
                at: t,
                bpm: bpm,
                continuity: continuity
            )
            let dry = sample * Float(trackVolume * p.volume * envelope.gain)
            bus[outIdx] += dry

            // Echo throws / ping-pong-ish repeats into later frames.
            if echoAmt > 0.05 {
                var echoGain = Float(echoAmt * 0.35)
                for tap in 1...4 {
                    let idx = outIdx + tap * echoDelayFrames
                    guard idx < bus.count else { break }
                    bus[idx] += dry * echoGain
                    echoGain *= 0.55
                }
            }
            // Reverb bloom ≈ diffuse multi-tap tail (bounce WAVs hear
            // atmosphere). Exponential decay across the taps, lower wet.
            if reverbAmt > 0.05 {
                let wet = dry * Float(reverbAmt * 0.18)
                var tapGain: Float = 0.6
                for d in reverbDelays {
                    let idx = outIdx + d
                    tapGain *= 0.72
                    guard idx < bus.count else { continue }
                    bus[idx] += wet * tapGain
                }
            }
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
            case .clubKick:
                // Soft-attack thump — avoid a sample-edge click at hit onset.
                let attack = Float(min(1, x / 0.08))
                let env = attack * Float(exp(-12 * x))
                let tone = Float(sin(2 * Double.pi * 55 * Double(i) / sampleRate))
                value = (noise * 0.25 + tone * 0.75) * env
            case .clubBass:
                let attack = Float(min(1, x / 0.05))
                let env = attack * Float(exp(-8 * x))
                let tone = Float(sin(2 * Double.pi * 45 * Double(i) / sampleRate))
                value = tone * env * 0.9
            }
            out[i] = value
        }
        return out
    }

    /// Overlap-add grains at native pitch while hopping through the source
    /// at `tempoRatio` — bounce WAVs match TimePitch.rate instead of chipmunking.
    private static func wsolaSample(
        samples: [Float],
        sourceStart: Double,
        tempoRatio: Double,
        outputIndex: Int,
        outputRate: Double,
        sourceRate: Double
    ) -> Float {
        let grain = 1024
        let hop = 512
        let g1 = max(0, outputIndex / hop)
        let g0 = max(0, g1 - 1)
        func grainAt(_ g: Int) -> (Float, Float) {
            let local = outputIndex - g * hop
            guard local >= 0, local < grain else { return (0, 0) }
            let src = sourceStart * sourceRate
                + Double(g * hop) * tempoRatio * (sourceRate / max(outputRate, 1))
                + Double(local) * (sourceRate / max(outputRate, 1))
            let w = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(local) / Double(grain - 1)))
            let i0 = Int(src)
            guard i0 >= 0, i0 + 1 < samples.count else { return (0, 0) }
            let frac = Float(src - Double(i0))
            let s = samples[i0] * (1 - frac) + samples[i0 + 1] * frac
            return (s, w)
        }
        let a = grainAt(g0)
        let b = grainAt(g1)
        let wsum = a.1 + b.1
        guard wsum > 1e-6 else { return 0 }
        return (a.0 * a.1 + b.0 * b.1) / wsum
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
