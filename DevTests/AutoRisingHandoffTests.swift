import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL")  \(name)")
    if !ok { failures += 1 }
}
let a = UUID(), b = UUID()
func placement(_ id: UUID, source: Double, at: Double, duration: Double, stem: AutoStemKind, role: AutoPlacementRole = .dominant) -> AutoClipPlacement {
    AutoClipPlacement(songID: id, sourceStart: source, timelineStart: at, timelineDuration: duration,
        tempoRatio: 1, volume: 0.5, fadeIn: .none, fadeOut: .none, effects: ClipEffectSettings(),
        role: role, slotIndex: id == a ? 0 : 1, stemKind: stem)
}
var plan = AutoRemixPlan(mode: .mashup, targetBPM: 120, targetDuration: 80,
    anchorSongIDs: [a], selectedSections: [], placements: [
        placement(a, source: 0, at: 32, duration: 16, stem: .vocals),
        placement(a, source: 0, at: 32, duration: 16, stem: .other, role: .supporting),
        placement(b, source: 32, at: 48, duration: 32, stem: .vocals)],
    sfxEvents: [], handoffCount: 1, songLetters: [:], sequence: [], transitionsUsed: [],
    decisions: [], warnings: [], confidence: 1, randomSeed: 1)
plan.mashupBedSongID = a
plan.pulseRegions = [.init(role: .drop, timelineStart: 48, timelineEnd: 80)]
var signal = SongSignalFeatures(sampleRate: 44100, durationSeconds: 180,
    rmsCurveDB: Array(repeating: -18, count: 1800), onsetStrength: Array(repeating: 0.6, count: 1800), hopSeconds: 0.1,
    downbeatOffsetSeconds: 0, beatConfidence: 0.99, leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
    energyCurve: Array(repeating: 0.7, count: 1800), bassEnergyCurve: Array(repeating: 0.6, count: 1800),
    vocalPresenceCurve: Array(repeating: 0.7, count: 1800), noveltyCurve: Array(repeating: 0.3, count: 1800),
    drumConfidence: 0.9, overallConfidence: 0.99)
signal.stemVocalRMSCurveDB = Array(repeating: -12, count: 1800)
for i in 140..<148 { signal.stemVocalRMSCurveDB[i] = -45 }
signal.lyricWords = [(12, "resolve"), (15, "new"), (15.5, "line")]
func profile(_ id: UUID, _ title: String) -> AutoSongProfile {
    let track = MixrTrack(id: id, title: title, artist: "Synthetic", duration: "3:00", durationSeconds: 180,
        bpm: 120, key: "C", color: .pink, volume: 1, isMuted: false, url: nil, artworkData: nil, clips: [])
    return AutoSectionCatalog.profile(track: track, tuning: .standard, signal: signal)
}
let pa = profile(a, "Outgoing"), pb = profile(b, "Incoming")
let completed = plan.placements[0]
var placements = plan.placements
var regions = plan.pulseRegions
var gaps = plan.intentionalGaps
var decisions = plan.decisions
var contracts = plan.joinContracts
AutoJoinEngine.appendPivotWallpaperLoop(completedPhrase: completed, dropTimelineStart: 48,
    deckATitle: "Outgoing", deckBTitle: "Incoming", barSec: 2, beatSec: 0.5, tuning: .standard,
    grainStem: .vocals, signal: signal, incomingSongID: b, incomingHookStart: 32,
    incomingTempoRatio: 1, incomingSignal: signal, incomingGrainStem: .vocals, bedHasOtherStem: true,
    placements: &placements, pulseRegions: &regions, intentionalGaps: &gaps,
    decisions: &decisions, joinContracts: &contracts)
plan.placements = placements
plan.pulseRegions = regions
plan.intentionalGaps = gaps
plan.decisions = decisions
plan.joinContracts = contracts
check("sweep does not preview a later outgoing lyric with an echo throw", !plan.placements.contains {
    $0.role == .supporting && $0.stemKind == .vocals && $0.timelineStart < 48
})
plan.sfxEvents = AutoFestivalMixWindow.events(dropAt: 48, dropEnd: 80, barSec: 2, beatSec: 0.5, protectedRanges: [])
let validated = AutoRemixValidator.validate(plan, profiles: [a: pa, b: pb], tuning: .standard)
check("validator does not introduce an incoming vocal detour", !validated.placements.contains {
    $0.songID == b && $0.stemKind == .vocals && $0.timelineStart < 47.99
})
check("quiet gap cannot shorten the outgoing lyrical passage", validated.placements.filter {
    $0.songID == a && $0.stemKind == .vocals && $0.timelineStart < 48
}.map(\.sourceEnd).max().map { $0 >= 16 } == true && validated.placements.contains {
    $0.songID == a && $0.stemKind == .other && $0.timelineEnd >= 48 && $0.timelineStart < 48
})
let approach = validated.sfxEvents.filter { $0.timelineEnd > 44 && $0.timelineStart < 48 }
check("first song handoff uses one small ascending effect", approach.count == 1 && approach[0].assetID == "riser")
var staged = validated.placements
AutoJoinEngine.boostJoinClipVolumes(placements: &staged, pulseRegions: validated.pulseRegions,
    beatSec: 0.5, barSec: 2, profiles: [a: pa, b: pb])
let outgoingGain = staged.first { $0.songID == a && $0.stemKind == .vocals }!.volume
let incomingGain = staged.first { $0.songID == b && $0.stemKind == .vocals }!.volume
check("equally loud vocal stems do not acquire an automatic six-dB jump",
    incomingGain <= outgoingGain * pow(10, 2.0 / 20))
// A title token later in the song must not trump a complete, measured
// phrase selected on the grid by the mashability search.
signal.lyricTitleHookStart = 60
signal.lyricWords.append((60, "Incoming"))
let anchored = profile(b, "Incoming")
let island = AutoMashabilityIsland(guestStart: 32, bedStart: 16, bars: 16, score: 0.9, harmonic: 1, rhythmic: 1, spectral: 1)
check("complete phrase can win over later title token", abs(AutoMashability.drop1GuestStart(guest: anchored, island: island) - 32) < 0.001)
signal.stemVocalRMSCurveDB = Array(repeating: -12, count: 1800)
let sustained = AutoRemixValidator.validate(plan, profiles: [a: profile(a, "Outgoing"), b: pb], tuning: .standard)
check("word gap alone cannot cut a sustained note", sustained.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && $0.sourceEnd >= 16
})
signal.stemVocalRMSCurveDB = []
let missing = AutoRemixValidator.validate(plan, profiles: [a: profile(a, "Outgoing"), b: pb], tuning: .standard)
check("missing isolated-stem evidence preserves outgoing phrase", missing.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && $0.sourceEnd >= 16
})
// A newly entered outgoing continuation must not be immediately interrupted.
// This is deliberately neutral vocabulary: no named-song or title-token rule.
signal.stemVocalRMSCurveDB = Array(repeating: -12, count: 1800)
signal.lyricWords = [(12, "earlier"), (14, "phrase"), (15.8, "new"), (16.3, "complete"), (17.1, "line")]
for i in 195..<204 { signal.stemVocalRMSCurveDB[i] = -50 }
signal.lyricWords.append((20.6, "later"))
let continuation = AutoRemixValidator.validate(plan, profiles: [a: profile(a, "Outgoing"), b: pb], tuning: .standard)
let delayed = continuation.joinContracts.first { $0.kind == .sweepJoin }!
check("new outgoing continuation gets time before the next song", delayed.cutAt >= 52 - 0.01)
check("delaying the handoff retains source-continuous outgoing coverage", continuation.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && $0.sourceEnd >= 19.5 - 0.01
} && continuation.placements.contains {
    $0.songID == a && $0.stemKind == .other && $0.timelineEnd >= delayed.cutAt - 0.01
})
check("incoming phrase and later material keep the same source clock", continuation.placements.filter { $0.songID == b }.allSatisfy {
    abs($0.timelineStart + (32 - $0.sourceStart) / $0.tempoRatio - delayed.cutAt) < 0.001
})
signal.stemVocalRMSCurveDB = Array(repeating: -12, count: 1800)
signal.lyricWords = [(14, "before"), (15.8, "keep"), (17, "the"), (19.8, "held"), (20.3, "last"), (21.2, "note"), (23, "later")]
for i in 218..<228 { signal.stemVocalRMSCurveDB[i] = -50 }
let longContinuationProfile = profile(a, "Outgoing")
let longContinuation = AutoRemixValidator.validate(plan, profiles: [a: longContinuationProfile, b: pb], tuning: .standard)
check("handoff waits past two bars when outgoing vocal is still active", longContinuation.joinContracts[0].cutAt >= 54 - 0.01)
check("outgoing vocal retires in measured pause before the next lyric", longContinuation.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && $0.sourceEnd >= 21.8 && $0.sourceEnd < 23
})
signal.lyricWords = [(32.5, "soft"), (33.1, "consonant")]
let withPickup = AutoRemixValidator.validate(plan, profiles: [a: pa, b: profile(b, "Incoming")], tuning: .standard)
let entry = withPickup.placements.first { $0.songID == b && $0.role == .dominant }!
check("incoming consonant pickup precedes the cut without shifting its beat clock",
    entry.sourceStart <= 31.9 && abs(entry.timelineStart + (32.5 - entry.sourceStart) / entry.tempoRatio - 48.5) < 0.001)
// A title can occur near the END of a chorus. Its containing measured
// vocal section is stronger entrance evidence than the isolated title word.
var sectionLed = anchored
sectionLed.loudness = AutoLoudnessSidecar(fullMixLUFS: nil, downbeats: Array(stride(from: 40.0, through: 66.0, by: 2)))
sectionLed.loudness?.vocalSections = [.init(startSeconds: 40, endSeconds: 64, bars: 12, vocalScore: 0.9)]
let tailIsland = AutoMashabilityIsland(guestStart: 56, bedStart: 16, bars: 8, score: 0.9, harmonic: 1, rhythmic: 1, spectral: 1)
check("a title near the end cannot replace the beginning of its complete measured section", abs(AutoMashability.drop1GuestStart(guest: sectionLed, island: tailIsland)-40)<0.001)
check("a measured complete section wins over the title-word fallback without an island", abs(AutoMashability.drop1GuestStart(guest: sectionLed, island: nil)-40)<0.001)
var weakSection = sectionLed
weakSection.loudness?.vocalSections[0].vocalScore = 0.1
check("weak section guesses cannot replace an independently selected full phrase", abs(AutoMashability.drop1GuestStart(guest: weakSection, island: island)-32)<0.001)

let sr = 8000.0
var incomingPCM = Array(repeating: Float(0), count: Int(sr * 65))
for i in Int(31.86 * sr)..<Int(31.99 * sr) {
    incomingPCM[i] = 0.3 * Float(sin(2 * Double.pi * 2500 * Double(i) / sr))
}
let zero = AutoOfflineMixdown.Source(samples: Array(repeating: 0, count: Int(sr * 65)), sampleRate: sr)
let voice = AutoOfflineMixdown.Source(samples: incomingPCM, sampleRate: sr)
let pcmSources = [a: zero, b: voice]
let beforePCM = AutoOfflineMixdown.render(plan: plan, sources: pcmSources, sampleRate: sr, includeTail: false)
let afterPCM = AutoOfflineMixdown.render(plan: withPickup, sources: pcmSources, sampleRate: sr, includeTail: false)
let onsetSpan = Int(47.86 * sr)..<Int(47.99 * sr)
let beforePeak = beforePCM.songBus[onsetSpan].map { abs($0) }.max() ?? 0
let afterPeak = afterPCM.songBus[onsetSpan].map { abs($0) }.max() ?? 0
check("rendered consonant control rejects old trim and retains new pickup", beforePeak < 0.001 && afterPeak > 0.03)
signal.lyricWords = [(32.05, "pickup"), (33.1, "word")]
let closePickupProfile = profile(b, "Incoming")
var stretchedPickupPlan = plan
for i in stretchedPickupPlan.placements.indices where stretchedPickupPlan.placements[i].songID == b {
    stretchedPickupPlan.placements[i].tempoRatio = 1.12
}
let once = AutoRemixValidator.validate(stretchedPickupPlan, profiles: [a: pa, b: closePickupProfile], tuning: .standard)
let twice = AutoRemixValidator.validate(once, profiles: [a: pa, b: closePickupProfile], tuning: .standard)
let firstEntry = once.placements.first { $0.songID == b && $0.role == .dominant }!
let secondEntry = twice.placements.first { $0.songID == b && $0.role == .dominant }!
check("revalidation cannot keep moving the incoming pickup earlier",
    abs(firstEntry.sourceStart - secondEntry.sourceStart) < 0.001
        && abs(firstEntry.timelineStart - secondEntry.timelineStart) < 0.001)
// A backing-stem entrance is not a new vocal owner. Lyric-tail repair must
// not split and demote an incoming pickup when the drums reach the downbeat.
var backedPickupPlan = plan
for i in backedPickupPlan.placements.indices where backedPickupPlan.placements[i].songID == b {
    backedPickupPlan.placements[i].timelineStart -= 0.2
    backedPickupPlan.placements[i].sourceStart -= 0.2
    backedPickupPlan.placements[i].timelineDuration += 0.2
}
backedPickupPlan.placements.append(placement(a, source: 90, at: 48, duration: 32, stem: .drums, role: .supporting))
signal.lyricWords = [(32.5, "entrance"), (63.8, "complete"), (64.2, "ending")]
let backed = AutoRemixValidator.validate(backedPickupPlan, profiles: [a: pa, b: profile(b, "Incoming")], tuning: .standard)
check("backing entrance cannot demote the incoming vocal to a short fragment", backed.placements.contains {
    $0.songID == b && $0.stemKind == .vocals && $0.role == .dominant
        && $0.timelineStart < 48 && $0.timelineEnd >= 64
})
check("backing entrance cannot create a duplicate incoming vocal tail", !backed.placements.contains {
    $0.songID == b && $0.stemKind == .vocals && $0.role == .supporting && $0.timelineStart < 48.1
})
signal.lyricWords = [(14, "before"), (15.8, "keep"), (16.5, "this"), (17.85, "line"), (18.24, "following"), (19.2, "phrase"), (22, "later")]
signal.stemVocalRMSCurveDB = Array(repeating: -12, count: 1800)
for i in 205..<218 { signal.stemVocalRMSCurveDB[i] = -50 }
var barPhraseProfile = profile(a, "Neutral continuation")
barPhraseProfile.loudness = AutoLoudnessSidecar(fullMixLUFS: nil, downbeats: [14.2,16.2,18.2,20.2,22.2])
let barPhrase = AutoRemixValidator.validate(plan, profiles: [a: barPhraseProfile, b: pb], tuning: .standard)
check("measured bar and following word entrance beat a later internal pause", barPhrase.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && abs($0.sourceEnd - 18.2) < 0.001
})
var withOldTail = plan
var oldTail = placement(a, source: 16, at: 48, duration: 0.3, stem: .vocals, role: .supporting)
oldTail.continuesPrevious = true
oldTail.overlapsPreviousSeconds = 0.12
withOldTail.placements.append(oldTail)
let absorbed = AutoRemixValidator.validate(withOldTail, profiles: [a: barPhraseProfile, b: pb], tuning: .standard)
let absorbedDrop = absorbed.joinContracts[0].cutAt
check("extended continuation absorbs its old tail instead of replaying it at the drop", !absorbed.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && $0.role == .supporting
        && $0.timelineStart >= absorbedDrop - 0.01 && $0.sourceStart < 18.2
})
var introPlan = plan
introPlan.placements = [placement(a, source: 0, at: 0, duration: 16, stem: .vocals),
    placement(a, source: 40, at: 16, duration: 36, stem: .vocals),
    placement(b, source: 32, at: 52, duration: 32, stem: .vocals)]
introPlan.placements[0].stemKind = nil
introPlan.joinContracts = plan.joinContracts.map { j in var c = j; c.cutAt = 52; c.windowStart = 48; return c }
introPlan.pulseRegions = [.init(role: .drop, timelineStart: 52, timelineEnd: 84)]
introPlan.sfxEvents = []
signal.lyricWords = [(15.8, "first"), (16.4, "lyric"), (18, "ending")]
signal.stemVocalRMSCurveDB = Array(repeating: -50, count: 1800)
var introProfile = profile(a, "Instrumental opening")
introProfile.loudness = AutoLoudnessSidecar(fullMixLUFS: nil, downbeats: Array(stride(from: 0.0, through: 40.0, by: 2.0)))
let compactIntro = AutoRemixValidator.validate(introPlan, profiles: [a: introProfile, b: pb], tuning: .standard)
check("a shorter vocal-free opening can make room for the delayed drop", compactIntro.placements.contains {
    $0.songID == a && $0.timelineStart == 0 && $0.timelineDuration >= 12 && $0.timelineDuration <= 12.15
} && compactIntro.joinContracts[0].cutAt <= 48)
check("intro compression shifts the existing hook without changing its source", compactIntro.placements.contains {
    $0.songID == a && abs($0.sourceStart - 40) < 0.001 && abs($0.timelineStart - 12) < 0.001
})

// Independent music fixture: the voice masks a backing dropout in the
// full-mix analysis. The prepared bed must carry it without a second kick.
let grooveDir = FileManager.default.temporaryDirectory.appendingPathComponent("mixr-groove-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: grooveDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: grooveDir) }
func writeGrooveWAV(_ samples: [Float], to url: URL) throws {
    var d = Data()
    func tag(_ text: String) { d.append(contentsOf: text.utf8) }
    func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
    func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
    tag("RIFF"); u32(UInt32(36 + samples.count * 4)); tag("WAVEfmt "); u32(16)
    u16(3); u16(1); u32(8000); u32(32000); u16(4); u16(32); tag("data"); u32(UInt32(samples.count * 4))
    samples.withUnsafeBytes { d.append(contentsOf: $0) }; try d.write(to: url)
}
var grooveStems = AutoStemSet()
var groovePCM: [AutoStemKind: AutoOfflineMixdown.Source] = [:]
for kind in [AutoStemKind.drums, .bass, .other] {
    var samples = [Float](repeating: 0, count: 8000 * 100)
    for i in samples.indices {
        let t = Double(i) / 8000
        if (12..<16).contains(t) { continue }
        let phase = t.truncatingRemainder(dividingBy: 0.5)
        let f = kind == .drums ? 80.0 : kind == .bass ? 50.0 : 400.0
        let shape = kind == .drums ? exp(-phase * 12) : 0.7
        samples[i] = Float(0.18 * sin(2 * .pi * f * t) * shape)
    }
    let url = grooveDir.appendingPathComponent("\(kind.rawValue).wav")
    try writeGrooveWAV(samples, to: url); grooveStems.set(kind, url: url)
    groovePCM[kind] = .init(samples: samples, sampleRate: 8000)
}
var grooveSignal = signal
grooveSignal.lyricWords = []; grooveSignal.stemVocalRMSCurveDB = []
let grooveTrack = MixrTrack(id: a, title: "Anonymous groove", artist: "Synthetic", duration: "1:40", durationSeconds: 100,
    bpm: 120, key: "C", color: .pink, volume: 1, isMuted: false, url: nil, artworkData: nil, clips: [])
var grooveTuning = AutoTuning.standard
grooveTuning.explicitStemsBySongID = [a: grooveStems]
var grooveProfile = AutoSectionCatalog.profile(track: grooveTrack, tuning: grooveTuning, signal: grooveSignal)
grooveProfile.loudness = AutoLoudnessSidecar(fullMixLUFS: nil, downbeats: Array(stride(from: 0.0, through: 98.0, by: 2)))
var groovePlan = plan
groovePlan.placements = [placement(a, source: 0, at: 32, duration: 14, stem: .vocals),
    placement(b, source: 32, at: 48, duration: 32, stem: .vocals)]
for kind in [AutoStemKind.drums, .bass, .other] {
    groovePlan.placements.append(placement(a, source: 0, at: 32, duration: 16, stem: kind, role: .supporting))
    groovePlan.placements.append(placement(a, source: 32, at: 48, duration: 32, stem: kind, role: .supporting))
}
groovePlan.stemsBySongID = [a: grooveStems]
groovePlan.sfxEvents = []
let grooveFixed = AutoRemixValidator.validate(groovePlan, profiles: [a: grooveProfile, b: pb], tuning: grooveTuning)
let bridgeDrums = grooveFixed.placements.filter { $0.stemKind == .drums && $0.timelineStart <= 47.2 && $0.timelineEnd > 47.2 }
check("prepared groove replaces the empty backing before the vocal handoff", bridgeDrums.count == 1 && bridgeDrums[0].sourceStart > 20)
let grooveBefore = AutoOfflineMixdown.render(plan: groovePlan, sources: [a: zero, b: zero], stemSources: [a: groovePCM], sampleRate: 8000, includeTail: false)
let grooveAfter = AutoOfflineMixdown.render(plan: grooveFixed, sources: [a: zero, b: zero], stemSources: [a: groovePCM], sampleRate: 8000, includeTail: false)
func windowRMS(_ x: [Float], _ t: Double) -> Double {
    let lo = Int(t * 8000), hi = Int((t + 0.4) * 8000)
    return sqrt(x[lo..<hi].reduce(0.0) { $0 + Double($1 * $1) } / Double(hi-lo))
}
check("rendered musical dropout fails old behavior and retains a groove after repair",
    windowRMS(grooveBefore.songBus, 47.2) < 0.001 && windowRMS(grooveAfter.songBus, 47.2) > 0.025)
var grooveControlProfile = grooveProfile
grooveControlProfile.stems = .empty
let grooveControl = AutoRemixValidator.validate(groovePlan, profiles: [a: grooveControlProfile, b: pb], tuning: grooveTuning)
check("preparing the bed does not move or shorten either vocal", grooveFixed.placements.filter { $0.stemKind == .vocals }.allSatisfy { p in
    grooveControl.placements.contains { $0.songID == p.songID && abs($0.sourceStart-p.sourceStart)<0.001 && abs($0.timelineEnd-p.timelineEnd)<0.15 }
})


let selectedBed = AutoJoinEngine.stableBedSourceStart(profile: grooveProfile, preferred: 14.5, duration: 16, sourceBeat: 0.5)
check("stable backing starts on a measured bar instead of a louder offbeat", grooveProfile.loudness!.downbeats.contains(selectedBed))
check("whole-island scoring rejects a backing passage with missing rhythm", selectedBed >= 16)
var unmeasuredBed = grooveProfile
unmeasuredBed.instrumentalEnergy = nil
check("missing backing evidence cannot invent a different island", AutoJoinEngine.stableBedSourceStart(profile: unmeasuredBed, preferred: 14.5, duration: 16, sourceBeat: 0.5) == 14.5)
let grooveAgain = AutoRemixValidator.validate(grooveFixed, profiles: [a: grooveProfile, b: pb], tuning: grooveTuning)
check("revalidation cannot duplicate the prepared kick owner", [44.5,45.5,46.5,47.5].allSatisfy { t in
    grooveAgain.placements.filter { $0.stemKind == .drums && $0.timelineStart <= t && $0.timelineEnd > t }.count == 1
})


var preparedStaging = grooveFixed.placements
var plainStaging = groovePlan.placements
AutoJoinEngine.boostJoinClipVolumes(placements: &preparedStaging, pulseRegions: grooveFixed.pulseRegions,
    beatSec: 0.5, barSec: 2, profiles: [a: grooveProfile, b: pb])
AutoJoinEngine.boostJoinClipVolumes(placements: &plainStaging, pulseRegions: groovePlan.pulseRegions,
    beatSec: 0.5, barSec: 2, profiles: [a: grooveProfile, b: pb])
let preparedAtDrop = preparedStaging.first { $0.stemKind == .drums && $0.timelineStart < 48 && $0.timelineEnd > 48 }!
let plainAtDrop = plainStaging.first { $0.stemKind == .drums && abs($0.timelineStart-48)<0.01 }!
check("preparing a drop bed early cannot remove its gain staging", abs(preparedAtDrop.volume-plainAtDrop.volume)<0.001)
check("gain staging retains the prepared harmony crossfade", preparedStaging.contains {
    $0.stemKind == .other && $0.timelineStart < 48 && $0.timelineEnd > 48 && $0.fadeIn.type == .crossfade
})


var loopStaging = groovePlan.placements
var nextLoop = plainAtDrop
nextLoop.timelineStart = 56
nextLoop.timelineDuration = 8
nextLoop.volume = 0.5
loopStaging.append(nextLoop)
AutoJoinEngine.boostJoinClipVolumes(placements: &loopStaging, pulseRegions: groovePlan.pulseRegions,
    beatSec: 0.5, barSec: 2, profiles: [a: grooveProfile, b: pb])
check("later backing loops retain the drop level", loopStaging.contains {
    $0.stemKind == .drums && abs($0.timelineStart-56)<0.01 && abs($0.volume-plainAtDrop.volume)<0.001
})
// Every long island contains a backing break, but a complete four-bar
// instrumental phrase plus its two-bar lead-in is available.
var boundedProfile = grooveProfile
var shortEnergy = AutoInstrumentalEnergy(power: Array(repeating: 0.000001, count: 1000), drumPower: Array(repeating: 0.000001, count: 1000))
for i in 200..<340 { shortEnergy.power[i] = 0.01; shortEnergy.drumPower[i] = 0.005 }
boundedProfile.instrumentalEnergy = shortEnergy
let boundedIsland = AutoJoinEngine.stableBedIsland(profile: boundedProfile, preferred: 26, duration: 16, sourceBeat: 0.5)
check("joint runway and island selection can choose a complete shorter instrumental phrase", boundedIsland.bars == 4 && boundedIsland.sourceStart >= 24 && boundedIsland.sourceStart+8 <= 34)


let levelRide = ClipTransition(type: .crossfade, duration: 4, curve: AutoTransitionEnvelope.equalPowerCurveName, floorGain: 0.63)
let rideValues = (0...200).map { i in AutoTransitionEnvelope.envelope(transitionIn: levelRide, transitionOut: .none,
    clipStart: 0, clipEnd: 8, at: Double(i)/100, bpm: 120, continuity: .init(previous: true, next: true)).gain }
check("a level rise starts audibly and ramps smoothly even across continuous audio", abs(rideValues[0]-0.63)<0.001 && abs(rideValues.last!-1)<0.001 && zip(rideValues,rideValues.dropFirst()).allSatisfy { $1 >= $0 && $1-$0 < 0.005 })
let legacyFade = try JSONDecoder().decode(ClipTransition.self, from: Data("{\"type\":\"Crossfade\",\"duration\":4,\"curve\":\"linear\"}".utf8))
check("existing saved fades decode without a level floor", legacyFade.floorGain == nil)
let rideSaved = try JSONDecoder().decode(ClipTransition.self, from: JSONEncoder().encode(levelRide))
check("level rise survives project serialization", rideSaved == levelRide)


let barPhraseAgain = AutoRemixValidator.validate(barPhrase, profiles: [a: barPhraseProfile, b: pb], tuning: .standard)
check("revalidation preserves the measured outgoing bar instead of starting the next word", barPhraseAgain.placements.contains {
    $0.songID == a && $0.stemKind == .vocals && abs($0.sourceEnd-18.2)<0.001
})
var duplicatePlan = groovePlan
var duplicateTail = placement(b, source: 32, at: 48, duration: 8, stem: .vocals, role: .supporting)
duplicateTail.continuesPrevious = true
duplicatePlan.placements.append(duplicateTail)
let noDuplicate = AutoRemixValidator.validate(duplicatePlan, profiles: [a: grooveProfile, b: pb], tuning: grooveTuning)
check("a fully covered continuation cannot replay over its own dominant vocal", !noDuplicate.placements.contains {
    $0.songID == b && $0.stemKind == .vocals && $0.role == .supporting && abs($0.timelineStart-48)<0.01
})
var balanceProfile = grooveProfile
// Stronger outgoing voice, measured independently of the backing.
var balanceSignal = grooveSignal
balanceSignal.stemVocalRMSCurveDB = Array(repeating: -8, count: 1000)
balanceProfile = AutoSectionCatalog.profile(track: grooveTrack, tuning: grooveTuning, signal: balanceSignal)
var balanced = grooveFixed
balanced.placements = preparedStaging
AutoRemixValidator.balancePreparedHandoffs(&balanced, profiles: [a: balanceProfile, b: pb])
let firstBalance = balanced.placements
AutoRemixValidator.balancePreparedHandoffs(&balanced, profiles: [a: balanceProfile, b: pb])
check("repeated balance preserves absolute gains and the outgoing vocal", zip(firstBalance, balanced.placements).allSatisfy {
    abs($0.volume-$1.volume)<0.00001 && $0.sourceStart == $1.sourceStart && $0.timelineDuration == $1.timelineDuration
})

// A replacement bed six dB above the native backing must not bury the lead.
// Orthogonal tones make the rendered balance independently measurable.
var foregroundSignal = signal
foregroundSignal.lyricWords = []
foregroundSignal.stemVocalRMSCurveDB = Array(repeating: -20, count: 1800)
let foregroundTrack = MixrTrack(id: b, title: "Neutral lead", artist: "Synthetic", duration: "1:40", durationSeconds: 100, bpm: 120, key: "C", color: .pink, volume: 1, isMuted: false, url: nil, artworkData: nil, clips: [])
var foregroundProfile = AutoSectionCatalog.profile(track: foregroundTrack, tuning: .standard, signal: foregroundSignal)
foregroundProfile.instrumentalEnergy = AutoInstrumentalEnergy(power: Array(repeating: 0.01, count: 1800), drumPower: Array(repeating: 0.003, count: 1800))
var foregroundBed = grooveProfile
foregroundBed.instrumentalEnergy = foregroundProfile.instrumentalEnergy
var foregroundPlan = groovePlan
foregroundPlan.joinContracts = []
foregroundPlan.placements = [placement(b, source: 32, at: 48, duration: 16, stem: .vocals)]
foregroundPlan.placements[0].volume = 1
for kind in [AutoStemKind.drums, .bass, .other] {
    var bed = placement(a, source: 32, at: 48, duration: 16, stem: kind, role: .supporting)
    bed.volume = 2; foregroundPlan.placements.append(bed)
}
let foregroundBefore = foregroundPlan
AutoRemixValidator.balancePreparedHandoffs(&foregroundPlan, profiles: [a: foregroundBed, b: foregroundProfile])
check("a louder replacement bed preserves the native foreground vocal balance", abs(foregroundPlan.placements[0].volume-2)<0.02)
check("foreground balancing preserves lyrics and the rhythmic bed", zip(foregroundBefore.placements,foregroundPlan.placements).allSatisfy {
    $0.sourceStart == $1.sourceStart && $0.timelineStart == $1.timelineStart && $0.timelineDuration == $1.timelineDuration && ($0.stemKind == .vocals || $0.volume == $1.volume)
})
let foregroundOnce = foregroundPlan.placements
AutoRemixValidator.balancePreparedHandoffs(&foregroundPlan, profiles: [a: foregroundBed, b: foregroundProfile])
check("foreground correction cannot compound on repeated repairs", zip(foregroundOnce,foregroundPlan.placements).allSatisfy { abs($0.volume-$1.volume)<0.001 })
var unknownForeground = foregroundBefore
var unmeasuredVocalSignal = foregroundSignal
unmeasuredVocalSignal.stemVocalRMSCurveDB = []
var noVocalMeasurement = AutoSectionCatalog.profile(track: foregroundTrack, tuning: .standard, signal: unmeasuredVocalSignal)
noVocalMeasurement.instrumentalEnergy = foregroundProfile.instrumentalEnergy
AutoRemixValidator.balancePreparedHandoffs(&unknownForeground, profiles: [a: foregroundBed, b: noVocalMeasurement])
check("missing vocal evidence does not invent a gain correction", unknownForeground.placements[0].volume == 1)
var toneStems: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]] = [:]
func tone(_ hz: Double, _ amplitude: Double) -> AutoOfflineMixdown.Source {
    .init(samples: (0..<800000).map { Float(amplitude*sin(2 * .pi * hz * Double($0)/8000)) }, sampleRate: 8000)
}
toneStems[b] = [.vocals: tone(1000, sqrt(0.02))]
toneStems[a] = [.drums: tone(100, sqrt(0.02/3)), .bass: tone(50, sqrt(0.02/3)), .other: tone(400, sqrt(0.02/3))]
func renderedForegroundDB(_ input: AutoRemixPlan) -> Double {
    let rendered = AutoOfflineMixdown.render(plan: input, sources: [a: zero,b: zero], stemSources: toneStems, sampleRate: 8000, includeTail: false)
    // Measure orthogonal frequencies in the SAME mastered render; separate
    // renders each normalize themselves and erase the balance under test.
    let lo = 52*8000, count = 3200
    func bandPower(_ hz: Double) -> Double {
        var re = 0.0, im = 0.0
        for n in 0..<count {
            let value = Double(rendered.songBus[lo+n])
            let phase = 2 * Double.pi * hz * Double(n)/8000
            re += value*cos(phase); im += value*sin(phase)
        }
        return re*re+im*im
    }
    return 10*log10(bandPower(1000)/(bandPower(100)+bandPower(50)+bandPower(400)))
}
check("rendered foreground regression rejects the buried lead and restores source contrast", renderedForegroundDB(foregroundBefore)<(-5.9) && abs(renderedForegroundDB(foregroundPlan))<0.1)

print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
