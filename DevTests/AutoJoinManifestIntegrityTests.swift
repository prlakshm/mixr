import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL") \(name)")
    if !condition { failures += 1 }
}
let sourceA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let sourceB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
func fixture() -> AutoRemixPlan {
    var plan = AutoRemixPlan(
        mode: .mashup, targetBPM: 126, targetDuration: 40,
        anchorSongIDs: [sourceA], selectedSections: [],
        placements: [AutoClipPlacement(songID: sourceA, sourceStart: 12,
            timelineStart: 0, timelineDuration: 32, tempoRatio: 1, volume: 0.7,
            fadeIn: .hardCut, fadeOut: .hardCut, effects: ClipEffectSettings(),
            role: .dominant, slotIndex: 0)],
        sfxEvents: [AutoSFXEvent(assetID: "impact", timelineStart: 16, purpose: "drop")],
        handoffCount: 0, songLetters: [sourceA: "A"], sequence: ["A"],
        transitionsUsed: [], decisions: [], warnings: [], confidence: 1, randomSeed: 42)
    plan.pulseRegions = [.init(role: .drop, timelineStart: 16, timelineEnd: 32)]
    plan.joinContracts = [.init(kind: .hardCut, windowStart: 16, cutAt: 16,
                               outgoingSongID: nil, incomingSongID: sourceA)]
    return plan
}
let base = fixture()
let fingerprint = AutoJoinManifest.fingerprint(plan: base)
func differs(_ label: String, _ mutate: (inout AutoRemixPlan) -> Void) {
    var changed = base
    mutate(&changed)
    check("fingerprint distinguishes \(label)", AutoJoinManifest.fingerprint(plan: changed) != fingerprint)
}
differs("source identity") { $0.placements[0].songID = sourceB }
differs("source offset") { $0.placements[0].sourceStart += 1 }
differs("playback rate") { $0.placements[0].tempoRatio = 1.12 }
differs("stem role") { $0.placements[0].stemKind = .vocals }
differs("gain below former rounding precision") { $0.placements[0].volume = $0.placements[0].volume.nextUp }
differs("timeline below former rounding precision") { $0.placements[0].timelineStart = 0.00001 }
differs("duration below former rounding precision") { $0.placements[0].timelineDuration = $0.placements[0].timelineDuration.nextUp }
differs("effect level") { $0.placements[0].effects.levels["echo"] = 35 }
differs("reverb preset") { $0.placements[0].effects.reverbPreset = .hall }
differs("echo preset") { $0.placements[0].effects.echoPreset = .reverse }
differs("pitch direction") { $0.placements[0].effects.pitchDirection = .down }
differs("fade type") { $0.placements[0].fadeIn.type = .crossfade }
differs("fade duration") { $0.placements[0].fadeOut.duration = 4 }
differs("fade curve") { $0.placements[0].fadeOut.curve = "equalPower" }
differs("level ride endpoint") { $0.placements[0].fadeIn.floorGain = 0.7 }
differs("continuation") { $0.placements[0].continuesPrevious = true }
differs("continuation shape") { $0.placements[0].continuationShape = 0.8 }
differs("declared overlap") { $0.placements[0].overlapsPreviousSeconds = 1 }
differs("slot") { $0.placements[0].slotIndex = 1 }
differs("target grid") { $0.targetBPM = 128 }
differs("export duration") { $0.targetDuration = 42 }
differs("pulse region end") { $0.pulseRegions[0].timelineEnd = 30 }
differs("pulse policy") { $0.pulsePolicy = .init(sourceHasClubKick: false, writesKick: true, writesBass: true, duckSourceLowEnd: true, detail: "thin") }
differs("flavor") { $0.clubFlavor = .snake }
differs("intentional gap") { $0.intentionalGaps = [.init(start: 15, end: 16, reason: "void")] }
differs("join source identity") { $0.joinContracts[0].incomingSongID = sourceB }
differs("SFX precise time") { $0.sfxEvents[0].timelineStart = $0.sfxEvents[0].timelineStart.nextUp }
differs("SFX asset") { $0.sfxEvents[0].assetID = "riser" }
differs("resolved stem source") { $0.stemsBySongID[sourceA] = AutoStemSet(vocals: URL(fileURLWithPath: "/fixture/vocals.wav")) }
check("random plan UUID does not change repeatable fingerprint", AutoJoinManifest.fingerprint(plan: fixture()) == fingerprint)
var ordered = base
ordered.placements[0].effects.levels = ["echo": 22, "reverb": 11]
var reversed = base
reversed.placements[0].effects.levels["reverb"] = 11
reversed.placements[0].effects.levels["echo"] = 22
check("effect dictionary insertion order is irrelevant", AutoJoinManifest.fingerprint(plan: ordered) == AutoJoinManifest.fingerprint(plan: reversed))

let body = AutoJoinManifest.dictionary(from: base, extra: [
    "schemaVersion": -1, "seed": 99, "planFingerprint": "forged", "joinContracts": [],
    "dropTimes": [], "preApplyScore": ["repairKept": true], "audioSHA256": "external-evidence"
])
check("extras cannot replace schema", body["schemaVersion"] as? Int == AutoJoinManifest.schemaVersion)
check("extras cannot replace fingerprint", body["planFingerprint"] as? String == fingerprint)
check("extras cannot replace seed", body["seed"] as? UInt64 == base.randomSeed)
check("extras cannot replace joins", (body["joinContracts"] as? [[String: Any]])?.count == 1)
check("extras cannot replace drops", body["dropTimes"] as? [Double] == [16])
check("extras cannot invent absent preapply evidence", body["preApplyScore"] == nil)
check("external evidence remains available", body["audioSHA256"] as? String == "external-evidence")
let ordinary = AutoJoinManifest.dictionary(from: base, extra: [:])
check("nil optional IDs produce valid JSON", JSONSerialization.isValidJSONObject(ordinary))
let joins = ordinary["joinContracts"] as? [[String: Any]]
check("absent song ID is explicitly JSON null", joins?.first?["outgoingSongID"] is NSNull)

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("mixr-manifest-integrity-\(UUID().uuidString)", isDirectory: true)
do {
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let output = root.appendingPathComponent("manifest.json")
    try AutoJoinManifest.writeAtomic(["value": 1], to: output)
    try AutoJoinManifest.writeAtomic(["value": 2], to: output)
    let read = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Int]
    check("atomic replacement writes complete new object", read?["value"] == 2)
    let dangling = root.appendingPathComponent("blocked.json")
    try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: root.appendingPathComponent("absent.json").path)
    do {
        try AutoJoinManifest.writeAtomic(["value": 3], to: dangling)
        check("dangling destination fails instead of losing evidence", false)
    } catch {
        check("write failure leaves no temporary files", try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.contains(".tmp-") })
        check("failed write preserves destination link", (try? fm.destinationOfSymbolicLink(atPath: dangling.path)) != nil)
    }
    do {
        try AutoJoinManifest.writeAtomic(["bad": Double.nan], to: output)
        check("invalid JSON fails closed", false)
    } catch {
        let preserved = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Int]
        check("invalid JSON preserves previous manifest", preserved?["value"] == 2)
    }
} catch {
    check("manifest file checks complete: \(error)", false)
}
print(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")
exit(failures == 0 ? 0 : 1)
