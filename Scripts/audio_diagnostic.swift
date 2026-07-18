import AVFoundation
import CoreMedia
import Foundation

struct WindowMetric {
    let start: Double
    let rmsDB: Double
    let peak: Float
    let nearClipSamples: Int
}

guard CommandLine.arguments.count == 2 else { fatalError("usage: audio_diagnostic <audio-file>") }

let sampleRate = 44_100.0
let channelCount = 2
let framesPerWindow = Int(sampleRate * 0.1)
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let track = asset.tracks(withMediaType: .audio).first else { fatalError("no audio track") }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
)
output.alwaysCopiesSampleData = false
guard reader.canAdd(output) else { fatalError("cannot add reader output") }
reader.add(output)
guard reader.startReading() else { fatalError("reader start failed: \(String(describing: reader.error))") }

var frameIndex: Int64 = 0
var sampleCount: Int64 = 0
var sumSquares = 0.0
var sum = 0.0
var absolutePeak: Float = 0
var countAt099 = 0
var countAt0999 = 0
var countAt1 = 0
var longestNearClipRun = 0
var currentNearClipRun = Array(repeating: 0, count: channelCount)
var previous = Array(repeating: Float(0), count: channelCount)
var hasPrevious = Array(repeating: false, count: channelCount)
var maxJump: Float = 0
var maxJumpTime = 0.0
var windowFrameCount = 0
var windowSumSquares = 0.0
var windowPeak: Float = 0
var windowNearClipSamples = 0
var windows: [WindowMetric] = []

func flushWindow() {
    guard windowFrameCount > 0 else { return }
    let rms = sqrt(windowSumSquares / Double(windowFrameCount * channelCount))
    windows.append(
        WindowMetric(
            start: Double(windows.count * framesPerWindow) / sampleRate,
            rmsDB: 20 * log10(max(rms, 1e-12)),
            peak: windowPeak,
            nearClipSamples: windowNearClipSamples
        )
    )
    windowFrameCount = 0
    windowSumSquares = 0
    windowPeak = 0
    windowNearClipSamples = 0
}

while let sampleBuffer = output.copyNextSampleBuffer() {
    guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
    var lengthAtOffset = 0
    var totalLength = 0
    var rawPointer: UnsafeMutablePointer<Int8>?
    let status = CMBlockBufferGetDataPointer(
        block,
        atOffset: 0,
        lengthAtOffsetOut: &lengthAtOffset,
        totalLengthOut: &totalLength,
        dataPointerOut: &rawPointer
    )
    guard status == kCMBlockBufferNoErr, let rawPointer else { continue }
    let floatCount = totalLength / MemoryLayout<Float>.size
    let samples = UnsafeRawPointer(rawPointer).bindMemory(to: Float.self, capacity: floatCount)
    let frameCount = floatCount / channelCount

    for frame in 0..<frameCount {
        for channel in 0..<channelCount {
            let value = samples[frame * channelCount + channel]
            let magnitude = abs(value)
            sampleCount += 1
            sum += Double(value)
            sumSquares += Double(value * value)
            windowSumSquares += Double(value * value)
            absolutePeak = max(absolutePeak, magnitude)
            windowPeak = max(windowPeak, magnitude)
            if magnitude >= 0.99 { countAt099 += 1 }
            if magnitude >= 0.999 {
                countAt0999 += 1
                windowNearClipSamples += 1
                currentNearClipRun[channel] += 1
                longestNearClipRun = max(longestNearClipRun, currentNearClipRun[channel])
            } else {
                currentNearClipRun[channel] = 0
            }
            if magnitude >= 1.0 { countAt1 += 1 }
            if hasPrevious[channel] {
                let jump = abs(value - previous[channel])
                if jump > maxJump {
                    maxJump = jump
                    maxJumpTime = Double(frameIndex + Int64(frame)) / sampleRate
                }
            }
            previous[channel] = value
            hasPrevious[channel] = true
        }
        windowFrameCount += 1
        if windowFrameCount == framesPerWindow { flushWindow() }
    }
    frameIndex += Int64(frameCount)
}
flushWindow()

if reader.status == .failed { fatalError("reader failed: \(String(describing: reader.error))") }

let duration = Double(frameIndex) / sampleRate
let overallRMS = sqrt(sumSquares / Double(max(sampleCount, 1)))
let overallDB = 20 * log10(max(overallRMS, 1e-12))
let crestDB = 20 * log10(max(Double(absolutePeak) / max(overallRMS, 1e-12), 1e-12))
let dc = sum / Double(max(sampleCount, 1))

print(String(format: "duration=%.3fs sampleRate=%.0f channels=%d", duration, sampleRate, channelCount))
print(String(format: "peak=%.6f (%.2f dBFS) rms=%.2f dBFS crest=%.2f dB dc=%+.7f", absolutePeak, 20 * log10(max(Double(absolutePeak), 1e-12)), overallDB, crestDB, dc))
print(String(format: ">=0.99=%d (%.5f%%) >=0.999=%d (%.5f%%) >=1.0=%d (%.5f%%)", countAt099, 100 * Double(countAt099) / Double(sampleCount), countAt0999, 100 * Double(countAt0999) / Double(sampleCount), countAt1, 100 * Double(countAt1) / Double(sampleCount)))
print(String(format: "longest>=0.999=%.3fms maxAdjacentJump=%.6f at %.3fs", 1000 * Double(longestNearClipRun) / sampleRate, maxJump, maxJumpTime))

func printRuns(label: String, matching: (WindowMetric) -> Bool, minimumWindows: Int) {
    var start: Int?
    for i in 0...windows.count {
        let matches = i < windows.count && matching(windows[i])
        if matches, start == nil { start = i }
        if !matches, let s = start {
            if i - s >= minimumWindows {
                let range = windows[s..<i]
                print(String(format: "%@ %.2f-%.2fs (%dms, rms %.1f..%.1f dBFS)", label, windows[s].start, min(duration, windows[i - 1].start + 0.1), (i - s) * 100, range.map(\.rmsDB).min() ?? 0, range.map(\.rmsDB).max() ?? 0))
            }
            start = nil
        }
    }
}

printRuns(label: "QUIET<-35", matching: { $0.rmsDB < -35 }, minimumWindows: 2)
printRuns(label: "SILENCE<-45", matching: { $0.rmsDB < -45 }, minimumWindows: 2)

print("TOP_CLIPPED_WINDOWS")
for item in windows.filter({ $0.nearClipSamples >= 5 }).sorted(by: { $0.nearClipSamples > $1.nearClipSamples }).prefix(25) {
    print(String(format: "  %.2fs rms=%6.1f peak=%.5f nearClip=%d", item.start, item.rmsDB, item.peak, item.nearClipSamples))
}

print("LARGEST_100MS_LEVEL_JUMPS")
let jumps = (1..<windows.count).map { i in
    (time: windows[i].start, delta: windows[i].rmsDB - windows[i - 1].rmsDB, before: windows[i - 1].rmsDB, after: windows[i].rmsDB)
}
for item in jumps.sorted(by: { abs($0.delta) > abs($1.delta) }).prefix(30) {
    print(String(format: "  %.2fs delta=%+6.1fdB (%6.1f -> %6.1f)", item.time, item.delta, item.before, item.after))
}

func meanDB(from start: Double, to end: Double) -> Double {
    let pool = windows.filter { $0.start >= start && $0.start < end }
    guard !pool.isEmpty else { return -120 }
    let meanPower = pool.map { pow(10, $0.rmsDB / 10) }.reduce(0, +) / Double(pool.count)
    return 10 * log10(max(meanPower, 1e-12))
}

let bpm = 103.0
let bar = 240.0 / bpm
let bars = [4, 8, 4, 8, 8, 4, 16, 4]
var cursor = 0.0
print("EXPECTED_103BPM_SLOT_BOUNDARIES")
for slotBars in bars.dropLast() {
    cursor += Double(slotBars) * bar
    print(String(format: "  %.3fs before=%6.1f center=%6.1f after=%6.1f dBFS", cursor, meanDB(from: max(0, cursor - 1), to: cursor - 0.2), meanDB(from: cursor - 0.2, to: cursor + 0.2), meanDB(from: cursor + 0.2, to: cursor + 1)))
}
