import AVFoundation
import Foundation

// MARK: - Export Renderer
//
// Offline bounce of the project using AVAudioEngine manual rendering.
// The graph is a mirror of MixrPlaybackEngine's live graph:
//
//   per song track: player → timePitch → EQ → flanger → delay → reverb → mainMixer
//   SFX track:      player → mainMixer
//   master:         mainMixer → peak limiter → output
//
// Every clip is scheduled with the same trim/offset/speed math as live
// playback, and before each render block the per-clip effect parameters
// are recomputed through ClipEffectDSP — the exact slider→parameter
// mapping the live engine uses — so the exported file sounds the same
// as real-time playback. Rendering continues past the last clip
// (ClipEffectDSP.exportTailSeconds) so reverb/echo tails decay
// naturally instead of being cut off.
//
// The source audio files are only ever opened for READING — export is
// fully non-destructive.
//
// nonisolated: the render loop runs inside a detached background task
// so the UI stays responsive while bouncing.
nonisolated enum MixrExportRenderer {

    enum ExportError: LocalizedError {
        case nothingToExport
        case renderFailed(String)

        var errorDescription: String? {
            switch self {
            case .nothingToExport: "Add a song to the timeline before exporting."
            case .renderFailed(let reason): "Export failed — \(reason)"
            }
        }
    }

    /// One offline effect chain per song track (mirrors TrackChain).
    private final class ExportChain {
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        let flangerNode: AVAudioUnit?
        let flangerKernel: FlangerKernel?
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        let file: AVAudioFile
        var appliedReverbPreset: ReverbPreset?
        var appliedDelayTime: TimeInterval = 0

        init(file: AVAudioFile) {
            self.file = file
            let node = ClipFlanger.makeNode()
            flangerNode = node
            flangerKernel = ClipFlanger.kernel(of: node)
        }

        var allNodes: [AVAudioNode] {
            var nodes: [AVAudioNode] = [player, timePitch, eq]
            if let flangerNode { nodes.append(flangerNode) }
            nodes.append(contentsOf: [delay, reverb])
            return nodes
        }
    }

    /// Renders the project to an AAC (.m4a) file and returns its URL.
    /// Runs synchronously — call from a background task so the render
    /// loop stays off the main thread.
    static func export(
        tracks: [MixrTrack],
        projectName: String,
        projectBPM: Int? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        let contentSeconds = MixrTimeline.remixDurationSeconds(tracks: tracks)
        guard contentSeconds > 0 else { throw ExportError.nothingToExport }
        let totalSeconds = contentSeconds + ClipEffectDSP.exportTailSeconds(tracks: tracks)

        let engine = AVAudioEngine()
        guard let renderFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
            throw ExportError.renderFailed("could not create render format")
        }

        // ── Build the graph (mirror of the live engine) ──
        var chains: [(track: MixrTrack, chain: ExportChain)] = []
        var scopedURLs: [URL] = []
        defer { for url in scopedURLs { url.stopAccessingSecurityScopedResource() } }

        for track in tracks where !track.isSFXTrack && !track.clips.isEmpty {
            guard let url = track.url else { continue }
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
            guard let file = try? AVAudioFile(forReading: url) else { continue }

            let chain = ExportChain(file: file)
            ClipEffectDSP.configureRestState(
                timePitch: chain.timePitch,
                eq: chain.eq,
                flanger: chain.flangerKernel,
                delay: chain.delay,
                reverb: chain.reverb
            )
            chain.appliedReverbPreset = .smallRoom

            for node in chain.allNodes { engine.attach(node) }
            let fmt = file.processingFormat
            engine.connect(chain.player, to: chain.timePitch, format: fmt)
            engine.connect(chain.timePitch, to: chain.eq, format: fmt)
            if let flangerNode = chain.flangerNode {
                engine.connect(chain.eq, to: flangerNode, format: fmt)
                engine.connect(flangerNode, to: chain.delay, format: fmt)
            } else {
                engine.connect(chain.eq, to: chain.delay, format: fmt)
            }
            engine.connect(chain.delay, to: chain.reverb, format: fmt)
            engine.connect(chain.reverb, to: engine.mainMixerNode, format: fmt)
            chains.append((track, chain))
        }

        // SFX track: buffers straight into the mixer (same as live).
        var sfxPlayer: AVAudioPlayerNode?
        var sfxSchedule: [(buffer: AVAudioPCMBuffer, startSeconds: Double)] = []
        if let sfxTrack = tracks.first(where: { $0.isSFXTrack }) {
            for clip in sfxTrack.clips.sorted(by: { $0.start < $1.start }) {
                guard let effectID = clip.soundEffectID,
                      let definition = SoundEffectLibrary.definition(for: effectID),
                      let buffer = sfxBuffer(for: definition)
                else { continue }
                sfxSchedule.append((buffer, MixrTimeline.seconds(fromUnits: clip.start)))
            }
            if let format = sfxSchedule.first?.buffer.format {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                sfxPlayer = player
                sfxSchedule = sfxSchedule.filter { $0.buffer.format == format }
            }
        }

        guard !chains.isEmpty || sfxPlayer != nil else { throw ExportError.nothingToExport }

        // Master output protection — identical placement to live playback.
        let limiter = ClipEffectDSP.makePeakLimiter()
        engine.attach(limiter)
        engine.connect(engine.mainMixerNode, to: limiter, format: renderFormat)
        engine.connect(limiter, to: engine.outputNode, format: renderFormat)

        // ── Offline mode + schedule all clips from t = 0 ──
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
        do {
            try engine.start()
        } catch {
            throw ExportError.renderFailed(error.localizedDescription)
        }

        for (track, chain) in chains {
            scheduleClips(for: track, chain: chain, timelineSeconds: 0)
            chain.player.play()

            // Pre-arm the playback rate: segment delays are scheduled in
            // the player's INPUT timeline (delay × rate), which assumes
            // the first clip's rate is in effect from render start.
            if let first = track.clips
                .filter({ !$0.isSoundEffect })
                .min(by: { $0.start < $1.start }) {
                chain.timePitch.rate = Float(max(first.playbackSpeed, 0.03125))
                if abs(first.playbackSpeed - 1.0) >= 0.001 { chain.timePitch.bypass = false }
            }
        }
        if let sfxPlayer {
            let sr = sfxSchedule.first?.buffer.format.sampleRate ?? 44_100
            for item in sfxSchedule {
                sfxPlayer.scheduleBuffer(
                    item.buffer,
                    at: AVAudioTime(sampleTime: AVAudioFramePosition(item.startSeconds * sr), atRate: sr)
                )
            }
            sfxPlayer.play()
        }

        // ── Output file ──
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFileName(projectName))
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outURL)
        let outFile = try AVAudioFile(
            forWriting: outURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let block = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            engine.stop()
            throw ExportError.renderFailed("could not allocate render buffer")
        }

        // ── Render loop ──
        // 1024-frame blocks (~23 ms at 44.1 kHz) so per-clip parameters,
        // transition envelopes, and volume automation track closely.
        let outputSR = renderFormat.sampleRate
        let totalFrames = AVAudioFramePosition(totalSeconds * outputSR)
        let blockFrames: AVAudioFrameCount = 1024
        var rendered: AVAudioFramePosition = 0

        while rendered < totalFrames {
            let t = Double(rendered) / outputSR
            applyParameters(at: t, tracks: tracks, chains: chains, sfxPlayer: sfxPlayer)

            let framesThisBlock = AVAudioFrameCount(min(AVAudioFramePosition(blockFrames), totalFrames - rendered))
            do {
                let status = try engine.renderOffline(framesThisBlock, to: block)
                switch status {
                case .success:
                    try outFile.write(from: block)
                    rendered += AVAudioFramePosition(block.frameLength)
                case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                    continue
                case .error:
                    throw ExportError.renderFailed("render error")
                @unknown default:
                    throw ExportError.renderFailed("unknown render status")
                }
            } catch let error as ExportError {
                engine.stop()
                throw error
            } catch {
                engine.stop()
                throw ExportError.renderFailed(error.localizedDescription)
            }

            progress?(Double(rendered) / Double(totalFrames))
        }

        engine.stop()
        return outURL
    }

    // MARK: - Scheduling (same trim/offset/speed math as live playback)

    private static func scheduleClips(
        for track: MixrTrack,
        chain: ExportChain,
        timelineSeconds: Double
    ) {
        let sr = chain.file.processingFormat.sampleRate
        let fileFrames = chain.file.length

        for clip in track.clips.sorted(by: { $0.start < $1.start }) {
            let clipStart = MixrTimeline.seconds(fromUnits: clip.start)
            let clipEnd = MixrTimeline.seconds(fromUnits: clip.start + clip.length)
            guard timelineSeconds < clipEnd else { continue }

            let speed = max(clip.playbackSpeed, 0.0001)
            let playStart = max(clipStart, timelineSeconds)
            let dur = clipEnd - playStart
            guard dur > 0.001 else { continue }

            let into = playStart - clipStart
            let srcStart = clip.sourceOffsetSeconds + into * speed
            var srcDur = dur * speed
            let startFrame = AVAudioFramePosition(srcStart * sr)
            guard startFrame < fileFrames else { continue }
            srcDur = min(srcDur, Double(fileFrames - startFrame) / sr)
            let frames = AVAudioFrameCount(max(0, srcDur * sr))
            guard frames > 0 else { continue }

            let delaySec = max(0, playStart - timelineSeconds) * speed
            chain.player.scheduleSegment(
                chain.file,
                startingFrame: startFrame,
                frameCount: frames,
                at: AVAudioTime(sampleTime: AVAudioFramePosition(delaySec * sr), atRate: sr)
            )
        }
    }

    // MARK: - Per-block parameters (mirror of applyTickParameters)

    private static func applyParameters(
        at t: Double,
        tracks: [MixrTrack],
        chains: [(track: MixrTrack, chain: ExportChain)],
        sfxPlayer: AVAudioPlayerNode?
    ) {
        let soloActive = tracks.contains { $0.isSoloed }

        for (track, chain) in chains {
            let audible = !track.isMuted && (!soloActive || track.isSoloed)
            let bpm = Double(track.bpm ?? 124)

            let clip = track.clips.first { clip in
                !clip.isSoundEffect
                    && t >= MixrTimeline.seconds(fromUnits: clip.start)
                    && t < MixrTimeline.seconds(fromUnits: clip.start + clip.length)
            }

            var volume: Float = 0
            if let clip, audible {
                let envelope = ClipEffectDSP.transitionEnvelope(for: clip, at: t, bpm: bpm)
                volume = Float(track.volume * clip.volume * envelope.gain)

                let targets = ClipEffectDSP.targets(
                    for: clip.effects,
                    playbackSpeed: clip.playbackSpeed,
                    bpm: bpm,
                    echoBoost: envelope.echoBoost
                )
                ClipEffectDSP.apply(
                    targets,
                    timePitch: chain.timePitch,
                    eq: chain.eq,
                    flanger: chain.flangerKernel,
                    delay: chain.delay,
                    reverb: chain.reverb,
                    timelineSeconds: t,
                    appliedReverbPreset: &chain.appliedReverbPreset,
                    appliedDelayTime: &chain.appliedDelayTime
                )
            } else {
                // No clip under this block — make sure the flanger never
                // lingers on the shared track chain.
                chain.flangerKernel?.setTargets(
                    wet: 0, feedback: 0, depthSeconds: 0,
                    baseDelaySeconds: 0.0006, lfoFrequency: 0.25, phase: 0
                )
            }
            chain.player.volume = volume
        }

        if let sfxPlayer, let sfxTrack = tracks.first(where: { $0.isSFXTrack }) {
            let audible = !sfxTrack.isMuted && (!soloActive || sfxTrack.isSoloed)
            sfxPlayer.volume = audible ? Float(sfxTrack.volume) : 0
        }
    }

    // MARK: - SFX buffers (bundled asset → synthesized fallback, like live)

    private static func sfxBuffer(for definition: SoundEffectDefinition) -> AVAudioPCMBuffer? {
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
            return loaded
        }
        return SFXSynthesizer.buffer(for: definition)
    }

    private static func safeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Mixr Remix" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return String(base.unicodeScalars.map { invalid.contains($0) ? "-" : Character($0) })
    }
}
