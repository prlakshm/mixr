import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { failures += 1 }
}
let duration = 180.0, bar = 240.0 / 128.0
let track = MixrTrack(id: UUID(), title: "Uncertain source", artist: "Synthetic fixture", duration: "3:00", durationSeconds: duration,
                     bpm: 128, key: "A", color: .pink, volume: 0.5, isMuted: false, url: nil,
                     clips: [MixrClip(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: duration))])
let hops = 1800
let signal = SongSignalFeatures(sampleRate: 8000, durationSeconds: duration,
    rmsCurveDB: Array(repeating: -20, count: hops), onsetStrength: Array(repeating: 0.2, count: hops), hopSeconds: 0.1,
    downbeatOffsetSeconds: 0, beatConfidence: 0.1, leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
    energyCurve: Array(repeating: 0.6, count: hops), bassEnergyCurve: Array(repeating: 0.6, count: hops),
    vocalPresenceCurve: Array(repeating: 0.5, count: hops), noveltyCurve: Array(repeating: 0.1, count: hops),
    drumConfidence: 0.8, overallConfidence: 0.1)
guard let result = AutoRemixPlanner.makePlan(tracks: [track], seed: 1234, signals: [track.id: signal]) else { fatalError("Required plan absent") }
let plan = result.plan
let clips = plan.placements.filter { $0.role == .dominant }.sorted { $0.timelineStart < $1.timelineStart }
let sourceContinuous = !clips.isEmpty && zip(clips, clips.dropFirst()).allSatisfy {
    abs($0.sourceEnd - $1.sourceStart) < 0.01 && abs($0.timelineEnd - $1.timelineStart) < 0.01
}
check("low confidence preserves continuous source order", sourceContinuous)
if !sourceContinuous {
    for (a, b) in zip(clips, clips.dropFirst()) where abs(a.sourceEnd - b.sourceStart) >= 0.01 || abs(a.timelineEnd - b.timelineStart) >= 0.01 {
        print("DISCONTINUITY timeline \(a.timelineEnd) → \(b.timelineStart), source \(a.sourceEnd) → \(b.sourceStart)")
    }
}
check("low confidence does not invent hook cut evidence", plan.cutRecords.isEmpty)
check("low confidence retains deliberate energy contrast", (clips.map(\.volume).max() ?? 0) > (clips.map(\.volume).min() ?? 0) * 1.2)
let drop = plan.pulseRegions.first { $0.role == .drop }
check("energy Drop 1 does not acquire an extra two-bar runway", drop.map { $0.timelineStart / bar <= 24.001 } ?? false)
check("source bounds remain valid", clips.allSatisfy { $0.sourceStart >= 0 && $0.sourceEnd <= duration + 0.01 })
var thin = signal
thin.drumConfidence = 0.19
if let thinResult = AutoRemixPlanner.makePlan(tracks: [track], seed: 1234, signals: [track.id: thin]) {
    let validated = AutoRemixValidator.validate(thinResult.plan, profiles: thinResult.profiles, tuning: .standard)
    var staged = validated
    AutoJoinEngine.boostJoinClipVolumes(placements: &staged.placements, pulseRegions: staged.pulseRegions,
        beatSec: staged.beatSeconds, barSec: staged.barSeconds, profiles: thinResult.profiles)
    for (label, p) in [("planner", thinResult.plan), ("validator", validated), ("staging", staged)] {
        print("ENERGY \(label) \(p.placements.map { $0.volume })")
    }
    check("thin-song energy contrast survives validation and staging", staged.placements.contains { $0.volume < 0.87 })
} else { check("required thin-source plan exists", false) }
print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
