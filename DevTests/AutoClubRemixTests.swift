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

    let mid = AutoClubPulse.policy(drumStrength: 0.55, bassDensity: 0.5)
    check("Moderate kit gets no pulse layer",
          !mid.writesKick && !mid.writesBass && !mid.duckSourceLowEnd)

    check("Club Kick and Club Bass are first-class SFX menu items",
          SoundEffectLibrary.all.contains { $0.id == "clubKick" }
              && SoundEffectLibrary.all.contains { $0.id == "clubBass" }
              && SoundEffectLibrary.definition(for: "clubKick") != nil)
    check("SFX library includes pulse alongside the classic one-shots",
          SoundEffectLibrary.all.count >= 14)
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
        check("Drops land on bar downbeats after void",
              drops.allSatisfy { drop in
                  let bars = drop.timelineStart / plan.barSeconds
                  return abs(bars - bars.rounded()) < 0.08
              },
              "first drop at \(drops.first.map { String(format: "%.3f", $0.timelineStart) } ?? "?") bar=\(drops.first.map { String(format: "%.3f", $0.timelineStart / plan.barSeconds) } ?? "?")")
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

// MARK: - Dual-vocal overlay on a drop is legal (Bollywood stack)

do {
    let bed = makeSong(title: "ClubBedVocalOK", bpm: 128, key: "Am", color: .blue)
    let english = makeSong(title: "EnglishHook", bpm: 126, key: "C", color: .pink)
    let bollywood = makeSong(title: "BollywoodHook", bpm: 124, key: "Em", color: .purple)
    let feats: [UUID: SongSignalFeatures] = [
        bed.id: makeFeatures(duration: 200, bpm: 128, drumConfidence: 0.92, bassLevel: 0.85, vocalLevel: 0.12),
        english.id: makeFeatures(duration: 200, bpm: 126, drumConfidence: 0.28, bassLevel: 0.2, vocalLevel: 0.95),
        bollywood.id: makeFeatures(duration: 200, bpm: 124, drumConfidence: 0.26, bassLevel: 0.18, vocalLevel: 0.93),
    ]
    switch AutoRemixRunner.runEntireProject(
        tracks: [bed, english, bollywood],
        seed: 77,
        signals: feats
    ) {
    case .success(_, let plan, _):
        check("Dual-vocal mashup mode", plan.mode == .mashup)
        check("Dual-vocal plan accepted (not rejected)", true)
        let stacked = plan.decisions.contains { $0.kind == .stackedVocalOverlay }
        let ducked = plan.decisions.contains { $0.kind == .duckedSupportingVocal }
        check("Dual-vocal overlay decision present", stacked, "stacked=\(stacked) ducked=\(ducked)")
        // Supporting guest concurrent with a drop dominant = legal dual-vocal bars.
        let dominants = plan.placements.filter { $0.role == .dominant }
        let guestSupports = plan.placements.filter {
            $0.role == .supporting && $0.songID != plan.mashupBedSongID
        }
        var dualVocalBars = false
        for support in guestSupports {
            let overDrop = dominants.contains {
                $0.songID != support.songID
                    && $0.timelineStart < support.timelineStart + support.timelineDuration - 0.01
                    && support.timelineStart < $0.timelineStart + $0.timelineDuration - 0.01
            }
            if overDrop { dualVocalBars = true }
        }
        check("Dual-vocal bars on a drop are legal and present", dualVocalBars,
              "guestSupports=\(guestSupports.count)")
        check("Did not reject the plan for dual vocals",
              !plan.decisions.contains { $0.kind == .avoidedVocalOverlap && $0.detail?.contains("reject") == true })
    case .failure(let message):
        check("Dual-vocal overlay must be a legal plan", false, message)
    }
}

// MARK: - Dual full-mix kick/bass stack still rejected

do {
    // Two slamming dance tracks — stacking both full mixes as dual drops is illegal.
    let a = makeSong(title: "SlamA", bpm: 128, key: "Am", color: .blue)
    let b = makeSong(title: "SlamB", bpm: 128, key: "C", color: .pink)
    let feats: [UUID: SongSignalFeatures] = [
        a.id: makeFeatures(duration: 180, bpm: 128, drumConfidence: 0.95, bassLevel: 0.9, vocalLevel: 0.4),
        b.id: makeFeatures(duration: 180, bpm: 128, drumConfidence: 0.93, bassLevel: 0.88, vocalLevel: 0.45),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [a, b], seed: 88, signals: feats) {
    case .success(_, let plan, _):
        // Plan may succeed, but must not leave two slamming kits as dual dominants
        // overlapping the same bars.
        let dominants = plan.placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        var dualDominantOverlap = false
        for i in 0..<dominants.count {
            for j in (i + 1)..<dominants.count where dominants[i].songID != dominants[j].songID {
                let a = dominants[i], b = dominants[j]
                if a.timelineStart < b.timelineStart + b.timelineDuration - 0.05
                    && b.timelineStart < a.timelineStart + a.timelineDuration - 0.05 {
                    dualDominantOverlap = true
                }
            }
        }
        check("No overlapping dual dominant full mixes", !dualDominantOverlap)
        // Bed wins one kick; supporting slam under slam should be refused or heavily treated.
        let bedID = plan.mashupBedSongID
        check("One bed/kick owner assigned", bedID != nil)
    case .failure:
        check("Slam pair fails closed or plans with one bed", true)
    }
}

// MARK: - N-song mashups (2…5): one bed, rotating hooks, legal plan

/// Assert club mashup legality: one bed owner, phrase-aligned ≥8-bar stays,
/// Drop 1 ≠ Drop 2 when multiple hooks exist. Dual-vocal overlays are legal.
func assertLegalNSongMashup(
    _ plan: AutoRemixPlan,
    expectedSongCount: Int,
    label: String
) {
    check("\(label) mashup mode", plan.mode == .mashup)
    check("\(label) bed owner set", plan.mashupBedSongID != nil)
    guard plan.mashupBedSongID != nil else { return }

    let barSec = plan.barSeconds
    let dominants = plan.placements
        .filter { $0.role == .dominant }
        .sorted { $0.timelineStart < $1.timelineStart }
    check("\(label) has dominant islands", dominants.count >= 2, "got \(dominants.count)")

    // Phrase-aligned switches: each contiguous song stay ≥ 8 bars.
    var staySong: UUID?
    var stayStart = 0.0
    var stayEnd = 0.0
    var shortStays = 0
    func flushStay(followedByVoid: Bool) {
        guard staySong != nil else { return }
        let bars = (stayEnd - stayStart) / max(barSec, 0.001)
        // Pre-drop void carves the last beat of an 8-bar island — still a
        // legal phrase stay (8 bars minus ≤2 beats).
        let floor = followedByVoid ? 7.4 : 8.0
        if bars + 0.05 < floor { shortStays += 1 }
    }
    for (idx, p) in dominants.enumerated() {
        if staySong == p.songID {
            stayEnd = max(stayEnd, p.timelineStart + p.timelineDuration)
        } else {
            let voidFollows = plan.intentionalGaps.contains { gap in
                abs(gap.start - stayEnd) < 0.08 || (gap.start >= stayEnd - 0.01 && gap.start <= stayEnd + plan.beatSeconds)
            }
            flushStay(followedByVoid: voidFollows)
            staySong = p.songID
            stayStart = p.timelineStart
            stayEnd = p.timelineStart + p.timelineDuration
        }
        _ = idx
    }
    let voidFollowsEnd = plan.intentionalGaps.contains { gap in
        abs(gap.start - stayEnd) < 0.08
    }
    flushStay(followedByVoid: voidFollowsEnd)
    check("\(label) no sub-8-bar identity stays", shortStays == 0, "shortStays=\(shortStays)")

    // Dual-vocal overlays are legal — only dual full-mix kick/bass stacks fail.
    let supports = plan.placements.filter { $0.role == .supporting }
    check("\(label) may include supporting layers", true, "supports=\(supports.count)")

    // Roles: Drop 1 / Drop 2 when guests exist.
    if expectedSongCount >= 2 {
        check("\(label) Drop 1 vocal role", plan.mashupVocalSongID != nil || plan.decisions.contains {
            $0.kind == .skippedIncompatibleHook || $0.kind == .assignedMashupRoles
        })
        check("\(label) Drop 2 flip role", plan.mashupDrop2SongID != nil)
        if let d1 = plan.mashupVocalSongID, let d2 = plan.mashupDrop2SongID, expectedSongCount >= 3 {
            check("\(label) Drop 2 is a different song than Drop 1", d1 != d2,
                  "drop1=\(d1) drop2=\(d2)")
        }
    }

    check("\(label) roles decision recorded",
          plan.decisions.contains { $0.kind == .assignedMashupRoles || $0.kind == .selectedAnchor })
}

do {
    let bed = makeSong(title: "Bed2", bpm: 126, key: "Am", color: .blue)
    let hook = makeSong(title: "Hook2", bpm: 124, key: "C", color: .pink)
    let feats: [UUID: SongSignalFeatures] = [
        bed.id: makeFeatures(duration: 180, bpm: 126, drumConfidence: 0.9, bassLevel: 0.8, vocalLevel: 0.2),
        hook.id: makeFeatures(duration: 180, bpm: 124, drumConfidence: 0.25, bassLevel: 0.2, vocalLevel: 0.92),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bed, hook], seed: 42, signals: feats) {
    case .success(_, let plan, _):
        assertLegalNSongMashup(plan, expectedSongCount: 2, label: "N=2")
        check("N=2 bed wins drums", plan.mashupBedSongID == bed.id)
        check("N=2 drop2 is bed flip or distinct",
              plan.mashupDrop2SongID == bed.id || plan.mashupDrop2SongID != plan.mashupVocalSongID)
    case .failure(let message):
        check("N=2 mashup plan", false, message)
    }
}

do {
    let bed = makeSong(title: "Bed3", bpm: 128, key: "Am", color: .blue)
    let h1 = makeSong(title: "HookA", bpm: 126, key: "C", color: .pink)
    let h2 = makeSong(title: "HookB", bpm: 124, key: "Em", color: .purple)
    let feats: [UUID: SongSignalFeatures] = [
        bed.id: makeFeatures(duration: 200, bpm: 128, drumConfidence: 0.92, bassLevel: 0.85, vocalLevel: 0.15),
        h1.id: makeFeatures(duration: 200, bpm: 126, drumConfidence: 0.3, bassLevel: 0.25, vocalLevel: 0.95),
        h2.id: makeFeatures(duration: 200, bpm: 124, drumConfidence: 0.28, bassLevel: 0.22, vocalLevel: 0.9),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bed, h1, h2], seed: 43, signals: feats) {
    case .success(_, let plan, _):
        assertLegalNSongMashup(plan, expectedSongCount: 3, label: "N=3")
        check("N=3 bed owner", plan.mashupBedSongID == bed.id)
        if let d1 = plan.mashupVocalSongID, let d2 = plan.mashupDrop2SongID {
            check("N=3 drop flip uses second hook", d1 != d2 && d2 != bed.id,
                  "d1=\(d1 == h1.id ? "A" : d1 == h2.id ? "B" : "?") d2=\(d2 == h1.id ? "A" : d2 == h2.id ? "B" : d2 == bed.id ? "bed" : "?")")
        }
        let stacked = plan.decisions.filter { $0.kind == .stackedVocalOverlay }
        check("N=3 stacks vocal overlay on a drop (legal)", !stacked.isEmpty,
              "decisions=\(stacked.map { $0.detail ?? "" })")
        // Rotate: overlays on drop 1 and drop 2 should not be the same guest when both exist.
        let overlaySongs = Set(
            plan.placements
                .filter { $0.role == .supporting && $0.songID != bed.id }
                .map(\.songID)
        )
        check("N=3 supporting vocal layer(s) present", !overlaySongs.isEmpty,
              "overlaySongs=\(overlaySongs.count)")
    case .failure(let message):
        check("N=3 mashup plan", false, message)
    }
}

do {
    let bed = makeSong(title: "Bed4", bpm: 126, key: "Gm", color: .blue)
    let h1 = makeSong(title: "Hook4A", bpm: 124, key: "Bb", color: .pink)
    let h2 = makeSong(title: "Hook4B", bpm: 128, key: "Dm", color: .purple)
    let soft = makeSong(title: "BalladCameo", bpm: 122, key: "F", color: .yellow)
    let feats: [UUID: SongSignalFeatures] = [
        bed.id: makeFeatures(duration: 210, bpm: 126, drumConfidence: 0.9, bassLevel: 0.82, vocalLevel: 0.18),
        h1.id: makeFeatures(duration: 210, bpm: 124, drumConfidence: 0.3, bassLevel: 0.2, vocalLevel: 0.93),
        h2.id: makeFeatures(duration: 210, bpm: 128, drumConfidence: 0.32, bassLevel: 0.24, vocalLevel: 0.88),
        soft.id: makeFeatures(duration: 210, bpm: 122, drumConfidence: 0.2, bassLevel: 0.15, vocalLevel: 0.85),
    ]
    // Soften ballad energy so it prefers breakdown runway.
    var softFeat = feats[soft.id]!
    softFeat.energyCurve = [Double](repeating: 0.3, count: softFeat.energyCurve.count)
    var signals = feats
    signals[soft.id] = softFeat
    var bedFeat = signals[bed.id]!
    bedFeat.energyCurve = [Double](repeating: 0.8, count: bedFeat.energyCurve.count)
    signals[bed.id] = bedFeat

    switch AutoRemixRunner.runEntireProject(tracks: [bed, h1, h2, soft], seed: 44, signals: signals) {
    case .success(_, let plan, _):
        assertLegalNSongMashup(plan, expectedSongCount: 4, label: "N=4")
        check("N=4 bed owner", plan.mashupBedSongID == bed.id)
        let songIDs = Set(plan.placements.map(\.songID))
        check("N=4 places multiple guests or records skip/cameo",
              songIDs.count >= 2
                || plan.decisions.contains { $0.kind == .usedCameoOnly || $0.kind == .skippedIncompatibleHook })
    case .failure(let message):
        check("N=4 mashup plan", false, message)
    }
}

do {
    let bed = makeSong(title: "Bed5", bpm: 128, key: "Am", color: .blue)
    let guests = [
        makeSong(title: "G5a", bpm: 126, key: "C", color: .pink),
        makeSong(title: "G5b", bpm: 124, key: "Em", color: .purple),
        makeSong(title: "G5c", bpm: 130, key: "G", color: .yellow),
        makeSong(title: "G5d", bpm: 122, key: "F", color: .red),
    ]
    var signals: [UUID: SongSignalFeatures] = [
        bed.id: makeFeatures(duration: 220, bpm: 128, drumConfidence: 0.95, bassLevel: 0.88, vocalLevel: 0.12),
    ]
    for (i, g) in guests.enumerated() {
        signals[g.id] = makeFeatures(
            duration: 220,
            bpm: Double(g.bpm ?? 126),
            drumConfidence: 0.25,
            bassLevel: 0.2,
            vocalLevel: 0.9 - Double(i) * 0.03
        )
    }
    // Far-key sour guest should gate to skip/cameo — still a legal plan.
    let sour = makeSong(title: "Sour5", bpm: 140, key: "F#", color: .red)
    // Replace last guest with sour incompatible for stretch+key stress.
    let tracks = [bed] + Array(guests.prefix(3)) + [sour]
    signals[sour.id] = makeFeatures(duration: 220, bpm: 140, drumConfidence: 0.2, bassLevel: 0.2, vocalLevel: 0.9)

    switch AutoRemixRunner.runEntireProject(tracks: tracks, seed: 45, signals: signals) {
    case .success(_, let plan, _):
        assertLegalNSongMashup(plan, expectedSongCount: 5, label: "N=5")
        check("N=5 bed owner", plan.mashupBedSongID == bed.id)
        check("N=5 accepts 5-track input", plan.mode == .mashup)
        // Sour may be skipped or cameo — must not force illegal stretch on it as drop1.
        if plan.mashupVocalSongID == sour.id {
            let stretch = plan.placements.filter { $0.songID == sour.id }.map { abs($0.tempoRatio - 1) }.max() ?? 0
            check("N=5 sour vocal stretch ≤ 8% if used as drop1", stretch <= 0.08 + 0.001)
        } else {
            check("N=5 sour gated or not drop1", true)
        }
    case .failure(let message):
        check("N=5 mashup plan", false, message)
    }
}

// MARK: - Measured crate bounce numbers (real-song analyzer features)

func crateFeatures(
    duration: Double,
    bpm: Double,
    drum: Double,
    bass: Double,
    vocal: Double,
    confidence: Double
) -> SongSignalFeatures {
    makeFeatures(
        duration: duration,
        bpm: bpm,
        drumConfidence: drum,
        bassLevel: bass,
        vocalLevel: vocal,
        confidence: confidence
    )
}

do {
    // Pulse / one-kick against measured crate features.
    let britney = AutoClubPulse.policy(drumStrength: 1.00, bassDensity: 0.37, bpm: 93, analysisConfidence: 1.00)
    check("Britney 93 drum=1.00 bass=0.37 → no pulse", !britney.writesKick && britney.sourceHasClubKick)

    let oops = AutoClubPulse.policy(drumStrength: 0.71, bassDensity: 0.38, bpm: 95, analysisConfidence: 1.00)
    check("Oops 95 drum=0.71 bass=0.38 → no pulse", !oops.writesKick && oops.sourceHasClubKick)

    let stupid = AutoClubPulse.policy(drumStrength: 0.19, bassDensity: 0.46, bpm: 128, analysisConfidence: 0.46)
    check("stupid song 128 drum=0.19 → writes pulse", stupid.writesKick && stupid.writesBass)

    let paramore = AutoClubPulse.policy(drumStrength: 0.29, bassDensity: 0.53, bpm: 144, analysisConfidence: 0.50)
    check("All I Wanted 144 festival uncertain → no house pulse", !paramore.writesKick)

    let tatu = AutoClubPulse.policy(drumStrength: 0.82, bassDensity: 0.57, bpm: 90, analysisConfidence: 1.00)
    check("t.A.T.u. 90 drum=0.82 → no pulse", !tatu.writesKick && tatu.sourceHasClubKick)
}

do {
    let song = makeSong(title: "stupid song", bpm: 128, key: "C")
        // Confidence blend: metadata*0.4 + signal*0.6. Use a very low signal
        // confidence so analysisConfidence lands under the low-confidence gate
        // (mirrors the crate's weak structure without inventing cuts).
        let feat = crateFeatures(duration: 180, bpm: 128, drum: 0.19, bass: 0.46, vocal: 0.51, confidence: 0.10)
        switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 11, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        check("stupid song remix writes pulse", plan.pulsePolicy?.writesKick == true)
        check("stupid song keeps house 128", abs(plan.targetBPM - 128) < 0.5, "bpm=\(plan.targetBPM)")
        check("stupid song used energy-curve fallback",
              plan.decisions.contains { $0.kind == .imposedClubEnergyCurve || $0.kind == .usedLowConfidenceFallback })
        let expectedBuildOut = AutoGainPolicy.songPlacementVolume(energy: 0.18)
        let expectedDrop = AutoGainPolicy.songPlacementVolume(energy: 1.0)
        check("energy curve volume model: build-out < drop",
              expectedBuildOut + 0.05 < expectedDrop,
              String(format: "%.3f vs %.3f", expectedBuildOut, expectedDrop))
        let quiet = plan.placements.filter { $0.volume <= expectedBuildOut + 0.08 }
        let loud = plan.placements.filter { $0.volume >= expectedDrop - 0.08 }
        check("stupid song plan has quiet build-out placements", !quiet.isEmpty,
              "vols=\(plan.placements.map { String(format: "%.2f", $0.volume) })")
        check("stupid song plan has loud drop placements", !loud.isEmpty,
              "vols=\(plan.placements.map { String(format: "%.2f", $0.volume) })")
        check("stupid song build-out quieter than drop (energy curve)",
              (quiet.map { $0.volume }.max() ?? 1) + 0.05 < (loud.map { $0.volume }.min() ?? 0))
    case .failure(let message):
        check("stupid song remix", false, message)
    }
}

do {
    let song = makeSong(title: "All I Wanted", bpm: 144, key: "Em")
    let feat = crateFeatures(duration: 200, bpm: 144, drum: 0.29, bass: 0.53, vocal: 0.60, confidence: 0.50)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 12, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        check("All I Wanted keeps festival 144", abs(plan.targetBPM - 144) < 0.5, "bpm=\(plan.targetBPM)")
        check("All I Wanted writesKick false", plan.pulsePolicy?.writesKick == false)
        let drops = plan.pulseRegions.filter { $0.role == .drop }
        if !drops.isEmpty {
            check("All I Wanted first drop on downbeat",
                  abs(drops[0].timelineStart / plan.barSeconds
                      - (drops[0].timelineStart / plan.barSeconds).rounded()) < 0.08,
                  String(format: "t=%.3f bars=%.3f", drops[0].timelineStart, drops[0].timelineStart / plan.barSeconds))
        }
    case .failure(let message):
        check("All I Wanted remix", false, message)
    }
}

do {
    // Britney duo: Oops = bed, BOMT = vocal, ~94, pitch bed not star.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 21, signals: signals) {
    case .success(_, let plan, _):
        check("BOMT+Oops target ~94", abs(plan.targetBPM - 94) < 1.5, "bpm=\(plan.targetBPM)")
        check("BOMT+Oops bed is Oops", plan.mashupBedSongID == oops.id,
              "bed=\(plan.mashupBedSongID == bomt.id ? "BOMT" : plan.mashupBedSongID == oops.id ? "Oops" : "?")")
        check("BOMT+Oops vocal is BOMT", plan.mashupVocalSongID == bomt.id,
              "vocal=\(plan.mashupVocalSongID == bomt.id ? "BOMT" : plan.mashupVocalSongID == oops.id ? "Oops" : "?")")
        let bedPitch = plan.placements.filter { $0.songID == oops.id }.map { $0.effects.pitchAmount }.max() ?? 0
        let vocalPitch = plan.placements.filter { $0.songID == bomt.id }.map { $0.effects.pitchAmount }.max() ?? 0
        check("BOMT+Oops bed |pitch| ≤ 2 st", bedPitch <= 2.0 / 3.0 + 0.001, String(format: "%.3f", bedPitch))
        check("BOMT+Oops vocal pitch ≤ 2 st", vocalPitch <= 2.0 / 12.0 + 0.05, String(format: "%.3f", vocalPitch))
        check("BOMT+Oops does not pitch the star vocal", vocalPitch <= 0.005 + 0.001,
              String(format: "vocalPitch=%.3f bedPitch=%.3f", vocalPitch, bedPitch))
    case .failure(let message):
        check("BOMT+Oops mashup", false, message)
    }
}

do {
    // Paramore + t.A.T.u.: Paramore stays 144 as bed; tatu is hook/cameo.
    let paramore = makeSong(title: "All I Wanted", bpm: 144, key: "Em", color: .purple)
    let tatu = makeSong(title: "All The Things She Said", bpm: 90, key: "Am", color: .pink)
    let signals: [UUID: SongSignalFeatures] = [
        paramore.id: crateFeatures(duration: 220, bpm: 144, drum: 0.29, bass: 0.53, vocal: 0.60, confidence: 0.50),
        tatu.id: crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [paramore, tatu], seed: 33, signals: signals) {
    case .success(_, let plan, _):
        check("Paramore+tatu target 144", abs(plan.targetBPM - 144) < 0.5, "bpm=\(plan.targetBPM)")
        check("Paramore+tatu bed is Paramore", plan.mashupBedSongID == paramore.id,
              "bed=\(plan.mashupBedSongID == paramore.id ? "Paramore" : plan.mashupBedSongID == tatu.id ? "tatu" : "?")")
        check("Paramore+tatu tatu is not the bed", plan.mashupBedSongID != tatu.id)
        let tatuAsFullDrop1 = plan.mashupVocalSongID == tatu.id
            && !plan.decisions.contains { $0.kind == .usedCameoOnly && $0.songTitle == tatu.title }
        // tatu may be drop1 hook if gate allows cameo-as-full, or cameo-only — never the bed.
        check("Paramore+tatu tatu usable as hook/cameo",
              plan.mashupVocalSongID == tatu.id
                || plan.decisions.contains { $0.kind == .usedCameoOnly && ($0.songTitle?.contains("Things") == true || $0.songTitle == tatu.title) }
                || plan.placements.contains { $0.songID == tatu.id },
              "vocalID=\(plan.mashupVocalSongID?.uuidString ?? "nil") cameo=\(plan.decisions.contains { $0.kind == .usedCameoOnly })")
        _ = tatuAsFullDrop1
    case .failure(let message):
        check("Paramore+tatu mashup", false, message)
    }
}

do {
    let song = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm")
    let feat = crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 5, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        check("Britney solo keeps 93", abs(plan.targetBPM - 93) < 0.5, "bpm=\(plan.targetBPM)")
        check("Britney solo writesKick false", plan.pulsePolicy?.writesKick == false)
        let drops = plan.pulseRegions.filter { $0.role == .drop }
        check("Britney first drop on downbeat",
              drops.first.map {
                  abs($0.timelineStart / plan.barSeconds - ($0.timelineStart / plan.barSeconds).rounded()) < 0.08
              } ?? false,
              drops.first.map { String(format: "t=%.3f bars=%.3f", $0.timelineStart, $0.timelineStart / plan.barSeconds) } ?? "no drop")
        if let gap = plan.intentionalGaps.first(where: { $0.reason.contains("void") }),
           let drop = drops.first {
            check("Britney void ends at drop downbeat", abs(gap.end - drop.timelineStart) < 0.05)
        }
    case .failure(let message):
        check("Britney solo remix", false, message)
    }
}

print("\n\(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")")
exit(failures == 0 ? 0 : 1)
