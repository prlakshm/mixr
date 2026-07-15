import AVFoundation
import Combine

// MARK: - Playback Engine
//
// Real DSP graph — every song track renders through its own effect chain:
//
//   player → timePitch → EQ (bass multi-band + blur LPF) → bass sat
//          → delay → reverb → mainMixer → peak limiter → output
//
// All clips of a track are scheduled (not just the first). Per-clip volume,
// effect settings (MixrClip.effects — see ClipEffectSettings), and transition
// envelopes are applied live by a 60 fps parameter tick:
//
//   • Each tick finds the clip under the playhead on every track and maps
//     that clip's stored slider levels/presets to audio-unit parameters via
//     ClipEffectDSP (the same mapping MixrExportRenderer uses offline, so
//     playback and export sound identical).
//   • Smoothable parameters (wet mixes, EQ gain/frequency, pitch, volume)
//     are RAMPED toward their targets instead of jumped, so live slider
//     moves are click-free and clip boundaries don't pop.
//   • Effects at 0 resolve to true bypasses (EQ band/vocoder/sat bypass,
//     0 wet) so untouched clips pay no processing cost and sound
//     bit-identical.
//   • The SFX track plays real audio buffers (bundled generated assets,
//     procedurally synthesized as a fallback).
//
// A master peak limiter after the main mixer protects the summed output
// when several boosted clips overlap.

@MainActor
final class MixrPlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var totalDurationSeconds: Double = 0

    private let engine = AVAudioEngine()
    /// Master output protection — mainMixer → limiter → output. Keeps the
    /// summed mix transparent when several boosted clips overlap.
    private let limiter = ClipEffectDSP.makePeakLimiter()
    private var limiterInstalled = false
    private var chains: [UUID: TrackChain] = [:]
    private var sfxChain: SFXChain?
    private var sfxBufferCache: [String: AVAudioPCMBuffer] = [:]

    /// (timelineSeconds at sync point, wall-clock seconds at sync point)
    private var anchor: (timeline: Double, wall: Double)?
    private var ticker: Timer?
    private var snapshot: [MixrTrack] = []
    private var audioSessionReady = false

    // MARK: - Per-track effect chain

    private final class TrackChain {
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        /// 4 bands: 0 shelf · 1 punch bell · 2 mud cut · 3 Blur LPF.
        let eq = AVAudioUnitEQ(numberOfBands: 4)
        /// Subtle harmonic stage for Bass Boost (upper slider half).
        let bassSat = ClipEffectDSP.makeBassSaturator()
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        let file: AVAudioFile
        let url: URL
        let securityScoped: Bool

        // Live-parameter state (tick-driven). Smoothable parameters ramp
        // toward their ClipEffectDSP targets each tick so slider moves and
        // clip boundaries never click or zipper.
        var appliedClipID: UUID?
        var appliedReverbPreset: ReverbPreset?
        var appliedDelayTime: TimeInterval = 0
        var smoothedVolume: Float = 0
        var smoothedPitch: Float = 0
        var smoothedLowPassFreq: Float = 20000
        var smoothedBassShelf: Float = 0
        var smoothedBassPunch: Float = 0
        var smoothedBassMud: Float = 0
        var smoothedBassSatWet: Float = 0
        var smoothedDelayWet: Float = 0
        var smoothedDelayFeedback: Float = 0
        var smoothedReverbWet: Float = 0

        init(file: AVAudioFile, url: URL, securityScoped: Bool) {
            self.file = file
            self.url = url
            self.securityScoped = securityScoped
        }

        var allNodes: [AVAudioNode] { [player, timePitch, eq, bassSat, delay, reverb] }
    }

    private final class SFXChain {
        let player = AVAudioPlayerNode()
        var format: AVAudioFormat?
        var smoothedVolume: Float = 0
    }

    // MARK: - Public API

    /// Full sync: called when tracks are added, removed, or clip geometry changes.
    func syncTracks(_ tracks: [MixrTrack]) {
        snapshot = tracks
        totalDurationSeconds = MixrTimeline.remixDurationSeconds(tracks: tracks)

        if tracks.isEmpty && isPlaying { pause() }

        if currentTimeSeconds > totalDurationSeconds {
            currentTimeSeconds = totalDurationSeconds
            if isPlaying { pause() }
        }

        // Remove chains whose track was deleted
        let live = Set(tracks.map(\.id))
        for id in chains.keys where !live.contains(id) {
            removeChain(id: id)
        }

        // Defer AVAudioEngine graph construction so launch UI can paint first.
        let pendingAdds = tracks.filter { !$0.isSFXTrack && chains[$0.id] == nil }
        guard !pendingAdds.isEmpty else {
            if isPlaying { startPlayback(from: currentTimeSeconds) }
            return
        }

        Task { @MainActor in
            await Task.yield()
            for track in pendingAdds where chains[track.id] == nil {
                addChain(for: track)
            }
            if isPlaying {
                startPlayback(from: currentTimeSeconds)
            }
        }
    }

    /// Lightweight sync: mix settings (volume/mute/solo) or per-clip
    /// settings (effect levels, presets, clip volume, transitions)
    /// changed. No reschedule needed — while playing the 60 fps tick
    /// picks the new snapshot up and ramps parameters live, so effect
    /// slider moves are audible immediately without restarting playback.
    func applyMixSettings(from tracks: [MixrTrack]) {
        snapshot = tracks
        if !isPlaying {
            // Keep node parameters current so play() starts correct.
            applyTickParameters(at: currentTimeSeconds, force: true)
        }
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        guard totalDurationSeconds > 0 else { return }
        if currentTimeSeconds >= totalDurationSeconds { currentTimeSeconds = 0 }
        startPlayback(from: currentTimeSeconds)
    }

    func pause() {
        if isPlaying { syncAnchorToCurrentTime() }
        stopAllNodes()
        if engine.isRunning { engine.pause() }
        isPlaying = false
        anchor = nil
        stopTicker()
    }

    func seek(to seconds: Double) {
        let t = seconds.clamped(to: 0...totalDurationSeconds)
        currentTimeSeconds = t
        if isPlaying { startPlayback(from: t) }
    }

    func skipToStart() { seek(to: 0) }

    func skipToEnd() {
        currentTimeSeconds = totalDurationSeconds
        if isPlaying { pause() }
    }

    // MARK: - Graph construction

    private func setupAudioSession() {
        guard !audioSessionReady else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default)
            try s.setActive(true)
            audioSessionReady = true
        } catch {
            print("MixrPlaybackEngine: AVAudioSession error — \(error.localizedDescription)")
        }
    }

    /// Reroutes mainMixer → peak limiter → output (once). Output gain
    /// protection for combined boosted clips — mirrored in export.
    private func installLimiterIfNeeded() {
        guard !limiterInstalled else { return }
        limiterInstalled = true
        engine.attach(limiter)
        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)
    }

    private func addChain(for track: MixrTrack) {
        guard let url = track.url else { return }
        setupAudioSession()
        installLimiterIfNeeded()
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let file = try AVAudioFile(forReading: url)
            let chain = TrackChain(file: file, url: url, securityScoped: scoped)

            // Configure the chain's units into their bypassed rest state.
            // ClipEffectDSP drives every parameter from the clip under the
            // playhead — see applyEffects(clip:chain:...).
            ClipEffectDSP.configureRestState(
                timePitch: chain.timePitch,
                eq: chain.eq,
                bassSat: chain.bassSat,
                delay: chain.delay,
                reverb: chain.reverb
            )
            chain.appliedReverbPreset = .smallRoom

            for node in chain.allNodes { engine.attach(node) }
            let fmt = file.processingFormat
            engine.connect(chain.player, to: chain.timePitch, format: fmt)
            engine.connect(chain.timePitch, to: chain.eq, format: fmt)
            engine.connect(chain.eq, to: chain.bassSat, format: fmt)
            engine.connect(chain.bassSat, to: chain.delay, format: fmt)
            engine.connect(chain.delay, to: chain.reverb, format: fmt)
            engine.connect(chain.reverb, to: engine.mainMixerNode, format: fmt)

            chains[track.id] = chain
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            print("MixrPlaybackEngine: cannot load \(url.lastPathComponent) — \(error.localizedDescription)")
        }
    }

    private func removeChain(id: UUID) {
        guard let chain = chains.removeValue(forKey: id) else { return }
        chain.player.stop()
        for node in chain.allNodes { engine.detach(node) }
        if chain.securityScoped { chain.url.stopAccessingSecurityScopedResource() }
    }

    private func ensureSFXChain(format: AVAudioFormat) -> SFXChain {
        if let sfxChain, sfxChain.format == format { return sfxChain }
        if let old = sfxChain {
            old.player.stop()
            engine.detach(old.player)
        }
        let chain = SFXChain()
        chain.format = format
        engine.attach(chain.player)
        engine.connect(chain.player, to: engine.mainMixerNode, format: format)
        sfxChain = chain
        return chain
    }

    // MARK: - SFX buffers (bundled assets, synthesized fallback)

    private func sfxBuffer(for definition: SoundEffectDefinition) -> AVAudioPCMBuffer? {
        if let cached = sfxBufferCache[definition.id] { return cached }

        var buffer: AVAudioPCMBuffer?
        let base = (definition.assetName as NSString).deletingPathExtension
        let url = Bundle.main.url(forResource: base, withExtension: "wav")
            ?? Bundle.main.url(forResource: base, withExtension: "wav", subdirectory: "SFX")
            ?? Bundle.main.url(forResource: base, withExtension: "wav", subdirectory: "Resources/SFX")

        if let url,
           let file = try? AVAudioFile(forReading: url),
           let loaded = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
           ),
           (try? file.read(into: loaded)) != nil {
            buffer = loaded
        } else {
            // Asset missing — regenerate procedurally so SFX never fail silently.
            buffer = SFXSynthesizer.buffer(for: definition)
        }

        sfxBufferCache[definition.id] = buffer
        return buffer
    }

    /// Sub-range copy used when the playhead starts inside an SFX clip.
    private func slice(_ buffer: AVAudioPCMBuffer, fromFrame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        let total = AVAudioFramePosition(buffer.frameLength)
        guard fromFrame > 0 else { return buffer }
        guard fromFrame < total,
              let out = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: AVAudioFrameCount(total - fromFrame)
              )
        else { return nil }
        let frames = Int(total - fromFrame)
        out.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<Int(buffer.format.channelCount) {
            if let src = buffer.floatChannelData?[ch], let dst = out.floatChannelData?[ch] {
                dst.update(from: src + Int(fromFrame), count: frames)
            }
        }
        return out
    }

    // MARK: - Playback scheduling

    private func startPlayback(from timelineSeconds: Double) {
        // ── 1. Tear down previous playback ──
        stopAllNodes()

        // ── 2. Start engine FIRST (nodes cannot render on a stopped engine) ──
        setupAudioSession()
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                print("MixrPlaybackEngine: engine.start() failed — \(error.localizedDescription)")
                return
            }
        }

        // ── 3. Common host-time sync point 50 ms out ──
        let bufferSec  = 0.05
        let syncTicks  = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: bufferSec)
        let syncWall   = CACurrentMediaTime() + bufferSec
        var scheduled  = false

        // ── 4. Song tracks: schedule EVERY clip as a segment ──
        for track in snapshot where !track.isSFXTrack {
            guard let chain = chains[track.id] else { continue }
            let sr = chain.file.processingFormat.sampleRate
            let fileFrames = chain.file.length
            var trackHasAudio = false

            for clip in track.clips.sorted(by: { $0.start < $1.start }) {
                let clipStart = MixrTimeline.seconds(fromUnits: clip.start)
                let clipEnd = MixrTimeline.seconds(fromUnits: clip.start + clip.length)
                guard timelineSeconds < clipEnd else { continue }

                let speed = max(clip.playbackSpeed, 0.0001)
                let intoClipSec = max(0, timelineSeconds - clipStart)
                let sourceStartSec = clip.sourceOffsetSeconds + intoClipSec * speed
                let timelinePlayableSec = clipEnd - max(timelineSeconds, clipStart)
                var sourceSec = timelinePlayableSec * speed

                let startFrame = AVAudioFramePosition(sourceStartSec * sr)
                guard startFrame < fileFrames else { continue }
                sourceSec = min(sourceSec, Double(fileFrames - startFrame) / sr)
                let frames = AVAudioFrameCount(max(0, sourceSec * sr))
                guard frames > 0 else { continue }

                // Downstream timePitch stretches output by 1/rate — schedule
                // delays in the player's INPUT timeline (delay × rate).
                // Exact for uniform-rate tracks (imports and beatmatched
                // songs); mixed per-clip speeds drift slightly — accepted V1
                // limitation until per-clip sub-chains land.
                let delaySec = max(0, clipStart - timelineSeconds) * speed
                let nodeTime = AVAudioTime(hostTime: syncTicks + AVAudioTime.hostTime(forSeconds: delaySec))

                chain.player.scheduleSegment(
                    chain.file,
                    startingFrame: startFrame,
                    frameCount: frames,
                    at: nodeTime
                )
                trackHasAudio = true
            }

            if trackHasAudio {
                chain.player.play()
                scheduled = true
            }
        }

        // ── 5. SFX track: schedule each clip's buffer at its host time ──
        if let sfxTrack = snapshot.first(where: { $0.isSFXTrack }) {
            var pending: [(buffer: AVAudioPCMBuffer, delaySec: Double)] = []

            for clip in sfxTrack.clips.sorted(by: { $0.start < $1.start }) {
                guard let effectID = clip.soundEffectID,
                      let definition = SoundEffectLibrary.definition(for: effectID),
                      let full = sfxBuffer(for: definition)
                else { continue }

                let clipStart = MixrTimeline.seconds(fromUnits: clip.start)
                let clipEnd = MixrTimeline.seconds(fromUnits: clip.start + clip.length)
                guard timelineSeconds < clipEnd else { continue }

                if timelineSeconds > clipStart {
                    // Playhead is inside this SFX — play the remainder.
                    let offsetFrames = AVAudioFramePosition(
                        (timelineSeconds - clipStart) * full.format.sampleRate
                    )
                    if let part = slice(full, fromFrame: offsetFrames) {
                        pending.append((part, 0))
                    }
                } else {
                    pending.append((full, clipStart - timelineSeconds))
                }
            }

            if let format = pending.first?.buffer.format {
                let chain = ensureSFXChain(format: format)
                for item in pending where item.buffer.format == format {
                    chain.player.scheduleBuffer(
                        item.buffer,
                        at: AVAudioTime(hostTime: syncTicks + AVAudioTime.hostTime(forSeconds: item.delaySec))
                    )
                }
                chain.player.play()
                scheduled = true
            }
        }

        guard scheduled else {
            if engine.isRunning { engine.pause() }
            return
        }

        // ── 6. Anchor, first parameter pass, ticker ──
        anchor = (timelineSeconds, syncWall)
        isPlaying = true
        applyTickParameters(at: timelineSeconds, force: true)

        // Pre-arm the playback rate for tracks whose next clip starts later:
        // segment delays were scheduled in the player's INPUT timeline
        // (delay × rate), which assumes the clip's rate is in effect from
        // the sync point — not only once the clip is reached.
        for track in snapshot where !track.isSFXTrack {
            guard let chain = chains[track.id] else { continue }
            let underPlayhead = track.clips.contains { clip in
                !clip.isSoundEffect
                    && timelineSeconds >= MixrTimeline.seconds(fromUnits: clip.start)
                    && timelineSeconds < MixrTimeline.seconds(fromUnits: clip.start + clip.length)
            }
            if !underPlayhead,
               let next = track.clips
                   .filter({ !$0.isSoundEffect && MixrTimeline.seconds(fromUnits: $0.start) >= timelineSeconds })
                   .min(by: { $0.start < $1.start }) {
                chain.timePitch.rate = Float(max(next.playbackSpeed, 0.03125))
                if abs(next.playbackSpeed - 1.0) >= 0.001 { chain.timePitch.bypass = false }
            }
        }

        startTicker()
    }

    private func stopAllNodes() {
        for chain in chains.values { chain.player.stop() }
        sfxChain?.player.stop()
    }

    // MARK: - Live parameters (60 fps)
    // Per tick: find the clip under the playhead on each track and drive
    // volume (track × clip × transition envelope × audibility) plus the
    // effect chain from that clip's settings. Light smoothing avoids
    // zipper noise on volume moves.

    private func applyTickParameters(at t: Double, force: Bool = false) {
        let soloAware = snapshot

        for track in snapshot where !track.isSFXTrack {
            guard let chain = chains[track.id] else { continue }
            let audible = TrackLibrary.isAudible(track, in: soloAware)
            let bpm = Double(track.bpm ?? 124)

            let clip = track.clips.first { clip in
                !clip.isSoundEffect
                    && t >= MixrTimeline.seconds(fromUnits: clip.start)
                    && t < MixrTimeline.seconds(fromUnits: clip.start + clip.length)
            }

            var targetVolume: Float = 0
            if let clip, audible {
                let envelope = ClipEffectDSP.transitionEnvelope(for: clip, at: t, bpm: bpm)
                // Bass Boost pulls the clip level down slightly so the
                // shelf adds low-end weight rather than raw loudness.
                let compensation = ClipEffectDSP.outputCompensation(for: clip.effects)
                targetVolume = Float(track.volume * clip.volume * envelope.gain * compensation)
                applyEffects(clip: clip, chain: chain, bpm: bpm, echoBoost: envelope.echoBoost, force: force)
            } else if audible {
                // Between clips: silent input, but let delay/reverb tails ring.
                chain.appliedClipID = nil
            }

            if force {
                chain.smoothedVolume = targetVolume
            } else {
                chain.smoothedVolume += (targetVolume - chain.smoothedVolume) * 0.45
            }
            chain.player.volume = chain.smoothedVolume
        }

        if let sfxTrack = snapshot.first(where: { $0.isSFXTrack }), let sfxChain {
            let audible = TrackLibrary.isAudible(sfxTrack, in: soloAware)
            let target: Float = audible ? Float(sfxTrack.volume) : 0
            if force {
                sfxChain.smoothedVolume = target
            } else {
                sfxChain.smoothedVolume += (target - sfxChain.smoothedVolume) * 0.45
            }
            sfxChain.player.volume = sfxChain.smoothedVolume
        }
    }

    /// Drives this track chain's audio units from the clip under the
    /// playhead. Targets come from ClipEffectDSP (the shared slider→
    /// parameter mapping); smoothable values ramp toward them each tick
    /// (~55 ms time constant at 60 fps) so live slider moves and clip
    /// boundaries never click. `force` snaps instantly (playback start,
    /// seek) — a fresh schedule has no audible state to protect.
    private func applyEffects(
        clip: MixrClip,
        chain: TrackChain,
        bpm: Double,
        echoBoost: Double,
        force: Bool
    ) {
        let t = ClipEffectDSP.targets(
            for: clip.effects,
            playbackSpeed: clip.playbackSpeed,
            bpm: bpm,
            echoBoost: echoBoost
        )
        let coeff: Float = force ? 1.0 : 0.28

        // ── Pitch Up (AVAudioUnitTimePitch) ──
        // Pitch ramps in cents → smooth glide between slider values.
        chain.smoothedPitch += (t.pitchCents - chain.smoothedPitch) * coeff
        if abs(t.pitchCents - chain.smoothedPitch) < 0.5 { chain.smoothedPitch = t.pitchCents }
        chain.timePitch.pitch = chain.smoothedPitch
        chain.timePitch.rate = t.playbackRate
        // Bypassing the phase vocoder changes its latency, so only
        // re-engage the bypass on force applies (start/seek) — engaging
        // it mid-stream would cause an audible timing jump.
        let pitchAtRest = t.timePitchBypass && chain.smoothedPitch == 0
        if !pitchAtRest {
            chain.timePitch.bypass = false
        } else if force {
            chain.timePitch.bypass = true
        }

        // ── Blur (EQ band 3 low-pass) — ramp the cutoff in the log domain ──
        let lowPass = chain.eq.bands[3]
        if chain.smoothedLowPassFreq > 0 {
            chain.smoothedLowPassFreq *= pow(t.lowPassFrequency / chain.smoothedLowPassFreq, coeff)
        } else {
            chain.smoothedLowPassFreq = t.lowPassFrequency
        }
        if abs(t.lowPassFrequency - chain.smoothedLowPassFreq) < 1 {
            chain.smoothedLowPassFreq = t.lowPassFrequency
        }
        lowPass.frequency = chain.smoothedLowPassFreq
        lowPass.bypass = t.lowPassBypass && chain.smoothedLowPassFreq >= 19_999

        // ── Bass Boost (multi-band EQ + subtle sat) ──
        chain.smoothedBassShelf += (t.bassShelfGainDB - chain.smoothedBassShelf) * coeff
        if abs(t.bassShelfGainDB - chain.smoothedBassShelf) < 0.02 {
            chain.smoothedBassShelf = t.bassShelfGainDB
        }
        chain.smoothedBassPunch += (t.bassPunchGainDB - chain.smoothedBassPunch) * coeff
        if abs(t.bassPunchGainDB - chain.smoothedBassPunch) < 0.02 {
            chain.smoothedBassPunch = t.bassPunchGainDB
        }
        chain.smoothedBassMud += (t.bassMudGainDB - chain.smoothedBassMud) * coeff
        if abs(t.bassMudGainDB - chain.smoothedBassMud) < 0.02 {
            chain.smoothedBassMud = t.bassMudGainDB
        }
        chain.smoothedBassSatWet += (t.bassSaturationWet - chain.smoothedBassSatWet) * coeff
        if abs(t.bassSaturationWet - chain.smoothedBassSatWet) < 0.05 {
            chain.smoothedBassSatWet = t.bassSaturationWet
        }

        let bassAtRest = t.bassBypass
            && chain.smoothedBassShelf == 0
            && chain.smoothedBassPunch == 0
            && abs(chain.smoothedBassMud) < 0.02

        let shelf = chain.eq.bands[0]
        shelf.gain = chain.smoothedBassShelf
        shelf.bypass = bassAtRest

        let punch = chain.eq.bands[1]
        punch.gain = chain.smoothedBassPunch
        punch.bypass = bassAtRest

        let mud = chain.eq.bands[2]
        mud.gain = chain.smoothedBassMud
        mud.bypass = bassAtRest

        chain.bassSat.wetDryMix = chain.smoothedBassSatWet
        if chain.smoothedBassSatWet > 0.05 {
            chain.bassSat.bypass = false
        } else if force || t.bassSaturationBypass {
            chain.bassSat.bypass = true
        }

        // ── Echo (AVAudioUnitDelay) ──
        // Wet mix and feedback ramp; delay TIME is set only when the
        // preset/BPM changes (time jumps smear the delay line audibly).
        if chain.appliedDelayTime != t.delayTime {
            chain.delay.delayTime = t.delayTime
            chain.appliedDelayTime = t.delayTime
        }
        chain.smoothedDelayWet += (t.delayWetDryMix - chain.smoothedDelayWet) * coeff
        if abs(t.delayWetDryMix - chain.smoothedDelayWet) < 0.05 { chain.smoothedDelayWet = t.delayWetDryMix }
        chain.smoothedDelayFeedback += (t.delayFeedback - chain.smoothedDelayFeedback) * coeff
        if abs(t.delayFeedback - chain.smoothedDelayFeedback) < 0.05 { chain.smoothedDelayFeedback = t.delayFeedback }
        chain.delay.lowPassCutoff = t.delayLowPassCutoff
        chain.delay.wetDryMix = chain.smoothedDelayWet
        chain.delay.feedback = chain.smoothedDelayFeedback
        // Un-bypass the moment any wet is requested; never re-bypass
        // mid-flight (that would cut a ringing tail abruptly).
        if chain.smoothedDelayWet > 0.01 { chain.delay.bypass = false }

        // ── Reverb (AVAudioUnitReverb) ──
        if chain.appliedReverbPreset != t.reverbPreset {
            chain.reverb.loadFactoryPreset(ClipEffectDSP.factoryPreset(for: t.reverbPreset))
            chain.appliedReverbPreset = t.reverbPreset
        }
        chain.smoothedReverbWet += (t.reverbWetDryMix - chain.smoothedReverbWet) * coeff
        if abs(t.reverbWetDryMix - chain.smoothedReverbWet) < 0.05 { chain.smoothedReverbWet = t.reverbWetDryMix }
        chain.reverb.wetDryMix = chain.smoothedReverbWet
        if chain.smoothedReverbWet > 0.01 { chain.reverb.bypass = false }

        chain.appliedClipID = clip.id
    }

    // MARK: - Timer

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isPlaying else { return }
        syncAnchorToCurrentTime()
        applyTickParameters(at: currentTimeSeconds)
        if currentTimeSeconds >= totalDurationSeconds {
            pause()
            currentTimeSeconds = totalDurationSeconds
        }
    }

    private func syncAnchorToCurrentTime() {
        guard let a = anchor else { return }
        let elapsed = CACurrentMediaTime() - a.wall
        currentTimeSeconds = min(a.timeline + elapsed, totalDurationSeconds)
    }
}

// MARK: - Comparable clamp helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
