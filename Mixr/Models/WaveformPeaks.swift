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
            Task.detached(priority: .utility) {
                let result = WaveformPeaks.read(url: url)
                await MainActor.run {
                    self.pending.remove(url)
                    if let result { self.peaks[url] = result }
                }
            }
        }
        return nil
    }
}
