import AVFoundation
import Combine

// MARK: - Playback Engine
//
// Real DSP graph — every song track renders through its own effect chain:
//
//   player → timePitch → EQ (bass shelf + blur low-pass) → delay → reverb → mixer
//
// All clips of a track are scheduled (not just the first), per-clip volume /
// effect settings / transition envelopes are applied live by a 60 fps
// parameter tick, and the SFX track plays real audio buffers (bundled
// generated assets, procedurally synthesized as a fallback).

@MainActor
final class MixrPlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var totalDurationSeconds: Double = 0

    private let engine = AVAudioEngine()
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
        let eq = AVAudioUnitEQ(numberOfBands: 2)
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        let file: AVAudioFile
        let url: URL
        let securityScoped: Bool

        // Live-parameter state (tick-driven)
        var appliedClipID: UUID?
        var appliedReverbPreset: ReverbPreset?
        var smoothedVolume: Float = 0

        init(file: AVAudioFile, url: URL, securityScoped: Bool) {
            self.file = file
            self.url = url
            self.securityScoped = securityScoped
        }

        var allNodes: [AVAudioNode] { [player, timePitch, eq, delay, reverb] }
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

    /// Lightweight sync: volume/mute/solo changed. The tick applies it live.
    func applyMixSettings(from tracks: [MixrTrack]) {
        snapshot = tracks
        if !isPlaying {
            // Keep node volumes roughly current so play() starts correct.
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

    private func addChain(for track: MixrTrack) {
        guard let url = track.url else { return }
        setupAudioSession()
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let file = try AVAudioFile(forReading: url)
            let chain = TrackChain(file: file, url: url, securityScoped: scoped)

            // Band 0: bass shelf (Bass Boost). Band 1: resonant low-pass (Blur).
            let bass = chain.eq.bands[0]
            bass.filterType = .lowShelf
            bass.frequency = 110
            bass.gain = 0
            bass.bypass = true
            let lowPass = chain.eq.bands[1]
            lowPass.filterType = .lowPass
            lowPass.frequency = 20000
            lowPass.bandwidth = 0.8
            lowPass.bypass = true

            chain.delay.wetDryMix = 0
            chain.delay.feedback = 40
            chain.delay.lowPassCutoff = 12000
            chain.reverb.loadFactoryPreset(.mediumHall)
            chain.reverb.wetDryMix = 0

            for node in chain.allNodes { engine.attach(node) }
            let fmt = file.processingFormat
            engine.connect(chain.player, to: chain.timePitch, format: fmt)
            engine.connect(chain.timePitch, to: chain.eq, format: fmt)
            engine.connect(chain.eq, to: chain.delay, format: fmt)
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
                let envelope = Self.transitionEnvelope(for: clip, at: t, bpm: bpm)
                targetVolume = Float(track.volume * clip.volume * envelope.gain)
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

    /// Maps a clip's stored settings onto the chain's audio units.
    private func applyEffects(
        clip: MixrClip,
        chain: TrackChain,
        bpm: Double,
        echoBoost: Double,
        force: Bool
    ) {
        let clipChanged = chain.appliedClipID != clip.id || force
        let fx = clip.effects

        // Blur — resonant low-pass rolling the top end off (20 kHz → ~350 Hz).
        let blur = fx.level(for: MixrEffect.blur.rawValue)
        let lowPass = chain.eq.bands[1]
        if blur > 0.5 {
            lowPass.bypass = false
            lowPass.frequency = Float(20000.0 * pow(350.0 / 20000.0, blur / 100.0))
        } else {
            lowPass.bypass = true
        }

        // Bass Boost — low shelf up to +9 dB.
        let bass = fx.level(for: MixrEffect.bassBoost.rawValue)
        let shelf = chain.eq.bands[0]
        if bass > 0.5 {
            shelf.bypass = false
            shelf.gain = Float(bass / 100.0 * 9.0)
        } else {
            shelf.bypass = true
        }

        // Reverb — wet mix 0…50%, preset per clip.
        let reverbLevel = fx.level(for: MixrEffect.reverb.rawValue)
        if clipChanged, chain.appliedReverbPreset != fx.reverbPreset {
            chain.reverb.loadFactoryPreset(Self.reverbPreset(fx.reverbPreset))
            chain.appliedReverbPreset = fx.reverbPreset
        }
        chain.reverb.wetDryMix = Float(reverbLevel / 100.0 * 50.0)

        // Echo — tempo-synced delay; echo-out transitions push the wet mix.
        let echoLevel = fx.level(for: MixrEffect.echo.rawValue)
        let beat = 60.0 / bpm
        chain.delay.delayTime = Self.delayTime(for: fx.echoPreset, beatSeconds: beat)
        chain.delay.feedback = Self.delayFeedback(for: fx.echoPreset)
        chain.delay.wetDryMix = Float(min(70.0, echoLevel / 100.0 * 45.0 + echoBoost))

        // Pitch Up — 0…+12 semitones, pitch-preserving rate for tempo.
        let pitch = fx.level(for: MixrEffect.pitchUp.rawValue)
        chain.timePitch.pitch = Float(pitch / 100.0 * 1200.0)
        chain.timePitch.rate = Float(max(clip.playbackSpeed, 0.03125))

        chain.appliedClipID = clip.id
    }

    // MARK: - Transition envelopes

    /// Volume gain (0…1) plus an extra delay-wet boost for echo-out tails.
    /// ClipTransition.duration is in beats (matching the transition UI).
    private static func transitionEnvelope(
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

    // MARK: - Effect mappings

    private static func reverbPreset(_ preset: ReverbPreset) -> AVAudioUnitReverbPreset {
        switch preset {
        case .smallRoom: .smallRoom
        case .hall: .largeHall
        case .ambient: .cathedral
        }
    }

    private static func delayTime(for preset: EchoPreset, beatSeconds: Double) -> TimeInterval {
        switch preset {
        case .classic: beatSeconds * 0.75      // dotted eighth — the DJ echo
        case .pingPong: beatSeconds * 0.5      // straight eighth
        case .reverse: beatSeconds * 0.25      // 16th swarm — reverse-feel
        }
        // True reverse delay needs a custom reversed tap — approximated here
        // with a dense short delay until a custom AU lands.
    }

    private static func delayFeedback(for preset: EchoPreset) -> Float {
        switch preset {
        case .classic: 42
        case .pingPong: 55
        case .reverse: 68
        }
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
