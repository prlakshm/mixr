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
        bedHasOtherStem: Bool = false,
        placements: inout [AutoClipPlacement],
        pulseRegions: inout [AutoClubPulse.Region],
        intentionalGaps: inout [AutoIntentionalGap],
        decisions: inout [AutoDecision],
        joinContracts: inout [AutoJoinContract]
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

        clearPivotWindow(
            placements: &placements,
            loopStart: loopStart,
            dropTimelineStart: dropTimelineStart,
            beatSec: beatSec
        )

        pulseRegions.removeAll {
            $0.timelineEnd > loopStart + 0.01 && $0.timelineStart < dropTimelineStart - 0.01
        }
        pulseRegions.append(
            AutoClubPulse.Region(role: .buildOut, timelineStart: loopStart, timelineEnd: dropTimelineStart)
        )
        joinContracts.append(
            AutoJoinContract(
                kind: .sweepJoin,
                windowStart: loopStart,
                cutAt: dropTimelineStart,
                outgoingSongID: completedPhrase.songID,
                incomingSongID: incomingSongID,
                coverage: bedHasOtherStem ? .bedOther : .duckedFullMix
            )
        )

        let grainVol = AutoGainPolicy.roleStagingVolume(
            role: .pivotGrain,
            measuredStemRMS: nil,
            referenceRMS: nil,
            useIncomingJoin: useIncomingJoin,
            stemKind: resolvedStem
        )
        // ── Sweep join (no stutter loop) ──
        // Product decision 2026-08-20, supersedes the Xirex wallpaper lock:
        // repetition may only appear TRANSFORMED, so the constant-rate
        // 1-beat grain loop is gone. The window instead keeps the outgoing
        // material playing straight through under a rising low-pass sweep
        // (split into per-bar sample-continuous segments so live, export,
        // and offline render the same ramp), with the take-out SFX and the
        // incoming vocal ride-in on top, into the same hard cut. One
        // decaying ECHO THROW of the outgoing last beat marks the join —
        // each repeat quieter and more distant, the classic any-song move.
        var sweepSegments: [AutoClipPlacement] = []
        for i in placements.indices {
            let p = placements[i]
            // Outgoing deck only — the incoming song's ride-in ends at the
            // window on purpose (extending it would pre-play the hook).
            guard p.songID == completedPhrase.songID else { continue }
            guard p.timelineEnd > loopStart - 0.08,
                  p.timelineEnd < dropTimelineStart + 0.05,
                  p.timelineStart < loopStart - 0.05,
                  abs(p.timelineEnd - loopStart) <= 0.35 || p.timelineEnd > loopStart
            else { continue }
            // Extend through the window; the sweep does the leaving.
            placements[i].timelineDuration = dropTimelineStart - p.timelineStart
            placements[i].fadeOut = ClipTransition(type: .none, duration: 0)

            // Split the window span into per-bar segments with rising blur.
            let src = placements[i]
            let bars = max(1, Int((loopDur / barSec).rounded()))
            let segDur = loopDur / Double(bars)
            // Head keeps everything before the window.
            placements[i].timelineDuration = loopStart - src.timelineStart
            for b in 0..<bars {
                var seg = src
                seg.timelineStart = loopStart + Double(b) * segDur
                seg.timelineDuration = segDur
                seg.sourceStart = src.sourceStart
                    + (seg.timelineStart - src.timelineStart) * src.tempoRatio
                seg.continuesPrevious = true
                seg.fadeIn = ClipTransition(type: .none, duration: 0)
                seg.fadeOut = ClipTransition(type: .none, duration: 0)
                var fx = seg.effects
                let ramp = Double(b + 1) / Double(bars)
                // Cap the ramp: the sweep THINS the window, it must not dig
                // an energy hole (Paramore's approach fell 11 dB when a 54
                // low-pass compounded with the lead taper — the gate allows
                // 5). Makeup on the non-lead layers pays for the LPF loss.
                fx.setLevel(
                    max(fx.level(for: MixrEffect.blur.rawValue), 14 + 32 * ramp),
                    for: MixrEffect.blur.rawValue
                )
                seg.effects = AutoSupportedEffects.sanitize(fx)
                if seg.stemKind == .vocals || seg.role == .dominant {
                    // The lead tapers so the incoming ride-in owns the ear.
                    seg.volume = src.volume * (1.0 - 0.25 * ramp)
                } else {
                    // Groove stems SWELL under the filter into the drop: the
                    // real DSP low-pass removes HF energy the offline meter
                    // never sees (real render dipped 7 dB vs the run-up with
                    // the old flat ×1.25), so makeup grows with the ramp and
                    // the remaining lows carry the approach — the DJ move.
                    seg.volume = min(
                        AutoGainPolicy.maxClipVolume,
                        src.volume * (1.25 + AutoGainPolicy.sweepSwellPerRamp * ramp)
                    )
                }
                seg.continuationShape = seg.volume / max(src.volume, 0.01)
                sweepSegments.append(seg)
            }
        }
        placements.append(contentsOf: sweepSegments)

        // One decaying echo throw of the OUTGOING last beat at the window
        // start. Echo taps decay ~0.55× each, so it reads as a throw into
        // the distance — never a loop.
        let throwSource = max(completedPhrase.sourceStart, phraseEnd - beatSec * completedPhrase.tempoRatio)
        var throwFX = ClipEffectSettings()
        throwFX.setLevel(55, for: MixrEffect.echo.rawValue)
        throwFX.echoPreset = .classic
        throwFX.setLevel(20, for: MixrEffect.blur.rawValue)
        throwFX = AutoSupportedEffects.sanitize(throwFX)
        placements.append(
            AutoClipPlacement(
                songID: completedPhrase.songID,
                sourceStart: throwSource,
                timelineStart: loopStart,
                timelineDuration: beatSec,
                tempoRatio: completedPhrase.tempoRatio,
                volume: grainVol * 0.8,
                fadeIn: ClipTransition(type: .none, duration: 0),
                fadeOut: ClipTransition(type: .echoOut, duration: 2),
                effects: throwFX,
                role: .supporting,
                slotIndex: completedPhrase.slotIndex,
                overlapsPreviousSeconds: beatSec,
                stemKind: grainStem
            )
        )
        _ = grainSource
        _ = grainSongID
        _ = resolvedStem
        _ = grainTempo

        decisions.append(
            AutoDecision(
                kind: .pivotWallpaperLoop,
                songTitle: useIncomingJoin ? deckBTitle : deckATitle,
                detail: String(
                    format: "sweep join%@ (filter ramp + echo throw, no loop) → hard cut @%.1fs",
                    pivot.map { " “\($0)”" } ?? "",
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

    /// Incoming clip swells from quiet to full while the outgoing yields.
    /// Real overlap — not both sides fading to a hole.
    static let takeoverBeats: Double = 4

    static func applyTakeoverJoin(
        prev: inout AutoClipPlacement,
        next: inout AutoClipPlacement,
        beatSec: Double,
        beats: Double = takeoverBeats
    ) {
        let overlapSec = max(beatSec, beats * beatSec)
        let needEnd = next.timelineStart + overlapSec
        if prev.timelineEnd < needEnd - 0.01 {
            prev.timelineDuration = max(prev.timelineDuration, needEnd - prev.timelineStart)
        }
        let curve = AutoTransitionEnvelope.equalPowerCurveName
        prev.fadeOut = ClipTransition(type: .crossfade, duration: beats, curve: curve)
        next.fadeIn = ClipTransition(type: .crossfade, duration: beats, curve: curve)
        next.overlapsPreviousSeconds = max(next.overlapsPreviousSeconds, overlapSec)
    }

    /// Outgoing fades down into the cut; incoming stays at full.
    /// Title-hook tokens must not sit inside an incoming swell.
    static func applyYieldJoin(
        prev: inout AutoClipPlacement,
        next: inout AutoClipPlacement,
        beats: Double = takeoverBeats,
        overhangSeconds: Double = 0
    ) {
        // Yield = fade ACROSS the entrance, not before it. With an overhang
        // the outgoing clip holds until `overhangSeconds` past the incoming
        // start, so the equal-power fade-out is mid-slope at the entrance.
        // A flush trim finishes the fade BEFORE the incoming vocal arrives —
        // a near-silent pre-title sliver that every re-validate re-created
        // after staging had extended the tail.
        let target = next.timelineStart + overhangSeconds
        if prev.timelineEnd > target + 0.05
            || (overhangSeconds > 0 && prev.timelineEnd < target - 0.05
                && prev.timelineEnd > next.timelineStart - 0.05) {
            let trimmed = target - prev.timelineStart
            if trimmed >= 0.05 {
                prev.timelineDuration = trimmed
            }
        }
        if overhangSeconds > 0 {
            next.overlapsPreviousSeconds = max(next.overlapsPreviousSeconds, overhangSeconds)
        }
        let curve = AutoTransitionEnvelope.equalPowerCurveName
        prev.fadeOut = ClipTransition(type: .crossfade, duration: beats, curve: curve)
        next.fadeIn = .hardCut
    }

    /// Clear the pivot wallpaper window and leave the blend floor under it.
    ///
    /// SINGLE SOURCE OF TRUTH for what survives `[loopStart, drop)`. The
    /// planner used to carry its own copy of this rule, so a change here was
    /// silently undone there — the same duplicated-constant failure that
    /// shipped a −4 st bed transpose.
    ///
    /// Removed: the outgoing VOCAL (a competing lead under the join is the
    /// "leftover chorus tail" failure) and drums/bass, so the kick and sub
    /// still drop out and the window keeps building tension.
    ///
    /// Kept: the bed's harmonic layer ("other"), ducked and handing over on
    /// the Drop 1 downbeat. Two decks genuinely overlapping is what makes a
    /// join read as a blend; cutting everything at `loopStart` stepped the
    /// mix from full band to one isolated stuttering vocal in a single
    /// sample, with nothing carrying through.
    static func clearPivotWindow(
        placements: inout [AutoClipPlacement],
        loopStart: Double,
        dropTimelineStart: Double,
        beatSec: Double
    ) {
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

        // NOTE: the blend floor is NOT added here. Bed stem clips do not exist
        // yet at this point in planning, so a pass here sees nothing to carry
        // through. AutoRemixValidator.addPivotBlendFloor does it on the
        // finished plan.
    }

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
                // Sample-continuous segment splits (the pivot sweep's ramp
                // pieces) are NOT title copies — treating them as such put
                // the ASR duck (0.18) under the whole pivot window and dug
                // an 11 dB hole into the drop approach.
                && !$0.continuesPrevious
                && !nearDrop($0.timelineStart)
                && $0.timelineStart < (dropStarts.min() ?? .infinity) - barSec * 0.25
                && $0.timelineDuration > beatSec * 2
        }
        // Intro / verse full-mix must not keep playing under the isolated
        // title vocal. Trim just past the title start with an equal-power
        // fade that OVERLAPS the entrance by one beat — trimming flush at
        // the title start leaves a near-silent hole while the fade finishes
        // before the ducked stems arrive. One fading beat of full-mix tail
        // under the first word keeps energy continuous without burying ASR.
        if let hookStart = titleVocalWindows.map(\.timelineStart).min() {
            for i in placements.indices {
                let p = placements[i]
                guard p.role == .dominant, p.stemKind != .vocals else { continue }
                // A clip spanning the entrance is trimmed to one beat past
                // it; a clip ending flush at the entrance is EXTENDED one
                // beat past it. Either way the equal-power fade-out crosses
                // the title start instead of completing before it (which
                // left a near-silent pre-title hole).
                let spans = p.timelineStart < hookStart - 0.05 && p.timelineEnd > hookStart + 0.05
                let endsFlush = p.timelineStart < hookStart - 0.05
                    && abs(p.timelineEnd - hookStart) <= max(0.1, beatSec * 0.6)
                guard spans || endsFlush else { continue }
                placements[i].timelineDuration = max(0.05, hookStart + beatSec - p.timelineStart)
                placements[i].overlapsPreviousSeconds = 0
                placements[i].fadeOut = ClipTransition(
                    type: .crossfade,
                    duration: 2,
                    curve: AutoTransitionEnvelope.equalPowerCurveName
                )
            }
            for i in placements.indices where isTitleHookCopy(placements[i])
                && abs(placements[i].timelineStart - hookStart) < 0.05 {
                placements[i].overlapsPreviousSeconds = max(
                    placements[i].overlapsPreviousSeconds, beatSec
                )
            }
        }
        // Stacked drums+bass+other at planner duck (~0.62 each) bury the
        // isolated title token. Offline mixdown has no blur DSP, so volume
        // must carry the duck. Cap overlapping supporting stems and any
        // full-mix duplicate under the title; never the vocal.
        //
        // The hard duck is TIME-LIMITED: it holds for the ASR probe window
        // (first ~4 s of each title vocal window) and then releases to
        // `titleInstrumentalOpenVolume`, so rests between vocal lines keep
        // the groove instead of collapsing into near-silence holes.
        // Placements spanning the release point are split sample-continuously.
        // dB TARGETS, not constants: each instrumental stem sits a fixed
        // distance under the title vocal, solved from measured stem LUFS
        // (analysis.json). The linear constants remain the no-sidecar
        // fallback — they were tuned for one recording and are exactly why
        // "loudness feels unnatural" tracked source changes.
        func targetVol(under targetDB: Double, stem kind: AutoStemKind,
                       songID: UUID, vocalVol: Double, fallback: Double) -> Double {
            if ProcessInfo.processInfo.environment["MIXR_NO_DBTARGETS"] == "1" { return fallback }
            guard let loud = profiles[songID]?.loudness,
                  let stemL = loud.stems[kind]?.lufs,
                  let vocalL = loud.stems[.vocals]?.lufs
            else { return fallback }
            let v = vocalVol * pow(10.0, (vocalL - stemL + targetDB) / 20.0)
            return min(max(v, fallback * 0.5), fallback * 2.2)
        }
        let duckVol = AutoGainPolicy.roleStagingVolume(role: .titleBed)
        // The duck is a RATIO, not an absolute level. Vocal makeup is now
        // measured per song (analysis.json), so an isolated title vocal can
        // land 1–2 dB hotter on one track than another; a fixed floor then
        // widens the vocal-to-bed contrast on exactly those songs and the
        // vocal's own inter-line rests read as dead air. Scaling the floor
        // with the vocal keeps the contrast invariant to makeup gain.
        let titleVocalVolume = titleVocalWindows
            .filter { $0.stemKind == .vocals }
            .map(\.volume)
            .max() ?? AutoGainPolicy.vocalStemMakeupDefault
        let openRatio = AutoGainPolicy.titleInstrumentalOpenVolume
            / max(AutoGainPolicy.vocalStemMakeupDefault, 0.01)
        let openFallback = min(
            AutoGainPolicy.maxClipVolume,
            max(AutoGainPolicy.titleInstrumentalOpenVolume, titleVocalVolume * openRatio)
        )
        // The hard 0.18 duck exists so ASR hears the title WORD — so it
        // starts at the vocal ONSET, not the clip edge. Title clips pad
        // beats before the word, and the vocal stem is silent through that
        // pad; ducking the instrumentals under stem silence carved a ~1.3 s
        // −30 dB hole at every title entrance ("dead air @26.85/@40.0" in
        // paramore-x-tatu the moment the anchor moved ahead of "All"). The
        // pad rides at open volume; the duck begins with the voice.
        let probeIntervals: [(Double, Double)] = titleVocalWindows.map { v in
            var onset = v.timelineStart
            if let signal = profiles[v.songID]?.analysis.signal {
                let ratio = max(v.tempoRatio, 0.0001)
                let limit = min(1.6, v.timelineDuration * 0.5)
                var probe = 0.0
                while probe < limit {
                    let src = v.sourceStart + probe * ratio
                    // −35, not −45: the duck must engage when the voice is
                    // properly SOUNDING, not on its first faint pre-attack —
                    // ducking a beat early left a 0.35 s sliver of ducked
                    // bed under no voice at every pad→probe seam.
                    if signal.meanStemVocalRMSDB(from: src, to: src + 0.12) > -35 { break }
                    probe += 0.1
                }
                if probe > 0.05, probe < limit {
                    onset = v.timelineStart + max(0, probe - 0.02)
                }
            }
            return (onset, onset + AutoGainPolicy.titleDuckProbeSeconds)
        }
        func inProbe(_ t: Double) -> Bool {
            probeIntervals.contains { t >= $0.0 - 0.01 && t < $0.1 - 0.01 }
        }
        var splitTail: [AutoClipPlacement] = []
        for i in placements.indices {
            let p = placements[i]
            if p.stemKind == .vocals { continue }
            if isPivotGrain(p) { continue }
            let maxOverlap = titleVocalWindows.map { v in
                min(v.timelineEnd, p.timelineEnd) - max(v.timelineStart, p.timelineStart)
            }.max() ?? 0
            guard maxOverlap > beatSec * 0.5 else { continue }
            if p.stemKind == nil {
                // A full-mix duplicate RUNNING under the title gets muted —
                // but a one-beat equal-power fade tail crossing the entrance
                // is the handoff overlap, not a duplicate. Muting it re-opens
                // the pre-title hole.
                if maxOverlap > beatSec * 1.25 {
                    placements[i].volume = 0
                }
                continue
            }
            // Boundaries where the duck state flips inside this placement.
            var cuts: [Double] = []
            for (s, e) in probeIntervals {
                for b in [s, e] where b > p.timelineStart + 0.05 && b < p.timelineEnd - 0.05 {
                    cuts.append(b)
                }
            }
            cuts.sort()
            let edges = [p.timelineStart] + cuts + [p.timelineEnd]
            var segments: [AutoClipPlacement] = []
            for k in 0..<(edges.count - 1) {
                let segStart = edges[k]
                let segEnd = edges[k + 1]
                guard segEnd - segStart > 0.01 else { continue }
                var seg = p
                seg.timelineStart = segStart
                seg.timelineDuration = segEnd - segStart
                seg.sourceStart = p.sourceStart + (segStart - p.timelineStart) * p.tempoRatio
                let mid = (segStart + segEnd) / 2
                let duckHere = targetVol(
                    under: -9.0, stem: p.stemKind ?? .other, songID: p.songID,
                    vocalVol: titleVocalVolume, fallback: duckVol
                )
                let openHere = targetVol(
                    under: -3.5, stem: p.stemKind ?? .other, songID: p.songID,
                    vocalVol: titleVocalVolume, fallback: openFallback
                )
                // Hold variation lives HERE, where levels are final: when
                // the title hold plays the same source twice, pass 1's
                // backing opens STRIPPED (×0.55) and pass 2 full — staging
                // used to re-raise the validator's thinning and the two
                // passes came out identical again (backing 1.86 vs 1.86).
                var passScale = 1.0
                let myWindow = titleVocalWindows.first {
                    p.timelineStart >= $0.timelineStart - 0.1 && p.timelineStart < $0.timelineEnd
                }
                if let myWindow {
                    let twins = titleVocalWindows.filter {
                        abs($0.sourceStart - myWindow.sourceStart) < 0.1
                    }.sorted { $0.timelineStart < $1.timelineStart }
                    if twins.count >= 2, abs(twins[0].timelineStart - myWindow.timelineStart) < 0.1 {
                        passScale = 0.55
                    }
                }
                // Probe caps DOWN (min); the open region ASSIGNS its level.
                // Stems can arrive here already capped to the 0.18 title-bed
                // duck by the earlier overlap cap, and min() can never
                // re-open — every post-probe segment then sat at duck level
                // and the whole title window rendered as a −34 dB pit.
                seg.volume = inProbe(mid)
                    ? min(p.volume, duckHere)
                    : min(max(p.volume, openHere * passScale), AutoGainPolicy.maxClipVolume)
                seg.continuesPrevious = k > 0 || p.continuesPrevious
                if k > 0 { seg.fadeIn = .hardCut }
                if k < edges.count - 2 { seg.fadeOut = .hardCut }
                segments.append(seg)
            }
            guard var first = segments.first else { continue }
            first.continuesPrevious = p.continuesPrevious
            placements[i] = first
            splitTail.append(contentsOf: segments.dropFirst())
        }
        placements.append(contentsOf: splitTail)
        placements.sort { $0.timelineStart < $1.timelineStart }
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
        // Grains need to be "at least as loud as the bed verse and the
        // title-hook vocal copy" — NOT louder. `dropVsIsolatedTitleBoost` is
        // Drop 1's floor, so that it out-punches an isolated title vocal;
        // applying it here too put the chop +6.4 dB above the vocal that
        // preceded it, and the mix's most salient element jumping that far in
        // one sample is heard as the chop slamming in from nowhere. The
        // wallpaper still cannot go quiet — the floor is the title vocal.
        for i in placements.indices where isPivotGrain(placements[i]) {
            placements[i].volume = min(
                AutoGainPolicy.maxClipVolume,
                max(placements[i].volume, titleVol)
            )
        }
        carryStagingIntoContinuations(placements: &placements)
    }

    /// Sample-continuous segments (the sweep join's per-bar pieces) are
    /// continuations of the clip they follow, not new clips — staging
    /// raises the head (title-window open, vocal makeup) but skipped them,
    /// so the window started with a −7…−9 dB cliff the listen loop could
    /// only report (dropDip residual on every sweep join). Each segment
    /// now carries the staged level of the placement it continues, keeping
    /// the planner's relative shaping (lead taper, bed makeup) on top.
    static func carryStagingIntoContinuations(placements: inout [AutoClipPlacement]) {
        func predecessor(of i: Int) -> Int? {
            let seg = placements[i]
            return placements.indices.first { k in
                k != i
                    && placements[k].songID == seg.songID
                    && placements[k].stemKind == seg.stemKind
                    && placements[k].role == seg.role
                    && abs(placements[k].timelineEnd - seg.timelineStart) < 0.03
            }
        }
        let order = placements.indices.sorted { placements[$0].timelineStart < placements[$1].timelineStart }
        for i in order {
            guard placements[i].continuesPrevious, let shape = placements[i].continuationShape else { continue }
            // Walk back through sweep segments to the clip the window
            // continues: the FIRST predecessor that is not a sweep segment.
            // (Staging's own probe/open split is sample-continuous too —
            // walking past the open piece landed on the 0.40 probe duck.)
            var head = i
            var hops = 0
            while placements[head].continuationShape != nil, hops < 16,
                  let j = predecessor(of: head) {
                head = j
                hops += 1
            }
            guard head != i, placements[head].continuationShape == nil else { continue }
            placements[i].volume = min(AutoGainPolicy.maxClipVolume, placements[head].volume * shape)
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
        // Offline BS.1770-4 measurement beats the constant. The default
        // assumes every vocal stem sits 4.0 dB under its mix; measured across
        // the crate it ranges 3.6…5.8 dB, so the constant is ~2 dB low on most
        // songs. Only used when an analysis.json sidecar exists.
        if let measured = profiles[p.songID]?.loudness?.makeupGain(for: .vocals),
           measured.isFinite, measured > 0.05 {
            return min(AutoGainPolicy.maxClipVolume, measured)
        }
        return AutoGainPolicy.vocalStemMakeupDefault
    }
}
