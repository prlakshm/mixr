import AVFoundation
import AudioToolbox

// MARK: - Flanger
//
// A real modulated fractional-delay flanger. iOS ships no built-in
// modulated-delay AudioUnit, so this file provides a custom AUAudioUnit
// (registered in-process) that both engines insert between the Blur
// low-pass EQ and the Echo delay:
//
//   player → timePitch → EQ (Blur) → FLANGER → delay → reverb → …
//
// Signal path per channel, per sample:
//
//   1. dry input
//   2. very short delayed copy (fractional read, linear interpolation)
//   3. sine LFO smoothly modulating the delay time (BPM-synced sweep)
//   4. controlled feedback written back into the delay line
//   5. wet/dry output mix with modest gain compensation
//
// The source audio always plays forward normally — the flanger only
// colors it with a moving comb-filter sweep; it never repeats, trims,
// or retimes the clip.
//
// Parameter targets come from ClipEffectDSP.targets(...) — the SINGLE
// slider→parameter mapping shared by MixrPlaybackEngine (live) and
// MixrExportRenderer (offline), so exports match playback. The LFO
// phase is derived from the PROJECT TIMELINE position (host-supplied
// every update), so playback is deterministic, seeking is consistent,
// and multiple playback starts never produce random sweep positions.
//
// All audible parameters are smoothed per-sample inside the kernel:
// no clicks, zipper noise, or comb jumps when the slider moves, and
// the engine graph is never rebuilt for a parameter change.

// MARK: - Kernel

/// Render-thread DSP state + host-set parameter targets.
///
/// Targets are written from the main actor (live ticks) or the export
/// render loop, and read on the audio render thread. Every field is a
/// word-sized scalar (no torn reads on arm64) and every audible value
/// is re-smoothed per sample, so no locking is needed.
nonisolated final class FlangerKernel {

    /// Longest supported delay excursion (base + depth ≤ ~10 ms, with margin).
    static let maxDelaySeconds = 0.02
    /// Small constant L/R LFO offset (cycles) — gentle width, cohesive
    /// motion, no ping-pong, and safe mono summing.
    private static let rightChannelPhaseOffset: Double = 0.04

    // ── Host-set targets ──
    private var targetWet: Float = 0
    private var targetFeedback: Float = 0
    private var targetDepthSeconds: Float = 0
    private var targetBaseDelaySeconds: Float = 0.0006
    private var targetLFOFrequency: Float = 0.25
    private var hostPhase: Float = 0
    private var hostPhaseEpoch: Int32 = 0

    // ── Render-thread smoothed state ──
    private var wet: Float = 0
    private var feedback: Float = 0
    private var depthSeconds: Float = 0
    private var baseDelaySeconds: Float = 0.0006
    private var lfoFrequency: Float = 0.25
    private var phase: Double = 0
    private var appliedPhaseEpoch: Int32 = 0
    private var smoothedDelaySamples: (Float, Float) = (0, 0)
    private var wasBypassed = true

    // ── Delay lines (raw pointers: allocation-free on the render thread) ──
    private var lines: UnsafeMutablePointer<Float>?
    private var capacity = 0
    private var lineChannels = 0
    private var writeIndex = 0
    private var sampleRate: Double = 44_100
    /// One-pole coefficients, derived from sampleRate in prepare().
    private var paramCoeff: Float = 0.001
    private var delayCoeff: Float = 0.005

    deinit {
        lines?.deallocate()
    }

    /// Called from allocateRenderResources — safe to allocate here.
    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = max(8_000, sampleRate)
        lineChannels = max(1, min(2, channels))
        capacity = Int(Self.maxDelaySeconds * self.sampleRate) + 8

        lines?.deallocate()
        lines = UnsafeMutablePointer<Float>.allocate(capacity: capacity * lineChannels)
        lines?.initialize(repeating: 0, count: capacity * lineChannels)
        writeIndex = 0
        wasBypassed = true

        // ~30 ms constant for musical params, ~4 ms for delay de-click.
        paramCoeff = 1 - exp(Float(-1.0 / (0.030 * self.sampleRate)))
        delayCoeff = 1 - exp(Float(-1.0 / (0.004 * self.sampleRate)))
    }

    /// Host update — live tick (60 fps) or export block (~23 ms).
    /// `phase` is the timeline-derived LFO phase 0…1; the kernel free-runs
    /// between updates and re-pins to the host phase on every call, which
    /// keeps the sweep deterministic across seeks, restarts, and export.
    func setTargets(
        wet: Float,
        feedback: Float,
        depthSeconds: Float,
        baseDelaySeconds: Float,
        lfoFrequency: Float,
        phase: Float
    ) {
        targetWet = max(0, min(0.75, wet))
        targetFeedback = max(0, min(0.85, feedback))
        targetDepthSeconds = max(0, min(Float(Self.maxDelaySeconds) * 0.5, depthSeconds))
        targetBaseDelaySeconds = max(0.0002, min(0.002, baseDelaySeconds))
        targetLFOFrequency = max(0.02, min(4, lfoFrequency))
        hostPhase = phase - phase.rounded(.down)
        hostPhaseEpoch &+= 1
    }

    /// True bypass — audio must be bit-identical to the unprocessed clip.
    private var isAtRest: Bool {
        targetWet <= 0.0005 && wet <= 0.0005 && feedback <= 0.001
    }

    /// Processes deinterleaved float32. `input` and `output` may share
    /// buffers (in-place). Channels beyond the first two pass through dry.
    func process(
        input: UnsafeMutablePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) {
        let inABL = UnsafeMutableAudioBufferListPointer(input)
        let outABL = UnsafeMutableAudioBufferListPointer(output)
        let ioChannels = min(inABL.count, outABL.count)
        guard ioChannels > 0, frameCount > 0, let lines else {
            passthrough(inABL: inABL, outABL: outABL, channels: ioChannels, frameCount: frameCount)
            return
        }

        if isAtRest {
            // True bypass: copy through, pin phase so re-engaging starts
            // exactly where the timeline says the sweep should be.
            passthrough(inABL: inABL, outABL: outABL, channels: ioChannels, frameCount: frameCount)
            phase = Double(hostPhase)
            appliedPhaseEpoch = hostPhaseEpoch
            wet = 0
            feedback = 0
            wasBypassed = true
            return
        }

        if wasBypassed {
            // Re-engaging: clear stale delay history so nothing from an
            // earlier clip leaks in, and start from the host state.
            lines.update(repeating: 0, count: capacity * lineChannels)
            writeIndex = 0
            depthSeconds = targetDepthSeconds
            baseDelaySeconds = targetBaseDelaySeconds
            lfoFrequency = targetLFOFrequency
            phase = Double(hostPhase)
            appliedPhaseEpoch = hostPhaseEpoch
            let startDelay = (baseDelaySeconds + depthSeconds) * Float(sampleRate)
            smoothedDelaySamples = (startDelay, startDelay)
            wasBypassed = false
        }

        if appliedPhaseEpoch != hostPhaseEpoch {
            // Timeline re-pin. Jumps are tiny between 60 fps updates; the
            // per-sample delay smoothing absorbs seek-sized jumps cleanly.
            appliedPhaseEpoch = hostPhaseEpoch
            phase = Double(hostPhase)
        }

        let fxChannels = min(ioChannels, lineChannels)
        let srF = Float(sampleRate)
        let twoPi = Float(2.0 * Double.pi)
        var localPhase = phase
        let maxDelay = Float(capacity - 2)

        // Fixed channel pointers — no heap allocation on the render thread.
        guard let in0 = inABL[0].mData?.assumingMemoryBound(to: Float.self),
              let out0 = outABL[0].mData?.assumingMemoryBound(to: Float.self) else {
            passthrough(inABL: inABL, outABL: outABL, channels: ioChannels, frameCount: frameCount)
            return
        }
        var in1 = in0
        var out1 = out0
        if fxChannels > 1 {
            guard let i1 = inABL[1].mData?.assumingMemoryBound(to: Float.self),
                  let o1 = outABL[1].mData?.assumingMemoryBound(to: Float.self) else {
                passthrough(inABL: inABL, outABL: outABL, channels: ioChannels, frameCount: frameCount)
                return
            }
            in1 = i1
            out1 = o1
        }

        for n in 0..<frameCount {
            // Per-sample one-pole smoothing — no zipper on slider moves.
            wet += (targetWet - wet) * paramCoeff
            feedback += (targetFeedback - feedback) * paramCoeff
            depthSeconds += (targetDepthSeconds - depthSeconds) * paramCoeff
            baseDelaySeconds += (targetBaseDelaySeconds - baseDelaySeconds) * paramCoeff
            lfoFrequency += (targetLFOFrequency - lfoFrequency) * paramCoeff

            // Modest compensation: stronger effect, not louder output.
            // Light makeup so intensity reads as more sweep, not more volume.
            let dryGain = 1 - 0.28 * wet
            let makeup = 1 / (1 + 0.16 * wet + 0.30 * wet * feedback)

            for ch in 0..<fxChannels {
                let chPhase = localPhase + (ch == 1 ? Self.rightChannelPhaseOffset : 0)
                let lfo = 0.5 * (1 + sin(twoPi * Float(chPhase - chPhase.rounded(.down))))
                var delaySamples = (baseDelaySeconds + depthSeconds * lfo) * srF
                // Final de-click smoothing directly on the delay length.
                var smoothed = ch == 0 ? smoothedDelaySamples.0 : smoothedDelaySamples.1
                smoothed += (delaySamples - smoothed) * delayCoeff
                if ch == 0 { smoothedDelaySamples.0 = smoothed } else { smoothedDelaySamples.1 = smoothed }
                delaySamples = min(max(1, smoothed), maxDelay)

                // Fractional delay read (linear interpolation).
                var readPos = Float(writeIndex) - delaySamples
                if readPos < 0 { readPos += Float(capacity) }
                let i0 = Int(readPos)
                let frac = readPos - Float(i0)
                let i1 = i0 + 1 == capacity ? 0 : i0 + 1
                let base = ch * capacity
                let delayed = lines[base + i0] * (1 - frac) + lines[base + i1] * frac

                let x = ch == 0 ? in0[n] : in1[n]
                // Stable feedback path — clamped write keeps the loop safe
                // even at maximum intensity.
                var fbSample = x + delayed * feedback
                fbSample = min(max(fbSample, -4), 4)
                lines[base + writeIndex] = fbSample

                let y = (x * dryGain + delayed * wet) * makeup
                if ch == 0 { out0[n] = y } else { out1[n] = y }
            }

            writeIndex += 1
            if writeIndex == capacity { writeIndex = 0 }
            localPhase += Double(lfoFrequency) / sampleRate
            if localPhase >= 1 { localPhase -= 1 }
        }
        phase = localPhase

        // Extra channels (beyond stereo) pass through dry.
        for ch in fxChannels..<ioChannels {
            copyChannel(from: inABL[ch], to: &outABL[ch], frameCount: frameCount)
        }
    }

    private func passthrough(
        inABL: UnsafeMutableAudioBufferListPointer,
        outABL: UnsafeMutableAudioBufferListPointer,
        channels: Int,
        frameCount: Int
    ) {
        for ch in 0..<channels {
            copyChannel(from: inABL[ch], to: &outABL[ch], frameCount: frameCount)
        }
    }

    private func copyChannel(from src: AudioBuffer, to dst: inout AudioBuffer, frameCount: Int) {
        guard let s = src.mData, let d = dst.mData, s != d else { return }
        memcpy(d, s, frameCount * MemoryLayout<Float>.size)
    }
}

// MARK: - AUAudioUnit

/// Minimal v3 effect unit hosting FlangerKernel. Registered in-process;
/// parameters are driven directly through the kernel (not AUParameters)
/// because both consumers already share ClipEffectDSP for mapping.
nonisolated final class FlangerAudioUnit: AUAudioUnit {
    let kernel = FlangerKernel()

    /// Buffers shared with the render block via a reference (the render
    /// block must not capture self).
    private final class RenderState {
        var inputBuffer: AVAudioPCMBuffer?
    }

    private let renderState = RenderState()
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!

    override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = outputBus.format
        kernel.prepare(sampleRate: format.sampleRate, channels: Int(format.channelCount))
        renderState.inputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: maximumFramesToRender
        )
    }

    override func deallocateRenderResources() {
        renderState.inputBuffer = nil
        super.deallocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = self.kernel
        let state = self.renderState

        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            guard let inputBuffer = state.inputBuffer,
                  frameCount <= inputBuffer.frameCapacity
            else { return kAudioUnitErr_TooManyFramesToProcess }

            let byteSize = UInt32(frameCount) * UInt32(MemoryLayout<Float>.size)
            let inputABL = inputBuffer.mutableAudioBufferList
            let inBuffers = UnsafeMutableAudioBufferListPointer(inputABL)
            for i in 0..<inBuffers.count { inBuffers[i].mDataByteSize = byteSize }

            var pullFlags = AudioUnitRenderActionFlags()
            let err = pullInputBlock(&pullFlags, timestamp, frameCount, 0, inputABL)
            guard err == noErr else { return err }

            // If the host passed null output pointers, process in place
            // in our pulled input buffer.
            let outBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            for i in 0..<outBuffers.count {
                outBuffers[i].mDataByteSize = byteSize
                if outBuffers[i].mData == nil, i < inBuffers.count {
                    outBuffers[i].mData = inBuffers[i].mData
                }
            }

            kernel.process(input: inputABL, output: outputData, frameCount: Int(frameCount))
            return noErr
        }
    }
}

// MARK: - Node factory

/// Registers the flanger subclass once and instantiates AVAudioUnit
/// wrappers for engine graphs (live and offline export).
nonisolated enum ClipFlanger {

    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("flgr"),
        componentManufacturer: fourCC("Mixr"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let registerOnce: Void = {
        AUAudioUnit.registerSubclass(
            FlangerAudioUnit.self,
            as: componentDescription,
            name: "Mixr: Flanger",
            version: 1
        )
    }()

    /// Synchronous instantiation of an in-process registered subclass —
    /// fast (no XPC), used during graph construction on either engine.
    static func makeNode() -> AVAudioUnit? {
        _ = registerOnce
        var node: AVAudioUnit?
        let semaphore = DispatchSemaphore(value: 0)
        AVAudioUnit.instantiate(with: componentDescription, options: []) { unit, error in
            if let error {
                print("ClipFlanger: instantiate failed — \(error.localizedDescription)")
            }
            node = unit
            semaphore.signal()
        }
        semaphore.wait()
        return node
    }

    static func kernel(of node: AVAudioUnit?) -> FlangerKernel? {
        (node?.auAudioUnit as? FlangerAudioUnit)?.kernel
    }

    private static func fourCC(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) | FourCharCode(scalar.value & 0xFF)
        }
        return result
    }
}
