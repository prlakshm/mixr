import AVFoundation
import Accelerate

// MARK: - On-Device Audio Analyzer

/// Estimates BPM (onset-strength autocorrelation) and musical key
/// (chromagram + Krumhansl-Schmuckler profiles) entirely on-device.
/// Runs on a background thread; does NOT block the main actor.
enum MixrAudioAnalyzer {

    struct Result {
        var bpm: Int?
        var bpmConfidence: Double?
        var key: String?
        var keyConfidence: Double?
    }

    static func analyze(url: URL) async -> Result {
        await Task.detached(priority: .utility) { analyzeSync(url: url) }.value
    }

    // MARK: – Top-level sync entry (background thread)

    private static func analyzeSync(url: URL) -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let (samples, sr) = readMono(url: url, maxSeconds: 90) else { return Result() }

        let bpmResult = estimateBPM(samples: samples, sampleRate: sr)
        let keyResult = estimateKey(samples: samples, sampleRate: sr)

        return Result(
            bpm:           bpmResult?.bpm,
            bpmConfidence: bpmResult?.confidence,
            key:           keyResult?.key,
            keyConfidence: keyResult?.confidence
        )
    }

    // MARK: – Audio reading

    /// Returns (mono float samples, sample rate). Mixes down to mono if needed.
    private static func readMono(url: URL, maxSeconds: Double) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sr       = file.processingFormat.sampleRate
        let maxLen   = AVAudioFrameCount(min(Double(file.length), sr * maxSeconds))
        guard maxLen > 0 else { return nil }

        guard let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: maxLen),
              (try? file.read(into: src)) != nil,
              let data = src.floatChannelData
        else { return nil }

        let count    = Int(src.frameLength)
        let channels = Int(src.format.channelCount)

        if channels == 1 {
            return (Array(UnsafeBufferPointer(start: data[0], count: count)), sr)
        }

        // Mix down: sum channels × (1/N)
        var mono  = [Float](repeating: 0, count: count)
        let scale = Float(1) / Float(channels)
        for ch in 0..<channels {
            vDSP_vsma(data[ch], 1, [scale], mono, 1, &mono, 1, vDSP_Length(count))
        }
        return (mono, sr)
    }

    // MARK: – BPM estimation (onset-strength autocorrelation)

    private static func estimateBPM(
        samples: [Float],
        sampleRate: Double
    ) -> (bpm: Int, confidence: Double)? {

        let hop        = 512
        let frameCount = samples.count / hop
        guard frameCount > 8 else { return nil }

        // Short-time RMS energy per hop
        var energy = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { buf in
            for i in 0..<frameCount {
                let start  = i * hop
                let length = min(hop, samples.count - start)
                var rms: Float = 0
                vDSP_rmsqv(buf.baseAddress! + start, 1, &rms, vDSP_Length(length))
                energy[i] = rms
            }
        }

        // Half-wave rectified first difference → onset strength
        var onset = [Float](repeating: 0, count: frameCount)
        for i in 1..<frameCount {
            onset[i] = max(0, energy[i] - energy[i - 1])
        }

        // Autocorrelation over the lag range that maps to 60–200 BPM
        let hps    = sampleRate / Double(hop)          // hops per second
        let minLag = max(2, Int(hps * 60.0 / 200.0))  // 200 BPM → shortest period
        let maxLag = min(frameCount - 1, Int(hps * 60.0 / 60.0))  // 60 BPM
        guard minLag < maxLag else { return nil }

        var bestLag  = minLag
        var bestCorr = Float(-1e9)
        var totalPow = Float(0)

        onset.withUnsafeBufferPointer { buf in
            for lag in minLag...maxLag {
                let n = vDSP_Length(frameCount - lag)
                var c = Float(0)
                vDSP_dotpr(buf.baseAddress!, 1,
                           buf.baseAddress! + lag, 1,
                           &c, n)
                totalPow += c
                if c > bestCorr { bestCorr = c; bestLag = lag }
            }
        }

        guard bestCorr > 0, totalPow > 0 else { return nil }

        let bpmExact = hps * 60.0 / Double(bestLag)
        let bpm      = Int(bpmExact.rounded())
        guard bpm >= 60, bpm <= 200 else { return nil }

        // Confidence: fraction of total correlation energy in the best lag
        let lagRange   = Double(maxLag - minLag + 1)
        let confidence = min(1.0, Double(bestCorr) / Double(totalPow) * lagRange)
        return (bpm, confidence)
    }

    // MARK: – Key estimation (chromagram + Krumhansl-Schmuckler)

    // Major and minor key profiles from Krumhansl (1990)
    private static let major: [Double] =
        [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minor: [Double] =
        [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    private static let notes = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

    private static func estimateKey(
        samples: [Float],
        sampleRate: Double
    ) -> (key: String, confidence: Double)? {

        let chroma = buildChroma(samples: samples, sampleRate: sampleRate)
        guard chroma.count == 12, chroma.reduce(0, +) > 0 else { return nil }

        var best  = -Double.infinity
        var second = -Double.infinity
        var bestKey = ""

        for root in 0..<12 {
            for (profile, suffix) in [(major, ""), (minor, "m")] {
                let score = pearson(rotated(profile, by: root), chroma)
                if score > best {
                    second = best; best = score
                    bestKey = notes[root] + suffix
                } else if score > second {
                    second = score
                }
            }
        }

        guard !bestKey.isEmpty else { return nil }
        let confidence = min(1.0, max(0.0, (best - second) * 4.0))
        return (bestKey, confidence)
    }

    /// Accumulate pitch-class energy from STFT frames (up to 256 hops).
    private static func buildChroma(samples: [Float], sampleRate: Double) -> [Double] {
        let fftN   = 4096
        let hop    = fftN / 2
        let log2n  = vDSP_Length(log2(Double(fftN)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(FFT_RADIX2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var hann = [Float](repeating: 0, count: fftN)
        vDSP_hann_window(&hann, vDSP_Length(fftN), Int32(vDSP_HANN_NORM))

        var realBuf = [Float](repeating: 0, count: fftN / 2)
        var imagBuf = [Float](repeating: 0, count: fftN / 2)
        var mags    = [Float](repeating: 0, count: fftN / 2)
        var chroma  = [Double](repeating: 0, count: 12)
        let maxHops = 256

        for hopIdx in 0..<maxHops {
            let start = hopIdx * hop
            guard start + fftN <= samples.count else { break }

            var frame = Array(samples[start ..< start + fftN])
            vDSP_vmul(frame, 1, hann, 1, &frame, 1, vDSP_Length(fftN))

            realBuf.withUnsafeMutableBufferPointer { rPtr in
                imagBuf.withUnsafeMutableBufferPointer { iPtr in
                    frame.withUnsafeMutableBufferPointer { fPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!,
                                                    imagp: iPtr.baseAddress!)
                        // vDSP real-FFT trick: pack N reals as N/2 complex
                        fPtr.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self, capacity: fftN / 2
                        ) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(fftN / 2))
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(fftN / 2))
                    }
                }
            }

            // Bin magnitudes into 12 pitch classes (A0 = 27.5 Hz → C8 ≈ 4186 Hz)
            for bin in 1 ..< fftN / 2 {
                let freq = Double(bin) * sampleRate / Double(fftN)
                guard freq >= 27.5, freq <= 4200 else { continue }
                let midi  = 69.0 + 12.0 * log2(freq / 440.0)
                let pc    = ((Int(midi.rounded()) % 12) + 12) % 12
                chroma[pc] += Double(mags[bin])
            }
        }

        // L1-normalise
        let sum = chroma.reduce(0, +)
        return sum > 0 ? chroma.map { $0 / sum } : chroma
    }

    // MARK: – Maths helpers

    private static func rotated(_ v: [Double], by n: Int) -> [Double] {
        (0..<v.count).map { v[($0 + n) % v.count] }
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n   = Double(a.count)
        let mA  = a.reduce(0, +) / n
        let mB  = b.reduce(0, +) / n
        var num = 0.0, dA = 0.0, dB = 0.0
        for i in 0..<a.count {
            let da = a[i] - mA;  let db = b[i] - mB
            num += da * db;  dA += da * da;  dB += db * db
        }
        return dA > 0 && dB > 0 ? num / sqrt(dA * dB) : 0
    }
}
