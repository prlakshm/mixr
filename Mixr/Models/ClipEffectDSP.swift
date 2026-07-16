import AVFoundation
import AudioToolbox

// MARK: - Clip Effect DSP Mapping
//
// SINGLE SOURCE OF TRUTH for turning a clip's stored effect state
// (ClipEffectSettings — slider levels 0…100 plus presets, stored on
// MixrClip.effects and persisted inside the project snapshot) into
// concrete AVAudioUnit parameters.
//
// Both consumers use exactly the same mapping so live playback and the
// exported file sound identical:
//
//   • MixrPlaybackEngine — live: computes ChainTargets every tick and
//     RAMPS the smoothable parameters toward them (no clicks/zipper).
//   • MixrExportRenderer — offline: applies ChainTargets per render block.
//
// Effect chain order (fixed, per track chain):
//   player → timePitch (Pitch) → EQ (Blur low-pass)
//          → flanger (Flanger) → delay (Echo) → reverb (Reverb)
//          → mixer → peak limiter → out
//
// Flanger processes the pitched and filtered signal; Echo and Reverb
// process the flanger output naturally. Pitch uses TimePitch.pitch
// (cents), never rate, so duration and timeline sync stay intact.
//
// nonisolated: pure math over value types — callable from the live
// engine (main actor) and the background export render loop alike.
nonisolated enum ClipEffectDSP {

    // MARK: - Chain targets

    /// Concrete audio-unit parameter targets for one clip's effect chain.
    struct ChainTargets {
        // Pitch → AVAudioUnitTimePitch
        var pitchCents: Float
        var playbackRate: Float
        /// True bypass when Pitch is 0 and the clip plays at normal speed.
        var timePitchBypass: Bool

        // Blur → AVAudioUnitEQ band 0 (low-pass)
        var lowPassFrequency: Float
        var lowPassBypass: Bool

        // Flanger → FlangerKernel (custom AU)
        var flangerWet: Float
        var flangerFeedback: Float
        var flangerDepthSeconds: Float
        var flangerBaseDelaySeconds: Float
        var flangerLFOFrequency: Float
        /// True bypass when the Flanger slider is at 0.
        var flangerBypass: Bool

        // Echo → AVAudioUnitDelay
        var delayTime: TimeInterval
        var delayFeedback: Float
        var delayWetDryMix: Float
        var delayLowPassCutoff: Float

        // Reverb → AVAudioUnitReverb
        var reverbPreset: ReverbPreset
        var reverbWetDryMix: Float
    }

    /// Maps a clip's slider levels + presets to audio-unit parameters.
    static func targets(
        for settings: ClipEffectSettings,
        playbackSpeed: Double,
        bpm: Double,
        echoBoost: Double
    ) -> ChainTargets {
        let reverbAmount = settings.level(for: MixrEffect.reverb.rawValue) / 100.0
        let echoAmount = settings.level(for: MixrEffect.echo.rawValue) / 100.0
        let pitchAmount = settings.pitchAmount
        let blurAmount = settings.level(for: MixrEffect.blur.rawValue) / 100.0
        let rate = Float(max(playbackSpeed, 0.03125))

        // ── PITCH ──
        // pitchInCents = amount * 1200 * (±1). Duration preserved.
        let pitchCents = Float(pitchAmount * 1200.0 * settings.pitchDirection.centsSign)
        let timePitchBypass = pitchAmount <= 0.001 && abs(playbackSpeed - 1.0) < 0.001

        // ── BLUR (low-pass) ──
        let lowPassBypass = blurAmount <= 0.001
        let eased = pow(blurAmount, 1.3)
        let lowPassFrequency = Float(20000.0 * pow(650.0 / 20000.0, eased))

        // ── FLANGER ──
        // The slider drives a coordinated group — wet mix, feedback,
        // sweep depth, and sweep rate — never just wet volume. An eased
        // curve (x^0.65) front-loads the response so 25/50 are clearly
        // audible, and 100 is a full jet sweep on par with the other
        // effects at max (ceilings sit just under the kernel clamps).
        let flangerAmount = min(max(settings.flangerAmount, 0), 1)
        let flangerBypass = flangerAmount <= 0.001
        let flangerShaped = pow(flangerAmount, 0.65)
        //   25% → wet ≈ 0.29, fb ≈ 0.34, swing ≈ 0.9–4.4 ms
        //   50% → wet ≈ 0.46, fb ≈ 0.54, swing ≈ 0.9–6.3 ms
        //   75% → wet ≈ 0.60, fb ≈ 0.70, swing ≈ 0.9–8.0 ms
        //  100% → wet ≈ 0.72, fb ≈ 0.84, swing ≈ 0.9–9.4 ms (jet, kernel-safe)
        let flangerWet = Float(0.72 * flangerShaped)
        let flangerFeedback = Float(0.84 * flangerShaped)
        let flangerBase: Float = 0.0009
        let flangerDepth = Float(flangerBypass ? 0 : 0.0085 * flangerShaped)

        // ── ECHO (tempo-synced delay) ──
        let beat = 60.0 / max(bpm, 1)
        let delayTime: TimeInterval
        let feedbackBase: Double
        let feedbackSpan: Double
        let delayLowPass: Float
        switch settings.echoPreset {
        case .classic:
            delayTime = beat * 1.0
            feedbackBase = 18; feedbackSpan = 34
            delayLowPass = 9000
        case .pingPong:
            delayTime = beat * 0.5
            feedbackBase = 25; feedbackSpan = 38
            delayLowPass = 10000
        case .reverse:
            delayTime = beat * 0.25
            feedbackBase = 35; feedbackSpan = 38
            delayLowPass = 7500
        }
        let delayFeedback = Float(echoAmount <= 0.001 ? 0 : feedbackBase + feedbackSpan * echoAmount)
        let delayWet = Float(min(70.0, 50.0 * pow(echoAmount, 0.9) + echoBoost))

        // ── REVERB ──
        let reverbCeiling: Double
        switch settings.reverbPreset {
        case .smallRoom: reverbCeiling = 45
        case .hall: reverbCeiling = 58
        case .ambient: reverbCeiling = 72
        }
        let reverbWet = Float(reverbCeiling * pow(reverbAmount, 0.85))

        return ChainTargets(
            pitchCents: pitchCents,
            playbackRate: rate,
            timePitchBypass: timePitchBypass,
            lowPassFrequency: lowPassFrequency,
            lowPassBypass: lowPassBypass,
            flangerWet: flangerWet,
            flangerFeedback: flangerFeedback,
            flangerDepthSeconds: flangerDepth,
            flangerBaseDelaySeconds: flangerBase,
            flangerLFOFrequency: flangerLFOFrequency(bpm: bpm, amount: flangerAmount),
            flangerBypass: flangerBypass,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayWetDryMix: delayWet,
            delayLowPassCutoff: delayLowPass,
            reverbPreset: settings.reverbPreset,
            reverbWetDryMix: reverbWet
        )
    }

    // MARK: - Flanger sweep (tempo-synced, deterministic phase)

    /// Tempo-synced LFO (4/4): one complete sweep every TWO BARS at low
    /// intensity — smooth, professional movement — tightening linearly to
    /// ONE BAR at 100%, so max intensity also sweeps noticeably faster.
    /// Falls back to a stable equivalent rate when the BPM is invalid.
    static func flangerLFOFrequency(bpm: Double, amount: Double = 1) -> Float {
        let sweepBars = 2.0 - min(max(amount, 0), 1)
        guard bpm.isFinite, bpm >= 30, bpm <= 300 else {
            return Float(0.5 / sweepBars) // 0.25 Hz at 2 bars, 0.5 Hz at 1
        }
        let secondsPerBar = (60.0 / bpm) * 4.0
        return Float(1.0 / (secondsPerBar * sweepBars))
    }

    /// LFO phase 0…1 derived from the PROJECT TIMELINE position — never
    /// restarted by slider moves, so playback is deterministic, seeking is
    /// consistent, and export matches real-time playback.
    static func flangerPhase(atTimelineSeconds t: Double, lfoFrequency: Float) -> Float {
        let cycles = max(0, t) * Double(lfoFrequency)
        return Float(cycles - cycles.rounded(.down))
    }

    /// Pushes a chain's flanger targets (with timeline-derived phase) into
    /// the kernel — identical call for live ticks and export blocks.
    static func applyFlanger(_ t: ChainTargets, kernel: FlangerKernel?, timelineSeconds: Double) {
        kernel?.setTargets(
            wet: t.flangerWet,
            feedback: t.flangerFeedback,
            depthSeconds: t.flangerDepthSeconds,
            baseDelaySeconds: t.flangerBaseDelaySeconds,
            lfoFrequency: t.flangerLFOFrequency,
            phase: flangerPhase(atTimelineSeconds: timelineSeconds, lfoFrequency: t.flangerLFOFrequency)
        )
    }

    /// Configures a clip chain's audio units into their bypassed rest state.
    static func configureRestState(
        timePitch: AVAudioUnitTimePitch,
        eq: AVAudioUnitEQ,
        flanger: FlangerKernel?,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb
    ) {
        flanger?.setTargets(
            wet: 0, feedback: 0, depthSeconds: 0,
            baseDelaySeconds: 0.0006, lfoFrequency: 0.25, phase: 0
        )
        timePitch.pitch = 0
        timePitch.rate = 1
        timePitch.bypass = true

        // Single band: Blur low-pass.
        let lowPass = eq.bands[0]
        lowPass.filterType = .lowPass
        lowPass.frequency = 20000
        lowPass.bandwidth = 0.7
        lowPass.bypass = true

        delay.wetDryMix = 0
        delay.feedback = 0
        delay.lowPassCutoff = 9000
        delay.bypass = true

        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 0
        reverb.bypass = true
    }

    /// Applies targets directly (host-side; the flanger kernel smooths
    /// per-sample internally) — used by offline export.
    static func apply(
        _ t: ChainTargets,
        timePitch: AVAudioUnitTimePitch,
        eq: AVAudioUnitEQ,
        flanger: FlangerKernel?,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb,
        timelineSeconds: Double,
        appliedReverbPreset: inout ReverbPreset?,
        appliedDelayTime: inout TimeInterval
    ) {
        timePitch.pitch = t.pitchCents
        timePitch.rate = t.playbackRate
        if !t.timePitchBypass { timePitch.bypass = false }

        let lowPass = eq.bands[0]
        lowPass.frequency = t.lowPassFrequency
        lowPass.bypass = t.lowPassBypass

        applyFlanger(t, kernel: flanger, timelineSeconds: timelineSeconds)

        if appliedDelayTime != t.delayTime {
            delay.delayTime = t.delayTime
            appliedDelayTime = t.delayTime
        }
        delay.feedback = t.delayFeedback
        delay.lowPassCutoff = t.delayLowPassCutoff
        delay.wetDryMix = t.delayWetDryMix
        if t.delayWetDryMix > 0.01 { delay.bypass = false }

        if appliedReverbPreset != t.reverbPreset {
            reverb.loadFactoryPreset(factoryPreset(for: t.reverbPreset))
            appliedReverbPreset = t.reverbPreset
        }
        reverb.wetDryMix = t.reverbWetDryMix
        if t.reverbWetDryMix > 0.01 { reverb.bypass = false }
    }

    static func factoryPreset(for preset: ReverbPreset) -> AVAudioUnitReverbPreset {
        switch preset {
        case .smallRoom: .smallRoom
        case .hall: .largeHall
        case .ambient: .cathedral
        }
    }

    // MARK: - Transition envelope

    static func transitionEnvelope(
        for clip: MixrClip,
        at t: Double,
        bpm: Double
    ) -> (gain: Double, echoBoost: Double) {
        let clipStart = MixrTimeline.seconds(fromUnits: clip.start)
        let clipEnd = MixrTimeline.seconds(fromUnits: clip.start + clip.length)
        let clipLen = max(0.01, clipEnd - clipStart)
        let beat = 60.0 / bpm

        var gain = 1.0
        var echoBoost = 0.0

        switch clip.transitionIn.type {
        case .crossfade, .auto:
            let dur = min(clip.transitionIn.duration * beat, clipLen * 0.5)
            if dur > 0.01 {
                gain *= min(1.0, max(0.0, (t - clipStart) / dur))
            }
        case .none, .fadeOut, .echoOut:
            break
        }

        let outDur = min(clip.transitionOut.duration * beat, clipLen * 0.5)
        switch clip.transitionOut.type {
        case .fadeOut, .crossfade, .auto:
            if outDur > 0.01 {
                gain *= min(1.0, max(0.0, (clipEnd - t) / outDur))
            }
        case .echoOut:
            if outDur > 0.01 {
                let k = min(1.0, max(0.0, 1.0 - (clipEnd - t) / outDur))
                echoBoost = k * 32.0
                gain *= 1.0 - 0.30 * k
            }
        case .none:
            break
        }

        return (gain, echoBoost)
    }

    // MARK: - Master output protection

    static func makePeakLimiter() -> AVAudioUnitEffect {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }

    // MARK: - Export tail

    static func exportTailSeconds(tracks: [MixrTrack]) -> Double {
        var tail = 0.3
        for track in tracks where !track.isSFXTrack {
            let bpm = Double(track.bpm ?? 124)
            let beat = 60.0 / max(bpm, 1)
            for clip in track.clips {
                let fx = clip.effects
                if fx.level(for: MixrEffect.reverb.rawValue) > 0.5 {
                    let decay: Double
                    switch fx.reverbPreset {
                    case .smallRoom: decay = 1.2
                    case .hall: decay = 3.5
                    case .ambient: decay = 6.0
                    }
                    tail = max(tail, decay)
                }
                if fx.level(for: MixrEffect.echo.rawValue) > 0.5 {
                    tail = max(tail, min(6.0, beat * 8.0))
                }
                if clip.transitionOut.type == .echoOut {
                    tail = max(tail, min(6.0, beat * 8.0))
                }
            }
        }
        return min(tail, 8.0)
    }
}
