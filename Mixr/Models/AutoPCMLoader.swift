import Foundation
import AVFoundation

/// Decodes song and stem audio to lean mono PCM for the in-engine listen
/// loop. The bounce harness passes 44.1 kHz PCM; the app decodes at
/// 11.025 kHz mono (level metering needs no more) so five songs with four
/// stems each stay around 100 MB transient. Without this the app path never
/// ran the listen loop — its hole fills and club invariants only existed in
/// the harness.
nonisolated enum AutoPCMLoader {

    static let listenSampleRate: Double = 11_025
    static let maxSongs = 6

    static func sources(for tracks: [MixrTrack]) -> [UUID: AutoOfflineMixdown.Source] {
        var out: [UUID: AutoOfflineMixdown.Source] = [:]
        let songs = tracks.filter { !$0.isSFXTrack && !$0.clips.isEmpty }
        guard songs.count <= maxSongs else { return out }
        for t in songs {
            guard let url = t.url, let pcm = decodeMono(url: url, targetRate: listenSampleRate) else { continue }
            out[t.id] = AutoOfflineMixdown.Source(samples: pcm, sampleRate: listenSampleRate)
        }
        return out
    }

    static func stemSources(
        for tracks: [MixrTrack], tuning: AutoTuning
    ) -> [UUID: [AutoStemKind: AutoOfflineMixdown.Source]] {
        var out: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]] = [:]
        let songs = tracks.filter { !$0.isSFXTrack && !$0.clips.isEmpty }
        guard songs.count <= maxSongs else { return out }
        for t in songs {
            let set = AutoStemResolver.resolve(track: t, tuning: tuning)
            var stems: [AutoStemKind: AutoOfflineMixdown.Source] = [:]
            let urls: [(AutoStemKind, URL?)] = [
                (.vocals, set.vocals), (.drums, set.drums), (.bass, set.bass), (.other, set.other),
            ]
            for (kind, url) in urls {
                guard let url, let pcm = decodeMono(url: url, targetRate: listenSampleRate) else { continue }
                stems[kind] = AutoOfflineMixdown.Source(samples: pcm, sampleRate: listenSampleRate)
            }
            if !stems.isEmpty { out[t.id] = stems }
        }
        return out
    }

    /// AVAudioFile → AVAudioConverter → mono Float32 at `targetRate`.
    static func decodeMono(url: URL, targetRate: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: file.processingFormat, to: outFormat) else { return nil }
        let inCap: AVAudioFrameCount = 32_768
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inCap) else { return nil }
        let ratio = targetRate / file.processingFormat.sampleRate
        let outCap = AVAudioFrameCount(Double(inCap) * ratio) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCap) else { return nil }
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * ratio) + 1024)
        var reachedEnd = false
        while !reachedEnd {
            var pulled = false
            var convError: NSError?
            let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
                if pulled { outStatus.pointee = .noDataNow; return nil }
                pulled = true
                inBuf.frameLength = 0
                do { try file.read(into: inBuf) } catch { outStatus.pointee = .endOfStream; return nil }
                if inBuf.frameLength == 0 { outStatus.pointee = .endOfStream; reachedEnd = true; return nil }
                outStatus.pointee = .haveData
                return inBuf
            }
            if status == .error || convError != nil { return samples.isEmpty ? nil : samples }
            if let data = outBuf.floatChannelData, outBuf.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(outBuf.frameLength)))
            }
            if status == .endOfStream { reachedEnd = true }
            outBuf.frameLength = 0
        }
        return samples
    }
}
