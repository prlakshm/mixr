// Copyright-free phrase fixture. The compositional grid below is independent
// of planner output. This is authored ground truth, not human audition approval.
import Foundation
import AVFoundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sr = 44100.0, bpm = 128.0, bar = 240.0 / 128.0, duration = 180.0
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * sr))!
buffer.frameLength = buffer.frameCapacity
// Every eight-bar phrase is complete. Its lead resolves before the final
// two-bar instrumental runway; no generated candidate decides these spans.
for i in 0..<Int(buffer.frameLength) {
    let t = Double(i) / sr, beatPhase = t.truncatingRemainder(dividingBy: bar / 4)
    let phrasePhase = t.truncatingRemainder(dividingBy: bar * 8)
    let kick = 0.11 * exp(-beatPhase * 45) * sin(2 * .pi * 62 * t)
    let chord = 0.025 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 330 * t))
    let syllable = t.truncatingRemainder(dividingBy: bar / 2)
    let lead = phrasePhase < bar * 6 ? 0.05 * pow(sin(.pi * syllable / (bar / 2)), 2) * (sin(2 * .pi * 440 * t) + 0.4 * sin(2 * .pi * 880 * t)) : 0
    for c in 0..<2 { buffer.floatChannelData![c][i] = Float(kick + chord + lead) }
}
let source = folder.appendingPathComponent("phrase-source.wav")
try AVAudioFile(forWriting: source, settings: format.settings).write(from: buffer)
func track(_ title: String) -> MixrTrack {
    MixrTrack(id: UUID(), title: title, artist: "Authored phrase regression", duration: "3:00", durationSeconds: duration, bpm: 128, key: "A", color: .pink, volume: 0.5, isMuted: false, url: source, artworkData: nil, clips: [MixrClip(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: duration))])
}
let hops = Int(duration / 0.1)
let features = SongSignalFeatures(sampleRate: sr, durationSeconds: duration,
    rmsCurveDB: Array(repeating: -20, count: hops), onsetStrength: Array(repeating: 0.8, count: hops), hopSeconds: 0.1,
    downbeatOffsetSeconds: 0, beatConfidence: 0.99, leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
    energyCurve: Array(repeating: 0.7, count: hops), bassEnergyCurve: Array(repeating: 0.7, count: hops),
    vocalPresenceCurve: (0..<hops).map { (Double($0) * 0.1).truncatingRemainder(dividingBy: bar * 8) < bar * 6 ? 0.8 : 0.1 },
    noveltyCurve: Array(repeating: 0.3, count: hops), drumConfidence: 0.9, overallConfidence: 0.99)
var failed = false
var reports: [[String: Any]] = []
for count in [1, 2] {
    let tracks = (0..<count).map { track("Phrase \($0)") }
    let signals = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, features) })
    guard let result = AutoRemixPlanner.makePlan(tracks: tracks, seed: 1234, signals: signals),
          let join = result.plan.joinContracts.first(where: { $0.kind == .sweepJoin }) else { fatalError("Missing mandatory sweep") }
    let elapsed = join.cutAt / bar
    let timingOK = elapsed >= 16 && elapsed <= 24.001 && abs(elapsed / 8 - (elapsed / 8).rounded()) < 0.001
    print("\(timingOK ? "PASS" : "FAIL") \(count)-song early phrase entrance: \(elapsed) elapsed bars")
    failed = failed || !timingOK
    reports.append(["songs": count, "drop1_elapsed_bars": elapsed, "early_phrase_pass": timingOK])
    if !timingOK { continue }
    // The composed source has phrase entrances every eight bars. Check the
    // actual incoming source boundary independently of timeline placement.
    let incoming = result.plan.placements.filter { abs($0.timelineStart - join.cutAt) < 0.01 && $0.role == .dominant }
    let sourceAligned = !incoming.isEmpty && incoming.allSatisfy { abs($0.sourceStart / (bar * 8) - ($0.sourceStart / (bar * 8)).rounded()) < 0.001 }
    print("\(sourceAligned ? "PASS" : "FAIL") \(count)-song incoming source phrase entrance")
    failed = failed || !sourceAligned
    // Every pre-drop outgoing sample through the sweep must preserve an
    // ordered source span: the last two bars cannot restart/repeat a grain.
    let sweep = result.plan.placements.filter { $0.songID == join.outgoingSongID && $0.timelineStart >= join.windowStart - 0.01 && $0.timelineStart < join.cutAt - 0.01 && $0.role == .dominant }.sorted { $0.timelineStart < $1.timelineStart }
    let continuous = !sweep.isEmpty && zip(sweep, sweep.dropFirst()).allSatisfy { abs($0.sourceEnd - $1.sourceStart) < 0.01 }
    print("\(continuous ? "PASS" : "FAIL") \(count)-song source-continuous outgoing sweep")
    failed = failed || !continuous
    let applied = AutoRemixApplier.apply(result.plan, to: tracks)
    let render = try MixrExportRenderer.export(tracks: applied.tracks, projectName: "phrase-\(UUID().uuidString)", projectBPM: 128)
    let dest = folder.appendingPathComponent("phrase-\(count).m4a")
    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
    try FileManager.default.moveItem(at: render, to: dest)
    print("RENDERED \(dest.path)")
}
try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("phrase-results.json"))
if failed { exit(1) }

print("PHRASE_RENDER_DONE cases=\(reports.count)")
