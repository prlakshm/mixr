import AppKit
import AVFoundation

guard CommandLine.arguments.count >= 4 else {
    fatalError("usage: script input.mp4 output-prefix seconds...")
}

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

for (index, secondsText) in CommandLine.arguments.dropFirst(3).enumerated() {
    guard let seconds = Double(secondsText) else { continue }
    let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    let path = "\(CommandLine.arguments[2])-\(index)-\(secondsText).png"
    try png.write(to: URL(fileURLWithPath: path))
}
