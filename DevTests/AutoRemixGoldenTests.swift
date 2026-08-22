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
                "Golden Oops×BOMT: gentle club-lift (not house 126 chipmunk)",
                plan.targetBPM > 98 && plan.targetBPM < 118,
                "bpm=\(plan.targetBPM)"
            )
            guard let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan) else {
                check("Golden Oops×BOMT: title-hook exists", false); break
            }
            let mixLead = AutoJoinEngine.mixTimeTitleLead(
                lyric: bedLyric, clipStart: hook.sourceStart, tempoRatio: hook.tempoRatio
            )
            check(
                "Golden Oops×BOMT: title token mixLead after a 1–2 beat pad",
                mixLead >= 0.70 && mixLead <= 1.50,
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
            // Sweep join: the window is COVERED by continuous outgoing
            // material under a rising low-pass, plus one decaying echo
            // throw — not a grain loop.
            let windowClips = plan.placements.filter {
                $0.timelineEnd > preDropStart + 0.05
                    && $0.timelineStart < drop1 - 0.05
                    && $0.role != .supporting || ($0.timelineEnd > preDropStart + 0.05 && $0.timelineStart < drop1 - 0.05)
            }
            let sweepCoverage = windowClips.contains {
                $0.timelineStart < preDropStart + 0.1 && $0.timelineEnd > drop1 - 0.1
                    || ($0.continuesPrevious && $0.timelineEnd > drop1 - 0.6)
            }
            let throwClips = plan.placements.filter {
                $0.role == .supporting
                    && $0.fadeOut.type == .echoOut
                    && abs($0.timelineStart - preDropStart) < plan.beatSeconds
            }
            check(
                "Golden Oops×BOMT: sweep join covers the window (material + echo throw, no loop)",
                sweepCoverage && !throwClips.isEmpty,
                String(format: "coverage=%@ throws=%d", sweepCoverage ? "yes" : "NO", throwClips.count)
            )

            // The chop must not SLAM in. Grains only need to be "at least as
            // loud as the title-hook vocal copy"; the extra
            // dropVsIsolatedTitleBoost belongs to Drop 1 alone. Applying it to
            // the grains put the chop +6.4 dB above the vocal that preceded
            // it — the most salient element in the mix jumping that far in one
            // sample is heard as "the baby baby baby is too sudden".
            if let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan), !grains.isEmpty {
                let loudest = grains.map(\.volume).max() ?? 0
                check(
                    "Golden Oops×BOMT: pivot grains do not slam above the title hook",
                    loudest <= hook.volume * 1.25 + 0.01,
                    String(format: "grain=%.2f title=%.2f ratio=%.2fx",
                           loudest, hook.volume, loudest / max(hook.volume, 0.001))
                )
            }

            // FEEDBACK 2026-08-21:
            // a) Volume steps on sample-continuous material must RAMP — the
            //    title-duck release stepped 0.18→0.62 in one sample ("jumps
            //    louder, isn't a smooth voice isolation to blend first").
            do {
                var worstStep = 0.0
                let sorted = plan.placements.sorted { $0.timelineStart < $1.timelineStart }
                for (a, b) in zip(sorted, sorted.dropFirst()) {
                    guard b.continuesPrevious,
                          a.songID == b.songID, a.stemKind == b.stemKind,
                          abs(a.timelineEnd - b.timelineStart) < 0.05,
                          a.volume > 0.01, b.volume > 0.01
                    else { continue }
                    let stepDB = abs(20 * log10(b.volume / a.volume))
                    worstStep = max(worstStep, stepDB)
                }
                check(
                    "Golden Oops×BOMT: no >4 dB instant volume step on continuous material",
                    worstStep <= 4.0,
                    String(format: "worst=%.1f dB", worstStep)
                )
            }
            // b) Drop 2 must bring FRESH source material — the same chorus
            //    already played twice as the title hold ("you already did
            //    that once, don't keep doing the same loops").
            do {
                let drops = plan.pulseRegions.filter { $0.role == .drop }
                    .map(\.timelineStart).sorted()
                if drops.count >= 2 {
                    let d2 = drops[1]
                    let before = plan.placements.filter {
                        $0.role == .dominant && $0.timelineEnd <= d2 + 0.1 && $0.timelineStart < d2 - 0.1
                    }
                    let after = plan.placements.filter {
                        $0.role == .dominant && $0.timelineStart >= d2 - 0.1
                            && $0.timelineDuration >= plan.barSeconds * 3
                    }
                    var overlap = 0.0
                    var total = 0.0
                    for p2 in after {
                        total += p2.sourceDuration
                        for p1 in before where p1.songID == p2.songID {
                            let lo = max(p1.sourceStart, p2.sourceStart)
                            let hi = min(p1.sourceEnd, p2.sourceEnd)
                            if hi > lo { overlap += hi - lo }
                        }
                    }
                    let frac = total > 0.1 ? overlap / total : 0
                    check(
                        "Golden Oops×BOMT: Drop 2 brings fresh source material (≤50% replay)",
                        frac <= 0.5,
                        String(format: "replayed %.0f%% of %.1fs", frac * 100, total)
                    )
                }
            }
            // NO BROKEN RECORDS (product decision 2026-08-20, supersedes the
            // Xirex wallpaper lock): repetition may only appear TRANSFORMED.
            //  a) no grain loops — never 3+ consecutive short clips replaying
            //     one identical source slice at a constant rate;
            //  b) no verbatim passes — two adjacent dominant clips playing the
            //     same source slice must differ audibly (volume, filter, or
            //     backing), or not exist at all.
            do {
                let shorts = plan.placements
                    .filter { $0.role == .supporting && $0.timelineDuration <= plan.beatSeconds * 1.4 }
                    .sorted { $0.timelineStart < $1.timelineStart }
                var runLen = 1
                var worstRun = 1
                for (a, b) in zip(shorts, shorts.dropFirst()) {
                    // Sequential repeats of one slice — NOT parallel stem
                    // layers of the same moment (drums+bass+other at one
                    // timestamp are one sound, not three repeats).
                    if a.stemKind == b.stemKind,
                       b.timelineStart >= a.timelineEnd - 0.05,
                       abs(a.sourceStart - b.sourceStart) < 0.05,
                       abs(a.timelineDuration - b.timelineDuration) < 0.05,
                       b.timelineStart - a.timelineEnd < plan.beatSeconds * 0.5 {
                        runLen += 1
                        worstRun = max(worstRun, runLen)
                    } else {
                        runLen = 1
                    }
                }
                var runDetail = ""
                if worstRun >= 3 {
                    runDetail = shorts.map {
                        String(format: "t=%.2f d=%.2f src=%.2f %@", $0.timelineStart,
                               $0.timelineDuration, $0.sourceStart, $0.stemKind?.rawValue ?? "mix")
                    }.joined(separator: " | ")
                }
                check(
                    "Golden Oops×BOMT: no grain stutter loops (broken-record ban)",
                    worstRun < 3,
                    "worst identical-grain run=\(worstRun) [\(runDetail)]"
                )

                let doms = plan.placements
                    .filter { $0.role == .dominant && $0.timelineDuration >= plan.barSeconds * 4 }
                    .sorted { $0.timelineStart < $1.timelineStart }
                var verbatim: [String] = []
                func backingLevel(_ pass: AutoClipPlacement) -> Double {
                    plan.placements
                        .filter { s in
                            s.role == .supporting && s.stemKind != nil && s.stemKind != .vocals
                                && min(s.timelineEnd, pass.timelineEnd)
                                    - max(s.timelineStart, pass.timelineStart) > pass.timelineDuration * 0.3
                        }
                        .map(\.volume)
                        .reduce(0, +)
                }
                for (a, b) in zip(doms, doms.dropFirst()) {
                    guard a.songID == b.songID,
                          abs(a.sourceStart - b.sourceStart) < 0.1,
                          abs(a.timelineDuration - b.timelineDuration) < plan.barSeconds * 0.5,
                          b.timelineStart - a.timelineEnd < plan.barSeconds
                    else { continue }
                    let sameVol = abs(a.volume - b.volume) < 0.05
                    let sameBlur = abs(a.effects.level(for: MixrEffect.blur.rawValue)
                        - b.effects.level(for: MixrEffect.blur.rawValue)) < 6
                    // The lead may repeat IF the pass underneath it changes —
                    // stripped-backing first pass into full second pass is the
                    // hold variation (the lead is the title vocal ASR needs).
                    let backA = backingLevel(a)
                    let backB = backingLevel(b)
                    let backingVaried = backB > 0.01
                        && abs(backA - backB) / max(backA, backB, 0.01) >= 0.25
                    if sameVol && sameBlur && !backingVaried {
                        verbatim.append(String(
                            format: "%.1fs+%.1fs src=%.1f (backing %.2f vs %.2f)",
                            a.timelineStart, b.timelineStart, a.sourceStart, backA, backB))
                    }
                }
                check(
                    "Golden Oops×BOMT: no verbatim repeated passes (broken-record ban)",
                    verbatim.isEmpty,
                    verbatim.joined(separator: ", ")
                )
            }

            // (first-line guard inserted below, after allDrops)\n            // EVERY drop needs something lifting into it, not just Drop 1.
            // Drop 2 got an impact only, so its last two bars fell 7 dB into
            // a hole and then slammed +11 dB — measured on rendered PCM,
            // while Drop 1's approach is flat within 2 dB. A take-out ending
            // on the downbeat is what turns that cliff into a build. The
            // grammar allows snare/riser into Drop 2 for exactly this.
            let allDrops = plan.pulseRegions.filter { $0.role == .drop }
                .map(\.timelineStart).sorted()

            // The guest's FIRST LINE owns the drop. The drop-ride stack
            // (air sweep at +1 beat, bass-drop at +half bar with its 4.5 dB
            // duck) landed exactly on "hit me baby", carving an 8 dB hole
            // through the words the whole join exists to deliver. Ride SFX
            // start after the first line, not after the first syllable.
            if let d1 = allDrops.first {
                let lineGuard = plan.beatSeconds * 3
                let offenders = plan.sfxEvents.filter {
                    ["airSweep", "bassDrop", "impact", "crash"].contains($0.assetID)
                        && $0.timelineStart > d1 + 0.02
                        && $0.timelineStart < d1 + lineGuard
                }
                check(
                    "Golden Oops×BOMT: drop-ride SFX stay off the guest's first line",
                    offenders.isEmpty,
                    offenders.map { String(format: "%@@%.2f", $0.assetID, $0.timelineStart) }
                        .joined(separator: ",")
                )
            }
            for (i, d) in allDrops.enumerated() {
                let lifts = plan.sfxEvents.filter {
                    ["riser", "snareBuild", "sweepUp"].contains($0.assetID)
                        && $0.timelineEnd > d - plan.beatSeconds * 1.5
                        && $0.timelineEnd <= d + plan.beatSeconds * 0.5
                        && $0.timelineStart < d - 0.05
                }
                check(
                    "Golden Oops×BOMT: drop \(i + 1) has a take-out lifting into it",
                    !lifts.isEmpty,
                    String(format: "drop@%.2f lifts=%d", d, lifts.count)
                )
            }

            // VOCAL RIDE-IN: the incoming voice should already be present,
            // over the outgoing track's music, BEFORE the switch. Otherwise
            // Drop 1 changes the lead voice and the energy in the same
            // sample, which is the remaining "jarring" part of the join once
            // level and filter are continuous. Classic DJ vocal preview: two
            // bars of Deck B's run-up phrase riding Deck A's instrumental,
            // clearly under Deck A's lead so it teases rather than duets.
            if let loopStart = grains.map(\.timelineStart).min(),
               let hook = AutoRemixDiagnostics.firstDeckAHookPlacement(plan: plan) {
                let rideWindow = (loopStart - plan.barSeconds * 2.5, loopStart + 0.05)
                let ride = plan.placements.filter { p in
                    p.songID == bomt.id && p.stemKind == .vocals
                        && p.timelineStart >= rideWindow.0 - 0.05
                        && p.timelineStart < rideWindow.1
                        && p.timelineEnd <= loopStart + 0.1
                }
                check(
                    "Golden Oops×BOMT: incoming vocal rides in before the switch",
                    !ride.isEmpty && ride.allSatisfy { $0.volume < hook.volume },
                    ride.isEmpty
                        ? String(format: "none in %.2f–%.2f (loopStart=%.2f)",
                                 rideWindow.0, rideWindow.1, loopStart)
                        : ride.map {
                            String(format: "t=%.2f-%.2f src=%.2f vol=%.2f (deckA=%.2f)",
                                   $0.timelineStart, $0.timelineEnd, $0.sourceStart,
                                   $0.volume, hook.volume)
                        }.joined(separator: ",")
                )
            }

            // The wallpaper ENTRY must be masked. Everything else is trimmed
            // at loopStart, so the mix drops from full band to one isolated
            // high-passed vocal in a single sample — measured as a 4-sigma
            // timbre outlier on rendered PCM ("the switch comes from
            // nowhere"). Take-out SFX are placed by their own duration
            // before the drop, so a 4.0s riser cannot reach a 4.56s (2-bar)
            // wallpaper. Something broadband has to cover the seam itself.
            // (seam-cover gate retired 2026-08-20: the sweep join rides
            // material continuously through the window, so there is no seam
            // to cover — continuity is asserted by the coverage gate above.)

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
            // c) The mix TRAILS OFF: the last ~12s decay progressively, not
            //    a flat shelf into a 4s collapse.
            do {
                let endT = rendered.mix.count > 0 ? Double(rendered.mix.count) / SR : 0
                if endT > 30 {
                    let a = AutoRemixDiagnostics.meanLoudnessDB(
                        samples: rendered.mix, sampleRate: SR, from: endT - 14, to: endT - 9)
                    let b = AutoRemixDiagnostics.meanLoudnessDB(
                        samples: rendered.mix, sampleRate: SR, from: endT - 9, to: endT - 4)
                    let c = AutoRemixDiagnostics.meanLoudnessDB(
                        samples: rendered.mix, sampleRate: SR, from: endT - 4, to: endT - 0.5)
                    check(
                        "Golden Oops×BOMT: ending trails off (progressive decay, ≥3 dB per stage)",
                        b <= a - 3 && c <= b - 3,
                        String(format: "%.1f -> %.1f -> %.1f dB", a, b, c)
                    )
                }
            }

            check(
                "Golden Oops×BOMT: Drop 1 8s mix RMS ≥ title-hook 4s",
                dropDB + 0.05 >= titleDB,
                String(format: "drop=%.2f title=%.2f", dropDB, titleDB)
            )
            // A bed transpose must RENDER the interval its decision claims.
            // pitchAmount is a 0…1 UI intensity over a full octave, so a
            // planner that divides semitones by anything but 12 ships the
            // wrong key: "−1 st on bed" rendered as −4 st (measured on
            // Britney's vocal), which reads as a male voice.
            if let pitchDecision = plan.decisions.first(where: { $0.kind == .pitchCorrectedOverlap }),
               let detail = pitchDecision.detail {
                let stated = Double(
                    detail.replacingOccurrences(of: " st on bed", with: "")
                        .replacingOccurrences(of: "+", with: "")
                ) ?? .nan
                let bent = plan.placements.filter {
                    $0.effects.pitchAmount > 0.001 && $0.songID != bomt.id
                }
                let worst = bent.map { abs($0.effects.pitchSemitones - stated) }.max() ?? 0
                check(
                    "Golden Oops×BOMT: bed renders the semitones its decision claims",
                    !stated.isNaN && !bent.isEmpty && worst < 0.2,
                    String(format: "stated=%.2f st rendered=%@ worstErr=%.2f st",
                           stated,
                           bent.prefix(3).map { String(format: "%.2f", $0.effects.pitchSemitones) }
                               .joined(separator: ","),
                           worst)
                )
            }
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
                // The title's OWN first word must survive. Chasing "the
                // distinctive token is the first thing ASR hears" started the
                // clip after "All", so the hook rendered as "...I wanted was
                // you" — the title of the song, beheaded. A leading word that
                // belongs to the title is not filler. The distinctive token
                // still has to land early enough to be heard, just not by
                // cutting the line.
                check(
                    "Golden Paramore×tatu: title clip keeps the title's first word ('All')",
                    hook.sourceStart <= titleLyric + 0.02
                        && (wanted - hook.sourceStart) <= 1.8,
                    String(format: "src=%.2f all=%.2f wanted=%.2f lead=%.2f",
                           hook.sourceStart, titleLyric, wanted, wanted - hook.sourceStart)
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
