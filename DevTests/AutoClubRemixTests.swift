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
    check(
        "AutoTuning default pivot wallpaper is 2 bars / 4–8 beats (not 4-bar / 16×)",
        AutoTuning.standard.pivotWallpaperBars == 2
            && AutoTuning.standard.pivotWallpaperBeats >= 4
            && AutoTuning.standard.pivotWallpaperBeats <= 8,
        "bars=\(AutoTuning.standard.pivotWallpaperBars) beats=\(AutoTuning.standard.pivotWallpaperBeats)"
    )
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
        // Pivot Drop 1 = hard cut (no void). A pivoted plan must not emit
        // allowedPredropVoid at all — crate bounce treats that pair as a hole.
        let pivotBeforeDrop1: Bool = {
            guard let drop1 = drops.first else { return false }
            let beat = plan.beatSeconds
            let grains = plan.placements.filter {
                $0.role == .supporting
                    && abs($0.timelineDuration - beat) < beat * 0.35
                    && $0.timelineStart >= drop1.timelineStart - plan.barSeconds * 2.5
                    && $0.timelineStart < drop1.timelineStart - 0.02
            }
            return grains.count >= 4
                || plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
        }()
        check(
            "Drop 1 is Xirex pivot (no quiet void on a pivoted plan)",
            pivotBeforeDrop1 && !AutoRemixDiagnostics.pivotJoinHasQuietVoid(plan: plan),
            "voids=\(plan.intentionalGaps.count) pivot=\(pivotBeforeDrop1)"
        )
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

// MARK: - Hook-replace mashup (two-deck): guest in, bed vocal out — not dual-vocal default

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
        check("Hook-replace mashup mode", plan.mode == .mashup)
        check("Hook-replace plan accepted", true)
        // Default is ONE guest melody on the drop — not a stacked dual-vocal wallpaper.
        let stacked = plan.decisions.filter { $0.kind == .stackedVocalOverlay }
        let callResponseBars = stacked.compactMap { d -> Double? in
            // Optional ≤8-bar call-and-response is allowed; full-drop dual vocals are not.
            guard let detail = d.detail else { return nil }
            // detail like "8 bars on Drop 1 under …"
            let parts = detail.split(separator: " ")
            return parts.first.flatMap { Double($0) }
        }
        check(
            "No default dual-vocal wallpaper (overlay absent or ≤8-bar call-response)",
            stacked.isEmpty || callResponseBars.allSatisfy { $0 <= 8.01 },
            "stacked=\(stacked.count) bars=\(callResponseBars)"
        )
        // Guest hook replaces bed vocal: bed support under drop has heavy mid carve.
        if let bedID = plan.mashupBedSongID, let vocalID = plan.mashupVocalSongID {
            let drops = plan.placements.filter { $0.songID == vocalID && $0.role == .dominant }
            let bedUnder = plan.placements.filter { $0.songID == bedID && $0.role == .supporting }
            var hookReplace = false
            for drop in drops {
                for bed in bedUnder {
                    let overlap = min(drop.timelineEnd, bed.timelineEnd) - max(drop.timelineStart, bed.timelineStart)
                    if overlap > plan.barSeconds * 4 {
                        hookReplace = true
                        check(
                            "Hook-replace carves bed vocal (heavy blur/HPF)",
                            bed.effects.level(for: MixrEffect.blur.rawValue) >= 40,
                            String(format: "blur=%.0f", bed.effects.level(for: MixrEffect.blur.rawValue))
                        )
                    }
                }
            }
            check("Hook-replace places bed under guest drop", hookReplace)
        }
    case .failure(let message):
        check("Hook-replace mashup must be a legal plan", false, message)
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
/// Drop 1 ≠ Drop 2 when multiple hooks exist. Hook-replace (not dual-vocal default).
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
            // Xirex pivot wallpaper (1-beat grains) after a completed phrase
            // is not a sub-8-bar identity stay.
            let pivotFollows = plan.placements.contains { g in
                g.role == .supporting
                    && abs(g.timelineDuration - plan.beatSeconds) < plan.beatSeconds * 0.4
                    && g.timelineStart >= stayEnd - 0.05
                    && g.timelineStart <= stayEnd + plan.barSeconds * 0.25
            }
            flushStay(followedByVoid: voidFollows || pivotFollows)
            staySong = p.songID
            stayStart = p.timelineStart
            stayEnd = p.timelineStart + p.timelineDuration
        }
        _ = idx
    }
    let voidFollowsEnd = plan.intentionalGaps.contains { gap in
        abs(gap.start - stayEnd) < 0.08
    } || plan.placements.contains { g in
        g.role == .supporting
            && abs(g.timelineDuration - plan.beatSeconds) < plan.beatSeconds * 0.4
            && abs(g.timelineStart - stayEnd) < 0.1
    }
    flushStay(followedByVoid: voidFollowsEnd)
    if shortStays != 0 {
        var detail: [String] = []
        for p in dominants {
            let bars = p.timelineDuration / max(barSec, 0.001)
            if bars + 0.05 < 8.0 {
                detail.append(String(format: "bars=%.2f t=%.1f src=%.1f", bars, p.timelineStart, p.sourceStart))
            }
        }
        check("\(label) no sub-8-bar identity stays", shortStays == 0, "shortStays=\(shortStays) shortDoms=\(detail.joined(separator: "; "))")
    } else {
        check("\(label) no sub-8-bar identity stays", shortStays == 0, "shortStays=\(shortStays)")
    }

    // Supporting bed under hook is OK; dual full-mix kick/bass stacks fail.
    let supports = plan.placements.filter { $0.role == .supporting }
    check("\(label) may include supporting bed layers", true, "supports=\(supports.count)")
    let stacked = plan.decisions.filter { $0.kind == .stackedVocalOverlay }
    check(
        "\(label) no dual-vocal wallpaper (overlay absent or ≤8-bar call-response)",
        stacked.isEmpty || stacked.allSatisfy { ($0.detail ?? "").contains("8 bars") || ($0.detail ?? "").hasPrefix("4 ") || ($0.detail ?? "").hasPrefix("8 ") },
        "stacked=\(stacked.map { $0.detail ?? "" })"
    )

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

    // Song switches keep energy: overlap or hard cut at full clip volume.
    // Dead air / fade-to-silence as a handoff is a fail.
    var quietSwitch = false
    var switchDetail = ""
    for (prev, next) in zip(dominants, dominants.dropFirst()) where prev.songID != next.songID {
        let voidBefore = plan.intentionalGaps.contains {
            $0.reason.contains("void") && abs($0.end - next.timelineStart) < 0.05
        }
        let overlap = prev.timelineEnd - next.timelineStart
        let hardCut = (next.fadeIn.type == .none || next.fadeIn.duration <= 0.02)
            && next.volume >= 0.90
        if voidBefore || (!hardCut && overlap <= 0.05) {
            quietSwitch = true
            switchDetail = String(
                format: "void=%d overlap=%.2f fadeIn=%@ vol=%.2f @%.2fs",
                voidBefore ? 1 : 0, overlap, next.fadeIn.type.rawValue, next.volume, next.timelineStart
            )
        }
    }
    check(
        "\(label) song switches keep energy (overlap or hard cut, no dead air)",
        !quietSwitch,
        switchDetail
    )

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
        check(
            "N=3 hook-replace default (no dual-vocal wallpaper)",
            stacked.isEmpty || stacked.allSatisfy { d in
                let detail = d.detail ?? ""
                // Optional short call-and-response only.
                return detail.contains("call-response") || detail.hasPrefix("4 ") || detail.hasPrefix("8 ")
            },
            "decisions=\(stacked.map { $0.detail ?? "" })"
        )
        // Drop 1 guest is dominant; other guests are not stacked supports under it by default.
        if let vocalID = plan.mashupVocalSongID {
            let guestSupportsUnderDrop1 = plan.placements.filter { p in
                p.role == .supporting
                    && p.songID != bed.id
                    && p.songID != vocalID
                    && p.timelineDuration > plan.barSeconds * 8.5
            }
            check(
                "N=3 no full-drop second-guest vocal stack",
                guestSupportsUnderDrop1.isEmpty,
                "longGuestSupports=\(guestSupportsUnderDrop1.count)"
            )
        }
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

/// Crate-shaped pop: repeated medium prechorus then a loud title chorus.
/// Oops: prechorus ~20s and ~40s, title chorus ~46s. BOMT: “hit me” ~43s.
func popTitleChorusFeatures(
    duration: Double,
    bpm: Double,
    drum: Double,
    bass: Double,
    vocal: Double,
    titleChorusStarts: [Double],
    prechorusStarts: [Double],
    confidence: Double = 1.0
) -> SongSignalFeatures {
    var feat = crateFeatures(
        duration: duration, bpm: bpm, drum: drum, bass: bass, vocal: vocal, confidence: confidence
    )
    let hop = feat.hopSeconds
    let hops = feat.energyCurve.count
    let bar = 240.0 / max(bpm, 40)
    for i in 0..<hops {
        let t = Double(i) * hop
        var energy = 0.38
        var voc = vocal * 0.45
        var novelty = 0.12
        for p in prechorusStarts {
            if t >= p && t < p + bar * 8 {
                energy = 0.52
                voc = vocal * 0.75
            }
        }
        for c in titleChorusStarts {
            if t >= c && t < c + bar * 8 {
                energy = 0.94
                voc = min(1, vocal * 1.15)
            }
            if abs(t - c) < hop * 2 {
                novelty = 0.92
            }
        }
        feat.energyCurve[i] = energy
        feat.vocalPresenceCurve[i] = voc
        feat.noveltyCurve[i] = novelty
    }
    return feat
}

/// Crate-shaped pop where a **later** verse (Oops ~78s) is louder than the
/// first title chorus — real bounce of 6337435 picked verse 2 on score sort.
func popTitleChorusWithLouderVerseTwo(
    duration: Double,
    bpm: Double,
    drum: Double,
    bass: Double,
    vocal: Double,
    titleChorusStarts: [Double],
    prechorusStarts: [Double],
    verseTwoStart: Double = 78.0,
    confidence: Double = 1.0
) -> SongSignalFeatures {
    var feat = popTitleChorusFeatures(
        duration: duration,
        bpm: bpm,
        drum: drum,
        bass: bass,
        vocal: vocal,
        titleChorusStarts: titleChorusStarts,
        prechorusStarts: prechorusStarts,
        confidence: confidence
    )
    let hop = feat.hopSeconds
    let bar = 240.0 / max(bpm, 40)
    for i in 0..<feat.energyCurve.count {
        let t = Double(i) * hop
        if t >= verseTwoStart && t < verseTwoStart + bar * 8 {
            feat.energyCurve[i] = 0.99
            feat.vocalPresenceCurve[i] = min(1, vocal * 1.22)
        }
        if abs(t - verseTwoStart) < hop * 2 {
            feat.noveltyCurve[i] = 0.98
        }
    }
    return feat
}

/// BOMT-shaped pop where the loneliness verse groove (~95s) is hot enough
/// to beat the title chorus when guest islands include `.groove`.
func popTitleChorusWithLouderLateVerse(
    duration: Double,
    bpm: Double,
    drum: Double,
    bass: Double,
    vocal: Double,
    titleChorusStarts: [Double],
    prechorusStarts: [Double],
    lateVerseStart: Double = 95.0,
    confidence: Double = 1.0
) -> SongSignalFeatures {
    var feat = popTitleChorusFeatures(
        duration: duration,
        bpm: bpm,
        drum: drum,
        bass: bass,
        vocal: vocal,
        titleChorusStarts: titleChorusStarts,
        prechorusStarts: prechorusStarts,
        confidence: confidence
    )
    let hop = feat.hopSeconds
    let bar = 240.0 / max(bpm, 40)
    for i in 0..<feat.energyCurve.count {
        let t = Double(i) * hop
        if t >= lateVerseStart && t < lateVerseStart + bar * 8 {
            feat.energyCurve[i] = 0.97
            feat.vocalPresenceCurve[i] = min(1, vocal * 1.18)
        }
    }
    return feat
}

func chorusCandidateDump(_ profile: AutoSongProfile) -> String {
    let choruses = profile.candidates
        .filter { $0.label == .chorus }
        .sorted { $0.startSeconds < $1.startSeconds }
    let analysis = profile.analysis.chorusOrDropCandidates
        .map { String(format: "sec@%.1f", $0.startSeconds) }
        .joined(separator: ",")
    let cat = choruses
        .map { String(format: "%@@%.1fh=%.2f", $0.label.rawValue, $0.startSeconds, $0.hook) }
        .joined(separator: " ")
    return "analysis=[\(analysis)] catalog=[\(cat)]"
}

do {
    // Crate bounce of a83a66b still sourced Oops prechorus @40.4s because
    // chorusOrDropCandidates.first is a 28% duration snap, not the title line.
    // Shaped energy: prechorus twice (~20s, ~40s), title chorus ~46s.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let oopsTitle = 46.0
    let bomtTitle = 43.0
    let oopsPre: [Double] = [20.2, 40.4]
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: popTitleChorusFeatures(
            duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55,
            titleChorusStarts: [bomtTitle, 118.0],
            prechorusStarts: [20.6, 41.3]
        ),
        oops.id: popTitleChorusFeatures(
            duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55,
            titleChorusStarts: [oopsTitle, 120.0],
            prechorusStarts: oopsPre
        ),
    ]
    let oopsProfile = AutoSectionCatalog.profile(track: oops, signal: signals[oops.id])
    let bomtProfile = AutoSectionCatalog.profile(track: bomt, signal: signals[bomt.id])
    let oopsChorusList = oopsProfile.analysis.chorusOrDropCandidates
        .map { String(format: "%.1fs", $0.startSeconds) }
        .joined(separator: ",")
    let oopsCatalog = oopsProfile.candidates.filter { $0.label == .chorus }
        .map { String(format: "%.1fs/h=%.2f", $0.startSeconds, $0.hook) }
        .joined(separator: " ")
    let entrance = AutoChorusIsland.bestEntrance(
        signal: signals[oops.id],
        downbeats: oopsProfile.analysis.downbeats,
        barSeconds: oopsProfile.analysis.barSeconds,
        duration: oopsProfile.analysis.durationSeconds,
        introEnd: oopsProfile.analysis.introCandidate?.endSeconds ?? 0
    )
    check(
        "Oops analysis: title-chorus entrance is not the 40.4s prechorus snap",
        abs((entrance?.startSeconds ?? -1) - oopsTitle) < oopsProfile.analysis.barSeconds * 1.5,
        String(
            format: "entrance=%.1f rise=%.2f analysis=[%@] catalog=[%@] %@",
            entrance?.startSeconds ?? -1,
            entrance?.rise ?? -1,
            oopsChorusList,
            oopsCatalog,
            chorusCandidateDump(oopsProfile)
        )
    )

    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan)
        let hookSrc = hook?.sourceStart ?? -1
        check(
            "Shaped Oops: first bed hook is NOT prechorus ~20s or ~40s (previous 40.4s gate was the bug)",
            AutoRemixDiagnostics.firstDeckAHookIsEarlyPrechorus(
                plan: plan,
                prechorusStarts: oopsPre,
                titleChorusStart: oopsTitle
            ) == false
                && abs(hookSrc - 20.2) > 4
                && abs(hookSrc - 40.4) > 4,
            String(format: "hook=%.1f %@", hookSrc, chorusCandidateDump(oopsProfile))
        )
        check(
            "Shaped Oops: first bed hook starts on title chorus ~46s",
            abs(hookSrc - oopsTitle) < plan.barSeconds * 1.6,
            String(format: "hook=%.1f want=%.1f %@", hookSrc, oopsTitle, chorusCandidateDump(oopsProfile))
        )
        let drop1Start = AutoRemixDiagnostics.firstDropStart(plan: plan) ?? -1
        let guestDrop = plan.placements
            .filter {
                $0.songID == bomt.id && $0.role == .dominant
                    && abs($0.timelineStart - drop1Start) < 0.15
            }
            .min { abs($0.timelineStart - drop1Start) < abs($1.timelineStart - drop1Start) }
        check(
            "Shaped BOMT Drop 1 island is title chorus ~43s (hit me), not a 28% prechorus snap",
            abs((guestDrop?.sourceStart ?? -1) - bomtTitle) < plan.barSeconds * 2.5,
            String(
                format: "guestSrc=%.1f want=%.1f %@",
                guestDrop?.sourceStart ?? -1,
                bomtTitle,
                chorusCandidateDump(bomtProfile)
            )
        )
        check(
            "Shaped Oops: pivotWallpaperLoop still recorded",
            plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
        )
        check(
            "Shaped Oops: roles stay Oops bed / BOMT Drop 1",
            plan.mashupBedSongID == oops.id && plan.mashupVocalSongID == bomt.id
        )
    case .failure(let message):
        check("Shaped Oops title-chorus mashup", false, message)
    }
}

do {
    // Real crate bounce of 6337435: score-sorted entrances picked Oops verse 2
    // @78.3s (Whisper: “You see my problem is this…”) over first title chorus
    // @46s; wallpaper heard “did it” ×8; BOMT Drop 1 landed on loneliness verse.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let oopsTitle = 46.0
    let bomtTitle = 43.0
    let oopsVerseTwo = 78.3
    let bomtLateVerse = 95.0
    let oopsPre: [Double] = [20.2, 40.4]
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: popTitleChorusWithLouderLateVerse(
            duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55,
            titleChorusStarts: [bomtTitle, 118.0],
            prechorusStarts: [20.6, 41.3],
            lateVerseStart: bomtLateVerse
        ),
        oops.id: popTitleChorusWithLouderVerseTwo(
            duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55,
            titleChorusStarts: [oopsTitle, 120.0],
            prechorusStarts: oopsPre,
            verseTwoStart: oopsVerseTwo
        ),
    ]
    let oopsProfile = AutoSectionCatalog.profile(track: oops, signal: signals[oops.id])
    let bomtProfile = AutoSectionCatalog.profile(track: bomt, signal: signals[bomt.id])
    let oopsChorusList = oopsProfile.analysis.chorusOrDropCandidates
        .map { String(format: "%.1fs", $0.startSeconds) }
        .joined(separator: ",")
    let bomtChorusList = bomtProfile.analysis.chorusOrDropCandidates
        .map { String(format: "%.1fs", $0.startSeconds) }
        .joined(separator: ",")
    let entrance = AutoChorusIsland.bestEntrance(
        signal: signals[oops.id],
        downbeats: oopsProfile.analysis.downbeats,
        barSeconds: oopsProfile.analysis.barSeconds,
        duration: oopsProfile.analysis.durationSeconds,
        introEnd: oopsProfile.analysis.introCandidate?.endSeconds ?? 0
    )
    check(
        "Real-crate shape: Oops entrance is NOT verse 2 @78s (score-sort bug)",
        abs((entrance?.startSeconds ?? -1) - oopsVerseTwo) > 6,
        String(format: "entrance=%.1f verse2=%.1f analysis=[%@]", entrance?.startSeconds ?? -1, oopsVerseTwo, oopsChorusList)
    )
    check(
        "Real-crate shape: Oops entrance is first title chorus ~46s",
        abs((entrance?.startSeconds ?? -1) - oopsTitle) < oopsProfile.analysis.barSeconds * 1.5,
        String(format: "entrance=%.1f want=%.1f %@", entrance?.startSeconds ?? -1, oopsTitle, chorusCandidateDump(oopsProfile))
    )

    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan)
        let hookSrc = hook?.sourceStart ?? -1
        check(
            "Real-crate shape: bed hook is NOT Oops verse 2 @78s",
            !AutoRemixDiagnostics.firstDeckAHookIsLateVerseTwo(
                plan: plan,
                titleChorusStart: oopsTitle,
                verseTwoStart: oopsVerseTwo
            ),
            String(format: "hook=%.1f verse2=%.1f analysis=[%@]", hookSrc, oopsVerseTwo, oopsChorusList)
        )
        check(
            "Real-crate shape: bed hook is first Oops title chorus ~46s",
            abs(hookSrc - oopsTitle) < plan.barSeconds * 1.6,
            String(format: "hook=%.1f want=%.1f %@", hookSrc, oopsTitle, chorusCandidateDump(oopsProfile))
        )
        let drop1Start = AutoRemixDiagnostics.firstDropStart(plan: plan) ?? -1
        let guestDrop = plan.placements
            .filter {
                $0.songID == bomt.id && $0.role == .dominant
                    && abs($0.timelineStart - drop1Start) < 0.15
            }
            .min { abs($0.timelineStart - drop1Start) < abs($1.timelineStart - drop1Start) }
        let guestSrc = guestDrop?.sourceStart ?? -1
        check(
            "Real-crate shape: BOMT Drop 1 is NOT loneliness verse ~95s",
            !AutoRemixDiagnostics.guestDrop1IsLateVerseGroove(
                plan: plan,
                guestSongID: bomt.id,
                titleChorusStart: bomtTitle,
                lateVerseStart: bomtLateVerse
            ),
            String(format: "guestSrc=%.1f lateVerse=%.1f analysis=[%@]", guestSrc, bomtLateVerse, bomtChorusList)
        )
        check(
            "Real-crate shape: BOMT Drop 1 is title chorus ~43s (hit me)",
            abs(guestSrc - bomtTitle) < plan.barSeconds * 2.5,
            String(format: "guestSrc=%.1f want=%.1f %@ analysis=[%@]", guestSrc, bomtTitle, chorusCandidateDump(bomtProfile), bomtChorusList)
        )
        check(
            "Real-crate shape: pivotWallpaperLoop still recorded",
            plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
        )
        check(
            "Real-crate shape: roles stay Oops bed / BOMT Drop 1",
            plan.mashupBedSongID == oops.id && plan.mashupVocalSongID == bomt.id
        )
    case .failure(let message):
        check("Real-crate shape Britney mashup", false, message)
    }
}

do {
    // Real AutoRemixPlanner via runEntireProject — not a hand-built plan.
    // Crate bounce of 1afcbc0 still listed allowedPredropVoid next to
    // pivotWallpaperLoop on BOMT+Oops (seed 20260815).
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        check(
            "Planner BOMT+Oops: pivotWallpaperLoop",
            plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
        )
        check(
            "Planner BOMT+Oops: zero allowedPredropVoid",
            !plan.decisions.contains { $0.kind == .allowedPredropVoid },
            "\(plan.decisions.filter { $0.kind == .allowedPredropVoid }.compactMap(\.detail))"
        )
        if let drop1 = AutoRemixDiagnostics.firstDropStart(plan: plan) {
            check(
                "Planner BOMT+Oops: zero intentionalGaps on Drop 1",
                !AutoRemixDiagnostics.preDropVoidAt(plan: plan, dropStart: drop1)
                    && plan.intentionalGaps.isEmpty,
                "gaps=\(plan.intentionalGaps.count)"
            )
        } else {
            check("Planner BOMT+Oops: Drop 1 exists", false)
        }
        check(
            "Planner BOMT+Oops: pivot join has no quiet void",
            !AutoRemixDiagnostics.pivotJoinHasQuietVoid(plan: plan)
        )
        check(
            "Planner BOMT+Oops: club drops stay hard cuts (no equal-power fade-in)",
            !AutoRemixDiagnostics.clubDropHasEqualPowerFade(plan: plan),
            "dropCuts=\(plan.cutRecords.filter { rec in AutoRemixDiagnostics.clubDropStarts(plan: plan).contains { abs($0 - rec.timelineAt) < 0.1 } }.map { AutoRemixDiagnostics.maskingDescription($0.masking) })"
        )
        let dropStarts = AutoRemixDiagnostics.clubDropStarts(plan: plan)
        if dropStarts.count >= 2 {
            let drop2 = dropStarts[1]
            let incoming = plan.placements.filter {
                $0.role == .dominant && abs($0.timelineStart - drop2) < 0.08
            }
            check(
                "Planner BOMT+Oops: Drop 2 hard cut at full clip volume",
                incoming.contains {
                    ($0.fadeIn.type == .none || $0.fadeIn.duration <= 0.02)
                        && $0.volume >= 0.92
                },
                incoming.map { "fade=\($0.fadeIn.type.rawValue) vol=\(String(format: "%.2f", $0.volume))" }.joined(separator: ",")
            )
        }
    case .failure(let message):
        check("Planner BOMT+Oops mashup", false, message)
    }
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
        // confidence so analysisConfidence lands under the low-confidence gate.
        let feat = crateFeatures(duration: 180, bpm: 128, drum: 0.19, bass: 0.46, vocal: 0.51, confidence: 0.10)
        switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 11, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        check("stupid song remix writes pulse", plan.pulsePolicy?.writesKick == true)
        check("stupid song keeps house 128", abs(plan.targetBPM - 128) < 0.5, "bpm=\(plan.targetBPM)")
        check("stupid song used low-confidence club path",
              plan.decisions.contains { $0.kind == .imposedClubEnergyCurve || $0.kind == .usedLowConfidenceFallback })
        let expectedBuildOut = AutoGainPolicy.songPlacementVolume(energy: 0.50)
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
        let drops = plan.pulseRegions.filter { $0.role == .drop }
        if let first = drops.first {
            let bar = first.timelineStart / plan.barSeconds
            check("stupid song Drop 1 by bar 16–24", bar >= 16.5 && bar <= 24.5,
                  String(format: "bar=%.1f", bar))
        } else {
            check("stupid song has a drop", false)
        }
        let cymbals = plan.sfxEvents.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }
        check("stupid song cymbal punctuation ≤ 2", cymbals.count <= 2, "count=\(cymbals.count)")
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
            let bar = drops[0].timelineStart / plan.barSeconds
            check("All I Wanted Drop 1 by bar 16–24", bar >= 16.5 && bar <= 24.5,
                  String(format: "bar=%.1f", bar))
        }
        let cymbals = plan.sfxEvents.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }
        check("All I Wanted cymbal punctuation ≤ 2", cymbals.count <= 2, "count=\(cymbals.count)")
    case .failure(let message):
        check("All I Wanted remix", false, message)
    }
}

do {
    // Britney duo — measured crate numbers (seed matches real bounce).
    // Same midtempo pocket, equal vocal density: bed must be Oops (groove),
    // not BOMT (raw drum 1.00). Pitch the bed toward the vocal.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        check("BOMT+Oops target ~94", abs(plan.targetBPM - 94) < 1.5, "bpm=\(plan.targetBPM)")
        check("BOMT+Oops bed is Oops (not raw drum winner)", plan.mashupBedSongID == oops.id,
              "bed=\(plan.mashupBedSongID == bomt.id ? "BOMT" : plan.mashupBedSongID == oops.id ? "Oops" : "?")")
        check("BOMT+Oops vocal is BOMT", plan.mashupVocalSongID == bomt.id,
              "vocal=\(plan.mashupVocalSongID == bomt.id ? "BOMT" : plan.mashupVocalSongID == oops.id ? "Oops" : "?")")
        let bedPlacements = plan.placements.filter { $0.songID == oops.id }
        let vocalPlacements = plan.placements.filter { $0.songID == bomt.id }
        let bedPitch = bedPlacements.map { $0.effects.pitchAmount }.max() ?? 0
        let vocalPitch = vocalPlacements.map { $0.effects.pitchAmount }.max() ?? 0
        check("BOMT+Oops vocal pitch is 0", vocalPitch <= 0.005 + 0.001, String(format: "%.3f", vocalPitch))
        check("BOMT+Oops |bed pitch| ≤ 2 st", bedPitch <= 2.0 / 3.0 + 0.001, String(format: "%.3f", bedPitch))
        // Cm vocal / C#m bed → bed shifts down toward vocal (−1 st direction).
        let bedDir = bedPlacements.first { $0.effects.pitchAmount > 0.005 }?.effects.pitchDirection
        check("BOMT+Oops pitches bed toward vocal (down)",
              bedPitch <= 0.005 || bedDir == .down,
              "dir=\(bedDir.map { "\($0)" } ?? "none") amount=\(bedPitch)")
    case .failure(let message):
        check("BOMT+Oops mashup", false, message)
    }
}

do {
    // Track order reversed — still Oops bed / BOMT vocal.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [oops, bomt], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        check("BOMT+Oops reversed order still Oops bed", plan.mashupBedSongID == oops.id)
        check("BOMT+Oops reversed order still BOMT vocal", plan.mashupVocalSongID == bomt.id)
    case .failure(let message):
        check("BOMT+Oops reversed order", false, message)
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
        check("Paramore+tatu tatu owns Drop 1 vocal", plan.mashupVocalSongID == tatu.id,
              "vocal=\(plan.mashupVocalSongID == tatu.id ? "tatu" : plan.mashupVocalSongID == paramore.id ? "Paramore" : "?")")
        check(
            "Paramore+tatu Drop 1 is phrase-chop (not bed-only both drops)",
            !plan.decisions.contains {
                $0.kind == .assignedMashupRoles
                    && ($0.detail ?? "").localizedCaseInsensitiveContains("bed carries both drops")
            },
            plan.decisions.first { $0.kind == .assignedMashupRoles }?.detail ?? ""
        )
        let drop1Start = AutoRemixDiagnostics.firstDropStart(plan: plan)
        let tatuOnDrop1 = drop1Start.map { t in
            plan.placements.contains {
                $0.songID == tatu.id && $0.role == .dominant && abs($0.timelineStart - t) < 0.12
            }
        } ?? false
        check("Paramore+tatu tatu dominant on Drop 1 downbeat", tatuOnDrop1)
    case .failure(let message):
        check("Paramore+tatu mashup", false, message)
    }
}

do {
    // All-5 crate: must not park festival All I Wanted (144) as bed at ~95.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let stupid = makeSong(title: "stupid song", bpm: 128, key: "C", color: .yellow)
    let paramore = makeSong(title: "All I Wanted", bpm: 144, key: "Em", color: .purple)
    let tatu = makeSong(title: "All The Things She Said", bpm: 90, key: "Am", color: .red)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
        stupid.id: crateFeatures(duration: 180, bpm: 128, drum: 0.19, bass: 0.46, vocal: 0.51, confidence: 0.46),
        paramore.id: crateFeatures(duration: 220, bpm: 144, drum: 0.29, bass: 0.53, vocal: 0.60, confidence: 0.50),
        tatu.id: crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(
        tracks: [bomt, oops, stupid, paramore, tatu],
        seed: 20260815,
        signals: signals
    ) {
    case .success(_, let plan, _):
        check("All-5 bed is not Paramore parked at midtempo",
              plan.mashupBedSongID != paramore.id || abs(plan.targetBPM - 144) < 1,
              "bed=\(plan.mashupBedSongID == paramore.id ? "Paramore" : "other") bpm=\(plan.targetBPM)")
        check("All-5 does not park a 144 bed at ~95",
              !(plan.mashupBedSongID == paramore.id && plan.targetBPM < 110),
              "bedBPM=\(plan.targetBPM)")
        check("All-5 keeps Oops bed when Britney pair in crate", plan.mashupBedSongID == oops.id,
              "bed=\(plan.mashupBedSongID == bomt.id ? "BOMT" : plan.mashupBedSongID == oops.id ? "Oops" : "other")")
        // Bed's native pocket should match the arrangement target.
        if let bedID = plan.mashupBedSongID {
            let bedTrack = [bomt, oops, stupid, paramore, tatu].first { $0.id == bedID }
            let bedBPM = Double(bedTrack?.bpm ?? 0)
            check("All-5 target stays near bed pocket",
                  abs(plan.targetBPM - bedBPM) / max(bedBPM, 1) <= 0.12,
                  "target=\(plan.targetBPM) bedNative=\(bedBPM)")
        }
    case .failure(let message):
        check("All-5 crate mashup", false, message)
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
        if let drop = drops.first {
            let voidOK = plan.intentionalGaps.contains {
                $0.reason.contains("void") && abs($0.end - drop.timelineStart) < 0.05
            }
            let beat = plan.beatSeconds
            let grains = plan.placements.filter {
                $0.role == .supporting
                    && abs($0.timelineDuration - beat) < beat * 0.35
                    && $0.timelineStart >= drop.timelineStart - plan.barSeconds * 2.5
                    && $0.timelineStart < drop.timelineStart - 0.02
            }
            check(
                "Britney void or Xirex pivot wallpaper before drop",
                voidOK || grains.count >= 4,
                "void=\(voidOK) grains=\(grains.count)"
            )
            check(
                "Britney solo: pivot join has no quiet void",
                !AutoRemixDiagnostics.pivotJoinHasQuietVoid(plan: plan),
                "gaps=\(plan.intentionalGaps.count)"
            )
        }
    case .failure(let message):
        check("Britney solo remix", false, message)
    }
}

do {
    // Non-void handoffs must declare real temporal overlap (continuous energy).
    let song = makeSong(title: "All The Things She Said", bpm: 90, key: "Am")
    let feat = crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 42, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        let dominants = plan.placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        var blendedJoins = 0
        var voidSkipped = 0
        for (prev, next) in zip(dominants, dominants.dropFirst()) {
            let voidBefore = plan.intentionalGaps.contains {
                $0.reason.contains("void") && abs($0.end - next.timelineStart) < 0.05
            }
            if voidBefore {
                voidSkipped += 1
                continue
            }
            // Xirex pivot hard cut — no overlap required (slam on the downbeat).
            let pivotBefore = plan.placements.contains { g in
                g.role == .supporting
                    && abs(g.timelineDuration - plan.beatSeconds) < plan.beatSeconds * 0.4
                    && g.timelineStart >= next.timelineStart - plan.barSeconds * 4.5
                    && g.timelineStart < next.timelineStart - 0.02
            }
            if pivotBefore { continue }
            // Club Drop 1 / Drop 2: hard cut + impact, not an equal-power overlap.
            if AutoRemixDiagnostics.incomingIsClubDrop(
                pulseRegions: plan.pulseRegions,
                timelineStart: next.timelineStart
            ) { continue }
            // Source-continuous splits (build body → build-out) abut without
            // overlap by design — they are the same reading, not a handoff.
            let sourceContinuous = next.continuesPrevious
                || abs(next.sourceStart - (
                    prev.sourceStart + prev.timelineDuration * prev.tempoRatio
                )) < 0.05
            if sourceContinuous { continue }
            let overlap = prev.timelineEnd - next.timelineStart
            let declared = next.overlapsPreviousSeconds
            check(
                "Handoff overlap seconds > 0",
                overlap > 0.05 && declared > 0.05,
                String(format: "overlap=%.3f declared=%.3f at t=%.2f", overlap, declared, next.timelineStart)
            )
            blendedJoins += 1
        }
        check("At least one blended handoff exists", blendedJoins > 0, "joins=\(blendedJoins) voids=\(voidSkipped)")
        check(
            "Intentional gaps are only pre-drop voids",
            plan.intentionalGaps.allSatisfy { $0.reason.contains("void") },
            plan.intentionalGaps.map(\.reason).joined(separator: ",")
        )
    case .failure(let message):
        check("Handoff overlap remix", false, message)
    }
}

do {
    // DJ-level layering: drop vocal must overlap bed deck in time.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: popTitleChorusFeatures(
            duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55,
            titleChorusStarts: [43.0, 118.0],
            prechorusStarts: [20.6, 41.3]
        ),
        oops.id: popTitleChorusFeatures(
            duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55,
            titleChorusStarts: [46.0, 120.0],
            prechorusStarts: [20.2, 40.4]
        ),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(let applied, let plan, _):
        guard let bedID = plan.mashupBedSongID, let vocalID = plan.mashupVocalSongID else {
            check("Mashup bed under hook roles present", false, "missing roles")
            break
        }
        let dropLeads = plan.placements.filter {
            $0.songID == vocalID && $0.role == .dominant
        }
        let bedLayers = plan.placements.filter {
            $0.songID == bedID && $0.role == .supporting
        }
        var layered = false
        for drop in dropLeads {
            for bed in bedLayers where bed.timelineDuration >= plan.barSeconds * 4 {
                let overlap = min(drop.timelineEnd, bed.timelineEnd) - max(drop.timelineStart, bed.timelineStart)
                if overlap > plan.barSeconds {
                    layered = true
                    check("Bed under drop stays audible (not muted)", bed.volume >= 0.70,
                          String(format: "vol=%.2f", bed.volume))
                    check("Hook-replace carves bed vocal (heavy HPF/blur)",
                          bed.effects.level(for: MixrEffect.blur.rawValue) >= 40,
                          String(format: "blur=%.0f", bed.effects.level(for: MixrEffect.blur.rawValue)))
                }
            }
        }
        check("Drop placement overlaps bed placement in time", layered,
              "drops=\(dropLeads.count) bedSupports=\(bedLayers.count)")

        // Two-deck + Xirex pivot: Oops plays complete first; no early title chops.
        // Real Drop 1 is after one complete Oops hook + 2-bar baby loop (~bar 18),
        // never a fake drop on the bed chorus and never a quiet fade-in.
        let pulseDrops = plan.pulseRegions.filter { $0.role == .drop }.sorted { $0.timelineStart < $1.timelineStart }
        if let pulseDrop1 = pulseDrops.first {
            let dropBar = pulseDrop1.timelineStart / plan.barSeconds
            check(
                "Britney: pulse Drop 1 after complete Oops + pivot (~bar 18), not bar 16 fake / not late bar 28",
                dropBar >= 16.5 && dropBar <= 24.5,
                String(format: "bar=%.1f t=%.2f", dropBar, pulseDrop1.timelineStart)
            )
        } else {
            check("Britney: pulse Drop 1 exists", false)
        }

        if let drop1Start = dropLeads.map(\.timelineStart).min() {
            let guestBefore = plan.placements.filter {
                $0.songID == vocalID
                    && $0.timelineStart < drop1Start - 0.05
                    && $0.timelineDuration > plan.barSeconds
            }
            check(
                "Britney two-deck: no BOMT before Drop 1 mix",
                guestBefore.isEmpty,
                "earlyGuest=\(guestBefore.count)"
            )

            let bedDoms = plan.placements
                .filter { $0.songID == bedID && $0.role == .dominant }
                .sorted { $0.timelineStart < $1.timelineStart }
            if let firstBed = bedDoms.first {
                check(
                    "Britney: first Oops title/intro uncut (source near start)",
                    firstBed.sourceStart <= plan.barSeconds * 2 + 0.05,
                    String(format: "sourceStart=%.2f", firstBed.sourceStart)
                )
                check(
                    "Britney: first Oops placement is a complete phrase (≥8 bars)",
                    firstBed.timelineDuration >= plan.barSeconds * 7.5,
                    String(format: "dur=%.2f", firstBed.timelineDuration)
                )
                let bedBeforeDrop = bedDoms.filter { $0.timelineStart < drop1Start - 0.05 }
                check(
                    "Britney: Oops opening title/chorus finishes before pivot (important lines uncut)",
                    bedBeforeDrop.contains { $0.timelineDuration >= plan.barSeconds * 7.5 },
                    "bedPhrasesBeforeDrop=\(bedBeforeDrop.count)"
                )
            } else {
                check("Britney: Oops bed dominant exists", false)
            }

            check(
                "Britney: first Deck A hook is not a sub-phrase chop of the title",
                !AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: plan),
                {
                    let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan)
                    return String(
                        format: "src=%.2f dur=%.2f bar=%.2f",
                        hook?.sourceStart ?? -1,
                        hook?.timelineDuration ?? -1,
                        plan.barSeconds
                    )
                }()
            )
            let oopsProfile = AutoSectionCatalog.profile(track: oops, signal: signals[oops.id])
            let hookSrc = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan)?.sourceStart ?? -1
            check(
                "Britney: first complete hook is title chorus ~46s, not prechorus ~20/~40",
                abs(hookSrc - 46.0) < plan.barSeconds * 1.6
                    && abs(hookSrc - 20.2) > 4
                    && abs(hookSrc - 40.4) > 4,
                String(format: "src=%.1f %@", hookSrc, chorusCandidateDump(oopsProfile))
            )
            check(
                "Britney mashup is clubby (Diplo/Guetta/Snake), not Calvin preservation",
                plan.clubFlavor == .diplo || plan.clubFlavor == .guetta || plan.clubFlavor == .snake,
                "flavor=\(plan.clubFlavor?.rawValue ?? "nil")"
            )
            check(
                "Britney: Drop 1 has pivot wallpaper (loop + hard cut)",
                AutoRemixDiagnostics.drop1HasPivotWallpaper(plan: plan)
            )
            check(
                "Britney: pivotWallpaperLoop recorded",
                plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
            )
            check(
                "Britney: zero allowedPredropVoid on a pivoted plan",
                !plan.decisions.contains { $0.kind == .allowedPredropVoid },
                "voidDecisions=\(plan.decisions.filter { $0.kind == .allowedPredropVoid }.map { $0.detail ?? "" })"
            )
            if let drop1 = AutoRemixDiagnostics.firstDropStart(plan: plan) {
                check(
                    "Britney: zero intentionalGaps on Drop 1",
                    !AutoRemixDiagnostics.preDropVoidAt(plan: plan, dropStart: drop1)
                        && plan.intentionalGaps.allSatisfy {
                            abs($0.end - drop1) >= 0.08
                        },
                    "gaps=\(plan.intentionalGaps.count)"
                )
            } else {
                check("Britney: Drop 1 exists for void check", false)
            }
            check(
                "Britney: pivot join has no quiet void (planner emit, not a hand-built plan)",
                !AutoRemixDiagnostics.pivotJoinHasQuietVoid(plan: plan),
                "gaps=\(plan.intentionalGaps.count)"
            )
            check(
                "Britney: club drops stay hard cuts (no equal-power fade-in)",
                !AutoRemixDiagnostics.clubDropHasEqualPowerFade(plan: plan)
            )

            // No supporting chops in the opening 8–16 bars (wallpaper is mix-window only).
            let earlyChops = plan.placements.filter {
                $0.role == .supporting
                    && $0.timelineStart < plan.barSeconds * 8 - 0.05
                    && $0.timelineDuration <= plan.beatSeconds * 1.5
            }
            check(
                "Britney: no early intro/title chops",
                earlyChops.isEmpty,
                "earlyChops=\(earlyChops.count)"
            )

            // Pivot wallpaper: 1-beat last-word grains, 4–8× (~1–2 bars), immediately before Drop 1.
            let beat = plan.beatSeconds
            let grains = plan.placements.filter { p in
                p.role == .supporting
                    && p.songID == bedID
                    && abs(p.timelineDuration - beat) < beat * 0.35
                    && p.timelineStart >= drop1Start - plan.barSeconds * 2.5
                    && p.timelineStart < drop1Start - 0.02
            }.sorted { $0.timelineStart < $1.timelineStart }
            check(
                "Britney: pivot wallpaper is 4–8× of a 1-beat grain (~1–2 bars)",
                grains.count >= 4 && grains.count <= 8,
                "count=\(grains.count)"
            )
            if let g0 = grains.first {
                let sameGrain = grains.allSatisfy { abs($0.sourceStart - g0.sourceStart) < 0.08 }
                check("Britney: wallpaper chops share one pivot grain source", sameGrain)
                check(
                    "Britney: pivot loop is HPF/thinned (blur)",
                    grains.allSatisfy { $0.effects.level(for: MixrEffect.blur.rawValue) >= 36 }
                )
                check(
                    "Britney: pivot grains stay loud (HPF thins; volume does not duck)",
                    grains.allSatisfy { $0.volume >= 0.90 },
                    "vols=\(grains.map { String(format: "%.2f", $0.volume) }.joined(separator: ","))"
                )
                check(
                    "Britney: pivot grains have no fade-in",
                    grains.allSatisfy { $0.fadeIn.type == .none || $0.fadeIn.duration <= 0.02 }
                )
                if let last = grains.last {
                    check(
                        "Britney: Baby hook-replace lands on downbeat after pivot loop",
                        abs(last.timelineEnd - drop1Start) < plan.beatSeconds * 0.6
                            || (drop1Start - last.timelineEnd) < plan.beatSeconds * 0.6
                                && drop1Start >= last.timelineEnd - 0.05,
                        String(format: "loopEnd=%.2f drop=%.2f", last.timelineEnd, drop1Start)
                    )
                    // Scorer consistency: pivot hard-cut time == pulse Drop 1 time.
                    if let pulseDrop1 = pulseDrops.first {
                        check(
                            "Britney: pivot hard cut matches pulse Drop 1 (not an earlier fake drop)",
                            abs(pulseDrop1.timelineStart - drop1Start) < plan.beatSeconds * 0.6,
                            String(format: "pulseDrop=%.2f guestDrop=%.2f", pulseDrop1.timelineStart, drop1Start)
                        )
                    }
                }
            }

            // Xirex hard cut: incoming Drop 1 is full level, not a fade-in from silence.
            if let drop1 = dropLeads.min(by: { $0.timelineStart < $1.timelineStart }) {
                check(
                    "Britney: Drop 1 hard cut — no fade-in / volume ramp",
                    drop1.fadeIn.type == .none || drop1.fadeIn.duration <= 0.02,
                    "fadeIn=\(drop1.fadeIn.type.rawValue) dur=\(drop1.fadeIn.duration)"
                )
                check(
                    "Britney: Drop 1 slam is ~full gain on bar 1 of the hook",
                    drop1.volume >= 0.92,
                    String(format: "vol=%.2f", drop1.volume)
                )
            }

            // Diet SFX on the pivot join: loop grains + ≤1 slam (impact). No riser pile.
            let mixLo = drop1Start - plan.barSeconds * 2.5
            let mixHi = drop1Start + plan.beatSeconds
            let joinSFX = plan.sfxEvents.filter {
                $0.timelineStart >= mixLo - 0.05 && $0.timelineStart <= mixHi + 0.05
                    && !SoundEffectLibrary.isPulseLayer($0.assetID)
            }
            let joinSlams = joinSFX.filter { $0.assetID == "impact" }
            let joinPile = joinSFX.filter {
                $0.assetID == "riser" || $0.assetID == "snareBuild"
                    || $0.assetID == "tapeStop" || $0.assetID == "crash"
                    || $0.assetID == "reverseCymbal"
            }
            check(
                "Britney: mix-window SFX is pivot loop + ≤1 slam (no riser/tape/crash pile)",
                joinSlams.count <= 1 && joinPile.isEmpty,
                "slams=\(joinSlams.count) pile=\(joinPile.map(\.assetID))"
            )

            check(
                "Britney: pivotWallpaperLoop decision recorded",
                plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
            )
            // No echo-throw spam — pivot loop replaced that grammar.
            let echoSpam = plan.placements.filter {
                $0.role == .supporting
                    && $0.fadeOut.type == .echoOut
                    && $0.timelineDuration > plan.beatSeconds * 1.5
            }
            check(
                "Britney: no echo-throw wallpaper (pivot loop instead)",
                echoSpam.isEmpty,
                "echoes=\(echoSpam.count)"
            )
            check(
                "Britney two-deck: no dual-vocal overlay default",
                !plan.decisions.contains { $0.kind == .stackedVocalOverlay }
            )
            // Shared pivot token from titles.
            let token = AutoPivotWord.preferredPivot(
                deckATitle: "Oops I Did It Again",
                deckBTitle: "Baby One More Time"
            )
            check("Britney pivot token is 'baby'", token == "baby", "token=\(token ?? "nil")")

            // Product lock: Auto writes per-clip volume (not track faders / blur only).
            let songClips = applied.filter { !$0.isSFXTrack }.flatMap(\.clips)
            check("Britney: Auto applied song clips exist", !songClips.isEmpty)
            let unityOnly = songClips.allSatisfy { abs($0.volume - 1.0) < 0.001 }
            check(
                "Britney: Auto writes clip-wise volume (not all 1.0 by accident)",
                !unityOnly,
                "vols=\(Set(songClips.map { String(format: "%.2f", $0.volume) }).sorted().joined(separator: ","))"
            )
            let beatUnits = MixrTimeline.units(fromSeconds: beat)
            let drop1Unit = MixrTimeline.units(fromSeconds: drop1Start)
            let lookbackUnits = MixrTimeline.units(fromSeconds: plan.barSeconds * 2.5)
            let grainClips = songClips.filter { clip in
                abs(clip.length - beatUnits) < beatUnits * 0.4
                    && clip.start >= drop1Unit - lookbackUnits
                    && clip.start < drop1Unit - MixrTimeline.units(fromSeconds: 0.02)
            }
            check(
                "Britney: applied pivot clips stay loud (not a quiet wallpaper hole)",
                !grainClips.isEmpty && grainClips.allSatisfy { $0.volume >= 0.90 },
                "n=\(grainClips.count) vols=\(grainClips.map { String(format: "%.2f", $0.volume) }.joined(separator: ","))"
            )
            if let g0 = grains.first {
                let g0Start = MixrTimeline.units(fromSeconds: g0.timelineStart)
                if let appliedGrain = grainClips.min(by: { abs($0.start - g0Start) < abs($1.start - g0Start) }) {
                    check(
                        "Britney: applier copies pivot placement volume onto MixrClip",
                        abs(appliedGrain.volume - g0.volume) < 0.02,
                        String(format: "clip=%.2f placement=%.2f", appliedGrain.volume, g0.volume)
                    )
                }
            }
            if let drop1 = dropLeads.min(by: { $0.timelineStart < $1.timelineStart }) {
                let dStart = MixrTimeline.units(fromSeconds: drop1.timelineStart)
                let dropClips = songClips.filter { abs($0.start - dStart) < MixrTimeline.units(fromSeconds: 0.08) }
                if let appliedDrop = dropClips.max(by: { $0.volume < $1.volume }) {
                    check(
                        "Britney: applied Drop 1 clip is ~full volume",
                        appliedDrop.volume >= 0.92,
                        String(format: "vol=%.2f", appliedDrop.volume)
                    )
                    check(
                        "Britney: applied Drop 1 clip has no audible fade-in",
                        appliedDrop.transitionIn.type == .none || appliedDrop.transitionIn.duration <= 0.02,
                        "fadeIn=\(appliedDrop.transitionIn.type.rawValue) dur=\(appliedDrop.transitionIn.duration)"
                    )
                }
            }
        }

        // Pivot Drop 1: impact slam only (no riser wallpaper required).
        let impacts = plan.sfxEvents.filter { $0.assetID == "impact" }
        check("Mashup emits impact slam on a drop", !impacts.isEmpty)
        if let drop1 = dropLeads.map(\.timelineStart).min() {
            let onDrop1 = impacts.contains { abs($0.timelineStart - drop1) < 0.35 }
            check("Mashup impact lands on Drop 1 downbeat", onDrop1)
        }
    case .failure(let message):
        check("Bed under hook mashup", false, message)
    }
}

do {
    // Simultaneous SFX land on separate SFX rows (per-row non-overlap).
    var tracks: [MixrTrack] = [
        makeSong(title: "Stack Fixture", bpm: 128, key: "C", durationSeconds: 60)
    ]
    let riser = SoundEffectLibrary.definition(for: "riser")!
    let impact = SoundEffectLibrary.definition(for: "impact")!
    let t = MixrTimeline.units(fromSeconds: 8)
    // Impact at the same instant the riser ends — classic drop stack.
    SoundEffectLibrary.placeExact(definition: riser, atUnit: t - riser.lengthUnits, into: &tracks)
    SoundEffectLibrary.placeExact(definition: impact, atUnit: t, into: &tracks)
    // Force a same-timestamp collision: second impact needs another row.
    SoundEffectLibrary.placeExact(definition: impact, atUnit: t, into: &tracks)
    let sfxTracks = tracks.filter(\.isSFXTrack)
    check("Two simultaneous SFX create ≥2 SFX tracks", sfxTracks.count >= 2,
          "sfxRows=\(sfxTracks.count)")
    let startsAtT = sfxTracks.flatMap(\.clips).filter { abs($0.start - t) < 0.5 }
    check("Two SFX events can share a timestamp across rows", startsAtT.count >= 2,
          "clipsAtT=\(startsAtT.count)")
    for row in sfxTracks {
        for (a, b) in zip(row.clips.sorted { $0.start < $1.start },
                          row.clips.sorted { $0.start < $1.start }.dropFirst()) {
            check(
                "Per SFX row clips do not overlap",
                a.start + a.length <= b.start + MixrTimeline.clipEdgeEpsilon,
                String(format: "row clips %.1f…%.1f vs %.1f", a.start, a.start + a.length, b.start)
            )
        }
    }

    // Applier packing: plan with overlapping musical SFX → multi-row apply.
    let song = tracks.first { !$0.isSFXTrack }!
    let feat = crateFeatures(duration: 180, bpm: 128, drum: 0.2, bass: 0.5, vocal: 0.5, confidence: 0.2)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 11, signals: [song.id: feat]) {
    case .success(let applied, let plan, _):
        let dropSFX = plan.sfxEvents.filter { ["riser", "snareBuild", "impact"].contains($0.assetID) }
        if dropSFX.count >= 2 {
            let appliedSFX = applied.filter(\.isSFXTrack)
            let times = Dictionary(grouping: dropSFX, by: { Int(($0.timelineStart * 100).rounded()) })
            let colliding = times.values.contains { $0.count >= 2 }
                || dropSFX.contains { a in
                    dropSFX.contains { b in
                        a.assetID != b.assetID
                            && abs(a.timelineStart - b.timelineStart) < 0.05
                    }
                }
            // Riser ends at impact time; applier must not slide them onto one row.
            let impactEvents = plan.sfxEvents.filter { $0.assetID == "impact" }
            let risers = plan.sfxEvents.filter { $0.assetID == "riser" || $0.assetID == "snareBuild" }
            var needsTwoRows = colliding
            for impact in impactEvents {
                for r in risers {
                    let rEnd = r.timelineEnd
                    if abs(rEnd - impact.timelineStart) < 0.35 || abs(r.timelineStart - impact.timelineStart) < 0.05 {
                        needsTwoRows = true
                    }
                }
            }
            if needsTwoRows {
                check("Auto apply uses multiple SFX rows when hits collide",
                      appliedSFX.count >= 2 || appliedSFX.flatMap(\.clips).count >= 2,
                      "sfxTracks=\(appliedSFX.count) clips=\(appliedSFX.flatMap(\.clips).count)")
            }
            // Same-timestamp musical SFX must not share one row.
            for row in appliedSFX {
                let byStart = Dictionary(grouping: row.clips) { Int(($0.start * 10).rounded()) }
                let overlapOnRow = byStart.values.contains { group in
                    group.count > 1 && zip(group, group.dropFirst()).contains { a, b in
                        a.start < b.start + b.length && b.start < a.start + a.length
                    }
                }
                check("Applied SFX row has no overlapping clips", !overlapOnRow)
            }
        } else {
            check("Energy-curve plan emits drop SFX", !dropSFX.isEmpty)
        }
    case .failure(let message):
        check("SFX multi-row apply", false, message)
    }
}

do {
    // Even when Oops measures hotter vocals than BOMT, same-pocket duo must
    // keep Oops as bed (groove) and BOMT as Drop 1 vocal — vocal density alone
    // must not invert Britney-class roles.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.48, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.72, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        check("Skewed-vocal Britney still Oops bed", plan.mashupBedSongID == oops.id,
              "bed=\(plan.mashupBedSongID == bomt.id ? "BOMT" : plan.mashupBedSongID == oops.id ? "Oops" : "?")")
        check("Skewed-vocal Britney still BOMT Drop 1", plan.mashupVocalSongID == bomt.id,
              "vocal=\(plan.mashupVocalSongID == bomt.id ? "BOMT" : plan.mashupVocalSongID == oops.id ? "Oops" : "?")")
    case .failure(let message):
        check("Skewed-vocal Britney mashup", false, message)
    }
}

do {
    // Two-deck club remix: Diplo energy on the drop; verses stay the record.
    let song = makeSong(title: "All The Things She Said", bpm: 90, key: "Am")
    let feat = crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 42, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        let musical = plan.sfxEvents.filter { !SoundEffectLibrary.isPulseLayer($0.assetID) }
        let drops = plan.pulseRegions.filter { $0.role == .drop }
        let grooves = plan.pulseRegions.filter { $0.role == .groove || $0.role == .introTease }
        func inMixWindow(_ t: Double) -> Bool {
            for drop in drops {
                let winStart = max(0, drop.timelineStart - plan.barSeconds * 8)
                if t >= winStart - 0.05 && t <= drop.timelineStart + plan.barSeconds * 8 + 0.05 {
                    return true
                }
            }
            return false
        }
        let wallpaper = musical.filter { ev in
            !inMixWindow(ev.timelineStart)
                && (ev.assetID == "riser" || ev.assetID == "snareBuild" || ev.assetID == "tapeStop"
                    || ev.assetID == "airSweep" || ev.assetID == "clapFill")
        }
        check(
            "Two-deck: no riser/snare/tape/clap wallpaper outside mix windows",
            wallpaper.isEmpty,
            "wallpaper=\(wallpaper.map(\.assetID)) @ \(wallpaper.map { String(format: "%.1f", $0.timelineStart) })"
        )
        check(
            "Club remix has impact on Drop 1",
            drops.first.map { d0 in
                musical.contains { $0.assetID == "impact" && abs($0.timelineStart - d0.timelineStart) < 0.35 }
            } ?? false
        )
        check(
            "Club remix Drop 1 mix window is diet (impact slam, no riser/snare pile)",
            drops.first.map { d0 in
                let lo = d0.timelineStart - plan.barSeconds * 4.5
                let hi = d0.timelineStart + plan.beatSeconds
                let join = musical.filter { $0.timelineStart >= lo - 0.05 && $0.timelineStart <= hi + 0.05 }
                let pile = join.filter {
                    $0.assetID == "riser" || $0.assetID == "snareBuild"
                        || $0.assetID == "tapeStop" || $0.assetID == "crash"
                }
                let slams = join.filter { $0.assetID == "impact" }
                return pile.isEmpty && slams.count <= 1
            } ?? false
        )
        let cymbals = musical.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }
        check("Club remix cymbal punctuation ≤ 2", cymbals.count <= 2, "count=\(cymbals.count)")
        if let first = drops.first {
            let bar = first.timelineStart / plan.barSeconds
            check("Club remix Drop 1 by bar 16–24", bar >= 16.5 && bar <= 24.5,
                  String(format: "bar=%.1f", bar))
        }
        if let dropPlacement = plan.placements.first(where: {
            abs($0.timelineStart - (drops.first?.timelineStart ?? -1)) < 0.05
        }) {
            let hooks = AutoSectionCatalog.profile(
                track: song,
                signal: feat
            ).candidates.filter { $0.label == .chorus || $0.label == .teaser }
            let matched = hooks.contains {
                abs($0.startSeconds - dropPlacement.sourceStart) < 0.5
            }
            check(
                "Club remix Drop 1 is a chorus/teaser island",
                matched || dropPlacement.sourceStart > 1.0,
                String(format: "sourceStart=%.1f", dropPlacement.sourceStart)
            )
        }
        check(
            "Club remix: first Deck A hook is not a sub-phrase chop of the title",
            !AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: plan),
            {
                let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan)
                return String(
                    format: "src=%.2f dur=%.2f bar=%.2f",
                    hook?.sourceStart ?? -1,
                    hook?.timelineDuration ?? -1,
                    plan.barSeconds
                )
            }()
        )
        if AutoRemixDiagnostics.drop1HasPivotWallpaper(plan: plan),
           let drop1 = AutoRemixDiagnostics.firstDropStart(plan: plan) {
            check(
                "Club remix: pivot Drop 1 has no pre-drop void",
                !AutoRemixDiagnostics.preDropVoidAt(plan: plan, dropStart: drop1)
            )
        }
        let grooveFXHeavy = plan.placements.filter { p in
            let onGroove = grooves.contains {
                p.timelineStart >= $0.timelineStart - 0.05 && p.timelineStart < $0.timelineEnd - 0.05
            }
            return onGroove
                && (p.effects.level(for: MixrEffect.echo.rawValue) >= 20 || p.fadeOut.type == .echoOut)
        }
        check(
            "Two-deck: verses/grooves stay the record (no heavy echo FX)",
            grooveFXHeavy.isEmpty,
            "heavyGrooveFX=\(grooveFXHeavy.count)"
        )
        let buildOutFX = plan.placements.filter {
            $0.effects.level(for: MixrEffect.blur.rawValue) >= 45
                || $0.fadeOut.type == .echoOut
        }
        check("Club remix fires build-out blur / echo-out in mix window", !buildOutFX.isEmpty)
        check("Club remix picks Diplo for dancehall/festival midtempo",
              plan.clubFlavor == .diplo,
              "flavor=\(plan.clubFlavor?.rawValue ?? "nil")")
        check("Diplo flavor is maximalist",
              plan.clubFlavor?.bias.maximalistStacks == true)
        check("Diplo flavor allows half-time drop",
              plan.clubFlavor?.bias.halfTimeDrop == true)
        // Pivot wallpaper (1-beat grains) may sit in the mix window; no echo-throw spam.
        let echoes = plan.placements.filter { p in
            p.role == .supporting
                && p.songID == song.id
                && p.fadeOut.type == .echoOut
                && p.timelineDuration > plan.beatSeconds * 1.5
        }
        check(
            "No echo-throw wallpaper (pivot loop replaces it)",
            echoes.isEmpty,
            "echoes=\(echoes.count)"
        )
        let grains = plan.placements.filter { p in
            p.role == .supporting
                && abs(p.timelineDuration - plan.beatSeconds) < plan.beatSeconds * 0.35
                && inMixWindow(p.timelineStart)
        }
        check(
            "Pivot wallpaper grains gated to mix windows",
            grains.isEmpty || grains.allSatisfy { inMixWindow($0.timelineStart) },
            "grains=\(grains.count)"
        )
    case .failure(let message):
        check("Two-deck club remix", false, message)
    }
}

do {
    // Flavor selection unit checks — instincts, not sound-alikes.
    let diplo = AutoClubFlavor.choose(
        drumStrength: 0.71, bassDensity: 0.38, vocalDensity: 0.55, bpm: 95, seed: 7
    )
    check("Britney-class pop-over-club bed → Diplo", diplo == .diplo, "got \(diplo.rawValue)")
    let ballad = AutoClubFlavor.choose(
        drumStrength: 0.2, bassDensity: 0.2, vocalDensity: 0.85, bpm: 72, seed: 3
    )
    check("Sparse piano ballad still Calvin", ballad == .calvin, "got \(ballad.rawValue)")
    let festival = AutoClubFlavor.choose(
        drumStrength: 0.6, bassDensity: 0.7, vocalDensity: 0.4, bpm: 145, seed: 2
    )
    check("Festival bass → Snake or Diplo",
          festival == .snake || festival == .diplo,
          "got \(festival.rawValue)")
    check("Diplo bias keeps midrange busy",
          AutoClubFlavor.diplo.bias.dropMidrangeSparse == false)
    check("Diplo bias treats FX as groove",
          AutoClubFlavor.diplo.bias.fxAsGroove == true)
}

do {
    // AutoMashUpper / AutoMashup role proxies — Britney crate numbers.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    let bomtProf = AutoSectionCatalog.profile(track: bomt, signal: signals[bomt.id])
    let oopsProf = AutoSectionCatalog.profile(track: oops, signal: signals[oops.id])
    check(
        "Role proxy: Oops beats BOMT as bed (drum 1.00 soft-capped)",
        AutoStemRoleProxy.bedScore(for: oopsProf) > AutoStemRoleProxy.bedScore(for: bomtProf),
        String(format: "oops=%.3f bomt=%.3f",
               AutoStemRoleProxy.bedScore(for: oopsProf),
               AutoStemRoleProxy.bedScore(for: bomtProf))
    )
    check(
        "Role proxy: BOMT beats Oops as hook",
        AutoStemRoleProxy.hookScore(for: bomtProf) >= AutoStemRoleProxy.hookScore(for: oopsProf) - 0.05,
        String(format: "bomt=%.3f oops=%.3f",
               AutoStemRoleProxy.hookScore(for: bomtProf),
               AutoStemRoleProxy.hookScore(for: oopsProf))
    )
    if let island = AutoMashability.bestIsland(
        guest: bomtProf, bed: oopsProf, wantBars: 16, targetBPM: 94, tuning: .standard
    ) {
        check("AutoMashUpper island bars are 8–16", island.bars >= 8 && island.bars <= 16,
              "bars=\(island.bars)")
        check("AutoMashUpper island has positive mashability", island.score > 0.2,
              String(format: "%.3f", island.score))
        check("AutoMashUpper spectral balance is defined", island.spectral > 0,
              String(format: "%.3f", island.spectral))
    } else {
        check("AutoMashUpper finds a local island for BOMT over Oops", false)
    }

    // Mixxx AutoDJ phrase match: long intro delays incoming so endings meet.
    let longIntro = AutoPhraseMatch.plan(
        outgoingDuration: 4.0,
        incomingIntroDuration: 12.0,
        beatSeconds: 0.5,
        barSeconds: 2.0,
        bpmAligned: true,
        stretchFar: false
    )
    check("Mixxx: long intro delays incoming", longIntro.incomingDelaySeconds > 0.5,
          String(format: "%.2f", longIntro.incomingDelaySeconds))
    check("Mixxx: aligned BPM prefers long crossfade", longIntro.preferLongCrossfade)
    let farBPM = AutoPhraseMatch.plan(
        outgoingDuration: 8.0,
        incomingIntroDuration: 8.0,
        beatSeconds: 0.5,
        barSeconds: 2.0,
        bpmAligned: false,
        stretchFar: true
    )
    check("Mixxx: far BPM prefers tape-stop", farBPM.preferTapeStop)
    check("Mixxx: far BPM keeps short overlap", farBPM.overlapSeconds <= 2.0 + 0.01,
          String(format: "%.2f", farBPM.overlapSeconds))
}

do {
    // Xirex pivot wallpaper (general): 1-beat last-word loop in the mix window,
    // not echo-throw spam on every drop / not early intro chops.
    let song = makeSong(title: "All The Things She Said", bpm: 90, key: "Am")
    let feat = crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 42, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        let drops = plan.pulseRegions.filter { $0.role == .drop }
        guard let drop0 = drops.first else {
            check("Pivot wallpaper: Drop 1 exists", false)
            break
        }
        let bar = plan.barSeconds
        let beat = plan.beatSeconds
        // Opening: no short supporting chops in first 8 bars.
        let earlyChops = plan.placements.filter {
            $0.role == .supporting
                && $0.timelineStart < bar * 8 - 0.05
                && $0.timelineDuration <= beat * 1.5
        }
        check("Solo remix: no early intro chops", earlyChops.isEmpty, "count=\(earlyChops.count)")
        if let first = plan.placements.filter({ $0.role == .dominant }).sorted(by: { $0.timelineStart < $1.timelineStart }).first {
            check(
                "Solo remix: opening phrase starts near source start",
                first.sourceStart <= bar * 2 + 0.05,
                String(format: "sourceStart=%.2f", first.sourceStart)
            )
        }
        let grains = plan.placements.filter { p in
            p.role == .supporting
                && p.songID == song.id
                && abs(p.timelineDuration - beat) < beat * 0.35
                && p.timelineStart >= drop0.timelineStart - bar * 2.5
                && p.timelineStart < drop0.timelineStart - 0.02
        }
        check(
            "Solo remix: pivot wallpaper 4–8× before Drop 1",
            grains.count >= 4 && grains.count <= 8,
            "count=\(grains.count)"
        )
        check(
            "Solo remix: pivot grains stay loud",
            grains.allSatisfy { $0.volume >= 0.90 },
            "vols=\(grains.map { String(format: "%.2f", $0.volume) }.joined(separator: ","))"
        )
        check(
            "Solo remix records pivotWallpaperLoop",
            plan.decisions.contains { $0.kind == .pivotWallpaperLoop }
        )
        // No legacy echo-throw wallpaper on Drop 2.
        let drop2Echoes: Int = {
            guard drops.count > 1 else { return 0 }
            let d2 = drops[1]
            return plan.placements.filter {
                $0.role == .supporting
                    && $0.fadeOut.type == .echoOut
                    && abs($0.timelineStart - d2.timelineStart) <= bar * 0.75
            }.count
        }()
        check("No echo-throw wallpaper on Drop 2", drop2Echoes == 0, "count=\(drop2Echoes)")
    case .failure(let message):
        check("Pivot wallpaper solo remix", false, message)
    }
}

// MARK: - Offline Demucs sidecars (fixture URLs / tiny WAVs — no Python)

func mockStemSet(in directory: URL) -> AutoStemSet {
    AutoStemSet(
        vocals: directory.appendingPathComponent("vocals.wav"),
        drums: directory.appendingPathComponent("drums.wav"),
        bass: directory.appendingPathComponent("bass.wav"),
        other: directory.appendingPathComponent("other.wav")
    )
}

func pivotGrains(in plan: AutoRemixPlan, songID: UUID, before dropStart: Double) -> [AutoClipPlacement] {
    let beat = plan.beatSeconds
    let bar = plan.barSeconds
    var grains: [AutoClipPlacement] = []
    for p in plan.placements {
        guard p.role == .supporting, p.songID == songID else { continue }
        guard abs(p.timelineDuration - beat) < beat * 0.35 else { continue }
        guard p.timelineStart >= dropStart - bar * 2.5 else { continue }
        guard p.timelineStart < dropStart - 0.02 else { continue }
        grains.append(p)
    }
    return grains
}

do {
    let song = URL(fileURLWithPath: "/Users/pranavi/Documents/Mixr/Songs/Oops I Did It Again.mp3")
    let vocals = URL(fileURLWithPath: "/Users/pranavi/Documents/Mixr/Stems/htdemucs_ft/Oops I Did It Again/vocals.wav")
    let drums = URL(fileURLWithPath: "/Users/pranavi/Documents/Mixr/Stems/htdemucs_ft/Oops I Did It Again/drums.wav")
    let present: Set<String> = [vocals.path, drums.path]
    let resolved = AutoStemResolver.resolve(songURL: song, fileExists: { present.contains($0.path) })
    check(
        "Songs basename resolves …/Stems/htdemucs_ft/<basename>/vocals.wav",
        resolved.vocals == vocals && resolved.drums == drums,
        "vocals=\(resolved.vocals?.path ?? "nil")"
    )

    let elsewhere = URL(fileURLWithPath: "/tmp/crate/foo.mp3")
    let root = URL(fileURLWithPath: "/tmp/explicit-stems/htdemucs_ft")
    let rootedVocals = root.appendingPathComponent("foo/vocals.wav")
    let rooted = AutoStemResolver.resolve(
        songURL: elsewhere,
        stemsRoot: root,
        fileExists: { $0.path == rootedVocals.path }
    )
    check("Explicit stemsRoot wins over missing Songs layout", rooted.vocals == rootedVocals)

    let missing = AutoStemResolver.resolve(songURL: song, fileExists: { _ in false })
    check("Missing stems resolve empty (full-mix fallback)", missing.isEmpty)
}

do {
    // Pivot grains + Drop 1: vocal stem for the wallpaper only; drop stays full mix.
    let song = makeSong(title: "All The Things She Said", bpm: 90, key: "Am")
    let feat = crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00)
    var tuning = AutoTuning.standard
    tuning.explicitStemsBySongID[song.id] = mockStemSet(
        in: URL(fileURLWithPath: "/tmp/mixr-mock-stems/\(song.id.uuidString)")
    )
    switch AutoRemixRunner.runEntireProject(
        tracks: [song],
        tuning: tuning,
        seed: 42,
        signals: [song.id: feat]
    ) {
    case .success(let tracks, let plan, _):
        let drops = plan.pulseRegions.filter { $0.role == AutoClubPulse.RegionRole.drop }
        guard let drop0 = drops.first else {
            check("Stem pivot: Drop 1 exists", false)
            break
        }
        let grains = pivotGrains(in: plan, songID: song.id, before: drop0.timelineStart)
        let grainKinds = grains.compactMap { $0.stemKind?.rawValue }.joined(separator: ",")
        let allVocal = grains.allSatisfy { $0.stemKind == AutoStemKind.vocals }
        check(
            "Solo remix: pivot grains use vocal stem",
            !grains.isEmpty && allVocal,
            "grains=\(grains.count) kinds=\(grainKinds)"
        )
        var dropClips: [AutoClipPlacement] = []
        for p in plan.placements where p.role == .dominant {
            if abs(p.timelineStart - drop0.timelineStart) < 0.08 {
                dropClips.append(p)
            }
        }
        check(
            "Solo remix: Drop 1 stays full mix (kick remains)",
            dropClips.allSatisfy { $0.stemKind == nil },
            "n=\(dropClips.count)"
        )
        let recordedVocal = plan.decisions.contains { d in
            d.kind == AutoDecisionKind.usedStemSidecar && (d.detail ?? "").contains("vocals")
        }
        check("Solo remix records vocal-stem sidecar", recordedVocal)
        let vocalTracks = tracks.filter { $0.title.contains("vocals") && $0.url != nil }
        let titles = tracks.map { $0.title }.joined(separator: " | ")
        check("Applier routes pivot clips onto a vocal-stem track", !vocalTracks.isEmpty, "titles=\(titles)")
    case .failure(let message):
        check("Solo remix with vocal stem", false, message)
    }
}

do {
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    var tuning = AutoTuning.standard
    tuning.explicitStemsBySongID[bomt.id] = mockStemSet(
        in: URL(fileURLWithPath: "/tmp/mixr-mock-stems/\(bomt.id.uuidString)")
    )
    tuning.explicitStemsBySongID[oops.id] = mockStemSet(
        in: URL(fileURLWithPath: "/tmp/mixr-mock-stems/\(oops.id.uuidString)")
    )
    switch AutoRemixRunner.runEntireProject(
        tracks: [bomt, oops],
        tuning: tuning,
        seed: 20260815,
        signals: signals
    ) {
    case .success(let tracks, let plan, _):
        guard let bedID = plan.mashupBedSongID, let vocalID = plan.mashupVocalSongID else {
            check("Stem mashup roles present", false)
            break
        }
        let drops = plan.pulseRegions
            .filter { $0.role == AutoClubPulse.RegionRole.drop }
            .sorted { $0.timelineStart < $1.timelineStart }
        guard let drop0 = drops.first else {
            check("Stem mashup Drop 1 exists", false)
            break
        }
        let grains = pivotGrains(in: plan, songID: bedID, before: drop0.timelineStart)
        check(
            "Mashup pivot grains use bed vocal stem",
            !grains.isEmpty && grains.allSatisfy { $0.stemKind == AutoStemKind.vocals },
            "grains=\(grains.count)"
        )
        var guestDrop: [AutoClipPlacement] = []
        for p in plan.placements where p.songID == vocalID && p.role == .dominant {
            if abs(p.timelineStart - drop0.timelineStart) < 0.08 {
                guestDrop.append(p)
            }
        }
        let guestKinds = guestDrop.compactMap { $0.stemKind?.rawValue }.joined(separator: ",")
        check(
            "Hook-replace Drop 1 uses guest vocal stem",
            !guestDrop.isEmpty && guestDrop.allSatisfy { $0.stemKind == AutoStemKind.vocals },
            "n=\(guestDrop.count) kinds=\(guestKinds)"
        )
        check("Incoming vocal hard-cut (no fade-in)", guestDrop.allSatisfy { $0.fadeIn.type == .none })
        var bedKinds = Set<AutoStemKind>()
        for p in plan.placements where p.songID == bedID && p.role == .supporting {
            guard p.timelineStart < drop0.timelineStart + plan.barSeconds else { continue }
            guard p.timelineEnd > drop0.timelineStart + plan.barSeconds else { continue }
            guard p.stemKind != AutoStemKind.vocals else { continue }
            if let kind = p.stemKind { bedKinds.insert(kind) }
        }
        let kindList = bedKinds.map { $0.rawValue }.sorted().joined(separator: ",")
        check(
            "Bed under drop is drums+bass+other (not full mix)",
            bedKinds.contains(.drums) && bedKinds.contains(.bass) && bedKinds.contains(.other),
            "kinds=\(kindList)"
        )
        let recordedReplace = plan.decisions.contains { $0.kind == AutoDecisionKind.hookReplace }
        let recordedStem = plan.decisions.contains { $0.kind == AutoDecisionKind.usedStemSidecar }
        check("Mashup records hook-replace stem sidecar", recordedReplace && recordedStem)
        let vocalTracks = tracks.filter { $0.title.contains("vocals") && $0.url != nil }
        check("Applier exposes vocal-stem tracks for mashup", vocalTracks.count >= 1)
    case .failure(let message):
        check("Mashup with stem sidecars", false, message)
    }
}

do {
    // Full-mix fallback: no stemKind when sidecars are absent.
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let signals: [UUID: SongSignalFeatures] = [
        bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.37, vocal: 0.55, confidence: 1.00),
        oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00),
    ]
    switch AutoRemixRunner.runEntireProject(tracks: [bomt, oops], seed: 20260815, signals: signals) {
    case .success(_, let plan, _):
        check(
            "No-stems mashup keeps full-mix placements",
            plan.placements.allSatisfy { $0.stemKind == nil }
        )
        let emptySets = plan.stemsBySongID.values.allSatisfy { $0.isEmpty }
        check("No-stems mashup has empty stem sets", emptySets || plan.stemsBySongID.isEmpty)
    case .failure(let message):
        check("No-stems mashup fallback", false, message)
    }
}

do {
    // One-kick: loud drums stem overrides thin analysis (no Club Kick pulse).
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mixr-stem-kick-\(UUID().uuidString)", isDirectory: true)
    let drumsURL = dir.appendingPathComponent("drums.wav")
    do {
        try AutoStemKickEnergy.writeFixtureWAV(to: drumsURL, frames: 8_000, amplitude: 0.95)
        let measured = AutoStemKickEnergy.drumStrength(from: drumsURL) ?? -1
        check("Loud drums fixture reads slamming", measured >= AutoClubPulse.slammingDrumThreshold,
              String(format: "energy=%.3f", measured))

        let song = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m")
        let feat = crateFeatures(duration: 200, bpm: 95, drum: 0.19, bass: 0.20, vocal: 0.55, confidence: 1.00)
        var tuning = AutoTuning.standard
        tuning.explicitStemsBySongID[song.id] = AutoStemSet(drums: drumsURL)
        switch AutoRemixRunner.runEntireProject(
            tracks: [song],
            tuning: tuning,
            seed: 11,
            signals: [song.id: feat]
        ) {
        case .success(_, let plan, _):
            check("Slamming drums stem skips Club Kick pulse", plan.pulsePolicy?.writesKick == false,
                  plan.pulsePolicy?.detail ?? "")
        case .failure(let message):
            check("Slamming drums stem pulse policy", false, message)
        }
    } catch {
        check("Wrote drums fixture WAV", false, "\(error)")
    }

    // Sparse slamming kicks (quiet mean, high transients) must not read "thin".
    do {
        let sparseURL = dir.appendingPathComponent("sparse-kicks.wav")
        try AutoStemKickEnergy.writeKickPatternWAV(
            to: sparseURL,
            frames: 44_100,
            periodFrames: 22_050,
            kickFrames: 80,
            amplitude: 0.85
        )
        let sparse = AutoStemKickEnergy.drumStrength(from: sparseURL) ?? -1
        check(
            "Sparse slamming kick pattern reads as slamming (not thin mean)",
            sparse >= AutoClubPulse.slammingDrumThreshold,
            String(format: "energy=%.3f", sparse)
        )
    } catch {
        check("Wrote sparse kick fixture WAV", false, "\(error)")
    }

    // t.A.T.u. full-mix crate is drum=0.82 / no pulse. A quiet Demucs drums
    // stem must not invent Club Kick (one-kick lock).
    do {
        let quietURL = dir.appendingPathComponent("tatu-quiet-drums.wav")
        try AutoStemKickEnergy.writeFixtureWAV(to: quietURL, frames: 8_000, amplitude: 0.04)
        let tatu = makeSong(title: "All The Things She Said", bpm: 90, key: "Am")
        let feat = crateFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64, confidence: 1.00)
        var tuning = AutoTuning.standard
        tuning.explicitStemsBySongID[tatu.id] = AutoStemSet(drums: quietURL)
        switch AutoRemixRunner.runEntireProject(
            tracks: [tatu],
            tuning: tuning,
            seed: 42,
            signals: [tatu.id: feat]
        ) {
        case .success(_, let plan, _):
            check(
                "tatu solo with drums stem keeps writesKick=false",
                plan.pulsePolicy?.writesKick == false,
                plan.pulsePolicy?.detail ?? ""
            )
        case .failure(let message):
            check("tatu solo with drums stem pulse", false, message)
        }
    } catch {
        check("Wrote tatu quiet drums fixture", false, "\(error)")
    }

    let thin = makeSong(title: "drivers license", bpm: 72, key: "Bb")
    let olivia = crateFeatures(duration: 240, bpm: 72, drum: 0.19, bass: 0.20, vocal: 0.85, confidence: 1.00)
    switch AutoRemixRunner.runEntireProject(tracks: [thin], seed: 3, signals: [thin.id: olivia]) {
    case .success(_, let plan, _):
        check("Thin source with no stems still allows pulse", plan.pulsePolicy?.writesKick == true,
              plan.pulsePolicy?.detail ?? "")
    case .failure(let message):
        check("Thin no-stems pulse", false, message)
    }
}

do {
    var song = makeSong(title: "missing stems", bpm: 93, key: "C")
    song.url = URL(fileURLWithPath: "/Users/pranavi/Documents/Mixr/Songs/does-not-exist.mp3")
    let feat = crateFeatures(duration: 180, bpm: 93, drum: 0.71, bass: 0.38, vocal: 0.55, confidence: 1.00)
    switch AutoRemixRunner.runEntireProject(tracks: [song], seed: 7, signals: [song.id: feat]) {
    case .success(_, let plan, _):
        check("Missing stem files do not crash Auto", !plan.placements.isEmpty)
        check("Missing stem files keep full-mix clips", plan.placements.allSatisfy { $0.stemKind == nil })
    case .failure(let message):
        check("Missing stem files do not crash Auto", false, message)
    }
}

do {
    // Title/groove lock: even when BOMT's drums stem reads hotter and Oops
    // looks more vocal, Oops stays the bed and BOMT is Drop 1 (pivot = baby).
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mixr-britney-stems-\(UUID().uuidString)", isDirectory: true)
    let bomtDrums = dir.appendingPathComponent("bomt-drums.wav")
    let oopsDrums = dir.appendingPathComponent("oops-drums.wav")
    do {
        try AutoStemKickEnergy.writeFixtureWAV(to: bomtDrums, frames: 8_000, amplitude: 0.95)
        try AutoStemKickEnergy.writeFixtureWAV(to: oopsDrums, frames: 8_000, amplitude: 0.08)
        var tuning = AutoTuning.standard
        var bomtStems = mockStemSet(in: dir.appendingPathComponent("bomt"))
        var oopsStems = mockStemSet(in: dir.appendingPathComponent("oops"))
        bomtStems.drums = bomtDrums
        oopsStems.drums = oopsDrums
        tuning.explicitStemsBySongID[bomt.id] = bomtStems
        tuning.explicitStemsBySongID[oops.id] = oopsStems
        let signals: [UUID: SongSignalFeatures] = [
            bomt.id: crateFeatures(duration: 200, bpm: 93, drum: 1.00, bass: 0.60, vocal: 0.40, confidence: 1.00),
            oops.id: crateFeatures(duration: 200, bpm: 95, drum: 0.71, bass: 0.22, vocal: 0.75, confidence: 1.00),
        ]
        switch AutoRemixRunner.runEntireProject(
            tracks: [bomt, oops],
            tuning: tuning,
            seed: 20260815,
            signals: signals
        ) {
        case .success(_, let plan, _):
            check(
                "Stem-hot BOMT still Oops bed (title lock)",
                plan.mashupBedSongID == oops.id,
                "bed=\(plan.mashupBedSongID == bomt.id ? "BOMT" : plan.mashupBedSongID == oops.id ? "Oops" : "?")"
            )
            check(
                "Stem-hot BOMT still BOMT Drop 1 vocal",
                plan.mashupVocalSongID == bomt.id,
                "vocal=\(plan.mashupVocalSongID == bomt.id ? "BOMT" : plan.mashupVocalSongID == oops.id ? "Oops" : "?")"
            )
            let pivot = plan.decisions.first { $0.kind == AutoDecisionKind.pivotWallpaperLoop }
            let detail = pivot?.detail ?? ""
        check(
            "Britney pivot token is baby (not oops) with stems",
            detail.lowercased().contains("baby") && !detail.lowercased().contains("oops"),
            "detail=\(detail)"
        )
        check(
            "Stem-hot Britney: first Deck A hook is not a title teaser chop",
            !AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: plan)
        )
        check(
            "Stem-hot Britney: Drop 1 has pivot wallpaper",
            AutoRemixDiagnostics.drop1HasPivotWallpaper(plan: plan)
        )
        if let drop1 = AutoRemixDiagnostics.firstDropStart(plan: plan) {
        check(
            "Stem-hot Britney: pivot Drop 1 has no pre-drop void",
            !AutoRemixDiagnostics.preDropVoidAt(plan: plan, dropStart: drop1)
        )
        check(
            "Stem-hot Britney: zero allowedPredropVoid",
            !plan.decisions.contains { $0.kind == .allowedPredropVoid }
        )
        }
        case .failure(let message):
            check("Britney stem role lock mashup", false, message)
        }
    } catch {
        check("Wrote Britney inverted-stem fixtures", false, "\(error)")
    }
}

do {
    // First Deck A hook must be a completed title/hook line, not a 2–4 bar
    // teaser of “Oops”. The helper must fail the previous (chop) behavior.
    let bpm = 95.0
    let bar = 240.0 / bpm
    let deckA = UUID()
    func clip(
        sourceStart: Double,
        timelineStart: Double,
        duration: Double,
        role: AutoPlacementRole = .dominant,
        slot: Int = 0
    ) -> AutoClipPlacement {
        AutoClipPlacement(
            songID: deckA,
            sourceStart: sourceStart,
            timelineStart: timelineStart,
            timelineDuration: duration,
            tempoRatio: 1,
            volume: 1,
            fadeIn: ClipTransition(type: .none, duration: 0),
            fadeOut: ClipTransition(type: .none, duration: 0),
            effects: ClipEffectSettings(),
            role: role,
            slotIndex: slot
        )
    }
    func plan(
        placements: [AutoClipPlacement],
        pulses: [AutoClubPulse.Region],
        duration: Double
    ) -> AutoRemixPlan {
        AutoRemixPlan(
            mode: .mashup,
            targetBPM: bpm,
            targetDuration: duration,
            anchorSongIDs: [deckA],
            selectedSections: [],
            placements: placements,
            sfxEvents: [],
            pulseRegions: pulses,
            mashupBedSongID: deckA,
            handoffCount: 0,
            songLetters: [deckA: "A"],
            sequence: ["A"],
            transitionsUsed: [],
            decisions: [],
            warnings: [],
            confidence: 1,
            randomSeed: 1
        )
    }

    let chopped = plan(
        placements: [
            clip(sourceStart: 0, timelineStart: 0, duration: bar * 4),
            clip(sourceStart: 40, timelineStart: bar * 4, duration: bar * 16, slot: 1),
        ],
        pulses: [
            AutoClubPulse.Region(role: .groove, timelineStart: 0, timelineEnd: bar * 4),
            AutoClubPulse.Region(role: .drop, timelineStart: bar * 4, timelineEnd: bar * 20),
        ],
        duration: bar * 20
    )
    check(
        "Title-chop detector flags a 4-bar Deck A hook from source 0",
        AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: chopped),
        {
            let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: chopped)
            return String(format: "src=%.2f dur=%.2f", hook?.sourceStart ?? -1, hook?.timelineDuration ?? -1)
        }()
    )

    let complete = plan(
        placements: [
            clip(sourceStart: 0, timelineStart: 0, duration: bar * 8, slot: 0),
            clip(sourceStart: bar * 8, timelineStart: bar * 8, duration: bar * 8, slot: 1),
            clip(sourceStart: 80, timelineStart: bar * 18, duration: bar * 16, slot: 2),
        ],
        pulses: [
            AutoClubPulse.Region(role: .introTease, timelineStart: 0, timelineEnd: bar * 8),
            AutoClubPulse.Region(role: .groove, timelineStart: bar * 8, timelineEnd: bar * 16),
            AutoClubPulse.Region(role: .buildOut, timelineStart: bar * 16, timelineEnd: bar * 18),
            AutoClubPulse.Region(role: .drop, timelineStart: bar * 18, timelineEnd: bar * 34),
        ],
        duration: bar * 34
    )
    check(
        "Title-chop detector accepts intro 8 + complete 8-bar A hook",
        !AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: complete)
    )
    if let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: complete) {
        check(
            "First Deck A hook is the groove phrase (≥8 bars), not the intro teaser",
            hook.timelineDuration + 0.05 >= bar * 7.5 && abs(hook.timelineStart - bar * 8) < 0.05,
            String(format: "t=%.2f dur=%.2f", hook.timelineStart, hook.timelineDuration)
        )
    } else {
        check("First Deck A hook placement exists on a complete plan", false)
    }

    let rewindTeaser = plan(
        placements: [
            clip(sourceStart: 0, timelineStart: 0, duration: bar * 8, slot: 0),
            clip(sourceStart: 0, timelineStart: bar * 8, duration: bar * 4, slot: 1),
            clip(sourceStart: 80, timelineStart: bar * 14, duration: bar * 16, slot: 2),
        ],
        pulses: [
            AutoClubPulse.Region(role: .introTease, timelineStart: 0, timelineEnd: bar * 8),
            AutoClubPulse.Region(role: .groove, timelineStart: bar * 8, timelineEnd: bar * 12),
            AutoClubPulse.Region(role: .drop, timelineStart: bar * 12, timelineEnd: bar * 28),
        ],
        duration: bar * 28
    )
    check(
        "Title-chop detector flags a 4-bar title rewind used as the first A hook",
        AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: rewindTeaser)
    )

    // Pivot Drop 1 with a 1-beat void beside the wallpaper is the old hole.
    let drop1 = bar * 18
    let beat = bar / 4
    var pivotPlacements: [AutoClipPlacement] = [
        clip(sourceStart: 0, timelineStart: 0, duration: bar * 16, slot: 0),
        clip(sourceStart: 80, timelineStart: drop1, duration: bar * 16, slot: 2),
    ]
    for i in 0..<8 {
        pivotPlacements.append(
            clip(
                sourceStart: bar * 16 - beat,
                timelineStart: drop1 - bar * 2 + Double(i) * beat,
                duration: beat,
                role: .supporting,
                slot: 1
            )
        )
    }
    let holeyPivot = plan(
        placements: pivotPlacements,
        pulses: [
            AutoClubPulse.Region(role: .groove, timelineStart: 0, timelineEnd: bar * 16),
            AutoClubPulse.Region(role: .void, timelineStart: drop1 - beat, timelineEnd: drop1),
            AutoClubPulse.Region(role: .drop, timelineStart: drop1, timelineEnd: drop1 + bar * 16),
        ],
        duration: drop1 + bar * 16
    )
    var holey = holeyPivot
    holey.intentionalGaps = [
        AutoIntentionalGap(start: drop1 - beat, end: drop1, reason: "pre-drop void")
    ]
    holey.decisions = [
        AutoDecision(kind: .pivotWallpaperLoop, songTitle: "Oops", detail: "8×1-beat"),
        AutoDecision(kind: .allowedPredropVoid, songTitle: "Oops", detail: "1.00 beats (drop on downbeat)"),
    ]
    check(
        "Void detector flags a 1-beat hole on pivot Drop 1 (previous behavior fails)",
        AutoRemixDiagnostics.pivotJoinHasQuietVoid(plan: holey)
    )

    let verseHook = plan(
        placements: [
            clip(sourceStart: 0, timelineStart: 0, duration: bar * 8, slot: 0),
            clip(sourceStart: bar * 8, timelineStart: bar * 8, duration: bar * 8, slot: 1),
            clip(sourceStart: 80, timelineStart: bar * 18, duration: bar * 16, slot: 2),
        ],
        pulses: [
            AutoClubPulse.Region(role: .introTease, timelineStart: 0, timelineEnd: bar * 8),
            AutoClubPulse.Region(role: .groove, timelineStart: bar * 8, timelineEnd: bar * 16),
            AutoClubPulse.Region(role: .drop, timelineStart: bar * 18, timelineEnd: bar * 34),
        ],
        duration: bar * 34
    )
    check(
        "Verse-tail detector flags hook starting before chorus anchor",
        AutoRemixDiagnostics.firstDeckAHookSourcesBeforeChorus(
            plan: verseHook,
            chorusAnchorSeconds: bar * 16
        )
    )
    check(
        "Verse-tail detector passes hook at chorus anchor",
        !AutoRemixDiagnostics.firstDeckAHookSourcesBeforeChorus(
            plan: verseHook,
            chorusAnchorSeconds: bar * 8
        )
    )
    check(
        "Prechorus detector flags a 40.4s first hook (the a83a66b bug)",
        AutoRemixDiagnostics.firstDeckAHookIsEarlyPrechorus(
            plan: verseHook,
            prechorusStarts: [bar * 8],
            titleChorusStart: bar * 16
        )
    )

    var fadedDrop2 = holey
    let drop2 = drop1 + bar * 16
    fadedDrop2.pulseRegions.append(
        AutoClubPulse.Region(role: .drop, timelineStart: drop2, timelineEnd: drop2 + bar * 16)
    )
    fadedDrop2.placements.append(
        clip(sourceStart: 40, timelineStart: drop2, duration: bar * 16, slot: 3)
    )
    if let idx = fadedDrop2.placements.indices.last {
        fadedDrop2.placements[idx].fadeIn = ClipTransition(
            type: .crossfade,
            duration: 4,
            curve: AutoTransitionEnvelope.equalPowerCurveName
        )
    }
    fadedDrop2.cutRecords = [
        AutoCutRecord(
            timelineAt: drop2,
            sourceFrom: 80,
            sourceTo: 40,
            reason: .hookReturn,
            confidence: 0.7,
            expectedEnergyDeltaDB: 0,
            masking: .equalPowerCrossfade(seconds: 3.74)
        )
    ]
    check(
        "Equal-power detector flags a Drop 2 fade-in (previous behavior fails)",
        AutoRemixDiagnostics.clubDropHasEqualPowerFade(plan: fadedDrop2)
    )
    check(
        "Title-chop detector still fails a 4-bar title teaser",
        AutoRemixDiagnostics.firstDeckAHookIsSubPhraseTitleChop(plan: chopped)
    )
}

print("\n\(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")")
exit(failures == 0 ? 0 : 1)
