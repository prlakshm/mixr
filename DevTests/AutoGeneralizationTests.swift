import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL") \(name)")
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
let a = song("Oops I Did It Again", 95), b = song("Baby One More Time", 95)
let signals = [a.id: signal(0.99, 0.1), b.id: signal(0.45, 0.99)]
func build(_ tracks: [MixrTrack], _ evidence: [UUID: SongSignalFeatures]) -> AutoRemixPlan {
    guard let plan = AutoRemixPlanner.makeValidatedPlan(tracks: tracks, seed: 4321, signals: evidence) else {
        fatalError("Required fixture plan missing")
    }
    return plan
}
let named = build([a,b], signals)
var renamedA = a, renamedB = b
renamedA.title = "Record A"; renamedB.title = "Record B"
let renamed = build([renamedA,renamedB], signals)
check("display titles do not select a privileged club bed", named.mashupBedSongID == renamed.mashupBedSongID)
check("same input evidence and seed reproduce the musical plan", AutoJoinManifest.fingerprint(plan: renamed) == AutoJoinManifest.fingerprint(plan: build([renamedA,renamedB], signals)))
let drop = renamed.pulseRegions.first { $0.role == .drop }!
let sounding = renamed.placements.filter { $0.timelineStart <= drop.timelineStart + 2 && $0.timelineEnd > drop.timelineStart + 2 && $0.volume > 0 }
let fullMixes = sounding.filter { $0.stemKind == nil }
check("missing stems never stack two complete records at the drop", Set(fullMixes.map(\.songID)).count <= 1)
check("missing stems do not claim isolated hook replacement", !renamed.decisions.contains { $0.kind == .hookReplace && ($0.detail ?? "").contains("HPF") })
var restrained = renamed
restrained.sfxEvents = [.init(assetID: "riser", timelineStart: max(0, drop.timelineStart - 4), purpose: "one rise")]
restrained.pulsePolicy = nil
restrained.pulseRegions = []
let applied = AutoRemixApplier.apply(restrained, to: [renamedA, renamedB])
check("applying a restrained plan never invents musical effects", applied.plan.sfxEvents.map(\.assetID) == ["riser"])
var noEffects = restrained
noEffects.sfxEvents = []
noEffects.decisions = []
let silentApplication = AutoRemixApplier.apply(noEffects, to: [renamedA, renamedB])
check("diagnostics never claim an effect that was not planned", silentApplication.plan.decisions.isEmpty)
let metadataOnly = build([renamedA, renamedB], [:])
check("metadata alone cannot authorize multi-song structural cuts", metadataOnly.mode == .remix && metadataOnly.cutRecords.isEmpty)
for bpm in [72, 95, 128, 145] {
    for confidence in [0.15, 0.95] {
        let track = song("Unseen \(bpm)", bpm), evidence = signal(0.8, 0.65, confidence: confidence)
        let result = build([track], [track.id: evidence])
        check("\(bpm) BPM / confidence \(confidence): finite bounded source placements", !result.placements.isEmpty && result.placements.allSatisfy {
            $0.sourceStart.isFinite && $0.sourceEnd.isFinite && $0.sourceStart >= 0 && $0.sourceEnd <= 180.01 && $0.tempoRatio > 0
        })
    }
}
let uncertain = build([renamedA, renamedB], [a.id: signal(0.8, 0.6, confidence: 0.1), b.id: signal(0.8, 0.6, confidence: 0.1)])
check("uncertain mashup does not invent hook cuts", uncertain.mode == .remix && uncertain.cutRecords.isEmpty)
let chain = uncertain.placements.filter { $0.role == .dominant }.sorted { $0.timelineStart < $1.timelineStart }
check("uncertain fallback keeps continuous source order", !chain.isEmpty && zip(chain, chain.dropFirst()).allSatisfy {
    $0.songID == $1.songID && abs($0.sourceEnd - $1.sourceStart) < 0.01
})
func leadOwners(_ plan: AutoRemixPlan, dropIndex: Int) -> [UUID: Double] {
    let drops = plan.pulseRegions.filter { $0.role == .drop }.sorted { $0.timelineStart < $1.timelineStart }
    guard dropIndex < drops.count else { return [:] }
    let span = drops[dropIndex]
    var durations: [UUID: Double] = [:]
    for p in plan.placements where p.role == .dominant {
        let overlap = max(0, min(p.timelineEnd, span.timelineEnd) - max(p.timelineStart, span.timelineStart))
        durations[p.songID, default: 0] += overlap
    }
    return durations.filter { $0.value >= plan.barSeconds * 7.99 }
}
func rotatedGuests(_ plan: AutoRemixPlan) -> Bool {
    let first = leadOwners(plan, dropIndex: 0), second = leadOwners(plan, dropIndex: 1)
    return first.count == 1 && second.count == 1 && first.keys.first != second.keys.first
        && first.keys.first != plan.mashupBedSongID && second.keys.first != plan.mashupBedSongID
}
for count in 2...5 {
    let tracks = (0..<count).map { song("Unseen group \($0)", 124 + $0) }
    let evidence = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($0.element.id, signal(0.55 + Double($0.offset) * 0.07, 0.65)) })
    let p = build(tracks, evidence)
    check("\(count)-song group: repeatable decisions", AutoJoinManifest.fingerprint(plan: p) == AutoJoinManifest.fingerprint(plan: build(tracks, evidence)))
    if count >= 3 {
        check("\(count)-song group: different complete guest hooks own both drops", rotatedGuests(p))
        let secondDrop = p.pulseRegions.filter { $0.role == .drop }.sorted { $0.timelineStart < $1.timelineStart }[1]
        var repeated = p
        for i in repeated.placements.indices where repeated.placements[i].role == .dominant
            && repeated.placements[i].timelineStart >= secondDrop.timelineStart - 0.01
            && repeated.placements[i].timelineStart < secondDrop.timelineEnd {
            repeated.placements[i].songID = p.mashupVocalSongID!
        }
        check("\(count)-song group: repeating the first guest fails rotation control", !rotatedGuests(repeated))
    }
    check("\(count)-song group: realized rates share tempo", p.placements.filter { $0.role == .dominant }.allSatisfy { clip in
        let sourceBPM = Double(tracks.first { $0.id == clip.songID }!.bpm!)
        return [0.5, 1.0, 2.0].contains { abs(sourceBPM * clip.tempoRatio * $0 - p.targetBPM) / p.targetBPM <= 0.001 }
    })
}
for count in [6, 12] {
    let tracks = (0..<count).map { song("Large timeline \($0)", 126) }
    let evidence = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, signal(0.8, 0.6)) })
    let p = build(tracks, evidence)
    check("\(count)-song timeline has a bounded five-song arrangement", !p.placements.isEmpty && Set(p.placements.map(\.songID)).count <= 5)
    check("\(count)-song timeline records every cap exclusion", p.decisions.filter { $0.kind == .excludedLowConfidenceSong && ($0.detail ?? "").contains("5-song") }.count == count - 5)
}
print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
