import AVFoundation
import Combine
import CoreGraphics

/// A song's loudness envelope: the peak level of each 1/100 s, 0…1
/// (normalised to the song's own loudest moment).
nonisolated struct WaveformPeaks: Sendable {
    static let peaksPerSecond: Double = 100

    let values: [Float]

    var durationSeconds: Double { Double(values.count) / Self.peaksPerSecond }

    /// `count` bars for the part of the song from `start` lasting `duration`
    /// seconds. Each bar is the loudest peak in its slice, eased (power 0.7)
    /// so quiet passages stay visible next to a loud drop. nil when the
    /// slice lies outside the song.
    func bars(start: Double, duration: Double, count: Int) -> [CGFloat]? {
        guard count > 0, duration > 0, !values.isEmpty else { return nil }
        let first = start * Self.peaksPerSecond
        let span = duration * Self.peaksPerSecond
        guard first < Double(values.count) else { return nil }
        var bars = [CGFloat](repeating: 0, count: count)
        for i in 0..<count {
            let lo = Int((first + span * Double(i) / Double(count)).rounded(.down))
            let hi = Int((first + span * Double(i + 1) / Double(count)).rounded(.up))
            let a = max(0, lo), b = min(values.count, max(hi, lo + 1))
            guard a < b else { continue }
            var peak: Float = 0
            for j in a..<b where values[j] > peak { peak = values[j] }
            bars[i] = CGFloat(pow(Double(peak), 0.7))
        }
        return bars
    }

    /// Peaks for `url`: from the on-disk cache if this file was read before,
    /// otherwise read from the audio and saved, so reopening a project
    /// draws every waveform at once.
    static func load(url: URL) -> WaveformPeaks? {
        let cacheFile = cacheURL(for: url)
        if let cacheFile, let data = try? Data(contentsOf: cacheFile),
           !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 {
            let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return WaveformPeaks(values: values)
        }
        guard let peaks = read(url: url) else { return nil }
        if let cacheFile {
            try? FileManager.default.createDirectory(
                at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = peaks.values.withUnsafeBufferPointer { Data(buffer: $0) }
            try? data.write(to: cacheFile, options: .atomic)
        }
        return peaks
    }

    /// Cache file keyed by the audio's path and size. Every import gets its
    /// own folder, so a path is never reused for different audio.
    private static func cacheURL(for url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let path = url.standardizedFileURL.path
        let key = "\(String(stableHash(path), radix: 16))-\(size)"
        return caches.appendingPathComponent("WaveformPeaks", isDirectory: true)
            .appendingPathComponent(key + ".peaks")
    }

    /// FNV-1a: stable across launches (Swift's Hasher is seeded per run).
    private static func stableHash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return h
    }

    /// Reads the file once: peak |sample| across channels per 10 ms.
    static func read(url: URL) -> WaveformPeaks? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let framesPerPeak = max(1, AVAudioFrameCount(format.sampleRate / peaksPerSecond))
        let chunk = framesPerPeak * 256
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              format.commonFormat == .pcmFormatFloat32 else { return nil }

        var values: [Float] = []
        values.reserveCapacity(Int(Double(file.length) / Double(framesPerPeak)) + 1)
        while file.framePosition < file.length {
            do { try file.read(into: buffer, frameCount: chunk) } catch { break }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }
            var start = 0
            while start < frames {
                let end = min(frames, start + Int(framesPerPeak))
                var peak: Float = 0
                for c in 0..<Int(format.channelCount) {
                    let samples = channels[c]
                    for k in start..<end {
                        let v = abs(samples[k])
                        if v > peak { peak = v }
                    }
                }
                values.append(peak)
                start = end
            }
        }
        guard let loudest = values.max(), loudest > 0 else { return nil }
        return WaveformPeaks(values: values.map { $0 / loudest })
    }
}

/// Decodes each song's peaks once, off the main thread, and shares them
/// with every clip of that song.
@MainActor
final class WaveformPeakCache: ObservableObject {
    static let shared = WaveformPeakCache()

    @Published private(set) var peaks: [URL: WaveformPeaks] = [:]
    private var pending: Set<URL> = []

    /// Cached peaks for `url`; starts reading them if they aren't ready.
    func peaks(for url: URL) -> WaveformPeaks? {
        if let ready = peaks[url] { return ready }
        if !pending.contains(url) {
            pending.insert(url)
            // User-initiated: these are on screen and the user is waiting.
            Task.detached(priority: .userInitiated) {
                let result = WaveformPeaks.load(url: url)
                await MainActor.run {
                    self.pending.remove(url)
                    if let result { self.peaks[url] = result }
                }
            }
        }
        return nil
    }
}
