import Foundation

// MARK: - Auto Join Engine
//
// Owns mashup join contracts: title-hook pad, pivot wallpaper, Drop 1 loudness
// floor vs title, and opening fade-in. The planner delegates here so join fixes
// stop whack-a-moling the 4.6k-line orchestrator.

nonisolated enum AutoJoinEngine {

    // MARK: Title-hook placement

    /// Title-hook clip start with club-lift mix-time pad when `tempoRatio > 1.12`.
    static func titleHookClipStart(
        lyric: Double,
        downbeats: [Double],
        barSeconds: Double,
        leadIn: AutoChorusIsland.TitleHookLeadIn = .enoughForTitleToken,
        title: String? = nil,
        lyricWords: [(t: Double, word: String)] = [],
        tempoRatio: Double = 1
    ) -> Double {
        AutoChorusIsland.titleHookClipStart(
            lyric: lyric,
            downbeats: downbeats,
            barSeconds: barSeconds,
            leadIn: leadIn,
            title: title,
            lyricWords: lyricWords,
            tempoRatio: tempoRatio
        )
    }

    /// Mix-time lead in seconds after club-lift stretch (for perceptual gates).
    static func mixTimeTitleLead(
        lyric: Double,
        clipStart: Double,
        tempoRatio: Double
    ) -> Double {
        (lyric - clipStart) / max(tempoRatio, 0.0001)
    }

    /// First complete Deck A hook for a mashup: jump to the bed's **title**
    /// chorus island (measured energy-rise entrance).
    static func bedFirstCompleteChorusSection(
        profile: AutoSongProfile,
        used: [(Double, Double)],
        bars: Int,
        energy: Double,
        tempoRatio: Double = 1
    ) -> AutoCandidateSection? {
        _ = bars
        let wantBars = 8
        let bar = profile.analysis.barSeconds
        let introEnd = profile.analysis.introCandidate?.endSeconds ?? bar * 8
        let phrase = profile.analysis.phraseBoundaries.count >= 2
            ? max(bar * 4, profile.analysis.phraseBoundaries[1] - profile.analysis.phraseBoundaries[0])
            : bar * 8
        let measured = AutoChorusIsland.bestEntrance(
            signal: profile.analysis.signal,
            downbeats: profile.analysis.downbeats,
            barSeconds: bar,
            duration: profile.analysis.durationSeconds,
            introEnd: introEnd,
            phraseSeconds: phrase,
            title: profile.title,
            tempoRatio: tempoRatio
        )

        func overlapsUsed(_ start: Double, bars: Int) -> Bool {
            let end = start + Double(bars) * bar
            return used.contains { range in
                let overlap = min(end, range.1) - max(start, range.0)
                return overlap > Double(bars) * bar * 0.5
            }
        }

        if let measured,
           profile.analysis.signal?.lyricTitleHookStart != nil,
           !overlapsUsed(measured.startSeconds, bars: wantBars)
        {
            return AutoCandidateSection(
                songID: profile.songID,
                label: .chorus,
                startSeconds: measured.startSeconds,
                barCount: wantBars,
                barSeconds: bar,
                hook: 0.9,
                energy: energy,
                vocal: 0.7,
                clarity: 0.7,
                rhythm: profile.analysis.drumStrength,
                uniqueness: 0.7,
                transitionUse: 0.55,
                confidence: profile.analysis.analysisConfidence
            )
        }

        let pool = profile.candidates.filter {
            $0.label == .chorus && $0.barCount >= wantBars && !overlapsUsed($0.startSeconds, bars: $0.barCount)
        }

        if let measured {
            let near = pool.filter { abs($0.startSeconds - measured.startSeconds) <= bar * 0.45 }
            let atOrBefore = near.filter { $0.startSeconds <= measured.startSeconds + 0.02 }
            if let best = atOrBefore.min(by: {
                abs($0.startSeconds - measured.startSeconds) < abs($1.startSeconds - measured.startSeconds)
            }) {
                return best
            }
            if !overlapsUsed(measured.startSeconds, bars: wantBars) {
                return completePhraseSection(
                    profile: profile,
                    from: measured.startSeconds,
                    bars: wantBars,
                    energy: energy
                )
            }
        }

        let unglued = pool.filter { $0.startSeconds > introEnd + bar * 1.5 }
        let ranked = (unglued.isEmpty ? pool : unglued).sorted { $0.hook > $1.hook }
        return ranked.first
    }

    private static func completePhraseSection(
        profile: AutoSongProfile,
        from: Double,
        bars: Int,
        energy: Double
    ) -> AutoCandidateSection? {
        let bar = profile.analysis.barSeconds
        let want = Double(max(8, bars))
        let snapped = profile.analysis.downbeats.last { $0 <= from + 0.01 } ?? max(0, from)
        let need = want * bar
        guard snapped + need <= profile.analysis.durationSeconds - 0.15 else { return nil }
        return AutoCandidateSection(
            songID: profile.songID,
            label: .chorus,
            startSeconds: snapped,
            barCount: max(8, bars),
            barSeconds: bar,
            hook: 0.9,
            energy: energy,
            vocal: 0.7,
            clarity: 0.7,
            rhythm: profile.analysis.drumStrength,
            uniqueness: 0.7,
            transitionUse: 0.55,
            confidence: profile.analysis.analysisConfidence
        )
    }

    // MARK: Pivot wallpaper

    static func appendPivotWallpaperLoop(
        completedPhrase: AutoClipPlacement,
        dropTimelineStart: Double,
        deckATitle: String?,
        deckBTitle: String?,
        barSec: Double,
        beatSec: Double,
        tuning: AutoTuning,
        grainStem: AutoStemKind? = nil,
        signal: SongSignalFeatures? = nil,
        incomingSongID: UUID? = nil,
        incomingHookStart: Double? = nil,
        incomingTempoRatio: Double? = nil,
        incomingSignal: SongSignalFeatures? = nil,
        incomingGrainStem: AutoStemKind? = nil,
        placements: inout [AutoClipPlacement],
        pulseRegions: inout [AutoClubPulse.Region],
        intentionalGaps: inout [AutoIntentionalGap],
        decisions: inout [AutoDecision]
    ) {
        let repeats = tuning.pivotWallpaperBeats
        let loopDur = tuning.pivotWindowSeconds(barSec: barSec)
        let loopStart = dropTimelineStart - loopDur
        guard loopStart >= 0.05 else { return }

        clearPredropVoidOnPivotJoin(
            dropTimelineStart: dropTimelineStart,
            intentionalGaps: &intentionalGaps,
            pulseRegions: &pulseRegions
        )

        let phraseEnd = min(completedPhrase.sourceEnd, completedPhrase.sourceStart + completedPhrase.timelineDuration * completedPhrase.tempoRatio)
        let phraseBars = (phraseEnd - completedPhrase.sourceStart)
            / max(barSec * completedPhrase.tempoRatio, 0.001)
        guard phraseBars + 0.05 >= AutoRemixDiagnostics.minCompleteHookBars else {
            fillPivotWindowWithoutLoop(
                completedPhrase: completedPhrase,
                loopStart: loopStart,
                dropTimelineStart: dropTimelineStart,
                deckATitle: deckATitle,
                reason: "phrase too short for a last-word grain — skip loop rather than slice the title",
                placements: &placements,
                decisions: &decisions
            )
            return
        }
        let useIncomingJoin = incomingSongID != nil && incomingHookStart != nil
        let pivot = useIncomingJoin
            ? AutoPivotWord.joinToken(
                deckATitle: deckATitle ?? "",
                deckBTitle: deckBTitle ?? deckATitle ?? ""
            )
            : AutoPivotWord.preferredPivot(
                deckATitle: deckATitle ?? "",
                deckBTitle: deckBTitle ?? deckATitle ?? ""
            )
        let grainSignal = useIncomingJoin ? incomingSignal : signal
        let vocalCurve = {
            guard let grainSignal else { return [Double]() }
            if !grainSignal.stemVocalPresenceCurve.isEmpty { return grainSignal.stemVocalPresenceCurve }
            return grainSignal.vocalPresenceCurve
        }()
        let grainTempo = incomingTempoRatio ?? completedPhrase.tempoRatio
        let grainSource: Double
        let grainSongID: UUID
        let resolvedStem: AutoStemKind?
        if useIncomingJoin, let incomingSongID, let incomingHookStart {
            grainSource = AutoPivotWord.joinTokenGrainSource(
                token: pivot,
                lyricWords: grainSignal?.lyricWords ?? [],
                hookStart: incomingHookStart,
                beatSec: beatSec,
                tempoRatio: grainTempo,
                vocalPresence: vocalCurve,
                hopSeconds: grainSignal?.hopSeconds ?? 0.1
            )
            grainSongID = incomingSongID
            resolvedStem = incomingGrainStem ?? grainStem
        } else {
            grainSource = AutoPivotWord.lastBeatGrainSource(
                phraseSourceStart: completedPhrase.sourceStart,
                phraseSourceEnd: phraseEnd,
                beatSec: beatSec,
                tempoRatio: completedPhrase.tempoRatio,
                pivotToken: pivot,
                lyricWords: signal?.lyricWords ?? [],
                vocalPresence: vocalCurve,
                hopSeconds: signal?.hopSeconds ?? 0.1
            )
            grainSongID = completedPhrase.songID
            resolvedStem = grainStem
        }

        for i in placements.indices {
            let p = placements[i]
            let isGrain = p.role == .supporting
                && abs(p.timelineDuration - beatSec) < beatSec * 0.4
            if isGrain { continue }
            guard p.timelineEnd > loopStart + 0.01,
                  p.timelineStart < dropTimelineStart - 0.01 else { continue }
            if p.timelineStart >= loopStart - 0.01 {
                placements[i].timelineDuration = 0
            } else {
                let newDur = loopStart - p.timelineStart
                if newDur >= 0.05 {
                    placements[i].timelineDuration = newDur
                    placements[i].fadeOut = ClipTransition(type: .none, duration: 0)
                } else {
                    placements[i].timelineDuration = 0
                }
            }
        }
        placements.removeAll { $0.timelineDuration < 0.05 }

        pulseRegions.removeAll {
            $0.timelineEnd > loopStart + 0.01 && $0.timelineStart < dropTimelineStart - 0.01
        }
        pulseRegions.append(
            AutoClubPulse.Region(role: .buildOut, timelineStart: loopStart, timelineEnd: dropTimelineStart)
        )

        let grainVol = AutoGainPolicy.roleStagingVolume(
            role: .pivotGrain,
            measuredStemRMS: nil,
            referenceRMS: nil,
            useIncomingJoin: useIncomingJoin,
            stemKind: resolvedStem
        )
        for i in 0..<repeats {
            let t0 = loopStart + Double(i) * beatSec
            let blur = 36.0 + (22.0 * Double(i) / Double(max(repeats - 1, 1)))
            var fx = ClipEffectSettings()
            fx.setLevel(blur, for: MixrEffect.blur.rawValue)
            fx = AutoSupportedEffects.sanitize(fx)

            placements.append(
                AutoClipPlacement(
                    songID: grainSongID,
                    sourceStart: grainSource,
                    timelineStart: t0,
                    timelineDuration: beatSec,
                    tempoRatio: grainTempo,
                    volume: grainVol,
                    fadeIn: ClipTransition(type: .none, duration: 0),
                    fadeOut: ClipTransition(type: .none, duration: 0),
                    effects: fx,
                    role: .supporting,
                    slotIndex: completedPhrase.slotIndex,
                    overlapsPreviousSeconds: beatSec,
                    stemKind: resolvedStem
                )
            )
        }

        decisions.append(
            AutoDecision(
                kind: .pivotWallpaperLoop,
                songTitle: useIncomingJoin ? deckBTitle : deckATitle,
                detail: String(
                    format: "%d×1-beat%@%@%@ src=%.2f → hard cut @%.1fs",
                    repeats,
                    pivot.map { " “\($0)”" } ?? "",
                    useIncomingJoin ? " incoming-join" : "",
                    resolvedStem == .vocals ? " vocal-stem" : "",
                    grainSource,
                    dropTimelineStart
                )
            )
        )
        if resolvedStem == .vocals {
            decisions.append(
                AutoDecision(
                    kind: .usedStemSidecar,
                    songTitle: useIncomingJoin ? deckBTitle : deckATitle,
                    detail: "pivot grain from vocals.wav"
                )
            )
        }
    }

    static func clearPredropVoidOnPivotJoin(
        dropTimelineStart: Double,
        intentionalGaps: inout [AutoIntentionalGap],
        pulseRegions: inout [AutoClubPulse.Region]
    ) {
        intentionalGaps.removeAll {
            $0.reason.localizedCaseInsensitiveContains("void")
                && abs($0.end - dropTimelineStart) < 0.08
        }
        pulseRegions.removeAll {
            $0.role == .void && abs($0.timelineEnd - dropTimelineStart) < 0.08
        }
    }

    static func stripVoidsWhenDrop1HasPivot(
        placements: [AutoClipPlacement],
        beatSec: Double,
        barSec: Double,
        decisions: inout [AutoDecision],
        intentionalGaps: inout [AutoIntentionalGap],
        pulseRegions: inout [AutoClubPulse.Region]
    ) {
        let drop1 = pulseRegions.filter { $0.role == .drop }.map(\.timelineStart).min()
        let hasPivotDecision = decisions.contains { $0.kind == .pivotWallpaperLoop }
        let hasPivotGrains: Bool = {
            guard let drop1 else { return false }
            return placements.contains {
                $0.role == .supporting
                    && abs($0.timelineDuration - beatSec) < beatSec * 0.35
                    && $0.timelineStart >= drop1 - barSec * 2.5
                    && $0.timelineStart < drop1 - 0.02
            }
        }()
        guard hasPivotDecision || hasPivotGrains else { return }
        intentionalGaps.removeAll { $0.reason.localizedCaseInsensitiveContains("void") }
        pulseRegions.removeAll { $0.role == .void }
        decisions.removeAll { $0.kind == .allowedPredropVoid }
    }

    static func fillPivotWindowWithoutLoop(
        completedPhrase: AutoClipPlacement,
        loopStart: Double,
        dropTimelineStart: Double,
        deckATitle: String?,
        reason: String,
        placements: inout [AutoClipPlacement],
        decisions: inout [AutoDecision]
    ) {
        for i in placements.indices where placements[i].role == .dominant
            && placements[i].songID == completedPhrase.songID
        {
            let p = placements[i]
            let endsAtWindow = abs(p.timelineEnd - loopStart) <= 0.08
            let straddlesWindow = p.timelineStart < loopStart
                && p.timelineEnd > loopStart - 0.05
                && p.timelineEnd < dropTimelineStart - 0.05
            if endsAtWindow || straddlesWindow {
                placements[i].timelineDuration = max(
                    p.timelineDuration,
                    dropTimelineStart - p.timelineStart
                )
                placements[i].fadeOut = ClipTransition(type: .none, duration: 0)
            }
        }
        decisions.append(
            AutoDecision(
                kind: .skippedPivotWallpaper,
                songTitle: deckATitle,
                detail: reason
            )
        )
    }

    // MARK: Opening fade + mix staging

    static func applyOpeningFadeIn(
        placements: inout [AutoClipPlacement],
        beatSec: Double,
        decisions: inout [AutoDecision]
    ) {
        let beats = AutoClubTempo.openingFadeInBeats
        let firstStart = placements
            .filter { $0.role == .dominant }
            .map(\.timelineStart)
            .min()
        guard let firstStart else { return }
        var faded = 0
        for i in placements.indices {
            let p = placements[i]
            guard abs(p.timelineStart - firstStart) < 0.05 else { continue }
            guard p.role == .dominant || p.role == .supporting else { continue }
            if p.role == .supporting, abs(p.timelineDuration - beatSec) < beatSec * 0.4 {
                continue
            }
            placements[i].fadeIn = ClipTransition(
                type: .crossfade,
                duration: beats,
                curve: AutoTransitionEnvelope.equalPowerCurveName
            )
            faded += 1
        }
        guard faded > 0 else { return }
        decisions.append(
            AutoDecision(
                kind: .selectedAnchor,
                songTitle: nil,
                detail: String(format: "opening fade-in %.0f beats (longer than UI 8)", beats)
            )
        )
    }

    static func boostJoinClipVolumes(
        placements: inout [AutoClipPlacement],
        pulseRegions: [AutoClubPulse.Region],
        beatSec: Double,
        barSec: Double,
        profiles: [UUID: AutoSongProfile]
    ) {
        let dropStarts = pulseRegions.filter { $0.role == .drop }.map(\.timelineStart)
        func nearDrop(_ t: Double) -> Bool {
            dropStarts.contains { abs($0 - t) < 0.12 }
        }
        func isPivotGrain(_ p: AutoClipPlacement) -> Bool {
            p.role == .supporting && abs(p.timelineDuration - beatSec) < beatSec * 0.4
        }
        func isTitleHookCopy(_ p: AutoClipPlacement) -> Bool {
            p.role == .dominant
                && !nearDrop(p.timelineStart)
                && p.timelineDuration > beatSec * 8
                && p.timelineStart < (dropStarts.min() ?? .infinity) - barSec
        }
        func isDropLead(_ p: AutoClipPlacement) -> Bool {
            p.role == .dominant && nearDrop(p.timelineStart)
        }
        func isBedUnderDrop(_ p: AutoClipPlacement) -> Bool {
            p.role == .supporting && nearDrop(p.timelineStart) && !isPivotGrain(p)
        }
        func measuredRMSDB(_ p: AutoClipPlacement) -> Double? {
            guard let signal = profiles[p.songID]?.analysis.signal else { return nil }
            let window = max(0.5, min(barSec, 2.6))
            let stem = signal.meanStemVocalRMSDB(from: p.sourceStart, to: p.sourceStart + window)
            if stem > -80 { return stem }
            let mix = signal.meanRMSDB(from: p.sourceStart, to: p.sourceStart + window)
            return mix > -80 ? mix : nil
        }
        func effectiveDB(_ p: AutoClipPlacement) -> Double? {
            guard let rms = measuredRMSDB(p) else { return nil }
            return rms + 20.0 * log10(max(p.volume, 0.001))
        }

        let verseVol = placements
            .filter { p in
                p.role == .dominant
                    && p.stemKind == nil
                    && !nearDrop(p.timelineStart)
                    && p.timelineDuration > beatSec * 2
            }
            .map(\.volume)
            .max() ?? AutoGainPolicy.preservationSongVolume
        let floor = max(
            verseVol,
            AutoGainPolicy.incomingDropVolume,
            AutoGainPolicy.pivotGrainVolume
        )

        var referenceRMS = -120.0
        for p in placements where p.role == .dominant && p.stemKind == nil
            && !nearDrop(p.timelineStart) && p.timelineDuration > beatSec * 8 {
            if let signal = profiles[p.songID]?.analysis.signal {
                let rms = signal.meanRMSDB(from: p.sourceStart, to: p.sourceStart + 4)
                if rms > referenceRMS { referenceRMS = rms }
            }
        }

        for i in placements.indices {
            let p = placements[i]
            let pivot = isPivotGrain(p)
            let dropLead = isDropLead(p)
            let bedUnderDrop = isBedUnderDrop(p)
            let titleHookCopy = isTitleHookCopy(p)
            guard pivot || dropLead || bedUnderDrop || titleHookCopy else { continue }
            var vol = max(p.volume, floor)
            if pivot {
                vol = max(vol, AutoGainPolicy.roleStagingVolume(role: .pivotGrain))
            }
            if p.stemKind == .vocals, dropLead || titleHookCopy || pivot {
                vol = max(vol, vocalStemMakeup(placement: p, referenceRMS: referenceRMS, profiles: profiles, barSec: barSec))
            }
            if dropLead {
                vol = max(vol, AutoGainPolicy.roleStagingVolume(role: .dropGuest))
            }
            if bedUnderDrop {
                vol = max(vol, AutoGainPolicy.roleStagingVolume(role: .bedUnderDrop))
            }
            if titleHookCopy, p.stemKind == .vocals {
                vol = max(vol, AutoGainPolicy.roleStagingVolume(role: .titleStem))
            }
            placements[i].volume = min(AutoGainPolicy.maxClipVolume, vol)
            if pivot || dropLead || bedUnderDrop {
                placements[i].fadeIn = .hardCut
            }
        }

        let titleVocals = placements.filter { isTitleHookCopy($0) && $0.stemKind == .vocals }
        let titleVocalWindows = placements.filter {
            $0.role == .dominant
                && $0.stemKind == .vocals
                && !nearDrop($0.timelineStart)
                && $0.timelineStart < (dropStarts.min() ?? .infinity) - barSec * 0.25
                && $0.timelineDuration > beatSec * 2
        }
        // Intro / verse full-mix must not keep playing at full volume under
        // the isolated title vocal. Split at the title start so the opening
        // stays loud and the overlap is ducked (trimming creates a gap the
        // validator fills with an equal-power overlap that re-buries the token).
        if let hookStart = titleVocalWindows.map(\.timelineStart).min() {
            var tails: [AutoClipPlacement] = []
            for i in placements.indices {
                let p = placements[i]
                guard p.role == .dominant, p.stemKind != .vocals else { continue }
                guard p.timelineStart < hookStart - 0.05, p.timelineEnd > hookStart + 0.05 else { continue }
                let tailDur = p.timelineEnd - hookStart
                var tail = p
                tail.timelineStart = hookStart
                tail.sourceStart = p.sourceStart + (hookStart - p.timelineStart) * p.tempoRatio
                tail.timelineDuration = tailDur
                tail.volume = min(p.volume, AutoGainPolicy.roleStagingVolume(role: .titleBed))
                tail.continuesPrevious = true
                tail.fadeIn = .none
                tails.append(tail)
                placements[i].timelineDuration = max(0.05, hookStart - p.timelineStart)
                placements[i].fadeOut = .none
            }
            placements.append(contentsOf: tails)
        }
        // Stacked drums+bass+other at planner duck (~0.62 each) bury the
        // isolated title token. Offline mixdown has no blur DSP, so volume
        // must carry the duck. Cap overlapping supporting stems and any
        // full-mix duplicate under the title; never the vocal.
        for i in placements.indices {
            let p = placements[i]
            if p.stemKind == .vocals { continue }
            if isPivotGrain(p) { continue }
            let underTitle = titleVocalWindows.contains { v in
                let overlap = min(v.timelineEnd, p.timelineEnd) - max(v.timelineStart, p.timelineStart)
                return overlap > beatSec * 0.5
            }
            guard underTitle else { continue }
            placements[i].volume = min(
                p.volume,
                AutoGainPolicy.roleStagingVolume(role: .titleBed)
            )
        }
        guard let titleHook = (titleVocals.min(by: { $0.timelineStart < $1.timelineStart })
                ?? titleVocalWindows.min(by: { $0.timelineStart < $1.timelineStart }))
                ?? titleVocals.first else { return }
        let titleVol = titleHook.volume
        let titleEff = effectiveDB(titleHook)
        let dropSongID = placements.first(where: { isDropLead($0) })?.songID
        guard let dropSongID else { return }

        var dropScale = 1.0
        for i in placements.indices {
            let p = placements[i]
            guard isDropLead(p), p.songID == dropSongID, p.stemKind == .vocals else { continue }
            var vol = max(p.volume, titleVol)
            if let titleEff, let rms = measuredRMSDB(p) {
                vol = max(vol, pow(10.0, (titleEff - rms) / 20.0))
            }
            vol = max(vol, titleVol * AutoGainPolicy.dropVsIsolatedTitleBoost)
            vol = min(AutoGainPolicy.maxClipVolume, vol)
            dropScale = max(dropScale, vol / max(p.volume, 0.001))
            placements[i].volume = vol
        }
        for i in placements.indices {
            let p = placements[i]
            guard p.songID == dropSongID else { continue }
            guard isDropLead(p) || isBedUnderDrop(p) else { continue }
            if isDropLead(p), p.stemKind == .vocals { continue }
            var vol = max(p.volume, titleVol)
            if dropScale > 1.001 {
                vol = max(vol, p.volume * dropScale)
            }
            placements[i].volume = min(AutoGainPolicy.maxClipVolume, vol)
        }
        let isolation = titleVol * AutoGainPolicy.dropVsIsolatedTitleBoost
        for i in placements.indices where isPivotGrain(placements[i]) {
            placements[i].volume = min(
                AutoGainPolicy.maxClipVolume,
                max(placements[i].volume, isolation)
            )
        }
    }

    private static func vocalStemMakeup(
        placement p: AutoClipPlacement,
        referenceRMS: Double,
        profiles: [UUID: AutoSongProfile],
        barSec: Double
    ) -> Double {
        let window = max(0.5, min(barSec, 2.6))
        let srcEnd = p.sourceStart + window
        if let signal = profiles[p.songID]?.analysis.signal {
            let stemRMS = signal.meanStemVocalRMSDB(from: p.sourceStart, to: srcEnd)
            if referenceRMS > -80, stemRMS > -80, stemRMS < referenceRMS - 0.4 {
                let delta = min(8.0, referenceRMS - stemRMS)
                return pow(10.0, delta / 20.0)
            }
            if !signal.stemVocalPresenceCurve.isEmpty, !signal.energyCurve.isEmpty {
                func mean(_ curve: [Double]) -> Double {
                    let hop = max(signal.hopSeconds, 0.05)
                    let lo = max(0, Int(p.sourceStart / hop))
                    let hi = min(curve.count - 1, Int(srcEnd / hop))
                    guard hi >= lo else { return 0 }
                    var s = 0.0
                    for i in lo...hi { s += curve[i] }
                    return s / Double(hi - lo + 1)
                }
                let stemE = mean(signal.stemVocalPresenceCurve)
                let mixE = mean(signal.energyCurve)
                if stemE > 0.04, mixE > stemE * 1.05 {
                    return min(AutoGainPolicy.maxClipVolume, mixE / stemE)
                }
            }
        }
        return AutoGainPolicy.vocalStemMakeupDefault
    }
}
