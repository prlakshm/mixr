import Foundation

// Corpus render harness — NOT part of the app target. Runs the REAL Auto
// pipeline (SongSignalAnalyzer → AutoRemixPlanner → AutoRemixValidator)
// on decoded audio and renders the plan through AutoOfflineMixdown so the
// result can be measured (Scripts/elevenlabs_remix_audit.py) and auditioned.
//
//   Scripts/run_corpus_render.sh job.json
//
// job.json:
//   { "out": "/path/prefix", "seed": 1,
//     "songs": [ { "title": "…", "mono": "a.f32", "left": "aL.f32",
//                  "right": "aR.f32", "bpm": 124, "key": "Am" } ],
//     "sfxDir": "Mixr/Resources/SFX" }
// Raw files are little-endian float32 at 44.1 kHz (ffmpeg -f f32le).
// Beatmatched songs are pre-stretched with Rubber Band (pitch preserved)
// for audition quality; the plan itself is untouched.

struct Job: Decodable {
    struct Song: Decodable { var title: String; var mono: String; var left: String; var right: String; var bpm: Int?; var key: String? }
    var out: String
    var seed: UInt64?
    var songs: [Song]
    var sfxDir: String?
}

func readF32(_ path: String) -> [Float] {
    guard let d = FileManager.default.contents(atPath: path) else { fatalError("missing \(path)") }
    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

func writeWAV(_ path: String, left: [Float], right: [Float], sampleRate: Int) {
    let n = min(left.count, right.count)
    var data = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4)); data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
    data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
    var pcm = [Int16](repeating: 0, count: n * 2)
    for i in 0..<n {
        pcm[2 * i] = Int16(max(-1, min(1, left[i])) * 32767)
        pcm[2 * i + 1] = Int16(max(-1, min(1, right[i])) * 32767)
    }
    pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    _ = FileManager.default.createFile(atPath: path, contents: data)
}

/// Time-stretches raw f32 by `ratio` (playback rate) with Rubber Band.
func stretched(_ path: String, rate: Double) -> [Float] {
    let tmp = NSTemporaryDirectory()
    let wavIn = tmp + "mixr_rb_in.wav", wavOut = tmp + "mixr_rb_out.wav", rawOut = tmp + "mixr_rb_out.f32"
    func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
    }
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", "44100", "-ac", "1", "-i", path, wavIn])
    run(["rubberband", "-q", "--fine", "-t", String(1.0 / rate), wavIn, wavOut])
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", wavOut, "-f", "f32le", "-ac", "1", "-ar", "44100", rawOut])
    return readF32(rawOut)
}

let jobPath = CommandLine.arguments[1]
let job = try! JSONDecoder().decode(Job.self, from: FileManager.default.contents(atPath: jobPath)!)
let sr = 44_100.0

var tracks: [MixrTrack] = []
var signals: [UUID: SongSignalFeatures] = [:]
var paths: [UUID: Job.Song] = [:]
for song in job.songs {
    let mono = readF32(song.mono)
    let duration = Double(mono.count) / sr
    let t0 = Date()
    let features = SongSignalAnalyzer.extract(samples: mono, sampleRate: sr, bpmHint: song.bpm.map(Double.init))
    let id = UUID()
    let track = MixrTrack(
        id: id, title: song.title, artist: "Corpus", duration: "--:--", durationSeconds: duration,
        bpm: song.bpm ?? features.structure.map { Int($0.bpm.rounded()) }, bpmConfidence: song.bpm == nil ? features.structure?.beatConfidence : nil,
        key: song.key, keyConfidence: nil, color: .pink, volume: 1.0, isMuted: false, url: nil, artworkData: nil,
        clips: [MixrClip(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: min(duration, 180)))]
    )
    tracks.append(track)
    signals[id] = features
    paths[id] = song
    let st = features.structure
    FileHandle.standardError.write("analyzed \(song.title): \(String(format: "%.1f", Date().timeIntervalSince(t0)))s bpm \(st.map { String(format: "%.2f", $0.bpm) } ?? "-") conf \(String(format: "%.2f", features.overallConfidence))\n".data(using: .utf8)!)
}

guard let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: tracks, seed: job.seed ?? 1, signals: signals) else {
    print("{\"error\": \"no plan\"}"); exit(1)
}
let plan = AutoRemixValidator.validate(draft, profiles: profiles, tuning: .standard)

// ── Render (stereo = the same plan over each channel) ──
var sfx: [String: [Float]] = [:]
if let dir = job.sfxDir {
    for def in SoundEffectLibrary.all {
        let wav = dir + "/" + def.assetName
        guard FileManager.default.fileExists(atPath: wav) else { continue }
        let raw = NSTemporaryDirectory() + "mixr_sfx.f32"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-f", "f32le", "-ac", "1", "-ar", "44100", raw]
        try! p.run(); p.waitUntilExit()
        // Bundled assets get the policy's nominal gain baked in by the
        // engines; the mixdown applies it itself, so pass them raw.
        sfx[def.id] = readF32(raw)
    }
}
var renderPlan = plan
var leftSources: [UUID: AutoOfflineMixdown.Source] = [:]
var rightSources: [UUID: AutoOfflineMixdown.Source] = [:]
for (id, song) in paths {
    let rates = Set(plan.placements.filter { $0.songID == id }.map { ($0.tempoRatio * 10000).rounded() / 10000 })
    if let rate = rates.first, rates.count == 1, abs(rate - 1) > 0.0005 {
        leftSources[id] = .init(samples: stretched(song.left, rate: rate), sampleRate: sr)
        rightSources[id] = .init(samples: stretched(song.right, rate: rate), sampleRate: sr)
        for i in renderPlan.placements.indices where renderPlan.placements[i].songID == id {
            renderPlan.placements[i].sourceStart /= rate
            renderPlan.placements[i].tempoRatio = 1
        }
    } else {
        leftSources[id] = .init(samples: readF32(song.left), sampleRate: sr)
        rightSources[id] = .init(samples: readF32(song.right), sampleRate: sr)
    }
}
let l = AutoOfflineMixdown.render(plan: renderPlan, sources: leftSources, sampleRate: sr, sfxSamples: sfx)
let r = AutoOfflineMixdown.render(plan: renderPlan, sources: rightSources, sampleRate: sr, sfxSamples: sfx)
writeWAV(job.out + ".wav", left: l.mix, right: r.mix, sampleRate: 44_100)

// ── Plan JSON (for diagnostics / the audit) ──
struct P: Encodable {
    var song: String; var sourceStart, sourceEnd, timelineStart, timelineEnd, rate, volume: Double
    var fadeIn, fadeOut: String; var continues: Bool; var overlap: Double
}
struct Out: Encodable {
    var mode: String; var targetBPM: Double; var duration: Double; var limiterDB: Double
    var placements: [P]; var sfx: [String]; var cuts: [String]; var decisions: [String]; var warnings: [String]
    var transitions: [String]; var payoffTimes: [Double]; var joins: [Double]
}
func edge(_ t: ClipTransition) -> String { "\(t.type.rawValue)/\(String(format: "%.1f", t.duration))b\(t.filter.map { "/" + $0.rawValue } ?? "")" }
let titles = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.title) })
let out = Out(
    mode: plan.mode.rawValue, targetBPM: plan.targetBPM, duration: plan.targetDuration, limiterDB: max(l.limiterGainReductionDB, r.limiterGainReductionDB),
    placements: plan.placements.sorted { $0.timelineStart < $1.timelineStart }.map {
        P(song: titles[$0.songID] ?? "?", sourceStart: $0.sourceStart, sourceEnd: $0.sourceEnd, timelineStart: $0.timelineStart,
          timelineEnd: $0.timelineEnd, rate: $0.tempoRatio, volume: $0.volume, fadeIn: edge($0.fadeIn), fadeOut: edge($0.fadeOut),
          continues: $0.continuesPrevious, overlap: $0.overlapsPreviousSeconds)
    },
    sfx: plan.sfxEvents.map { String(format: "%.2f %@ — %@", $0.timelineStart, $0.assetID, $0.purpose) },
    cuts: plan.cutRecords.map { String(format: "%.2f %@ %.1f→%.1f", $0.timelineAt, $0.reason.rawValue, $0.sourceFrom, $0.sourceTo) },
    decisions: plan.decisions.map(\.userFacingSentence), warnings: plan.warnings,
    transitions: plan.transitionsUsed.map(\.rawValue), payoffTimes: plan.payoffTimes,
    joins: plan.placements.filter { !$0.continuesPrevious }.map(\.timelineStart).sorted().filter { $0 > 0.5 }
)
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
_ = FileManager.default.createFile(atPath: job.out + ".plan.json", contents: try! enc.encode(out))
print(String(data: try! enc.encode(out), encoding: .utf8)!)
