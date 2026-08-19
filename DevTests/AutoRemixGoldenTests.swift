import Foundation

// Perceptual golden tier: stem-shaped fixtures + rendered RMS windows for
// Oops×BOMT @126 and Paramore×tatu @144 patterns. Runs in cloud CI via:
//   Scripts/run_auto_remix_tests.sh golden
//
// Offline mixdown uses linear resample (not AVAudioUnitTimePitch overlap).
// Title-token timing gates use plan placement mixLead; RMS gates use rendered PCM.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

let SR = 44_100.0

func makeSong(
    title: String,
    bpm: Int?,
    key: String?,
    durationSeconds: Double = 200,
    color: MixrWaveformColor = .pink
) -> MixrTrack {
    let length = MixrTimeline.units(fromSeconds: min(durationSeconds, 180))
    return MixrTrack(
        id: UUID(), title: title, artist: "Fixture", duration: "--:--",
        durationSeconds: durationSeconds, bpm: bpm, key: key, color: color,
        volume: 1.0, isMuted: false, clips: [MixrClip(id: UUID(), start: 0, length: length)]
    )
}

func makeFeatures(
    duration: Double, bpm: Double, drum: Double, bass: Double, vocal: Double,
    confidence: Double = 1.0
) -> SongSignalFeatures {
    let hop = SongSignalAnalyzer.hopSeconds
    let hops = max(8, Int(duration / hop))
    return SongSignalFeatures(
        sampleRate: SR, durationSeconds: duration,
        rmsCurveDB: [Double](repeating: -12, count: hops),
        onsetStrength: [Double](repeating: 0.6, count: hops),
        hopSeconds: hop, downbeatOffsetSeconds: 0, beatConfidence: confidence,
        leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
        energyCurve: [Double](repeating: 0.7, count: hops),
        bassEnergyCurve: [Double](repeating: bass, count: hops),
        vocalPresenceCurve: [Double](repeating: vocal, count: hops),
        noveltyCurve: [Double](repeating: 0.3, count: hops),
        drumConfidence: drum, overallConfidence: confidence
    )
}

func popTitleChorusRealCrate(
    duration: Double, bpm: Double, drum: Double, bass: Double, vocal: Double,
    titleChorusStart: Double, chorusTailStart: Double, prechorusTwoStart: Double
) -> SongSignalFeatures {
    var feat = makeFeatures(duration: duration, bpm: bpm, drum: drum, bass: bass, vocal: vocal)
    let hop = feat.hopSeconds
    let bar = 240.0 / max(bpm, 40)
    for i in 0..<feat.energyCurve.count {
        let t = Double(i) * hop
        if t >= prechorusTwoStart - bar && t < prechorusTwoStart + bar * 2 {
            feat.energyCurve[i] = max(feat.energyCurve[i], 0.82)
            feat.vocalPresenceCurve[i] = max(feat.vocalPresenceCurve[i], vocal * 0.98)
        }
        if t >= titleChorusStart && t < titleChorusStart + bar * 8 {
            feat.energyCurve[i] = 0.94
            feat.vocalPresenceCurve[i] = min(1, vocal * 1.15)
        }
        if t >= chorusTailStart && t < chorusTailStart + bar * 4 {
            feat.energyCurve[i] = max(feat.energyCurve[i], 0.88)
        }
    }
    return feat
}

func popBOMTFeatures(
    duration: Double, bpm: Double, hitMeStart: Double
) -> SongSignalFeatures {
    var feat = makeFeatures(duration: duration, bpm: bpm, drum: 1.0, bass: 0.37, vocal: 0.55)
    let hop = feat.hopSeconds
    let bar = 240.0 / max(bpm, 40)
    for i in 0..<feat.energyCurve.count {
        let t = Double(i) * hop
        if t >= hitMeStart && t < hitMeStart + bar * 8 {
            feat.energyCurve[i] = 0.96
            feat.vocalPresenceCurve[i] = 0.85
        }
    }
    return feat
}

func writeLyricsJSON(
    to url: URL, title: String, titleHookStart: Double,
    words: [(Double, String)]
) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let wordJSON = words.map { "{\"t\":\(String(format: "%.2f", $0.0)),\"word\":\"\($0.1)\"}" }.joined(separator: ",")
    let json = """
    {"title":"\(title)","titleHookStart":\(String(format: "%.2f", titleHookStart)),"words":[\(wordJSON)]}
    """
    try json.data(using: .utf8)!.write(to: url)
}

func mockStemSet(in dir: URL) -> AutoStemSet {
    AutoStemSet(
        vocals: dir.appendingPathComponent("vocals.wav"),
        drums: dir.appendingPathComponent("drums.wav"),
        bass: dir.appendingPathComponent("bass.wav"),
        other: dir.appendingPathComponent("other.wav")
    )
}

/// Stem-shaped vocal envelope: louder at token times for perceptual gates.
func stemShapedSource(
    duration: Double, bpm: Double, tokenTimes: [Double], baseAmp: Float = 0.25
) -> [Float] {
    let n = Int(duration * SR)
    var samples = [Float](repeating: 0, count: n)
    let beat = 60.0 / max(bpm, 40)
    for i in 0..<n {
        let t = Double(i) / SR
        var amp = baseAmp
        for token in tokenTimes {
            let dt = abs(t - token)
            if dt < beat * 0.45 { amp = max(amp, baseAmp * 2.8) }
        }
        if t < 16 * beat { amp *= Float(t / (16 * beat)) } // opening fade region in source
        samples[i] = amp * Float(sin(2 * .pi * 440 * t))
    }
    return samples
}

// MARK: - Oops×BOMT @126

do {
    let oops = makeSong(title: "Oops I Did It Again", bpm: 95, key: "C#m", color: .blue)
    let bomt = makeSong(title: "Baby One More Time", bpm: 93, key: "Cm", color: .pink)
    let bedLyric = 50.38
    let dropLyric = 60.26
    let stemRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("mixr-golden-oops-\(UUID().uuidString)", isDirectory: true)
    let oopsLyrics = stemRoot.appendingPathComponent("Oops I Did It Again/lyrics.json")
    let bomtLyrics = stemRoot.appendingPathComponent("Baby One More Time/lyrics.json")
    do {
        try writeLyricsJSON(
            to: oopsLyrics, title: oops.title, titleHookStart: bedLyric,
            words: [(bedLyric, "oops"), (bedLyric + 0.2, "I"), (bedLyric + 0.5, "did")]
        )
        try writeLyricsJSON(
            to: bomtLyrics, title: bomt.title, titleHookStart: dropLyric,
            words: [(dropLyric, "hit"), (dropLyric + 0.24, "me"), (dropLyric + 0.44, "baby")]
        )
        var tuning = AutoTuning.standard
        var oopsStems = mockStemSet(in: oopsLyrics.deletingLastPathComponent())
        oopsStems.lyrics = oopsLyrics
        var bomtStems = mockStemSet(in: bomtLyrics.deletingLastPathComponent())
        bomtStems.lyrics = bomtLyrics
        tuning.explicitStemsBySongID[oops.id] = oopsStems
        tuning.explicitStemsBySongID[bomt.id] = bomtStems
        var signals: [UUID: SongSignalFeatures] = [
            oops.id: {
                var s = popTitleChorusRealCrate(
                    duration: 200, bpm: 95, drum: 0.71, bass: 0.38, vocal: 0.55,
                    titleChorusStart: 48.0, chorusTailStart: 50.5, prechorusTwoStart: 40.4
                )
                s.lyricTitleHookStart = bedLyric
                return s
            }(),
            bomt.id: {
                var s = popBOMTFeatures(duration: 200, bpm: 93, hitMeStart: 59.5)
                s.lyricTitleHookStart = dropLyric
                return s
            }(),
        ]
        switch AutoRemixRunner.runEntireProject(
            tracks: [bomt, oops], tuning: tuning, seed: 20260818, signals: signals
        ) {
        case .success(_, let plan, _):
            check(
                "Golden Oops×BOMT: club-lifts into house",
                AutoClubTempo.housePocketRange.contains(plan.targetBPM),
                "bpm=\(plan.targetBPM)"
            )
            guard let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan) else {
                check("Golden Oops×BOMT: title-hook exists", false); break
            }
            let mixLead = AutoJoinEngine.mixTimeTitleLead(
                lyric: bedLyric, clipStart: hook.sourceStart, tempoRatio: hook.tempoRatio
            )
            check(
                "Golden Oops×BOMT: title token mixLead after stretch settle",
                mixLead >= 1.60 && mixLead <= 1.80,
                String(format: "mixLead=%.2f ratio=%.2f", mixLead, hook.tempoRatio)
            )
            guard let drop1 = AutoRemixDiagnostics.firstDropStart(plan: plan) else {
                check("Golden Oops×BOMT: Drop 1 exists", false); break
            }
            let preDropStart = drop1 - plan.barSeconds * 2
            let grains = plan.placements.filter {
                $0.role == .supporting
                    && abs($0.timelineDuration - plan.beatSeconds) < plan.beatSeconds * 0.4
                    && $0.timelineStart >= preDropStart - 0.05
                    && $0.timelineStart < drop1
            }
            check("Golden Oops×BOMT: pivot grains fill pre-drop window", grains.count >= 4)

            let oopsTone = stemShapedSource(duration: 200, bpm: 95, tokenTimes: [bedLyric, 50.5])
            let bomtTone = stemShapedSource(duration: 200, bpm: 93, tokenTimes: [dropLyric, 60.7])
            let rendered = AutoOfflineMixdown.render(
                plan: plan,
                sources: [
                    oops.id: AutoOfflineMixdown.Source(samples: oopsTone, sampleRate: SR),
                    bomt.id: AutoOfflineMixdown.Source(samples: bomtTone, sampleRate: SR),
                ],
                sampleRate: SR,
                includeTail: false
            )
            let openDB = AutoRemixDiagnostics.meanLoudnessDB(
                samples: rendered.mix, sampleRate: SR, from: 0.5, to: 2.0
            )
            let midOpenDB = AutoRemixDiagnostics.meanLoudnessDB(
                samples: rendered.mix, sampleRate: SR, from: 4.0, to: 8.0
            )
            check(
                "Golden Oops×BOMT: opening fades from silence (not a slam)",
                openDB < midOpenDB - 3.0,
                String(format: "early=%.1f later=%.1f", openDB, midOpenDB)
            )
            let titleDB = AutoRemixDiagnostics.meanLoudnessDB(
                samples: rendered.mix, sampleRate: SR,
                from: hook.timelineStart + 0.4, to: hook.timelineStart + 4.0
            )
            let preDropDB = AutoRemixDiagnostics.meanLoudnessDB(
                samples: rendered.mix, sampleRate: SR,
                from: preDropStart + 0.2, to: drop1 - 0.2
            )
            check(
                "Golden Oops×BOMT: pre-drop window is not silent",
                preDropDB > -50,
                String(format: "preDrop=%.1f dB", preDropDB)
            )
            let dropDB = AutoRemixDiagnostics.meanLoudnessDB(
                samples: rendered.mix, sampleRate: SR,
                from: drop1 + 0.05, to: drop1 + 8.0
            )
            let dropVocals = plan.placements.filter {
                $0.role == .dominant && $0.stemKind == .vocals
                    && abs($0.timelineStart - drop1) < 0.12
            }
            let titleVol = hook.volume
            let isolationFloor = titleVol * AutoGainPolicy.dropVsIsolatedTitleBoost
            check(
                "Golden Oops×BOMT: Drop 1 clip volume meets isolation floor",
                !dropVocals.isEmpty && dropVocals.allSatisfy { $0.volume + 0.001 >= isolationFloor },
                String(format: "title=%.2f floor=%.2f drop=%@",
                       titleVol, isolationFloor,
                       dropVocals.map { String(format: "%.2f", $0.volume) }.joined(separator: ","))
            )
            check(
                "Golden Oops×BOMT: Drop 1 window is audible on rendered PCM",
                dropDB > -45,
                String(format: "drop=%.1f dB", dropDB)
            )
            check(
                "Golden Oops×BOMT: Drop 1 8s mix RMS ≥ title-hook 4s",
                dropDB + 0.05 >= titleDB,
                String(format: "drop=%.2f title=%.2f", dropDB, titleDB)
            )
        case .failure(let msg):
            check("Golden Oops×BOMT planner", false, msg)
        }
    } catch {
        check("Golden Oops×BOMT fixture", false, "\(error)")
    }
}

// MARK: - Paramore×tatu @144

do {
    let paramore = makeSong(title: "All I Wanted", bpm: 144, key: "Em", color: .purple)
    let tatu = makeSong(title: "All The Things She Said", bpm: 90, key: "Am", color: .pink)
    let titleLyric = 39.84
    let stemRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("mixr-golden-paramore-\(UUID().uuidString)", isDirectory: true)
    let bedLyrics = stemRoot.appendingPathComponent("All I Wanted/lyrics.json")
    let guestLyrics = stemRoot.appendingPathComponent("All The Things She Said/lyrics.json")
    do {
        try writeLyricsJSON(
            to: bedLyrics, title: paramore.title, titleHookStart: titleLyric,
            words: [(titleLyric, "all"), (titleLyric + 0.2, "i"), (titleLyric + 0.42, "wanted")]
        )
        try writeLyricsJSON(
            to: guestLyrics, title: tatu.title, titleHookStart: 64.0,
            words: [(64.0, "all"), (64.2, "the"), (64.4, "things"), (64.7, "she"), (65.0, "said")]
        )
        var tuning = AutoTuning.standard
        var bedStems = mockStemSet(in: bedLyrics.deletingLastPathComponent())
        bedStems.lyrics = bedLyrics
        var guestStems = mockStemSet(in: guestLyrics.deletingLastPathComponent())
        guestStems.lyrics = guestLyrics
        tuning.explicitStemsBySongID[paramore.id] = bedStems
        tuning.explicitStemsBySongID[tatu.id] = guestStems
        var bedSignal = makeFeatures(duration: 220, bpm: 144, drum: 0.29, bass: 0.53, vocal: 0.60, confidence: 0.50)
        bedSignal.lyricTitleHookStart = titleLyric
        bedSignal.lyricWords = [(titleLyric, "all"), (titleLyric + 0.2, "i"), (titleLyric + 0.42, "wanted")]
        var guestSignal = makeFeatures(duration: 220, bpm: 90, drum: 0.82, bass: 0.57, vocal: 0.64)
        guestSignal.lyricTitleHookStart = 64.0
        switch AutoRemixRunner.runEntireProject(
            tracks: [paramore, tatu], tuning: tuning, seed: 33,
            signals: [paramore.id: bedSignal, tatu.id: guestSignal]
        ) {
        case .success(_, let plan, _):
            check(
                "Golden Paramore×tatu: stays at festival 144 (no house lift)",
                abs(plan.targetBPM - 144) < 0.5,
                "bpm=\(plan.targetBPM)"
            )
            check("Golden Paramore×tatu: tatu owns Drop 1 vocal", plan.mashupVocalSongID == tatu.id)
            if let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan) {
                let wanted = titleLyric + 0.42
                check(
                    "Golden Paramore×tatu: title clip starts on distinctive token, not phrase-start filler",
                    hook.sourceStart > titleLyric + 0.05
                        && hook.sourceStart < wanted
                        && (wanted - hook.sourceStart) <= 0.35,
                    String(format: "src=%.2f all=%.2f wanted=%.2f", hook.sourceStart, titleLyric, wanted)
                )
            }
            if let drop1 = AutoRemixDiagnostics.firstDropStart(plan: plan) {
                let paramoreTone = stemShapedSource(duration: 220, bpm: 144, tokenTimes: [titleLyric])
                let tatuTone = stemShapedSource(duration: 220, bpm: 90, tokenTimes: [64.0, 65.0])
                let rendered = AutoOfflineMixdown.render(
                    plan: plan,
                    sources: [
                        paramore.id: AutoOfflineMixdown.Source(samples: paramoreTone, sampleRate: SR),
                        tatu.id: AutoOfflineMixdown.Source(samples: tatuTone, sampleRate: SR),
                    ],
                    sampleRate: SR,
                    includeTail: false
                )
                let dropDB = AutoRemixDiagnostics.meanLoudnessDB(
                    samples: rendered.mix, sampleRate: SR,
                    from: drop1 + 0.05, to: drop1 + 8.0
                )
                check(
                    "Golden Paramore×tatu: Drop 1 is audible",
                    dropDB > -45,
                    String(format: "drop=%.1f dB", dropDB)
                )
            }
        case .failure(let msg):
            check("Golden Paramore×tatu planner", false, msg)
        }
    } catch {
        check("Golden Paramore×tatu fixture", false, "\(error)")
    }
}

if failures > 0 {
    print("\nFAILED: \(failures)")
    exit(1)
}
print("\nALL PASSED")
