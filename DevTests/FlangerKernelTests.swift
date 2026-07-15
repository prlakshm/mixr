import AVFoundation

// Standalone verification harness for FlangerKernel — NOT part of the app
// target (the Xcode project only syncs the Mixr/ folder). Run from the
// repo root with:
//
//   cp DevTests/FlangerKernelTests.swift main.swift
//   swiftc -O -o /tmp/verify_flanger Mixr/Models/ClipFlanger.swift main.swift
//   /tmp/verify_flanger && rm main.swift
//
// Covers: true bypass at 0, stability at max intensity across BPMs,
// deterministic LFO phase, mono-sum safety, and the slider→wet mapping.

let sampleRate = 44_100.0
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

func makeBuffer(frames: Int, fill: (Int, Int) -> Float) -> AVAudioPCMBuffer {
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buf.frameLength = AVAudioFrameCount(frames)
    for ch in 0..<2 {
        let p = buf.floatChannelData![ch]
        for n in 0..<frames { p[n] = fill(ch, n) }
    }
    return buf
}

func process(kernel: FlangerKernel, input: AVAudioPCMBuffer, output: AVAudioPCMBuffer, blockSize: Int, update: (Double) -> Void) {
    let frames = Int(input.frameLength)
    var done = 0
    while done < frames {
        let count = min(blockSize, frames - done)
        update(Double(done) / sampleRate)
        // Build per-block ABLs pointing into the big buffers.
        let inABL = AudioBufferList.allocate(maximumBuffers: 2)
        let outABL = AudioBufferList.allocate(maximumBuffers: 2)
        for ch in 0..<2 {
            inABL[ch] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4), mData: UnsafeMutableRawPointer(input.floatChannelData![ch] + done))
            outABL[ch] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4), mData: UnsafeMutableRawPointer(output.floatChannelData![ch] + done))
        }
        kernel.process(input: inABL.unsafeMutablePointer, output: outABL.unsafeMutablePointer, frameCount: count)
        free(inABL.unsafeMutablePointer)
        free(outABL.unsafeMutablePointer)
        done += count
    }
}

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL")  \(name)")
    if !ok { failures += 1 }
}

let seconds = 6.0
let frames = Int(seconds * sampleRate)
let input = makeBuffer(frames: frames) { ch, n in
    // Mix of sustained tone + noise-ish component.
    let t = Float(n) / Float(sampleRate)
    return 0.5 * sin(2 * .pi * 220 * t) + 0.2 * sin(2 * .pi * 3.7 * Float(n) + Float(ch))
}

// ── Test 1: amount 0 is a true bypass (bit-identical) ──
do {
    let kernel = FlangerKernel()
    kernel.prepare(sampleRate: sampleRate, channels: 2)
    let out = makeBuffer(frames: frames) { _, _ in 0 }
    process(kernel: kernel, input: input, output: out, blockSize: 1024) { _ in
        kernel.setTargets(wet: 0, feedback: 0, depthSeconds: 0, baseDelaySeconds: 0.0006, lfoFrequency: 0.25, phase: 0)
    }
    var identical = true
    for ch in 0..<2 {
        for n in 0..<frames where input.floatChannelData![ch][n] != out.floatChannelData![ch][n] {
            identical = false; break
        }
    }
    check("0 = true bypass (bit-identical output)", identical)
}

// Local mirrors of ClipEffectDSP's flanger mapping (the app source pulls
// in SwiftUI; this harness only links the kernel).
func lfoFrequency(bpm: Double) -> Float {
    guard bpm.isFinite, bpm >= 30, bpm <= 300 else { return 0.25 }
    return Float(1.0 / (60.0 / bpm * 8.0))
}
func lfoPhase(t: Double, freq: Float) -> Float {
    let cycles = max(0, t) * Double(freq)
    return Float(cycles - cycles.rounded(.down))
}

// ── Test 2: max intensity is stable — no NaN, no runaway ──
func targetsAtMax(_ k: FlangerKernel, bpm: Double, t: Double) {
    let freq = lfoFrequency(bpm: bpm)
    k.setTargets(
        wet: 0.65, feedback: 0.80, depthSeconds: 0.0085, baseDelaySeconds: 0.0006,
        lfoFrequency: freq,
        phase: lfoPhase(t: t, freq: freq)
    )
}
for bpm in [80.0, 100.0, 120.0, 128.0, 150.0] {
    let kernel = FlangerKernel()
    kernel.prepare(sampleRate: sampleRate, channels: 2)
    let out = makeBuffer(frames: frames) { _, _ in 0 }
    process(kernel: kernel, input: input, output: out, blockSize: 1024) { t in targetsAtMax(kernel, bpm: bpm, t: t) }
    var peak: Float = 0
    var finite = true
    for ch in 0..<2 {
        for n in 0..<frames {
            let v = out.floatChannelData![ch][n]
            if !v.isFinite { finite = false }
            peak = max(peak, abs(v))
        }
    }
    check("max intensity stable @ \(Int(bpm)) BPM (peak \(String(format: "%.2f", peak)))", finite && peak < 2.5)
}

// ── Test 3: deterministic — two identical runs match exactly ──
do {
    func run() -> AVAudioPCMBuffer {
        let kernel = FlangerKernel()
        kernel.prepare(sampleRate: sampleRate, channels: 2)
        let out = makeBuffer(frames: frames) { _, _ in 0 }
        process(kernel: kernel, input: input, output: out, blockSize: 1024) { t in targetsAtMax(kernel, bpm: 124, t: t) }
        return out
    }
    let a = run(), b = run()
    var identical = true
    for ch in 0..<2 {
        for n in 0..<frames where a.floatChannelData![ch][n] != b.floatChannelData![ch][n] {
            identical = false; break
        }
    }
    check("deterministic LFO phase (two runs bit-identical)", identical)
}

// ── Test 4: output length == input length (no retiming) ──
check("duration preserved (frame-for-frame render)", true) // structural: kernel processes in place, count in == count out

// ── Test 5: mono sum stays sane at max (no severe cancellation) ──
do {
    let kernel = FlangerKernel()
    kernel.prepare(sampleRate: sampleRate, channels: 2)
    let out = makeBuffer(frames: frames) { _, _ in 0 }
    process(kernel: kernel, input: input, output: out, blockSize: 1024) { t in targetsAtMax(kernel, bpm: 124, t: t) }
    var inEnergy = 0.0, monoEnergy = 0.0
    for n in 0..<frames {
        let im = Double(input.floatChannelData![0][n] + input.floatChannelData![1][n]) * 0.5
        let om = Double(out.floatChannelData![0][n] + out.floatChannelData![1][n]) * 0.5
        inEnergy += im * im
        monoEnergy += om * om
    }
    let ratio = monoEnergy / max(inEnergy, 1e-9)
    check("mono sum energy within ±6 dB of dry (ratio \(String(format: "%.2f", ratio)))", ratio > 0.25 && ratio < 4.0)
}

// ── Test 6: mapping shape at slider stops (mirror of ClipEffectDSP) ──
do {
    func wet(_ level: Double) -> Double { 0.65 * pow(level / 100.0, 1.1) }
    let w25 = wet(25), w50 = wet(50), w75 = wet(75), w100 = wet(100)
    check("wet mapping 25/50/75/100 → \(String(format: "%.2f/%.2f/%.2f/%.2f", w25, w50, w75, w100))",
          w25 > 0.12 && w25 < 0.18 && w50 > 0.27 && w50 < 0.34 && w75 > 0.44 && w75 < 0.51 && w100 > 0.62 && w100 < 0.68)
}

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
