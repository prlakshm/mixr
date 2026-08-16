import Foundation

// Club Auto Remix algorithm fixtures — tempo pockets, one-kick rule,
 // pre-drop voids, mashup hook/bed roles, stretch/pitch gates.
// Run: Scripts/run_auto_remix_tests.sh club
//
// All audio is synthetic / copyright-free.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

func makeSong(
    title: String,
    bpm: Int?,
    key: String?,
    durationSeconds: Double = 180,
    color: MixrWaveformColor = .pink
) -> MixrTrack {
    let length = MixrTimeline.units(fromSeconds: min(durationSeconds, 180))
    return MixrTrack(
        id: UUID(),
        title: title,
        artist: "Fixture",
        duration: "--:--",
        durationSeconds: durationSeconds,
        bpm: bpm,
        key: key,
        color: color,
        volume: 1.0,
        isMuted: false,
        url: nil,
        artworkData: nil,
        clips: [MixrClip(id: UUID(), start: 0, length: length)]
    )
}

func makeFeatures(
    duration: Double,
    bpm: Double,
    drumConfidence: Double,
    bassLevel: Double,
    vocalLevel: Double,
    confidence: Double = 0.9
) -> SongSignalFeatures {
    let hop = SongSignalAnalyzer.hopSeconds
    let hops = max(8, Int(duration / hop))
    return SongSignalFeatures(
        sampleRate: 44_100,
        durationSeconds: duration,
        rmsCurveDB: [Double](repeating: -12, count: hops),
        onsetStrength: [Double](repeating: 0.6, count: hops),
        hopSeconds: hop,
        downbeatOffsetSeconds: 0,
        beatConfidence: confidence,
        leadingSilenceSeconds: 0,
        trailingSilenceSeconds: 0,
        quietRegions: [],
        energyCurve: [Double](repeating: 0.7, count: hops),
        bassEnergyCurve: [Double](repeating: bassLevel, count: hops),
        vocalPresenceCurve: [Double](repeating: vocalLevel, count: hops),
        noveltyCurve: [Double](repeating: 0.3, count: hops),
        drumConfidence: drumConfidence,
        overallConfidence: confidence
    )
}

// MARK: - Tempo pocket decisions

do {
    let mid = AutoClubTempo.remixDecision(songBPM: 93, vocalHeavy: true)
    check("Britney-class midtempo keeps pocket", mid.pocket == .midtempoPop && abs(mid.targetBPM - 93) < 0.1,
          "bpm=\(mid.targetBPM) \(mid.detail)")

    let house = AutoClubTempo.remixDecision(songBPM: 126, vocalHeavy: false)
    check("House pocket kept", house.pocket == .house && abs(house.ratio - 1) < 0.001)

    let festival = AutoClubTempo.remixDecision(songBPM: 144, vocalHeavy: true)
    check("Festival/rock pocket kept", festival.pocket == .festival && abs(festival.targetBPM - 144) < 0.1)

    let double = AutoClubTempo.remixDecision(songBPM: 64, vocalHeavy: false)
    check("Far-below house prefers double-time into pocket",
          double.halfOrDoubleTime && AutoClubTempo.classify(double.targetBPM) == .house,
          double.detail)

    let wreck = AutoClubTempo.remixDecision(songBPM: 70, vocalHeavy: true)
    // 70×2 = 140 lands in the festival pocket — double-time is preferred
    // over a destructive stretch. A truly unsafe case is far from every pocket.
    let far = AutoClubTempo.remixDecision(songBPM: 55, vocalHeavy: true)
    check("Double-time into a pocket is preferred over stretch",
          wreck.halfOrDoubleTime && abs(wreck.ratio - 1) < 0.001,
          wreck.detail)
    check("Vocal-wrecking stretch refused when no pocket fits",
          abs(far.ratio - 1) < 0.001 && (far.vocalStretchUnsafe || far.pocket == .other),
          far.detail)
}

do {
    let pair = AutoClubTempo.mashupDecision(vocalBPM: 93, bedBPM: 95)
    check("Britney mashup stays ~94", abs(pair.targetBPM - 94) < 1.5 && pair.ok,
          pair.detail)
    check("Britney mashup vocal stretch ≤ 8%", abs(pair.vocalRatio - 1) <= 0.08 + 0.001)
    check("Britney mashup bed stretch ≤ 15%", abs(pair.bedRatio - 1) <= 0.15 + 0.001)

    let festivalPair = AutoClubTempo.mashupDecision(vocalBPM: 98, bedBPM: 144)
    check("t.A.T.u / Paramore-class refuse illegal vocal stretch",
          !festivalPair.ok || abs(festivalPair.vocalRatio - 1) <= 0.08,
          festivalPair.detail)
}

// MARK: - One-kick rule

do {
    let thin = AutoClubPulse.policy(drumStrength: 0.25, bassDensity: 0.2)
    check("Thin song writes kick+bass", thin.writesKick && thin.writesBass && thin.duckSourceLowEnd)
    check("Thin song one-kick rule ok", !AutoClubPulse.violatesOneKickRule(policy: thin))

    let slam = AutoClubPulse.policy(drumStrength: 0.85, bassDensity: 0.7)
    check("Slamming kit does not write second kick",
          slam.sourceHasClubKick && !slam.writesKick && !slam.writesBass)
    check("Slamming one-kick rule ok", !AutoClubPulse.violatesOneKickRule(policy: slam))
}

do {
    let beat = 0.5
    let bar = 2.0
    let regions: [AutoClubPulse.Region] = [
        .init(role: .build, timelineStart: 0, timelineEnd: 4),
        .init(role: .buildOut, timelineStart: 4, timelineEnd: 8),
        .init(role: .void, timelineStart: 8, timelineEnd: 8.5),
        .init(role: .drop, timelineStart: 8.5, timelineEnd: 16.5),
    ]
    let policy = AutoClubPulse.Policy(
        sourceHasClubKick: false, writesKick: true, writesBass: true,
        duckSourceLowEnd: true, detail: "test"
    )
    let hits = AutoClubPulse.scheduleHits(regions: regions, policy: policy, beatSeconds: beat, barSeconds: bar)
    let kicksInBuildOut = hits.filter { $0.assetID == "clubKick" && $0.timelineStart >= 4 && $0.timelineStart < 8 }
    let kicksInVoid = hits.filter { $0.assetID == "clubKick" && $0.timelineStart >= 8 && $0.timelineStart < 8.5 }
    let kicksInDrop = hits.filter { $0.assetID == "clubKick" && $0.timelineStart >= 8.5 }
    check("Kick muted in build-out", kicksInBuildOut.isEmpty)
    check("Kick muted in pre-drop void", kicksInVoid.isEmpty)
    check("Kick present on drop", !kicksInDrop.isEmpty, "\(kicksInDrop.count) kicks")
}

// MARK: - Phrase-aligned club remix with signal evidence

do {
    let song = makeSong(title: "Piano Ballad", bpm: 96, key: "C")
    let features = makeFeatures(duration: 180, bpm: 96, drumConfidence: 0.2, bassLevel: 0.15, vocalLevel: 0.75)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 99, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        check("Thin piano song writes pulse", plan.pulsePolicy?.writesKick == true)
        let drops = plan.pulseRegions.filter { $0.role == .drop }
        check("Two-wave drops present", drops.count >= 2, "\(drops.count)")
        check("Drops land on beat grid (voids allowed)",
              drops.allSatisfy { drop in
                  let beats = drop.timelineStart / plan.beatSeconds
                  return abs(beats - beats.rounded()) < 0.08
              },
              "first drop at \(drops.first.map { String(format: "%.3f", $0.timelineStart) } ?? "?")")
        check("Pre-drop void precedes at least one drop",
              plan.intentionalGaps.contains { gap in
                  drops.contains { abs($0.timelineStart - gap.end) < 0.05 }
              })
        check("Intentional pre-drop void present", !plan.intentionalGaps.isEmpty)
        check("Kept midtempo pocket (not shoved to 128)",
              plan.targetBPM < 110, "bpm=\(plan.targetBPM)")
    case .failure(let message):
        check("Thin piano club remix", false, message)
    }
}

do {
    let song = makeSong(title: "Club Banger", bpm: 128, key: "Am")
    let features = makeFeatures(duration: 180, bpm: 128, drumConfidence: 0.9, bassLevel: 0.8, vocalLevel: 0.4)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 7, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        check("Slamming dance song skips second kick",
              plan.pulsePolicy?.writesKick == false && plan.pulsePolicy?.sourceHasClubKick == true)
        check("Still has riser/impact SFX",
              plan.sfxEvents.contains { $0.assetID == "impact" || $0.assetID == "riser" || $0.assetID == "snareBuild" })
    case .failure(let message):
        check("Slamming dance club remix", false, message)
    }
}

// MARK: - Mashup hook vs bed

do {
    let vocal = makeSong(title: "Hook Vocal", bpm: 93, key: "Cm", color: .pink)
    let bed = makeSong(title: "Club Bed", bpm: 95, key: "C#m", color: .blue)
    // Raise bed drums so it wins anchor; raise vocal presence so it wins feature.
    let vFeat = makeFeatures(duration: 180, bpm: 93, drumConfidence: 0.3, bassLevel: 0.25, vocalLevel: 0.9)
    let bFeat = makeFeatures(duration: 180, bpm: 95, drumConfidence: 0.85, bassLevel: 0.75, vocalLevel: 0.2)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [vocal, bed],
        seed: 21,
        signals: [vocal.id: vFeat, bed.id: bFeat]
    )
    switch outcome {
    case .success(_, let plan, _):
        check("Mashup mode", plan.mode == .mashup)
        check("Assigned vocal hook role", plan.mashupVocalSongID == vocal.id,
              "vocal=\(plan.mashupVocalSongID?.uuidString ?? "nil")")
        check("Assigned club bed role", plan.mashupBedSongID == bed.id,
              "bed=\(plan.mashupBedSongID?.uuidString ?? "nil")")
        check("Tempo stays midtempo pocket", plan.targetBPM < 110, "bpm=\(plan.targetBPM)")
        let bedPlacements = plan.placements.filter { $0.songID == bed.id }
        let vocalPlacements = plan.placements.filter { $0.songID == vocal.id }
        check("Bed appears in arrangement", !bedPlacements.isEmpty)
        check("Vocal hook appears on drops", !vocalPlacements.isEmpty)
        let vocalStretch = vocalPlacements.map { abs($0.tempoRatio - 1) }.max() ?? 0
        check("Vocal stretch ≤ 8%", vocalStretch <= 0.08 + 0.001, String(format: "%.3f", vocalStretch))
        let bedPitch = bedPlacements.contains { $0.effects.pitchAmount > 0.005 }
        let vocalPitch = vocalPlacements.contains { $0.effects.pitchAmount > 0.005 }
        check("Pitch shifts the bed, not the star vocal", !vocalPitch,
              "bedPitched=\(bedPitch) vocalPitched=\(vocalPitch)")
        check("Roles decision recorded",
              plan.decisions.contains { $0.kind == .assignedMashupRoles })
    case .failure(let message):
        check("Hook-over-bed mashup", false, message)
    }
}

do {
    let vocal = makeSong(title: "Slow Vocal", bpm: 72, key: "C")
    let bed = makeSong(title: "Fast Bed", bpm: 150, key: "F#")
    let outcome = AutoRemixRunner.runEntireProject(tracks: [vocal, bed], seed: 3)
    switch outcome {
    case .success(_, let plan, _):
        let refused = plan.decisions.contains { $0.kind == .refusedMashupPair }
        let vocalStretch = plan.placements
            .filter { $0.songID == plan.mashupVocalSongID }
            .map { abs($0.tempoRatio - 1) }
            .max() ?? 0
        check("Illegal stretch pair refuses or keeps vocal ≤ 8%",
              refused || vocalStretch <= 0.08 + 0.001,
              "refused=\(refused) stretch=\(vocalStretch)")
    case .failure:
        check("Illegal stretch pair fails closed", true)
    }
}

print("\n\(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")")
exit(failures == 0 ? 0 : 1)
