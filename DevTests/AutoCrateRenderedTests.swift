// Render the crate through the REAL app DSP path for listening.
//
// Bounces/*.wav come from AutoOfflineMixdown — a deterministic reference
// renderer used by the quality gates. It explicitly does NOT model
// AVAudioUnitTimePitch, and approximates reverb with a tap cluster. Judging
// the mix by those files is how "metallic / robot glitchy" got chased for a
// day. These renders go through MixrExportRenderer — the same AVAudioUnit
// chain (TimePitch → EQ → flanger → delay → reverb → peak limiter) the app
// uses for playback and export — so they are what a user actually hears.
//
// Output: Bounces/LISTEN/<name>.m4a

import AVFoundation
import CoreMedia
import Foundation

let songsDir = "/Users/pranavi/Documents/Mixr/Songs"
guard CommandLine.arguments.count >= 2 else { fatalError("Output directory required") }
let outDir = CommandLine.arguments[1]
let stemsRoot = URL(fileURLWithPath: "/Users/pranavi/Documents/Mixr/Stems/htdemucs_ft")

func decodeMono(_ path: String, targetRate: Double = 44100) throws -> (samples: [Float], rate: Double) {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
        throw NSError(domain: "mixr", code: 1, userInfo: [NSLocalizedDescriptionKey: "no audio \(path)"])
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: targetRate,
        AVNumberOfChannelsKey: 1,
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "mixr", code: 2) }
    var samples: [Float] = []
    while let buf = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buf) {
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        if let dataPointer {
            dataPointer.withMemoryRebound(to: Float.self, capacity: length / 4) { fp in
                samples.append(contentsOf: UnsafeBufferPointer(start: fp, count: length / 4))
            }
        }
        CMSampleBufferInvalidate(buf)
    }
    return (samples, targetRate)
}

func makeTrack(title: String, artist: String, bpm: Int, key: String, duration: Double,
               color: MixrWaveformColor, url: URL?) -> MixrTrack {
    let length = MixrTimeline.units(fromSeconds: min(duration, 180))
    return MixrTrack(
        id: UUID(), title: title, artist: artist,
        duration: String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60),
        durationSeconds: duration, bpm: bpm, key: key, color: color,
        volume: 1.0, isMuted: false, url: url,
        clips: [MixrClip(id: UUID(), start: 0, length: length)]
    )
}

struct Item {
    var file: String, title: String, artist: String, bpm: Int, key: String
    var color: MixrWaveformColor
}

let items: [Item] = [
    .init(file: "britney-baby-one-more-time.mp3", title: "Baby One More Time", artist: "Britney", bpm: 93, key: "Cm", color: .pink),
    .init(file: "britney-oops-i-did-it-again.mp3", title: "Oops I Did It Again", artist: "Britney", bpm: 95, key: "C#m", color: .blue),
    .init(file: "olivia-stupid-song.mp3", title: "stupid song", artist: "Olivia", bpm: 128, key: "B", color: .purple),
    .init(file: "paramore-all-i-wanted.mp3", title: "All I Wanted", artist: "Paramore", bpm: 144, key: "F#m", color: .red),
    .init(file: "tatu-all-the-things-she-said.mp3", title: "All The Things She Said", artist: "t.A.T.u.", bpm: 90, key: "Fm", color: .yellow),
]

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var tracks: [MixrTrack] = []
var signals: [UUID: SongSignalFeatures] = [:]

for item in items {
    let path = "\(songsDir)/\(item.file)"
    let decoded = try decodeMono(path)
    let features = SongSignalAnalyzer.extract(samples: decoded.samples, sampleRate: decoded.rate, bpmHint: Double(item.bpm))
    let duration = Double(decoded.samples.count) / decoded.rate
    let track = makeTrack(title: item.title, artist: item.artist, bpm: item.bpm, key: item.key,
                          duration: duration, color: item.color, url: URL(fileURLWithPath: path))
    tracks.append(track)
    signals[track.id] = features
    print("decoded \(item.title) (\(String(format: "%.1f", duration))s)")
}

func sig(_ subset: [MixrTrack]) -> [UUID: SongSignalFeatures] {
    var out: [UUID: SongSignalFeatures] = [:]
    for t in subset { out[t.id] = signals[t.id] }
    return out
}

/// name → track subset. Solo entries render the single-song club remix.
var cases: [(name: String, idx: [Int])] = [
    ("01-mashup-oops-x-baby",        [1, 0]),
    ("02-mashup-paramore-x-tatu",    [3, 4]),
    ("03-mashup-all-5",              [0, 1, 2, 3, 4]),
    ("04-remix-oops-i-did-it-again", [1]),
    ("05-remix-baby-one-more-time",  [0]),
    ("06-remix-stupid-song",         [2]),
    ("07-remix-all-i-wanted",        [3]),
    ("08-remix-all-the-things-she-said", [4]),
]

if CommandLine.arguments.contains("--all-subsets") {
    cases = (1..<(1 << items.count)).map { mask in
        let indices = items.indices.filter { mask & (1 << $0) != 0 }
        return (name: "crate-" + indices.map(String.init).joined(separator: "-"), idx: indices)
    }
} else if CommandLine.arguments.contains("--pair-only") {
    cases = Array(cases.prefix(2))
}

if let index = CommandLine.arguments.firstIndex(of: "--case"), index + 1 < CommandLine.arguments.count {
    cases = cases.filter { $0.name == CommandLine.arguments[index + 1] }
}
guard !cases.isEmpty else { fatalError("No requested render cases") }

func gitCommit() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", "/Users/pranavi/Documents/GitHub/mixr", "rev-parse", "HEAD"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
}

func inputAssetHashes(_ subset: [MixrTrack]) -> [String: String] {
    var out: [String: String] = [:]
    for t in subset {
        guard let url = t.url else { continue }
        out[url.lastPathComponent] = (try? AutoJoinManifest.sha256(ofFile: url)) ?? ""
    }
    return out
}

var failures = 0
for c in cases {
    let subset = c.idx.map { tracks[$0] }
    print("\n=== \(c.name) ===")
    switch AutoRemixRunner.runEntireProject(
        tracks: subset, seed: 20260815, signals: sig(subset), stemsRoot: stemsRoot
    ) {
    case .failure(let message):
        print("  FAIL runner: \(message)")
        failures += 1
    case .success(let applied, let plan, let summary):
        let drops = plan.pulseRegions.filter { $0.role == .drop }
            .map(\.timelineStart).sorted()
        let dropStr = drops.prefix(2)
            .map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }
            .joined(separator: ", ")
        print("  \(summary.modeTitle) bpm=\(summary.targetBPM) drops at \(dropStr)")
        // Same definition as the crate bounce gate / listen-loop invariant.
        let titleTimes = plan.placements.filter {
            $0.role == .dominant && $0.stemKind == .vocals && $0.timelineDuration > plan.barSeconds * 6
        }.map(\.timelineStart)
        if let t = titleTimes.min(), let d1 = drops.first {
            print(String(format: "  TITLE_PROBE t=%.2f drop1=%.2f beat=%.3f", t, d1, plan.beatSeconds))
        }
        if ProcessInfo.processInfo.environment["MIXR_DUMP_DROPS"] == "1" {
            let bar = plan.barSeconds
            for (di, d) in drops.enumerated() {
                print(String(format: "  -- drop %d @%.2f --", di + 1, d))
                for e in plan.sfxEvents.sorted(by: { $0.timelineStart < $1.timelineStart })
                where e.timelineEnd > d - 3 * bar && e.timelineStart < d + bar {
                    print(String(format: "     SFX %@ %.2f-%.2f", e.assetID, e.timelineStart, e.timelineEnd))
                }
                for p in plan.placements.sorted(by: { $0.timelineStart < $1.timelineStart })
                where p.timelineEnd > d - 2 * bar && p.timelineStart < d + bar {
                    print(String(format: "     CLIP %@ %@ %.2f-%.2f vol=%.2f blur=%.0f",
                                 p.role.rawValue, p.stemKind?.rawValue ?? "mix",
                                 p.timelineStart, p.timelineEnd, p.volume,
                                 p.effects.level(for: "blur")))
                }
            }
        }
        do {
            let url = try MixrExportRenderer.export(
                tracks: applied,
                projectName: c.name,
                projectBPM: Int(plan.targetBPM.rounded()),
                auditURL: URL(fileURLWithPath: "\(outDir)/\(c.name).master_audit.json")
            )
            let dest = URL(fileURLWithPath: "\(outDir)/\(c.name).\(url.pathExtension)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: url, to: dest)
            print("  wrote \(dest.lastPathComponent)")
            let audioHash = try AutoJoinManifest.sha256(ofFile: dest)
            let extra: [String: Any] = [
                "targetBPM": plan.targetBPM,
                "sfxEvents": plan.sfxEvents.map { ["assetID": $0.assetID, "timelineStart": $0.timelineStart, "duration": $0.duration] as [String: Any] },
                "intentionalGaps": plan.intentionalGaps.map { ["start": $0.start, "end": $0.end, "reason": $0.reason] as [String: Any] },
                "placements": plan.placements.map { p -> [String: Any] in
                    ["songID": p.songID.uuidString, "sourceStart": p.sourceStart,
                     "timelineStart": p.timelineStart, "timelineDuration": p.timelineDuration,
                     "tempoRatio": p.tempoRatio, "volume": p.volume,
                     "stemKind": p.stemKind?.rawValue ?? "fullMix", "role": p.role.rawValue,
                     "effects": p.effects.levels, "continuesPrevious": p.continuesPrevious,
                     "fadeIn": ["type": p.fadeIn.type.rawValue, "beats": p.fadeIn.duration, "curve": p.fadeIn.curve, "floorGain": p.fadeIn.floorGain as Any? ?? NSNull()],
                     "fadeOut": ["type": p.fadeOut.type.rawValue, "beats": p.fadeOut.duration, "curve": p.fadeOut.curve, "floorGain": p.fadeOut.floorGain as Any? ?? NSNull()],
                     "overlapSeconds": p.overlapsPreviousSeconds]
                },
                "sourceIdentity": subset.map { ["id": $0.id.uuidString, "path": $0.url?.path ?? ""] },
                "dropBars": drops.map { $0 / plan.barSeconds },
                "warnings": plan.warnings,
                "gitCommit": gitCommit(),
                "audioSHA256": audioHash,
                "inputAssetHashes": inputAssetHashes(subset),
            ]
            let manifestURL = URL(fileURLWithPath: "\(outDir)/\(c.name).join_manifest.json")
            try AutoJoinManifest.writeAtomic(
                AutoJoinManifest.dictionary(from: plan, extra: extra),
                to: manifestURL
            )
            print("  wrote \(manifestURL.lastPathComponent)")
        } catch {
            print("  FAIL export: \(error)")
            failures += 1
        }
    }
}
print("\nLISTEN_RENDERS_DONE cases=\(cases.count) failures=\(failures)")
if failures > 0 { exit(1) }
