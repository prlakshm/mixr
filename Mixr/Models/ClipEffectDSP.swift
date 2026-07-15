import AVFoundation
import AudioToolbox

// MARK: - Clip Effect DSP Mapping
//
// SINGLE SOURCE OF TRUTH for turning a clip's stored effect state
// (ClipEffectSettings — slider levels 0…100 plus reverb/echo presets,
// stored on MixrClip.effects and persisted inside the project snapshot)
// into concrete AVAudioUnit parameters.
//
// Both consumers use exactly the same mapping so live playback and the
// exported file sound identical:
//
//   • MixrPlaybackEngine — live: computes ChainTargets every tick and
//     RAMPS the smoothable parameters toward them (no clicks/zipper).
//   • MixrExportRenderer — offline: computes ChainTargets per render
//     block and applies them directly.
//
// Effect chain order (fixed, per track chain):
//   player → timePitch (Pitch Up)
//         → EQ (Bass Boost multi-band + Blur low-pass)
//         → bass sat (subtle harmonics, upper slider half)
//         → delay (Echo) → reverb (Reverb)
//         → mixer → peak limiter → out
//
// Bass Boost is a multi-stage enhancer (not a single shelf):
//   band 0 low shelf · band 1 kick/sub bell · band 2 low-mid cut ·
//   optional harmonic saturation · output gain compensation.
// Slider uses shapedAmount = pow(amount, 1.6) so the upper half
// becomes clearly powerful while 0 stays true bypass.
//
// nonisolated: pure math over value types — callable from the live
// engine (main actor) and the background export render loop alike.
nonisolated enum ClipEffectDSP {

    // MARK: - Chain targets

    /// Concrete audio-unit parameter targets for one clip's effect chain.
    struct ChainTargets {
        // Pitch Up → AVAudioUnitTimePitch
        var pitchCents: Float
        var playbackRate: Float
        /// True bypass when Pitch Up is 0 and the clip plays at normal
        /// speed — the phase vocoder is skipped entirely.
        var timePitchBypass: Bool

        // Blur → AVAudioUnitEQ band 3 (low-pass)
        var lowPassFrequency: Float
        var lowPassBypass: Bool

        // Bass Boost → EQ bands 0–2 + optional saturation
        /// Low shelf @ ~110 Hz — overall bass weight.
        var bassShelfGainDB: Float
        /// Focused bell @ ~72 Hz — kick / sub punch.
        var bassPunchGainDB: Float
        /// Broad cut @ ~280 Hz — clears mud so vocals stay clear.
        var bassMudGainDB: Float
        /// True bypass when Bass Boost is 0 (all EQ bands + sat off).
        var bassBypass: Bool
        /// Distortion wet mix 0…100 — subtle harmonics for phone/laptop
        /// speakers; only rises in the upper half of the slider.
        var bassSaturationWet: Float
        var bassSaturationBypass: Bool

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
    ///
    /// - Parameters:
    ///   - settings: the clip's stored effect state (0…100 per effect).
    ///   - playbackSpeed: the clip's tempo multiplier — shares the
    ///     TimePitch unit with Pitch Up (rate is pitch-preserving).
    ///   - bpm: the track's tempo, used to sync echo repeats musically.
    ///   - echoBoost: extra delay wet mix pushed by echo-out transitions.
    static func targets(
        for settings: ClipEffectSettings,
        playbackSpeed: Double,
        bpm: Double,
        echoBoost: Double
    ) -> ChainTargets {
        // Normalize slider levels (0…100) to 0…1 amounts.
        let reverbAmount = settings.level(for: MixrEffect.reverb.rawValue) / 100.0
        let echoAmount = settings.level(for: MixrEffect.echo.rawValue) / 100.0
        let pitchAmount = settings.level(for: MixrEffect.pitchUp.rawValue) / 100.0
        let blurAmount = settings.level(for: MixrEffect.blur.rawValue) / 100.0
        let bassAmount = settings.level(for: MixrEffect.bassBoost.rawValue) / 100.0
        let rate = Float(max(playbackSpeed, 0.03125))

        // ── PITCH UP ──
        // sliderAmount × 1200 cents: 0 = original, 50% ≈ 6 semitones,
        // 100% = one octave. Duration is preserved (TimePitch, not rate).
        let pitchCents = Float(pitchAmount * 1200.0)
        let timePitchBypass = pitchAmount <= 0.001 && abs(playbackSpeed - 1.0) < 0.001

        // ── BLUR (low-pass) ──
        // Logarithmic cutoff sweep, perceptually eased with a 1.3 exponent:
        //   0% → 20 kHz (open) · 25% → ~11.4 kHz · 50% → ~5 kHz
        //   75% → ~1.9 kHz · 100% → 650 Hz (underwater)
        let lowPassBypass = blurAmount <= 0.001
        let eased = pow(blurAmount, 1.3)
        let lowPassFrequency = Float(20000.0 * pow(650.0 / 20000.0, eased))

        // ── BASS BOOST (multi-stage) ──
        // shapedAmount = pow(slider, 1.6) — lower half stays musical,
        // upper half climbs hard so 50% / 75% / 100% are unmistakable.
        //   25% → ~0.11 · 50% → ~0.33 · 75% → ~0.63 · 100% → 1.0
        let bassBypass = bassAmount <= 0.001
        let shaped = bassBypass ? 0.0 : pow(bassAmount, 1.6)

        // 1) Low shelf ~110 Hz — overall weight (max +14.5 dB).
        let bassShelfGainDB = Float(shaped * 14.5)
        // 2) Focused punch bell ~72 Hz — kick/sub impact (max +5.5 dB).
        let bassPunchGainDB = Float(shaped * 5.5)
        // 3) Broad low-mid cut ~280 Hz — prevents mud (max −3.5 dB).
        let bassMudGainDB = Float(shaped * -3.5)
        // 4) Harmonic sat — only the upper half of the slider, capped wet
        //    so it thickens phone/laptop bass without obvious fuzz.
        let satDrive = max(0.0, (shaped - 0.40) / 0.60)   // 0 below ~mid
        let bassSaturationWet = Float(satDrive * 12.0)     // 0…12% wet
        let bassSaturationBypass = bassSaturationWet < 0.05

        // ── ECHO (tempo-synced delay) ──
        // The slider drives wet mix AND feedback together: low = 1–2
        // subtle repeats, high = long stable trails. Feedback is capped
        // well below 100% so it can never build infinitely.
        let beat = 60.0 / max(bpm, 1)
        let delayTime: TimeInterval
        let feedbackBase: Double
        let feedbackSpan: Double
        let delayLowPass: Float
        switch settings.echoPreset {
        case .classic:
            // Centered quarter-note echo; repeats get quieter and softer.
            delayTime = beat * 1.0
            feedbackBase = 18; feedbackSpan = 34   // max 52%
            delayLowPass = 9000
        case .pingPong:
            // Eighth-note repeats with more feedback for obvious motion.
            // (AVAudioUnitDelay has no true alternating-pan tap — the
            // faster musically-timed repeat pattern approximates it.)
            delayTime = beat * 0.5
            feedbackBase = 25; feedbackSpan = 38   // max 63%
            delayLowPass = 10000
        case .reverse:
            // Reverse-feel: a dense 16th-note swarm with high feedback and
            // darkened repeats swells around the dry transient. A true
            // reversed pre-rendered wet tap is a future upgrade.
            delayTime = beat * 0.25
            feedbackBase = 35; feedbackSpan = 38   // max 73%
            delayLowPass = 7500
        }
        let delayFeedback = Float(echoAmount <= 0.001 ? 0 : feedbackBase + feedbackSpan * echoAmount)
        // Slightly eased wet curve; echo-out transitions add up to +32.
        let delayWet = Float(min(70.0, 50.0 * pow(echoAmount, 0.9) + echoBoost))

        // ── REVERB ──
        // The slider is the wet/dry mix into the selected space. Each
        // preset has its own ceiling so "high" stays immersive, not harsh:
        //   Small Room (short/intimate) → Apple .smallRoom, max 45% wet
        //   Hall (large/lush)           → Apple .largeHall, max 58% wet
        //   Ambient (dreamy/diffuse)    → Apple .cathedral, max 72% wet
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
            bassShelfGainDB: bassShelfGainDB,
            bassPunchGainDB: bassPunchGainDB,
            bassMudGainDB: bassMudGainDB,
            bassBypass: bassBypass,
            bassSaturationWet: bassSaturationWet,
            bassSaturationBypass: bassSaturationBypass,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayWetDryMix: delayWet,
            delayLowPassCutoff: delayLowPass,
            reverbPreset: settings.reverbPreset,
            reverbWetDryMix: reverbWet
        )
    }

    /// Linear gain multiplier that pulls the clip's level down as Bass
    /// Boost rises, so the multi-stage EQ adds low-end weight instead of
    /// raw loudness (≈ −4.5 dB at maximum). Applied to the player volume
    /// alongside track × clip × transition gain.
    static func outputCompensation(for settings: ClipEffectSettings) -> Double {
        let bassAmount = settings.level(for: MixrEffect.bassBoost.rawValue) / 100.0
        guard bassAmount > 0.001 else { return 1.0 }
        let shaped = pow(bassAmount, 1.6)
        let compensationDB = shaped * 4.5
        return pow(10.0, -compensationDB / 20.0)
    }

    /// Factory for the subtle Bass Boost harmonic stage. Uses a soft
    /// multi-band distortion preset at very low wet mix — enough to lift
    /// bass on small speakers, not enough to sound fuzzy.
    static func makeBassSaturator() -> AVAudioUnitDistortion {
        let unit = AVAudioUnitDistortion()
        // Mild factory tone — wet mix stays ≤12%, so this only adds
        // harmonics rather than an obvious lo-fi grit.
        unit.loadFactoryPreset(.drumsBitBrush)
        unit.wetDryMix = 0
        unit.preGain = -10
        unit.bypass = true
        return unit
    }

    /// Configures a clip chain's audio units into their bypassed rest
    /// state (all effects at 0 = bit-identical passthrough). Called once
    /// per chain by both the live engine and the export renderer.
    static func configureRestState(
        timePitch: AVAudioUnitTimePitch,
        eq: AVAudioUnitEQ,
        bassSat: AVAudioUnitDistortion,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb
    ) {
        timePitch.pitch = 0
        timePitch.rate = 1
        timePitch.bypass = true

        // Band 0: low shelf — overall bass weight.
        let shelf = eq.bands[0]
        shelf.filterType = .lowShelf
        shelf.frequency = 110
        shelf.gain = 0
        shelf.bypass = true

        // Band 1: focused punch bell — kick / sub impact.
        let punch = eq.bands[1]
        punch.filterType = .parametric
        punch.frequency = 72
        punch.bandwidth = 0.85   // moderate Q — punchy, not resonant
        punch.gain = 0
        punch.bypass = true

        // Band 2: broad low-mid cut — clears mud under vocals.
        let mud = eq.bands[2]
        mud.filterType = .parametric
        mud.frequency = 280
        mud.bandwidth = 1.8      // broad Q
        mud.gain = 0
        mud.bypass = true

        // Band 3: Blur low-pass.
        let lowPass = eq.bands[3]
        lowPass.filterType = .lowPass
        lowPass.frequency = 20000
        lowPass.bandwidth = 0.7  // gentle slope — no whistle at the cutoff
        lowPass.bypass = true

        bassSat.loadFactoryPreset(.drumsBitBrush)
        bassSat.wetDryMix = 0
        bassSat.preGain = -10
        bassSat.bypass = true

        delay.wetDryMix = 0
        delay.feedback = 0
        delay.lowPassCutoff = 9000
        delay.bypass = true

        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 0
        reverb.bypass = true
    }

    /// Applies targets directly (no smoothing) — used by the offline
    /// export renderer at block boundaries. `appliedReverbPreset` /
    /// `appliedDelayTime` avoid redundant factory-preset reloads and
    /// delay-line time jumps.
    static func apply(
        _ t: ChainTargets,
        timePitch: AVAudioUnitTimePitch,
        eq: AVAudioUnitEQ,
        bassSat: AVAudioUnitDistortion,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb,
        appliedReverbPreset: inout ReverbPreset?,
        appliedDelayTime: inout TimeInterval
    ) {
        timePitch.pitch = t.pitchCents
        timePitch.rate = t.playbackRate
        // One-directional: bypassing the phase vocoder changes its latency,
        // so once it is active it stays active for the rest of the render.
        if !t.timePitchBypass { timePitch.bypass = false }

        // ── Bass Boost multi-band ──
        let shelf = eq.bands[0]
        shelf.gain = t.bassBypass ? 0 : t.bassShelfGainDB
        shelf.bypass = t.bassBypass

        let punch = eq.bands[1]
        punch.gain = t.bassBypass ? 0 : t.bassPunchGainDB
        punch.bypass = t.bassBypass

        let mud = eq.bands[2]
        mud.gain = t.bassBypass ? 0 : t.bassMudGainDB
        mud.bypass = t.bassBypass

        bassSat.wetDryMix = t.bassSaturationWet
        if t.bassSaturationBypass {
            bassSat.bypass = true
        } else {
            bassSat.bypass = false
        }

        // ── Blur ──
        let lowPass = eq.bands[3]
        lowPass.frequency = t.lowPassFrequency
        lowPass.bypass = t.lowPassBypass

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

    /// Mixr preset → Apple factory reverb space.
    static func factoryPreset(for preset: ReverbPreset) -> AVAudioUnitReverbPreset {
        switch preset {
        case .smallRoom: .smallRoom     // short, intimate (~0.5 s decay)
        case .hall: .largeHall          // spacious, lush (~2–3 s decay)
        case .ambient: .cathedral       // diffuse, ethereal (~4–6 s decay)
        }
    }

    // MARK: - Transition envelope

    /// Volume gain (0…1) plus an extra delay-wet boost for echo-out tails.
    /// ClipTransition.duration is in beats (matching the transition UI).
    /// Shared by live playback (per tick) and export (per render block).
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

        // Entry ramp
        switch clip.transitionIn.type {
        case .crossfade, .auto:
            let dur = min(clip.transitionIn.duration * beat, clipLen * 0.5)
            if dur > 0.01 {
                gain *= min(1.0, max(0.0, (t - clipStart) / dur))
            }
        case .none, .fadeOut, .echoOut:
            break
        }

        // Exit ramp
        let outDur = min(clip.transitionOut.duration * beat, clipLen * 0.5)
        switch clip.transitionOut.type {
        case .fadeOut, .crossfade, .auto:
            if outDur > 0.01 {
                gain *= min(1.0, max(0.0, (clipEnd - t) / outDur))
            }
        case .echoOut:
            if outDur > 0.01 {
                let k = min(1.0, max(0.0, 1.0 - (clipEnd - t) / outDur))
                echoBoost = k * 32.0        // push the delay wet mix
                gain *= 1.0 - 0.30 * k      // ease under the incoming song
            }
        case .none:
            break
        }

        return (gain, echoBoost)
    }

    // MARK: - Master output protection

    /// Apple's transparent peak limiter — sits after the main mixer in
    /// both the live engine and the export engine so combined boosted
    /// clips cannot clip the output.
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

    /// Extra seconds to render past the last clip so reverb/echo tails
    /// decay naturally in the exported file instead of being cut off.
    static func exportTailSeconds(tracks: [MixrTrack]) -> Double {
        var tail = 0.3   // always leave a little breathing room
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
                    // Enough repeats for the feedback trail to fall away.
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
