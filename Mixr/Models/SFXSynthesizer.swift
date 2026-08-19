import AVFoundation
import Foundation

// MARK: - SFX Synthesizer (fallback)

/// Procedurally regenerates any SFX whose bundled asset is missing, using
/// the same sound designs as Scripts/generate_sfx_assets.py — so playback
/// never fails silently. Deterministic (seeded PRNG), mono float32.
///
/// nonisolated: pure DSP math — also called from the export renderer's
/// background render loop.
nonisolated enum SFXSynthesizer {

    // MARK: Entry point

    static func buffer(
        for definition: SoundEffectDefinition,
        sampleRate: Double = 44100
    ) -> AVAudioPCMBuffer? {
        let samples = render(definition.synthesisType, duration: definition.durationSeconds, sr: sampleRate)
        return makeBuffer(samples: samples, sampleRate: sampleRate)
    }

    // MARK: Rendering

    private static func render(_ type: SFXSynthesisType, duration: Double, sr: Double) -> [Float] {
        var samples: [Double]
        switch type {
        case .riser:         samples = riser(duration, sr)
        case .downlifter:    samples = downlifter(duration, sr)
        case .impact:        samples = impact(duration, sr)
        case .sweepUp:       samples = sweep(duration, sr, rising: true, seed: 4)
        case .sweepDown:     samples = sweep(duration, sr, rising: false, seed: 5)
        case .reverseCymbal: samples = reverseCymbal(duration, sr)
        case .crash:         samples = crash(duration, sr)
        case .snareBuild:    samples = snareBuild(duration, sr)
        case .clapFill:      samples = clapFill(duration, sr)
        case .bassDrop:      samples = bassDrop(duration, sr)
        case .tapeStop:      samples = tapeStop(duration, sr)
        case .airSweep:      samples = airSweep(duration, sr)
        case .clubKick:      samples = clubKick(duration, sr)
        case .clubBass:      samples = clubBass(duration, sr)
        }
        normalize(&samples)
        edgeFades(&samples, sr: sr)
        return samples.map { Float($0) }
    }

    private static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData?[0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }

    // MARK: DSP toolkit

    /// Deterministic xorshift PRNG in -1…1.
    private struct Noise {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 2_000_000) / 1_000_000.0 - 1.0
        }
    }

    private struct OnePoleLP {
        var y = 0.0
        mutating func process(_ x: Double, fc: Double, sr: Double) -> Double {
            let a = 1.0 - exp(-2.0 * .pi * max(1.0, fc) / sr)
            y += a * (x - y)
            return y
        }
    }

    private struct SVF {
        var low = 0.0
        var band = 0.0
        mutating func process(_ x: Double, fc: Double, q: Double, sr: Double) -> (low: Double, band: Double) {
            let f = 2.0 * sin(.pi * min(fc, sr * 0.22) / sr)
            low += f * band
            let high = x - low - (1.0 / max(q, 0.5)) * band
            band += f * high
            return (low, band)
        }
    }

    private static func expInterp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a * pow(b / a, min(max(t, 0), 1))
    }

    private static func normalize(_ s: inout [Double], peak: Double = 0.708) {
        let m = max(1e-9, s.map(abs).max() ?? 1)
        let g = peak / m
        for i in s.indices { s[i] *= g }
    }

    private static func edgeFades(_ s: inout [Double], sr: Double, fadeSec: Double = 0.008) {
        let f = min(Int(fadeSec * sr), s.count / 2)
        guard f > 0 else { return }
        for i in 0..<f {
            let g = Double(i) / Double(f)
            s[i] *= g
            s[s.count - 1 - i] *= g
        }
    }

    private static func addInto(_ dest: inout [Double], _ src: [Double], startSec: Double, sr: Double, gain: Double) {
        let start = Int(startSec * sr)
        for (i, v) in src.enumerated() {
            let j = start + i
            if j >= 0 && j < dest.count { dest[j] += v * gain }
        }
    }

    // MARK: Sound designs (mirroring the Python generator)

    private static func riser(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 1), svf = SVF()
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let fc = expInterp(300, 7000, t)
            let band = svf.process(noise.next(), fc: fc, q: 1 + 3 * t, sr: sr).band
            phase += 2 * .pi * expInterp(110, 440, t) / sr
            let amp = expInterp(0.12, 1.0, t)
            var gate = 1.0
            if t > 0.75 {
                gate = sin(2 * .pi * (Double(i) / sr) * 8) > 0 ? 1.0 : 0.62
            }
            out.append((band * 1.6 + sin(phase) * 0.4) * amp * gate)
        }
        return out
    }

    private static func downlifter(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 2), svf = SVF()
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let band = svf.process(noise.next(), fc: expInterp(5000, 250, t), q: 2, sr: sr).band
            phase += 2 * .pi * expInterp(400, 70, t) / sr
            out.append((band * 1.5 + sin(phase) * 0.5 * (1 - t)) * expInterp(1.0, 0.14, t))
        }
        return out
    }

    private static func impact(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 3), lp = OnePoleLP()
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let ts = Double(i) / sr
            phase += 2 * .pi * expInterp(85, 42, min(1, ts / 0.5)) / sr
            let sub = sin(phase) * exp(-ts / 0.35)
            let burst = lp.process(noise.next(), fc: 2500, sr: sr) * exp(-ts / 0.06) * 2.2
            out.append(tanh((sub * 1.1 + burst) * 1.2))
        }
        return out
    }

    private static func sweep(_ duration: Double, _ sr: Double, rising: Bool, seed: UInt64) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: seed), svf = SVF()
        var out = [Double](); out.reserveCapacity(n)
        let peakAt = rising ? 0.72 : 0.28
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let fc = rising ? expInterp(500, 9000, t) : expInterp(9000, 400, t)
            let (low, band) = svf.process(noise.next(), fc: fc, q: 1.4, sr: sr)
            let x = (t - peakAt) / 0.62
            out.append((low * 0.8 + band * 0.9) * exp(-x * x * 3.2))
        }
        return out
    }

    private static func reverseCymbal(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 6), lp = OnePoleLP()
        var out = [Double](); out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let x = noise.next()
            let bright = x - lp.process(x, fc: 3800, sr: sr)
            out.append(bright * exp((t - 1) * 5.2))
        }
        var accentNoise = Noise(seed: 106)
        let accent = Int(0.045 * sr)
        for i in 0..<accent {
            out[n - accent + i] += accentNoise.next() * (1 - Double(i) / Double(accent)) * 0.8
        }
        return out
    }

    private static func crash(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 7), lp = OnePoleLP()
        var out = [Double](); out.reserveCapacity(n)
        for i in 0..<n {
            let ts = Double(i) / sr
            let x = noise.next()
            out.append((x - lp.process(x, fc: 3200, sr: sr)) * exp(-ts / 0.30))
        }
        return out
    }

    private static func snareHit(seed: UInt64, sr: Double) -> [Double] {
        let n = Int(0.12 * sr)
        var noise = Noise(seed: seed), lp = OnePoleLP()
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let ts = Double(i) / sr
            phase += 2 * .pi * 190 / sr
            let x = noise.next()
            out.append(sin(phase) * exp(-ts / 0.045) * 0.8
                + (x - lp.process(x, fc: 1600, sr: sr)) * exp(-ts / 0.055) * 1.1)
        }
        return out
    }

    private static func snareBuild(_ duration: Double, _ sr: Double, bpm: Double = 128) -> [Double] {
        var out = [Double](repeating: 0, count: Int(duration * sr))
        let beat = 60.0 / bpm
        var t = 0.0
        var idx: UInt64 = 8
        while t < duration - 0.05 {
            let progress = t / duration
            let step: Double = progress < 0.5 ? beat / 2 : progress < 0.78 ? beat / 4 : progress < 0.93 ? beat / 8 : beat / 16
            addInto(&out, snareHit(seed: idx, sr: sr), startSec: t, sr: sr, gain: 0.45 + 0.55 * progress)
            t += step
            idx += 1
        }
        return out
    }

    private static func clap(seed: UInt64, sr: Double) -> [Double] {
        let n = Int(0.16 * sr)
        var noise = Noise(seed: seed), svf = SVF()
        var out = [Double](repeating: 0, count: n)
        for b in 0..<3 {
            let start = Int(Double(b) * 0.012 * sr)
            for i in 0..<Int(0.010 * sr) where start + i < n {
                out[start + i] += svf.process(noise.next(), fc: 2100, q: 1.8, sr: sr).band * 2.0
            }
        }
        for i in 0..<n {
            let ts = Double(i) / sr
            if ts > 0.036 {
                out[i] += svf.process(noise.next(), fc: 1700, q: 1.5, sr: sr).band * 1.6 * exp(-(ts - 0.036) / 0.05)
            }
        }
        return out
    }

    private static func clapFill(_ duration: Double, _ sr: Double, bpm: Double = 128) -> [Double] {
        var out = [Double](repeating: 0, count: Int(duration * sr))
        let step = 60.0 / bpm / 2
        var t = 0.0
        var idx: UInt64 = 9
        while t < duration - 0.1 {
            let progress = t / duration
            addInto(&out, clap(seed: idx, sr: sr), startSec: t, sr: sr, gain: 0.5 + 0.5 * progress)
            if progress > 0.72 {
                addInto(&out, clap(seed: idx + 50, sr: sr), startSec: t + step / 2, sr: sr, gain: 0.45 + 0.5 * progress)
            }
            t += step
            idx += 1
        }
        return out
    }

    private static func bassDrop(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let ts = Double(i) / sr
            phase += 2 * .pi * expInterp(160, 32, min(1, ts / 1.1)) / sr
            let amp = ts < 1.1 ? 1.0 : exp(-(ts - 1.1) / 0.16)
            out.append(tanh(sin(phase) * 1.25 * 1.3) * amp)
        }
        return out
    }

    private static func tapeStop(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 11), lp = OnePoleLP()
        let freqs = [220.0, 277.2, 329.6, 440.0]
        var phases = [Double](repeating: 0, count: freqs.count)
        var out = [Double](); out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let speed = pow(max(0, 1 - t), 1.6)
            var sample = 0.0
            for (k, f) in freqs.enumerated() {
                phases[k] += 2 * .pi * f * speed / sr
                sample += sin(phases[k]) * (0.28 - 0.04 * Double(k))
            }
            let bed = lp.process(noise.next(), fc: 1200 * speed + 60, sr: sr) * 0.35
            out.append((sample + bed) * pow(speed, 0.8))
        }
        return out
    }

    private static func airSweep(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var noise = Noise(seed: 12), svf = SVF()
        var out = [Double](); out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let ts = Double(i) / sr
            let fc = max(300, 900 + 600 * sin(2 * .pi * 0.5 * ts))
            let low = svf.process(noise.next(), fc: fc, q: 1.1, sr: sr).low
            out.append(low * pow(sin(.pi * t), 1.5))
        }
        return out
    }

    private static func clubKick(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        var noise = Noise(seed: 21)
        for i in 0..<n {
            let t = Double(i) / sr
            let env = exp(-14 * t / max(duration, 0.01))
            phase += 2 * .pi * expInterp(120, 48, min(1, t / duration)) / sr
            out.append((sin(phase) * 0.85 + noise.next() * 0.15) * env)
        }
        return out
    }

    private static func clubBass(_ duration: Double, _ sr: Double) -> [Double] {
        let n = Int(duration * sr)
        var out = [Double](); out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let env = exp(-8 * t / max(duration, 0.01))
            phase += 2 * .pi * 45 / sr
            out.append(sin(phase) * env)
        }
        return out
    }
}
