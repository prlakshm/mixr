import AVFoundation
import Combine

// MARK: - Playback Engine

@MainActor
final class MixrPlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var totalDurationSeconds: Double = 0

    private let engine = AVAudioEngine()
    private var players: [UUID: TrackPlayer] = [:]
    /// (timelineSeconds at sync point, wall-clock seconds at sync point)
    private var anchor: (timeline: Double, wall: Double)?
    private var ticker: Timer?
    private var snapshot: [MixrTrack] = []
    private var audioSessionReady = false

    private struct TrackPlayer {
        let node: AVAudioPlayerNode
        let file: AVAudioFile
        let url: URL
        let securityScoped: Bool
    }

    // MARK: - Public API

    /// Full sync: called when tracks are added, removed, or clip lengths change.
    func syncTracks(_ tracks: [MixrTrack]) {
        snapshot = tracks
        totalDurationSeconds = MixrTimeline.remixDurationSeconds(tracks: tracks)

        if tracks.isEmpty && isPlaying { pause() }

        if currentTimeSeconds > totalDurationSeconds {
            currentTimeSeconds = totalDurationSeconds
            if isPlaying { pause() }
        }

        // Remove players whose track was deleted
        let live = Set(tracks.map(\.id))
        for id in players.keys where !live.contains(id) {
            removePlayer(id: id)
        }

        // Add players for new tracks, apply state for all
        for track in tracks {
            if players[track.id] == nil { addPlayer(for: track) }
            applyVolume(for: track)
        }
    }

    /// Lightweight sync: called when only volume/mute changes (does NOT restart engine).
    func applyMixSettings(from tracks: [MixrTrack]) {
        snapshot = tracks
        for track in tracks { applyVolume(for: track) }
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

    // MARK: - Engine Internals

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

    private func addPlayer(for track: MixrTrack) {
        guard let url = track.url else { return }
        setupAudioSession()
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let file = try AVAudioFile(forReading: url)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            players[track.id] = TrackPlayer(node: node, file: file, url: url, securityScoped: scoped)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            print("MixrPlaybackEngine: cannot load \(url.lastPathComponent) — \(error.localizedDescription)")
        }
    }

    private func removePlayer(id: UUID) {
        guard let p = players.removeValue(forKey: id) else { return }
        p.node.stop()
        engine.detach(p.node)     // also disconnects
        if p.securityScoped { p.url.stopAccessingSecurityScopedResource() }
    }

    /// Mute + solo aware: soloing any track silences all non-soloed tracks.
    private func isAudible(_ track: MixrTrack) -> Bool {
        TrackLibrary.isAudible(track, in: snapshot)
    }

    private func applyVolume(for track: MixrTrack) {
        players[track.id]?.node.volume = isAudible(track) ? Float(track.volume) : 0
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

        // ── 3. Choose a common host-time sync point 50 ms in the future ──
        //    All tracks begin rendering at this moment; tracks with future clip starts
        //    have their scheduleSegment at: time pushed further out.
        let bufferSec  = 0.05
        let syncTicks  = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: bufferSec)
        let syncWall   = CACurrentMediaTime() + bufferSec
        var scheduled  = false

        // ── 4. Schedule each track ──
        for track in snapshot {
            guard isAudible(track),
                  let p = players[track.id],
                  let clip = track.clips.first
            else { continue }

            let clipStart = MixrTimeline.seconds(fromUnits: clip.start)
            let clipEnd   = MixrTimeline.seconds(fromUnits: clip.start + clip.length)
            guard timelineSeconds < clipEnd else { continue }

            let sr           = p.file.processingFormat.sampleRate
            let fileDuration = Double(p.file.length) / sr

            // How long before this clip starts (relative to current timeline pos)
            let clipDelaySec  = max(0, clipStart - timelineSeconds)
            // How far into the file to seek — clip content begins at its
            // source offset (set by splits/trims) plus elapsed clip time.
            let fileOffsetSec = clip.sourceOffsetSeconds + max(0, timelineSeconds - clipStart)

            let playableSec = min(
                clipEnd - max(timelineSeconds, clipStart),
                max(0, fileDuration - fileOffsetSec)
            )
            guard playableSec > 0.01 else { continue }

            let startFrame = AVAudioFramePosition(fileOffsetSec * sr)
            let nFrames    = AVAudioFrameCount(playableSec * sr)
            guard nFrames > 0, startFrame < p.file.length else { continue }

            // The absolute host time at which this node should produce its first sample
            let nodeHostTicks = syncTicks + AVAudioTime.hostTime(forSeconds: clipDelaySec)
            let nodeAVTime    = AVAudioTime(hostTime: nodeHostTicks)

            let trackID = track.id
            p.node.scheduleSegment(
                p.file,
                startingFrame: startFrame,
                frameCount: nFrames,
                at: nodeAVTime          // precise output time for synchronisation
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.onSegmentEnd(trackID: trackID)
                }
            }

            // node.play() (no argument) starts the render cycle; the segment
            // itself carries the timing so all tracks are sample-aligned.
            p.node.play()
            scheduled = true
        }

        guard scheduled else {
            if engine.isRunning { engine.pause() }
            return
        }

        // ── 5. Record wall-clock anchor ──
        anchor   = (timelineSeconds, syncWall)
        isPlaying = true
        startTicker()
    }

    private func stopAllNodes() {
        for p in players.values { p.node.stop() }
    }

    // MARK: - Segment completion

    private func onSegmentEnd(trackID: UUID) {
        guard isPlaying else { return }
        syncAnchorToCurrentTime()

        // Only stop if every non-muted track has reached its clip end
        let anyLive = snapshot.contains { track in
            guard isAudible(track), let clip = track.clips.first else { return false }
            return currentTimeSeconds < MixrTimeline.seconds(fromUnits: clip.start + clip.length)
        }
        if !anyLive { pause(); currentTimeSeconds = totalDurationSeconds }
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
