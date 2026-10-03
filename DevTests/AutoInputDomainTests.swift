import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL") \(name)")
    fflush(stdout)
    if !ok { failures += 1 }
}
func song(_ title: String, _ bpm: Int) -> MixrTrack {
    MixrTrack(id: UUID(), title: title, artist: "Synthetic", duration: "3:00", durationSeconds: 180,
        bpm: bpm, key: "C", color: .pink, volume: 1, isMuted: false, url: nil, artworkData: nil,
        clips: [.init(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: 180))])
}
func signal(_ drum: Double, _ bass: Double, confidence: Double = 0.95) -> SongSignalFeatures {
    SongSignalFeatures(sampleRate: 8000, durationSeconds: 180,
        rmsCurveDB: Array(repeating: -18, count: 1800), onsetStrength: Array(repeating: 0.6, count: 1800), hopSeconds: 0.1,
        downbeatOffsetSeconds: 0, beatConfidence: confidence, leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
        energyCurve: Array(repeating: 0.7, count: 1800), bassEnergyCurve: Array(repeating: bass, count: 1800),
        vocalPresenceCurve: Array(repeating: 0.6, count: 1800), noveltyCurve: Array(repeating: 0.2, count: 1800),
        drumConfidence: drum, overallConfidence: confidence)
}

for seconds in [2.0, 15.0, 45.0, 360.0] {
    for bpm: Int? in [nil, 60, 95, 128, 180] {
        var track = song("Boundary input", bpm ?? 120)
        track.bpm = bpm
        track.durationSeconds = seconds
        track.clips[0].length = MixrTimeline.units(fromSeconds: seconds)
        let outcome = AutoRemixRunner.runEntireProject(tracks: [track], seed: 9876)
        switch outcome {
        case .failure(let message):
            check("\(seconds)s / \(String(describing: bpm)): defined refusal", !message.isEmpty && seconds < 45)
        case .success(_, let plan, _):
            check("\(seconds)s / \(String(describing: bpm)): bounded output", !plan.placements.isEmpty && plan.placements.allSatisfy {
                $0.sourceStart.isFinite && $0.sourceEnd.isFinite && $0.sourceStart >= 0 && $0.sourceEnd <= seconds + 0.01
            })
        }
    }
}
let duplicate = song("Duplicate identity", 128)
switch AutoRemixRunner.runEntireProject(tracks: [duplicate, duplicate], seed: 9876) {
case .failure(let message): check("duplicate identity has a defined outcome", !message.isEmpty)
case .success(let tracks, let p, _): check("duplicate identity is treated as one song", p.mode == .remix && tracks.filter { $0.id == duplicate.id }.count == 1)
}
for duration in [Double.nan, Double.infinity, -1.0, 0.0, Double.greatestFiniteMagnitude] {
    print("CHECK_DURATION \(duration)"); fflush(stdout)
    var invalid = song("Invalid duration", 128); invalid.durationSeconds = duration
    switch AutoRemixRunner.runEntireProject(tracks: [invalid], seed: 9876) {
    case .failure(let message): check("invalid duration is rejected without crashing", !message.isEmpty)
    case .success: check("invalid duration is rejected without crashing", false)
    }
}
for bpm in [0, -1, Int.max] {
    let track = song("Invalid tempo", bpm)
    switch AutoRemixRunner.runEntireProject(tracks: [track], seed: 9876) {
    case .success(_, let p, _): check("invalid tempo becomes unknown without invented cuts", p.targetBPM.isFinite && p.cutRecords.isEmpty && p.placements.allSatisfy { $0.tempoRatio == 1 })
    case .failure: check("invalid tempo becomes unknown without invented cuts", false)
    }
}
var trimmed = song("Missing duration", 128)
trimmed.durationSeconds = nil
trimmed.clips[0].sourceOffsetSeconds = 30
trimmed.clips[0].length = MixrTimeline.units(fromSeconds: 60)
check("duration inference includes the source offset", AutoRemixInput.sourceDuration(trimmed) == 90)
let empty = AutoRemixRunner.runEntireProject(tracks: [], seed: 9876)
if case .failure(let message) = empty { check("empty timeline has a defined refusal", !message.isEmpty) }
else { check("empty timeline has a defined refusal", false) }
print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
