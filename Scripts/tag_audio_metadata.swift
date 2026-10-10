import AVFoundation

// Writes title, artist, tempo and initial-key tags into an .m4a (passthrough,
// no re-encode), the way DJ software tags a library.
//   tag_audio_metadata <in.m4a> <out.m4a> <title> <artist> <bpm> <key>
let args = CommandLine.arguments
guard args.count == 7, let bpm = Int(args[5]) else {
    FileHandle.standardError.write("usage: tag_audio_metadata in out title artist bpm key\n".data(using: .utf8)!)
    exit(2)
}

func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value
    item.extendedLanguageTag = "und"
    return item
}

let initialKey = AVMetadataItem.identifier(
    forKey: "com.apple.iTunes.initialkey" as NSString,
    keySpace: AVMetadataKeySpace(rawValue: "itlk")
)!
let session = AVAssetExportSession(
    asset: AVURLAsset(url: URL(fileURLWithPath: args[1])),
    presetName: AVAssetExportPresetPassthrough
)!
session.metadata = [
    item(.commonIdentifierTitle, args[3] as NSString),
    item(.commonIdentifierArtist, args[4] as NSString),
    item(.iTunesMetadataBeatsPerMin, NSNumber(value: bpm)),
    item(initialKey, args[6] as NSString),
]
try? FileManager.default.removeItem(atPath: args[2])
let done = DispatchSemaphore(value: 0)
var failure: Error?
Task {
    do { try await session.export(to: URL(fileURLWithPath: args[2]), as: .m4a) } catch { failure = error }
    done.signal()
}
done.wait()
if let failure {
    FileHandle.standardError.write("export failed: \(failure)\n".data(using: .utf8)!)
    exit(1)
}
