import AVFoundation
import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sr = 44100.0
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
let samples = (0..<Int(sr * 3)).map { Float(0.977 * sin(2 * Double.pi * 997 * Double($0) / sr)) }
let channels = [samples, samples]
let raw = folder.appendingPathComponent("unguarded.m4a")
do {
    let f = try AVAudioFile(forWriting: raw, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sr, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256000],
        commonFormat: .pcmFormatFloat32, interleaved: false)
    let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    b.frameLength = b.frameCapacity
    for c in 0..<2 { for i in samples.indices { b.floatChannelData![c][i] = samples[i] } }
    try f.write(from: b)
}
let audit = try MixrExportRenderer.encodePeakSafeAAC(channels, format: format, to: folder.appendingPathComponent("guarded.m4a"))
try JSONEncoder().encode(audit).write(to: folder.appendingPathComponent("audit.json"))
print("ENCODED_PEAK_CONTROL_DONE")
