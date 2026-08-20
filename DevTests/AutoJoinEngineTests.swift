import Foundation

// Direct unit tests on AutoJoinEngine — faster red/green than full mashup plans.

var failures = 0

func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { print("PASS  \(name)") }
    else { print("FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")"); failures += 1 }
}

func makeFeatures(
    duration: Double,
    bpm: Double,
    drumConfidence: Double = 0.9,
    bassLevel: Double = 0.5,
    vocalLevel: Double = 0.6,
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

let barSec = 240.0 / 95.0
let beatSec = barSec / 4
let lateLyric = 50.38
let downbeats = [37.9, 40.4, 45.5, 48.0, 50.5, 53.1, 55.6, 58.1, 60.6]

// MARK: - Title-hook mix-time pad

do {
    let lifted = AutoJoinEngine.titleHookClipStart(
        lyric: lateLyric,
        downbeats: downbeats,
        barSeconds: barSec,
        title: "Oops I Did It Again",
        lyricWords: [(lateLyric, "oops"), (lateLyric + 0.2, "I")],
        tempoRatio: 1.35
    )
    let mixLead = AutoJoinEngine.mixTimeTitleLead(
        lyric: lateLyric, clipStart: lifted, tempoRatio: 1.35
    )
    check(
        "Join: club-lift title pad puts token after stretch settle",
        mixLead >= 1.60 && mixLead <= 1.80 && lifted < lateLyric - 0.05,
        String(format: "onset=%.2f mixLead=%.2f", lifted, mixLead)
    )
    let native = AutoJoinEngine.titleHookClipStart(
        lyric: lateLyric,
        downbeats: downbeats,
        barSeconds: barSec,
        leadIn: .twoBeats,
        tempoRatio: 1.0
    )
    check(
        "Join: native tempo keeps 2-beat source pad",
        abs((lateLyric - native) - 2 * beatSec) < beatSec * 0.5,
        String(format: "onset=%.2f lead=%.2f", native, lateLyric - native)
    )
    let filled = AutoJoinEngine.titleHookClipStart(
        lyric: lateLyric,
        downbeats: downbeats,
        barSeconds: barSec,
        title: "Oops I Did It Again",
        lyricWords: [
            (49.06, "baby"), (50.08, "back"), (lateLyric, "oops"), (lateLyric + 0.2, "I")
        ],
        tempoRatio: 1.35
    )
    check(
        "Join: club-lift pad does not pull a previous lyric ahead of the distinctive token",
        filled > 50.08 && filled < lateLyric && (lateLyric - filled) <= 0.28,
        String(format: "start=%.2f oops=%.2f", filled, lateLyric)
    )
}

// MARK: - Distinctive token vs phrase-start filler

do {
    let emptyVocal = [Double](repeating: 0.5, count: 32)
    let phrase = 39.84
    let wanted = 41.66
    let isolated = AutoChorusIsland.isolatedTitleTokenTime(
        lyric: phrase,
        title: "All I Wanted",
        words: [(phrase, "all"), (41.24, "I"), (wanted, "wanted"), (42.26, "was")],
        vocalPresence: emptyVocal,
        hop: 0.1
    )
    check(
        "Join: isolated token walks past generic phrase-start filler to distinctive",
        abs(isolated - wanted) < 0.08,
        String(format: "got=%.2f want=%.2f (phrase=%.2f)", isolated, wanted, phrase)
    )
    let oopsKept = AutoChorusIsland.isolatedTitleTokenTime(
        lyric: lateLyric,
        title: "Oops I Did It Again",
        words: [(51.18, "I"), (51.46, "did"), (52.44, "again")],
        vocalPresence: emptyVocal,
        hop: 0.1
    )
    check(
        "Join: missing attack word in lyrics does not walk to a later distinctive",
        abs(oopsKept - lateLyric) < 0.08,
        String(format: "got=%.2f want=%.2f", oopsKept, lateLyric)
    )
    var lateOnly = makeFeatures(duration: 214, bpm: 90)
    lateOnly.lyricTitleHookStart = 180.24
    lateOnly.lyricWords = [(180.24, "all"), (180.46, "things"), (180.8, "said")]
    let rejected = AutoChorusIsland.snapLyricTitleHook(
        signal: lateOnly,
        downbeats: [40, 48, 176, 180.2, 184],
        barSeconds: 240.0 / 90.0,
        title: "All The Things She Said"
    )
    check(
        "Join: title lyric in the last 30% of the song is not the opening hook",
        rejected == nil,
        String(format: "got=%@", rejected.map { String(format: "%.1f", $0) } ?? "nil")
    )
    var withEarly = lateOnly
    withEarly.lyricWords = [(48.1, "things"), (180.24, "all"), (180.46, "things")]
    let early = AutoChorusIsland.snapLyricTitleHook(
        signal: withEarly,
        downbeats: [40, 48, 176, 180.2, 184],
        barSeconds: 240.0 / 90.0,
        title: "All The Things She Said"
    )
    check(
        "Join: late sidecar still uses the first-half distinctive token when present",
        early != nil && (early ?? 0) < 55,
        String(format: "got=%@", early.map { String(format: "%.1f", $0) } ?? "nil")
    )
    var energyLate = makeFeatures(duration: 214, bpm: 90)
    energyLate.lyricTitleHookStart = 180.24
    energyLate.lyricWords = [(180.24, "all"), (180.46, "things")]
    // First-half vocal plateau so energy entrance can own the opening title.
    let hop = energyLate.hopSeconds
    let island = 57.5
    for i in energyLate.vocalPresenceCurve.indices {
        let t = Double(i) * hop
        if t >= island && t < island + 20 {
            energyLate.vocalPresenceCurve[i] = 0.85
            energyLate.energyCurve[i] = 0.8
        } else if t >= 8 && t < island {
            energyLate.vocalPresenceCurve[i] = 0.35
            energyLate.energyCurve[i] = 0.4
        }
    }
    let energyOnset = AutoChorusIsland.titleHookOnset(
        signal: energyLate,
        downbeats: stride(from: 0.0, through: 80, by: 240.0 / 90.0).map { $0 },
        barSeconds: 240.0 / 90.0,
        duration: 214,
        introEnd: 16,
        phraseSeconds: 240.0 / 90.0 * 8,
        title: "All The Things She Said"
    )
    check(
        "Join: rejected late lyric still lands the opening title island",
        energyOnset != nil && (energyOnset ?? 999) < 214 * 0.55,
        String(format: "got=%@", energyOnset.map { String(format: "%.1f", $0) } ?? "nil")
    )
    let liftedEnergy = AutoChorusIsland.titleHookOnset(
        signal: energyLate,
        downbeats: stride(from: 0.0, through: 80, by: 240.0 / 90.0).map { $0 },
        barSeconds: 240.0 / 90.0,
        duration: 214,
        introEnd: 16,
        phraseSeconds: 240.0 / 90.0 * 8,
        title: "All The Things She Said",
        tempoRatio: 1.40
    )
    if let native = energyOnset, let lifted = liftedEnergy {
        let mixLead = AutoJoinEngine.mixTimeTitleLead(
            lyric: native, clipStart: lifted, tempoRatio: 1.40
        )
        check(
            "Join: club-lift energy island pads so the title token is after stretch settle",
            mixLead >= 1.55 && mixLead <= 1.90 && lifted < native - 0.05,
            String(format: "native=%.2f lifted=%.2f mixLead=%.2f", native, lifted, mixLead)
        )
    } else {
        check("Join: club-lift energy island pads so the title token is after stretch settle", false, "missing onset")
    }
    let festivalBar = 240.0 / 144.0
    let clip = AutoJoinEngine.titleHookClipStart(
        lyric: wanted,
        downbeats: [38.17, 39.84, 41.5, 43.17],
        barSeconds: festivalBar,
        title: "All I Wanted",
        lyricWords: [(phrase, "all"), (41.24, "I"), (wanted, "wanted")],
        tempoRatio: 1.0
    )
    check(
        "Join: native pad starts on distinctive token, not the filler before it",
        clip > 41.24 && clip < wanted && (wanted - clip) <= 0.35,
        String(format: "start=%.2f wanted=%.2f", clip, wanted)
    )
}

// MARK: - Pivot pre-drop window

do {
    let dropStart = 45.71
    let loopStart = dropStart - barSec * 2
    var placements: [AutoClipPlacement] = [
        AutoClipPlacement(
            songID: UUID(),
            sourceStart: 48.0,
            timelineStart: 0,
            timelineDuration: loopStart,
            tempoRatio: 1.33,
            volume: 1.0,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 0
        )
    ]
    var pulse: [AutoClubPulse.Region] = [
        AutoClubPulse.Region(role: .drop, timelineStart: dropStart, timelineEnd: dropStart + 16)
    ]
    var gaps: [AutoIntentionalGap] = [
        AutoIntentionalGap(start: dropStart - beatSec, end: dropStart, reason: "pre-drop void")
    ]
    var decisions: [AutoDecision] = []
    var guestSignal = makeFeatures(duration: 200, bpm: 93)
    guestSignal.lyricWords = [(60.7, "baby"), (60.26, "hit")]
    AutoJoinEngine.appendPivotWallpaperLoop(
        completedPhrase: placements[0],
        dropTimelineStart: dropStart,
        deckATitle: "Oops I Did It Again",
        deckBTitle: "Baby One More Time",
        barSec: barSec,
        beatSec: beatSec,
        tuning: AutoTuning.standard,
        incomingSongID: UUID(),
        incomingHookStart: 60.26,
        incomingTempoRatio: 1.33,
        incomingSignal: guestSignal,
        incomingGrainStem: .vocals,
        placements: &placements,
        pulseRegions: &pulse,
        intentionalGaps: &gaps,
        decisions: &decisions
    )
    let grains = placements.filter {
        $0.role == .supporting && abs($0.timelineDuration - beatSec) < beatSec * 0.4
    }
    check("Join: pivot wallpaper emits grains", grains.count >= 4)
    if let g0 = grains.first {
        check(
            "Join: pivot window starts ~2 bars before Drop 1",
            abs(g0.timelineStart - loopStart) < beatSec * 0.6,
            String(format: "grain0=%.2f loop=%.2f", g0.timelineStart, loopStart)
        )
    }
    check(
        "Join: pre-drop void stripped on pivot join",
        !gaps.contains { $0.reason.localizedCaseInsensitiveContains("void") }
    )
}

// MARK: - Drop 1 isolation floor vs title

do {
    let bedID = UUID()
    let guestID = UUID()
    let dropStart = 45.0
    var placements: [AutoClipPlacement] = [
        AutoClipPlacement(
            songID: bedID,
            sourceStart: 48.59,
            timelineStart: 11.0,
            timelineDuration: barSec * 8,
            tempoRatio: 1.33,
            volume: 1.16,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 0,
            stemKind: .vocals
        ),
        AutoClipPlacement(
            songID: guestID,
            sourceStart: 60.05,
            timelineStart: dropStart,
            timelineDuration: barSec * 8,
            tempoRatio: 1.33,
            volume: 1.0,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 1,
            stemKind: .vocals
        )
    ]
    let pulse = [AutoClubPulse.Region(role: .drop, timelineStart: dropStart, timelineEnd: dropStart + 16)]
    var signal = makeFeatures(duration: 200, bpm: 95)
    signal.stemVocalRMSCurveDB = [Double](repeating: -22.0, count: signal.hopCount)
    signal.stemVocalPresenceCurve = [Double](repeating: 0.55, count: signal.hopCount)
    var guestSignal = makeFeatures(duration: 200, bpm: 93)
    guestSignal.stemVocalRMSCurveDB = [Double](repeating: -28.0, count: guestSignal.hopCount)
    guestSignal.stemVocalPresenceCurve = [Double](repeating: 0.5, count: guestSignal.hopCount)
    let bedTrack = MixrTrack(
        id: bedID, title: "Bed", artist: "Fixture", duration: "3:00",
        durationSeconds: 200, bpm: 95, key: "Cm", color: .blue,
        volume: 1, isMuted: false, clips: []
    )
    let guestTrack = MixrTrack(
        id: guestID, title: "Guest", artist: "Fixture", duration: "3:00",
        durationSeconds: 200, bpm: 93, key: "Cm", color: .pink,
        volume: 1, isMuted: false, clips: []
    )
    let bedProfile = AutoSectionCatalog.profile(track: bedTrack, signal: signal)
    let guestProfile = AutoSectionCatalog.profile(track: guestTrack, signal: guestSignal)
    AutoJoinEngine.boostJoinClipVolumes(
        placements: &placements,
        pulseRegions: pulse,
        beatSec: beatSec,
        barSec: barSec,
        profiles: [bedID: bedProfile, guestID: guestProfile]
    )
    let titleVol = placements.first { $0.songID == bedID && $0.stemKind == .vocals }?.volume ?? 0
    let dropVol = placements.first { $0.songID == guestID && abs($0.timelineStart - dropStart) < 0.1 }?.volume ?? 0
    let floor = titleVol * AutoGainPolicy.dropVsIsolatedTitleBoost
    check(
        "Join: Drop 1 vocal volume ≥ title × isolation boost",
        dropVol + 0.001 >= floor,
        String(format: "title=%.2f drop=%.2f floor=%.2f", titleVol, dropVol, floor)
    )
}

do {
    let bedID = UUID()
    let guestID = UUID()
    let dropStart = 45.0
    var placements: [AutoClipPlacement] = [
        AutoClipPlacement(
            songID: bedID,
            sourceStart: 51.64,
            timelineStart: 11.25,
            timelineDuration: barSec * 8,
            tempoRatio: 1.0,
            volume: 2.51,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 0,
            stemKind: .vocals
        ),
        AutoClipPlacement(
            songID: guestID,
            sourceStart: 60.05,
            timelineStart: dropStart,
            timelineDuration: barSec * 8,
            tempoRatio: 1.0,
            volume: 1.0,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 1,
            stemKind: .vocals
        )
    ]
    let pulse = [AutoClubPulse.Region(role: .drop, timelineStart: dropStart, timelineEnd: dropStart + 16)]
    var signal = makeFeatures(duration: 200, bpm: 128)
    signal.stemVocalRMSCurveDB = [Double](repeating: -18.0, count: signal.hopCount)
    var guestSignal = makeFeatures(duration: 200, bpm: 93)
    guestSignal.stemVocalRMSCurveDB = [Double](repeating: -22.0, count: guestSignal.hopCount)
    let bedTrack = MixrTrack(
        id: bedID, title: "Bed", artist: "Fixture", duration: "3:00",
        durationSeconds: 200, bpm: 128, key: "B", color: .purple,
        volume: 1, isMuted: false, clips: []
    )
    let guestTrack = MixrTrack(
        id: guestID, title: "Guest", artist: "Fixture", duration: "3:00",
        durationSeconds: 200, bpm: 93, key: "Cm", color: .pink,
        volume: 1, isMuted: false, clips: []
    )
    AutoJoinEngine.boostJoinClipVolumes(
        placements: &placements,
        pulseRegions: pulse,
        beatSec: beatSec,
        barSec: barSec,
        profiles: [
            bedID: AutoSectionCatalog.profile(track: bedTrack, signal: signal),
            guestID: AutoSectionCatalog.profile(track: guestTrack, signal: guestSignal)
        ]
    )
    let titleVol = placements.first { $0.songID == bedID && $0.stemKind == .vocals }?.volume ?? 0
    let dropVol = placements.first { $0.songID == guestID && abs($0.timelineStart - dropStart) < 0.1 }?.volume ?? 0
    let floor = titleVol * AutoGainPolicy.dropVsIsolatedTitleBoost
    check(
        "Join: hot title stem does not clamp Drop 1 below isolation boost",
        dropVol + 0.001 >= floor && dropVol <= AutoGainPolicy.maxClipVolume,
        String(format: "title=%.2f drop=%.2f floor=%.2f cap=%.2f", titleVol, dropVol, floor, AutoGainPolicy.maxClipVolume)
    )
}

do {
    let bedID = UUID()
    let guestID = UUID()
    let dropStart = 45.0
    var placements: [AutoClipPlacement] = [
        AutoClipPlacement(
            songID: bedID,
            sourceStart: 50.32,
            timelineStart: 11.4,
            timelineDuration: barSec * 8,
            tempoRatio: 1.33,
            volume: AutoGainPolicy.vocalStemMakeupDefault,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 0,
            stemKind: .vocals
        ),
        AutoClipPlacement(
            songID: bedID,
            sourceStart: 50.32,
            timelineStart: 11.4,
            timelineDuration: barSec * 8,
            tempoRatio: 1.33,
            volume: 0.62,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .supporting,
            slotIndex: 0,
            stemKind: .drums
        ),
        AutoClipPlacement(
            songID: guestID,
            sourceStart: 60.05,
            timelineStart: dropStart,
            timelineDuration: barSec * 16,
            tempoRatio: 1.35,
            volume: 1.0,
            fadeIn: .hardCut,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 1,
            stemKind: .vocals
        )
    ]
    let pulse = [AutoClubPulse.Region(role: .drop, timelineStart: dropStart, timelineEnd: dropStart + 16)]
    AutoJoinEngine.boostJoinClipVolumes(
        placements: &placements,
        pulseRegions: pulse,
        beatSec: beatSec,
        barSec: barSec,
        profiles: [:]
    )
    let drums = placements.first { $0.stemKind == .drums }?.volume ?? 99
    let title = placements.first { $0.stemKind == .vocals && $0.songID == bedID }?.volume ?? 0
    check(
        "Join: title-hook instrumental stems stay quieter than the isolated vocal",
        drums <= AutoGainPolicy.titleInstrumentalDuckVolume + 0.001
            && drums + 0.05 < title,
        String(format: "drums=%.2f title=%.2f cap=%.2f", drums, title, AutoGainPolicy.titleInstrumentalDuckVolume)
    )
}

do {
    let bedID = UUID()
    let guestID = UUID()
    let dropStart = 45.0
    let titleStart = 11.4
    var placements: [AutoClipPlacement] = [
        AutoClipPlacement(
            songID: bedID,
            sourceStart: 0,
            timelineStart: 0,
            timelineDuration: 15.4,
            tempoRatio: 1.33,
            volume: 0.9,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 0
        ),
        AutoClipPlacement(
            songID: bedID,
            sourceStart: 50.32,
            timelineStart: titleStart,
            timelineDuration: barSec * 8,
            tempoRatio: 1.33,
            volume: AutoGainPolicy.vocalStemMakeupDefault,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 1,
            stemKind: .vocals
        ),
        AutoClipPlacement(
            songID: guestID,
            sourceStart: 60.05,
            timelineStart: dropStart,
            timelineDuration: barSec * 16,
            tempoRatio: 1.35,
            volume: 1.0,
            fadeIn: .hardCut,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 2,
            stemKind: .vocals
        )
    ]
    let pulse = [AutoClubPulse.Region(role: .drop, timelineStart: dropStart, timelineEnd: dropStart + 16)]
    AutoJoinEngine.boostJoinClipVolumes(
        placements: &placements,
        pulseRegions: pulse,
        beatSec: beatSec,
        barSec: barSec,
        profiles: [:]
    )
    let introHead = placements.first {
        $0.songID == bedID && $0.stemKind == nil && $0.timelineStart < 1
    }
    // The intro may cross the title entrance ONLY as a short equal-power
    // fade tail (≤1.25 beats) — trimming flush left a near-silent hole
    // before the entrance. Anything longer is a duplicate full-mix bed.
    let introOverlap = placements.contains {
        $0.songID == bedID
            && $0.stemKind == nil
            && min($0.timelineEnd, titleStart + 4) - max($0.timelineStart, titleStart) > beatSec * 1.25
    }
    let introFades = introHead == nil
        || introHead?.timelineEnd ?? 99 <= titleStart + 0.02
        || introHead?.fadeOut.type == .crossfade
        || introHead?.fadeOut.type == .fadeOut
    check(
        "Join: intro full-mix does not keep playing under the title vocal",
        introHead != nil
            && (introHead?.timelineEnd ?? 99) <= titleStart + beatSec * 1.25 + 0.02
            && introFades
            && !introOverlap,
        String(format: "headEnd=%.2f overlap=%@ title=%.2f", introHead?.timelineEnd ?? -1, introOverlap ? "yes" : "no", titleStart)
    )
}

// MARK: - Opening fade

do {
    var placements: [AutoClipPlacement] = [
        AutoClipPlacement(
            songID: UUID(),
            sourceStart: 0,
            timelineStart: 0,
            timelineDuration: barSec * 8,
            tempoRatio: 1.0,
            volume: 1.0,
            fadeIn: .none,
            fadeOut: .none,
            effects: ClipEffectSettings(),
            role: .dominant,
            slotIndex: 0
        )
    ]
    var decisions: [AutoDecision] = []
    AutoJoinEngine.applyOpeningFadeIn(
        placements: &placements,
        beatSec: beatSec,
        decisions: &decisions
    )
    check(
        "Join: opening fade-in on first dominant clip",
        placements[0].fadeIn.type == .crossfade
            && placements[0].fadeIn.duration == AutoClubTempo.openingFadeInBeats,
        "fade=\(placements[0].fadeIn.type.rawValue) dur=\(placements[0].fadeIn.duration)"
    )
}

do {
    var prev = AutoClipPlacement(
        songID: UUID(),
        sourceStart: 0,
        timelineStart: 0,
        timelineDuration: 8,
        tempoRatio: 1,
        volume: 1,
        fadeIn: .none,
        fadeOut: .none,
        effects: ClipEffectSettings(),
        role: .dominant,
        slotIndex: 0
    )
    var next = AutoClipPlacement(
        songID: UUID(),
        sourceStart: 40,
        timelineStart: 8,
        timelineDuration: 16,
        tempoRatio: 1,
        volume: 1,
        fadeIn: .hardCut,
        fadeOut: .none,
        effects: ClipEffectSettings(),
        role: .dominant,
        slotIndex: 1
    )
    AutoJoinEngine.applyTakeoverJoin(prev: &prev, next: &next, beatSec: 0.5, beats: 4)
    check(
        "Join: takeover overlaps and incoming swells quiet → loud",
        next.fadeIn.type == .crossfade
            && next.fadeIn.duration == 4
            && prev.fadeOut.type == .crossfade
            && prev.timelineEnd >= next.timelineStart + 1.9
            && next.overlapsPreviousSeconds >= 1.9,
        String(format: "in=%@ dur=%.1f overlap=%.2f prevEnd=%.2f",
               next.fadeIn.type.rawValue, next.fadeIn.duration, next.overlapsPreviousSeconds, prev.timelineEnd)
    )
}

do {
    var prev = AutoClipPlacement(
        songID: UUID(),
        sourceStart: 0,
        timelineStart: 0,
        timelineDuration: 12,
        tempoRatio: 1,
        volume: 1,
        fadeIn: .none,
        fadeOut: .none,
        effects: ClipEffectSettings(),
        role: .dominant,
        slotIndex: 0
    )
    var next = AutoClipPlacement(
        songID: prev.songID,
        sourceStart: 50,
        timelineStart: 8,
        timelineDuration: 16,
        tempoRatio: 1,
        volume: 1,
        fadeIn: .hardCut,
        fadeOut: .none,
        effects: ClipEffectSettings(),
        role: .dominant,
        slotIndex: 1
    )
    AutoJoinEngine.applyYieldJoin(prev: &prev, next: &next, beats: 4)
    check(
        "Join: yield fades the outgoing; incoming title stays at full",
        prev.fadeOut.type == .crossfade
            && prev.fadeOut.duration == 4
            && next.fadeIn.type == .none
            && next.fadeIn.duration < 0.25
            && prev.timelineEnd <= next.timelineStart + 0.02,
        String(format: "out=%@ in=%@ prevEnd=%.2f nextStart=%.2f",
               prev.fadeOut.type.rawValue, next.fadeIn.type.rawValue, prev.timelineEnd, next.timelineStart)
    )
}

if failures > 0 {
    print("\nFAILED: \(failures)")
    exit(1)
}
print("\nALL PASSED")
