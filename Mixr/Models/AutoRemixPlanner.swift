import Foundation

// MARK: - Auto Remix Planner
//
// Generates an AutoRemixPlan from the project's songs:
//
//   1 song   → REMIX: rearranged hook-forward edit with hype SFX
//   2 songs  → MASHUP: A → B → A → B → A (roles switch, ≥3 handoffs)
//   3 songs  → MASHUP: A → B → A → C → B → C → A
//   4 songs  → MASHUP: A → B → C → A → D → B → C → A
//   5+ songs → MASHUP: anchor-and-rotation (A → B → C → A → D → E → B → A …)
//
// Every handoff picks ONE primary transition recipe; SFX arrive as
// coordinated events (riser + impact = one moment); low-confidence songs
// degrade to clean phrase-aligned crossfades.

enum AutoRemixPlanner {

    // MARK: Slot model

    private struct Slot {
        var songIdx: Int                            // index into letter-ordered profiles
        var role: AutoCandidateSection.Label
        var bars: Int
        var entry: AutoTransitionRecipe             // transition INTO this slot
        var energy: Double                          // 0…1 volume/energy story
        var isFinalPeak = false
        var isEnding = false
        /// Second+ use of the same hook must vary its treatment.
        var isReturn = false
        /// Shrink priority when the arrangement exceeds the timeline budget
        /// (higher shrinks first).
        var shrinkPriority = 1
    }

    private struct PlacedSlot {
        var slot: Slot
        var section: AutoCandidateSection
        var timelineStart: Double
        var timelineDuration: Double
        var tempoRatio: Double
        var reusedSection: Bool
    }

    // MARK: Entry point

    /// Draft plan only (no validation). Prefer `AutoRemixRunner` for the
    /// full draft → validate → apply → summary path.
    static func makePlan(
        tracks: [MixrTrack],
        tuning: AutoTuning = .standard,
        seed: UInt64 = UInt64(Date().timeIntervalSince1970),
        signals: [UUID: SongSignalFeatures] = [:]
    ) -> (plan: AutoRemixPlan, profiles: [UUID: AutoSongProfile])? {
        let songTracks = tracks.filter { !$0.isSFXTrack && !$0.clips.isEmpty }
        guard !songTracks.isEmpty else { return nil }

        let profiles = songTracks.map {
            AutoSectionCatalog.profile(track: $0, tuning: tuning, signal: signals[$0.id])
        }
        var rng = AutoRandom(seed: seed)

        let plan: AutoRemixPlan?
        if profiles.count == 1 {
            plan = remixPlan(profile: profiles[0], tuning: tuning, seed: seed, rng: &rng)
        } else {
            plan = mashupPlan(profiles: profiles, tuning: tuning, seed: seed, rng: &rng)
        }
        guard let plan else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.songID, $0) })
        return (plan, byID)
    }

    /// Builds and validates a plan. Returns nil when there is nothing to arrange.
    static func makeValidatedPlan(
        tracks: [MixrTrack],
        tuning: AutoTuning = .standard,
        seed: UInt64 = UInt64(Date().timeIntervalSince1970),
        signals: [UUID: SongSignalFeatures] = [:]
    ) -> AutoRemixPlan? {
        guard let (plan, profiles) = makePlan(
            tracks: tracks, tuning: tuning, seed: seed, signals: signals
        ) else {
            return nil
        }
        return AutoRemixValidator.validate(plan, profiles: profiles, tuning: tuning)
    }

    /// Builds the user-facing summary for a validated / applied plan.
    static func summary(for plan: AutoRemixPlan, tracks: [MixrTrack]) -> AutoRemixSummary {
        func title(_ id: UUID) -> String {
            tracks.first { $0.id == id }?.title ?? "Unknown Song"
        }
        let legend = plan.songLetters
            .sorted { $0.value < $1.value }
            .map { "\($0.value) — \(title($0.key))" }

        var effectNames = Set<String>()
        for p in plan.placements {
            let fx = p.effects
            if fx.level(for: MixrEffect.reverb.rawValue) > 0.5 {
                effectNames.insert("Reverb (\(fx.reverbPreset.title))")
            }
            if fx.level(for: MixrEffect.echo.rawValue) > 0.5 {
                effectNames.insert("Echo (\(fx.echoPreset.title))")
            }
            if fx.level(for: MixrEffect.blur.rawValue) > 0.5 { effectNames.insert("Blur") }
            if fx.flangerAmount > 0.005 { effectNames.insert("Flanger") }
            if fx.pitchAmount > 0.005 {
                effectNames.insert("Pitch \(fx.pitchDirection == .up ? "Up" : "Down")")
            }
        }
        let sfxNames = Array(Set(plan.sfxEvents.compactMap {
            SoundEffectLibrary.definition(for: $0.assetID)?.title
        })).sorted()

        let sequenceTitles = plan.sequenceTitles.isEmpty
            ? plan.sequence.compactMap { letter in
                plan.songLetters.first { $0.value == letter }.map { title($0.key) }
            }
            : plan.sequenceTitles

        let displaySequence = dedupedSequence(sequenceTitles).joined(separator: " → ")

        return AutoRemixSummary(
            modeTitle: plan.mode.rawValue,
            targetBPM: Int(plan.targetBPM.rounded()),
            anchorNames: plan.anchorSongIDs.map(title),
            sequence: displaySequence.isEmpty
                ? dedupedSequence(plan.sequence).joined(separator: " → ")
                : displaySequence,
            handoffCount: plan.handoffCount,
            songLegend: legend,
            transitionRecipes: Array(Set(plan.transitionsUsed.map(\.rawValue))).sorted(),
            effectsUsed: effectNames.sorted(),
            sfxUsed: sfxNames,
            decisions: plan.decisions.map(\.userFacingSentence),
            warnings: plan.warnings,
            randomSeed: plan.randomSeed
        )
    }

    private static func dedupedSequence(_ letters: [String]) -> [String] {
        var out: [String] = []
        for l in letters where l != out.last { out.append(l) }
        return out
    }

    // MARK: - Remix (one song, preservation-first)
    //
    // A one-song Auto Remix PRESERVES the song: one continuous placement
    // covering the usable source range, trimmed only where measured
    // evidence shows silence at the edges. Internal cuts default to ZERO;
    // any cut requires signal evidence, a structured AutoCutRecord, and
    // an audible masking layer — never a cut for variety. Effects ride on
    // source-continuous segment splits, not structural edits. When
    // analysis confidence is low the result is a nearly untouched song.

    private static func remixPlan(
        profile: AutoSongProfile,
        tuning: AutoTuning,
        seed: UInt64,
        rng: inout AutoRandom
    ) -> AutoRemixPlan? {
        let analysis = profile.analysis
        let duration = analysis.durationSeconds
        guard duration > 1 else { return nil }
        let bpm = analysis.bpm
        let beat = 60.0 / max(bpm, 40)
        let bar = beat * 4

        var decisions: [AutoDecision] = [
            AutoDecision(kind: .selectedAnchor, songTitle: profile.title, detail: "remix — preservation-first")
        ]
        var warnings: [String] = []

        let signal = analysis.signal
        let signalTrusted = (signal?.overallConfidence ?? 0) >= 0.4

        // ── Usable range: trim only MEASURED edge silence ──
        var usableStart = 0.0
        var usableEnd = duration
        if let signal, signalTrusted {
            if signal.leadingSilenceSeconds > 0.35 {
                usableStart = max(0, signal.leadingSilenceSeconds - 0.15)
                decisions.append(
                    AutoDecision(
                        kind: .skippedIntro,
                        songTitle: profile.title,
                        detail: String(format: "%.1fs of leading silence", signal.leadingSilenceSeconds)
                    )
                )
            }
            if signal.trailingSilenceSeconds > 0.35 {
                usableEnd = min(duration, duration - signal.trailingSilenceSeconds + 0.15)
                decisions.append(
                    AutoDecision(
                        kind: .shortenedLowEnergySection,
                        songTitle: profile.title,
                        detail: String(format: "trailing silence (%.1fs)", signal.trailingSilenceSeconds)
                    )
                )
            }
        }
        if usableEnd - usableStart < max(tuning.minSegmentSeconds, 8.0) {
            usableStart = 0
            usableEnd = duration
            warnings.append("Edge trimming would have removed too much material; kept the full source.")
        }

        // Timeline budget: trim the END, never chop the middle.
        var trimmedForBudget = false
        if usableEnd - usableStart > tuning.maxTimelineSeconds {
            usableEnd = usableStart + tuning.maxTimelineSeconds
            trimmedForBudget = true
            decisions.append(
                AutoDecision(
                    kind: .shortenedForMaterial,
                    songTitle: profile.title,
                    detail: "ending to fit the timeline"
                )
            )
        }

        let confident = signalTrusted
            && analysis.analysisConfidence >= tuning.lowConfidenceThreshold
            && (signal?.beatConfidence ?? 0) > 0.4
        if !confident {
            decisions.append(
                AutoDecision(kind: .usedLowConfidenceFallback, songTitle: profile.title, detail: nil)
            )
        }

        let volume = AutoGainPolicy.preservationSongVolume

        // A trailing fade only when we cut into audible material.
        let endsMidAudio = trimmedForBudget
            || (usableEnd < duration - 0.05 && (signal.map { $0.trailingSilenceSeconds <= 0.35 } ?? true))
        let finalFadeOut: ClipTransition = endsMidAudio
            ? ClipTransition(type: .fadeOut, duration: 2, curve: AutoTransitionEnvelope.equalPowerCurveName)
            : .none

        // ── Transformation recipe: measured structure → scored
        // opportunities → varied, distributed selection ──
        var structure = AutoRemixStructureMap.empty
        structure.usableRange = usableStart...usableEnd
        var recipe = AutoRemixRecipe.empty
        if confident {
            structure = AutoRemixStructureMapBuilder.build(
                analysis: analysis,
                usableRange: usableStart...usableEnd,
                tuning: tuning
            )
            let opportunities = AutoRemixOpportunityGenerator.opportunities(
                structure: structure,
                analysis: analysis,
                tuning: tuning
            )
            recipe = AutoRemixRecipePlanner.recipe(
                from: opportunities,
                structure: structure,
                tuning: tuning,
                seed: seed
            )
        }

        // ── Assembly: walk the usable range in source order, applying
        // the recipe. Structural removals crossfade ACROSS the removed
        // material (real temporal overlap); loops rewind briefly with a
        // justified record; DSP zones are source-continuous splits. ──
        let crossfadeSeconds = min(1.5, beat * 4)
        struct Removal {
            var start: Double
            var end: Double
            var op: AutoRemixOpportunity
        }
        var removals: [Removal] = []
        var loops: [AutoRemixOpportunity] = []
        var dspZones: [AutoRemixOpportunity] = []
        var hookReturnOp: AutoRemixOpportunity?
        for op in recipe.selected {
            switch op.kind {
            case .shortenRepeat, .outroCompress:
                removals.append(Removal(start: op.zoneStart, end: op.zoneEnd, op: op))
            case .loopStutter:
                loops.append(op)
            case .hookReturn:
                hookReturnOp = op
            case .filteredBuild, .echoThrow, .partialDropout, .finalChorusLift:
                dspZones.append(op)
            case .sfxAccent:
                break
            }
        }
        removals.sort { $0.start < $1.start }
        dspZones.removeAll { zone in
            removals.contains { max(zone.zoneStart, $0.start) < min(zone.zoneEnd, $0.end) - 0.01 }
        }

        // A DSP effect can only live on a clip that meets the model's
        // minimum length; a sub-minimum zone would be dropped by the
        // validator and lost. Expand short zones BACKWARD (the effect
        // leads into its anchor) to a valid whole-bar length, clamped so
        // they never cross a removal, another zone, or the usable start.
        let minZone = tuning.minSegmentSeconds + 0.15
        dspZones.sort { $0.zoneStart < $1.zoneStart }
        for i in dspZones.indices {
            var z = dspZones[i]
            guard z.zoneEnd - z.zoneStart < minZone else { continue }
            // The zone END is the musically important edge (a phrase
            // boundary); its START sits inside continuous material, so it
            // need not be bar-aligned. Extend back just enough for a
            // valid clip, clamped to the prior removal/zone/usable start.
            let lowerClamp = max(
                usableStart,
                removals.filter { $0.end <= z.zoneStart + 0.01 }.map(\.end).max() ?? usableStart,
                i > 0 ? dspZones[i - 1].zoneEnd : usableStart
            )
            let newStart = max(z.zoneEnd - minZone, lowerClamp)
            if z.zoneEnd - newStart >= tuning.minSegmentSeconds {
                z.zoneStart = newStart
                dspZones[i] = z
            }
        }
        // Drop any zone that still can't reach a valid length (no room).
        let droppedForRoom = dspZones.filter { $0.zoneEnd - $0.zoneStart < tuning.minSegmentSeconds }
        dspZones.removeAll { $0.zoneEnd - $0.zoneStart < tuning.minSegmentSeconds }
        for op in droppedForRoom {
            warnings.append(
                "Remix zone dropped: \(op.kind.rawValue) had no room for a minimum-length clip."
            )
        }

        func effectsFor(_ op: AutoRemixOpportunity) -> ClipEffectSettings {
            var fx = ClipEffectSettings()
            switch op.kind {
            case .filteredBuild:
                fx.setLevel(55, for: MixrEffect.blur.rawValue)
                fx.setLevel(10, for: MixrEffect.echo.rawValue)
                fx.echoPreset = .classic
                fx.flangerAmount = 0.15
            case .echoThrow:
                fx.setLevel(35, for: MixrEffect.echo.rawValue)
                fx.echoPreset = .classic
            case .partialDropout:
                fx.setLevel(50, for: MixrEffect.blur.rawValue)
            case .finalChorusLift:
                fx.setLevel(18, for: MixrEffect.echo.rawValue)
                fx.echoPreset = .classic
                fx.setLevel(10, for: MixrEffect.reverb.rawValue)
                fx.reverbPreset = .hall
                fx.flangerAmount = 0.12
            default:
                break
            }
            return AutoSupportedEffects.sanitize(fx)
        }

        // Segment boundaries in source time (milliseconds for stable keys).
        var boundaryKeys = Set<Int>()
        func addBoundary(_ t: Double) {
            if t > usableStart + 0.01, t < usableEnd - 0.01 {
                boundaryKeys.insert(Int((t * 1000).rounded()))
            }
        }
        for removal in removals {
            addBoundary(removal.start)
            addBoundary(removal.end)
        }
        for zone in dspZones {
            addBoundary(zone.zoneStart)
            addBoundary(zone.zoneEnd)
        }
        for loop in loops {
            addBoundary(loop.zoneStart)
            addBoundary(loop.zoneEnd)
        }
        let sortedBoundaries = ([usableStart, usableEnd] + boundaryKeys.map { Double($0) / 1000 })
            .sorted()

        var placements: [AutoClipPlacement] = []
        var cutRecords: [AutoCutRecord] = []
        var timeline = 0.0
        var pendingCut: Removal?
        var slot = 0

        func crossfadeTransition() -> ClipTransition {
            ClipTransition(
                type: .crossfade,
                duration: crossfadeSeconds / beat,
                curve: AutoTransitionEnvelope.equalPowerCurveName
            )
        }

        func emit(
            sourceStart: Double,
            sourceEnd: Double,
            fx: ClipEffectSettings,
            volumeScale: Double,
            transformationID: UUID?
        ) {
            guard sourceEnd - sourceStart > 0.01 else { return }
            var fadeIn = ClipTransition.none
            var overlap = 0.0
            var continues = false
            var tid = transformationID
            var record: AutoCutRecord?
            var startTimeline = timeline

            if let cut = pendingCut {
                pendingCut = nil
                if var prev = placements.popLast() {
                    prev.timelineDuration += crossfadeSeconds
                    prev.fadeOut = crossfadeTransition()
                    placements.append(prev)
                    startTimeline = prev.timelineEnd - crossfadeSeconds
                    overlap = crossfadeSeconds
                    fadeIn = crossfadeTransition()
                    if tid == nil { tid = cut.op.id }
                    let before = signal?.meanRMSDB(from: cut.start - 2, to: cut.start) ?? -20
                    let after = signal?.meanRMSDB(from: cut.end, to: cut.end + 2) ?? -20
                    record = AutoCutRecord(
                        timelineAt: startTimeline,
                        sourceFrom: cut.start,
                        sourceTo: cut.end,
                        reason: cut.op.kind == .outroCompress ? .edgeTrim : .redundantRepeat,
                        confidence: cut.op.confidence,
                        expectedEnergyDeltaDB: after - before,
                        masking: .equalPowerCrossfade(seconds: crossfadeSeconds)
                    )
                }
            } else if !placements.isEmpty {
                continues = true
            }

            placements.append(
                AutoClipPlacement(
                    songID: profile.songID,
                    sourceStart: sourceStart,
                    timelineStart: startTimeline,
                    timelineDuration: sourceEnd - sourceStart,
                    tempoRatio: 1.0,
                    volume: volume * volumeScale,
                    fadeIn: fadeIn,
                    fadeOut: .none,
                    effects: fx,
                    role: .dominant,
                    slotIndex: slot,
                    continuesPrevious: continues,
                    overlapsPreviousSeconds: overlap,
                    transformationID: tid
                )
            )
            slot += 1
            if let record { cutRecords.append(record) }
            timeline = startTimeline + (sourceEnd - sourceStart)
        }

        for (intervalStart, intervalEnd) in zip(sortedBoundaries, sortedBoundaries.dropFirst()) {
            guard intervalEnd - intervalStart > 0.01 else { continue }
            let mid = (intervalStart + intervalEnd) / 2

            if let removal = removals.first(where: { mid >= $0.start && mid < $0.end }) {
                if pendingCut == nil { pendingCut = removal }
                continue
            }

            let zone = dspZones.first { mid >= $0.zoneStart && mid < $0.zoneEnd }
            emit(
                sourceStart: intervalStart,
                sourceEnd: intervalEnd,
                fx: zone.map(effectsFor) ?? ClipEffectSettings(),
                // Moderated depth (−8 dB): the dropout zone is a phrase
                // pullback into the return, not a momentary hole.
                volumeScale: zone?.kind == .partialDropout ? 0.4 : 1.0,
                transformationID: zone?.id
            )

            // Beat-synchronous loop: repeat the just-emitted zone once,
            // as a justified source rewind with a structured record.
            if let loop = loops.first(where: {
                abs($0.zoneStart - intervalStart) < 0.02 && abs($0.zoneEnd - intervalEnd) < 0.05
            }) {
                let loopDuration = intervalEnd - intervalStart
                placements.append(
                    AutoClipPlacement(
                        songID: profile.songID,
                        sourceStart: intervalStart,
                        timelineStart: timeline,
                        timelineDuration: loopDuration,
                        tempoRatio: 1.0,
                        volume: volume,
                        fadeIn: .none,
                        fadeOut: .none,
                        effects: ClipEffectSettings(),
                        role: .dominant,
                        slotIndex: slot,
                        transformationID: loop.id
                    )
                )
                slot += 1
                cutRecords.append(
                    AutoCutRecord(
                        timelineAt: timeline,
                        sourceFrom: intervalEnd,
                        sourceTo: intervalStart,
                        reason: .loop,
                        confidence: loop.confidence,
                        expectedEnergyDeltaDB: 0,
                        masking: .alignedHardCut
                    )
                )
                timeline += loopDuration
            }
        }

        // Hook return for the close: one justified rewind, crossfaded.
        if let op = hookReturnOp, var prev = placements.popLast() {
            prev.timelineDuration += crossfadeSeconds
            prev.fadeOut = crossfadeTransition()
            let prevSourceEnd = prev.sourceEnd
            placements.append(prev)
            let startTimeline = prev.timelineEnd - crossfadeSeconds
            placements.append(
                AutoClipPlacement(
                    songID: profile.songID,
                    sourceStart: op.zoneStart,
                    timelineStart: startTimeline,
                    timelineDuration: op.zoneEnd - op.zoneStart,
                    tempoRatio: 1.0,
                    volume: volume,
                    fadeIn: crossfadeTransition(),
                    fadeOut: .none,
                    effects: ClipEffectSettings(),
                    role: .dominant,
                    slotIndex: slot,
                    overlapsPreviousSeconds: crossfadeSeconds,
                    transformationID: op.id
                )
            )
            slot += 1
            cutRecords.append(
                AutoCutRecord(
                    timelineAt: startTimeline,
                    sourceFrom: prevSourceEnd,
                    sourceTo: op.zoneStart,
                    reason: .hookReturn,
                    confidence: op.confidence,
                    expectedEnergyDeltaDB: 0,
                    masking: .equalPowerCrossfade(seconds: crossfadeSeconds)
                )
            )
            timeline = startTimeline + (op.zoneEnd - op.zoneStart)
        }

        // Trailing fade: the song either ends naturally or fades where a
        // trim / hook return leaves audible material.
        if var last = placements.popLast() {
            if last.fadeOut.type == .none {
                last.fadeOut = hookReturnOp != nil
                    ? ClipTransition(
                        type: .fadeOut, duration: 2,
                        curve: AutoTransitionEnvelope.equalPowerCurveName
                    )
                    : finalFadeOut
            }
            placements.append(last)
        }

        // ── SFX: reinforce the top transformation zones only ──
        var sfx: [AutoSFXEvent] = []
        func timelineFor(sourceTime t: Double) -> Double? {
            for p in placements where t >= p.sourceStart - 0.01 && t < p.sourceEnd + 0.01 {
                return p.timelineStart + (t - p.sourceStart)
            }
            return nil
        }
        let sfxKinds: Set<AutoTransformationKind> = [.filteredBuild, .partialDropout, .shortenRepeat]
        for op in recipe.selected.filter({ sfxKinds.contains($0.kind) })
            .sorted(by: { $0.score > $1.score })
            .prefix(2) {
            let sourceAnchor = op.kind == .shortenRepeat ? op.zoneEnd : op.anchorDownbeat
            guard let anchorTimeline = timelineFor(sourceTime: sourceAnchor) else { continue }
            if let riser = SoundEffectLibrary.definition(for: "riser"),
               anchorTimeline - riser.durationSeconds >= 0 {
                sfx.append(
                    AutoSFXEvent(
                        assetID: "riser",
                        timelineStart: anchorTimeline - riser.durationSeconds,
                        purpose: "riser into the \(op.kind.rawValue) zone",
                        transformationID: op.id
                    )
                )
            }
            sfx.append(
                AutoSFXEvent(
                    assetID: "impact",
                    timelineStart: anchorTimeline,
                    purpose: "impact on the \(op.kind.rawValue) downbeat",
                    transformationID: op.id
                )
            )
        }

        // ── Decisions + unmet-target visibility ──
        for op in recipe.selected {
            decisions.append(
                AutoDecision(
                    kind: .transformedZone,
                    songTitle: profile.title,
                    detail: transformationSentence(op, bar: bar)
                )
            )
        }
        warnings.append(contentsOf: recipe.unmetTargets.map { "Remix target unmet: \($0)." })

        let totalDuration = max(timeline, placements.map(\.timelineEnd).max() ?? 0)
        let section = AutoSelectedSection(
            songID: profile.songID,
            sourceStart: usableStart,
            sourceEnd: usableEnd,
            phraseType: "song",
            barCount: Int((totalDuration / bar).rounded()),
            hookScore: 1.0,
            energyScore: analysis.meanEnergy(from: usableStart, to: usableEnd),
            vocalDensity: analysis.meanVocalDensity(from: usableStart, to: usableEnd),
            compatibilityRole: .dominant,
            confidence: analysis.analysisConfidence
        )

        return AutoRemixPlan(
            mode: .remix,
            targetBPM: bpm,
            targetDuration: totalDuration,
            anchorSongIDs: [profile.songID],
            selectedSections: [section],
            placements: placements,
            sfxEvents: sfx,
            cutRecords: cutRecords,
            remixRecipe: recipe,
            structureMap: confident ? structure : nil,
            usableSourceRange: usableStart...usableEnd,
            intentionalGaps: [],                  // silence only by explicit recipe
            handoffCount: 0,
            songLetters: [profile.songID: "A"],
            sequence: ["A"],
            sequenceTitles: [profile.title],
            transitionsUsed: [],
            decisions: decisions,
            warnings: warnings,
            confidence: analysis.analysisConfidence,
            randomSeed: seed
        )
    }

    /// User-facing sentence for one applied transformation.
    private static func transformationSentence(_ op: AutoRemixOpportunity, bar: Double) -> String {
        let bars = Int((op.zoneDuration / max(bar, 0.001)).rounded())
        switch op.kind {
        case .filteredBuild:
            return "Filtered build into a measured entrance (\(bars) bars)."
        case .echoThrow:
            return "Echo throw on a vocal phrase ending."
        case .partialDropout:
            return "Brief dropout before the return."
        case .shortenRepeat:
            return "Shortened repeated material (\(bars) bars) under a masked crossfade."
        case .outroCompress:
            return "Compressed the outro (\(bars) bars)."
        case .loopStutter:
            return "Stuttered the hook entrance (1-bar loop)."
        case .finalChorusLift:
            return "Intensified the final chorus with an effect arc."
        case .hookReturn:
            return "Returned to the hook for the close."
        case .sfxAccent:
            return "Accented a transformation with SFX."
        }
    }

    // MARK: - Mashup (2+ songs)

    private static func mashupPlan(
        profiles: [AutoSongProfile],
        tuning: AutoTuning,
        seed: UInt64,
        rng: inout AutoRandom
    ) -> AutoRemixPlan? {
        guard let anchor = profiles.max(by: { $0.anchorScore < $1.anchorScore }) else { return nil }
        let features = profiles
            .filter { $0.songID != anchor.songID }
            .sorted { $0.featureScore > $1.featureScore }
        var ordered = [anchor] + features

        var preDecisions: [AutoDecision] = [
            AutoDecision(kind: .selectedAnchor, songTitle: anchor.title, detail: "groove / continuity")
        ]
        var preWarnings: [String] = []

        if ordered.count >= 6 {
            let budgetBars = Int(tuning.maxTimelineSeconds / (240.0 / anchor.analysis.bpm))
            let neededBars = 24 + ordered.count * 10
            if neededBars > budgetBars,
               let weakest = ordered.dropFirst().min(by: {
                   $0.analysis.analysisConfidence < $1.analysis.analysisConfidence
               }) {
                ordered.removeAll { $0.songID == weakest.songID }
                preDecisions.append(
                    AutoDecision(
                        kind: .excludedLowConfidenceSong,
                        songTitle: weakest.title,
                        detail: "not enough timeline for a recognizable phrase from every song"
                    )
                )
                preWarnings.append(
                    "Excluded \(weakest.title): not enough timeline for a recognizable phrase from every song, and its analysis confidence was lowest."
                )
            }
        }

        let targetBPM = AutoTempo.targetBPM(
            profiles: ordered,
            anchorID: anchor.songID,
            maxStretch: tuning.maxStretch
        )

        let slots: [Slot]
        switch ordered.count {
        case 2: slots = duoSlots()
        case 3: slots = trioSlots()
        case 4: slots = quadSlots()
        default: slots = rotationSlots(count: ordered.count)
        }

        var plan = buildPlan(
            mode: .mashup,
            slots: slots,
            ordered: ordered,
            targetBPM: targetBPM,
            tuning: tuning,
            seed: seed,
            rng: &rng,
            preDecisions: preDecisions
        )
        plan?.warnings.insert(contentsOf: preWarnings, at: 0)
        return plan
    }

    /// A → B → A → B → A (roles switch; ≥3 handoffs; returns vary treatment).
    private static func duoSlots() -> [Slot] {
        [
            Slot(songIdx: 0, role: .teaser, bars: 4, entry: .none, energy: 0.55, shrinkPriority: 2),
            Slot(songIdx: 0, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.62),
            Slot(songIdx: 1, role: .chorus, bars: 8, entry: .reverseEntrance, energy: 0.8),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 0.9, isReturn: true),
            Slot(songIdx: 1, role: .chorus, bars: 16, entry: .blurReveal, energy: 0.95, isReturn: true, shrinkPriority: 1),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 1.0, isFinalPeak: true, isReturn: true),
            Slot(songIdx: 0, role: .ending, bars: 4, entry: .vocalEchoOut, energy: 0.6, isEnding: true, shrinkPriority: 0),
        ]
    }

    private static func trioSlots() -> [Slot] {
        [
            Slot(songIdx: 0, role: .teaser, bars: 4, entry: .none, energy: 0.55, shrinkPriority: 2),
            Slot(songIdx: 0, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.62),
            Slot(songIdx: 1, role: .chorus, bars: 8, entry: .reverseEntrance, energy: 0.78),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 0.88, isReturn: true),
            Slot(songIdx: 2, role: .chorus, bars: 8, entry: .blurReveal, energy: 0.82),
            Slot(songIdx: 1, role: .groove, bars: 8, entry: .flangerBuild, energy: 0.72, isReturn: true, shrinkPriority: 2),
            Slot(songIdx: 2, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 0.95, isReturn: true),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 1.0, isFinalPeak: true, isReturn: true),
            Slot(songIdx: 0, role: .ending, bars: 4, entry: .vocalEchoOut, energy: 0.6, isEnding: true, shrinkPriority: 0),
        ]
    }

    private static func quadSlots() -> [Slot] {
        [
            Slot(songIdx: 0, role: .teaser, bars: 4, entry: .none, energy: 0.55, shrinkPriority: 2),
            Slot(songIdx: 0, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.6),
            Slot(songIdx: 1, role: .chorus, bars: 8, entry: .reverseEntrance, energy: 0.75),
            Slot(songIdx: 2, role: .chorus, bars: 8, entry: .blurReveal, energy: 0.8),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 0.9, isReturn: true),
            Slot(songIdx: 3, role: .chorus, bars: 8, entry: .reverseEntrance, energy: 0.85),
            Slot(songIdx: 1, role: .groove, bars: 8, entry: .flangerBuild, energy: 0.72, isReturn: true, shrinkPriority: 2),
            Slot(songIdx: 2, role: .chorus, bars: 8, entry: .atmosphericHandoff, energy: 0.9, isReturn: true, shrinkPriority: 2),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 1.0, isFinalPeak: true, isReturn: true),
            Slot(songIdx: 0, role: .ending, bars: 4, entry: .vocalEchoOut, energy: 0.6, isEnding: true, shrinkPriority: 0),
        ]
    }

    private static func rotationSlots(count: Int) -> [Slot] {
        var slots: [Slot] = [
            Slot(songIdx: 0, role: .teaser, bars: 4, entry: .none, energy: 0.55, shrinkPriority: 2),
            Slot(songIdx: 0, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.6),
            Slot(songIdx: 1, role: .chorus, bars: 8, entry: .reverseEntrance, energy: 0.75),
            Slot(songIdx: 2, role: .chorus, bars: 8, entry: .blurReveal, energy: 0.8),
            Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 0.88, isReturn: true),
            Slot(songIdx: 3, role: .chorus, bars: 8, entry: .reverseEntrance, energy: 0.82),
            Slot(songIdx: 4, role: .chorus, bars: 8, entry: .blurReveal, energy: 0.86),
            Slot(songIdx: 1, role: .chorus, bars: 8, entry: .flangerBuild, energy: 0.9, isReturn: true, shrinkPriority: 2),
        ]
        for extra in 5..<count {
            slots.append(
                Slot(
                    songIdx: extra,
                    role: .chorus,
                    bars: 8,
                    entry: extra % 2 == 0 ? .reverseEntrance : .blurReveal,
                    energy: 0.85
                )
            )
        }
        slots.append(Slot(songIdx: 0, role: .chorus, bars: 8, entry: .hardHypeCut, energy: 1.0, isFinalPeak: true, isReturn: true))
        slots.append(Slot(songIdx: 0, role: .ending, bars: 4, entry: .vocalEchoOut, energy: 0.6, isEnding: true, shrinkPriority: 0))
        return slots
    }

    // MARK: - Plan construction

    private static func buildPlan(
        mode: AutoRemixMode,
        slots slotsIn: [Slot],
        ordered: [AutoSongProfile],
        targetBPM: Double,
        tuning: AutoTuning,
        seed: UInt64,
        rng: inout AutoRandom,
        preDecisions: [AutoDecision] = []
    ) -> AutoRemixPlan? {
        let barSec = 240.0 / max(targetBPM, 40)
        let beatSec = barSec / 4
        let minBars = barSec * 2 >= tuning.minSegmentSeconds ? 2 : 4

        var decisions: [AutoDecision] = preDecisions
        var warnings: [String] = []
        var intentionalGaps: [AutoIntentionalGap] = []

        let letters = ordered.enumerated().reduce(into: [UUID: String]()) { dict, item in
            dict[item.element.songID] = String(UnicodeScalar(UInt8(65 + min(item.offset, 25))))
        }

        var fits: [Int: AutoTempo.Fit] = [:]
        for (i, p) in ordered.enumerated() {
            let fit = mode == .remix
                ? AutoTempo.Fit(ratio: 1.0, gridAligned: true, halfOrDoubleTime: false)
                : AutoTempo.fit(songBPM: p.analysis.bpm, targetBPM: targetBPM, maxStretch: tuning.maxStretch)
            fits[i] = fit
            if mode == .mashup {
                if abs(fit.ratio - 1) > 0.0001 {
                    let pct = Int(((fit.ratio - 1) * 100).rounded())
                    decisions.append(
                        AutoDecision(
                            kind: .beatmatchedSong,
                            songTitle: p.title,
                            detail: "\(pct >= 0 ? "+" : "")\(pct)% to \(Int(targetBPM.rounded())) BPM"
                        )
                    )
                } else if fit.halfOrDoubleTime {
                    decisions.append(
                        AutoDecision(
                            kind: .beatmatchedSong,
                            songTitle: p.title,
                            detail: "half/double-time lock at native tempo"
                        )
                    )
                } else if !fit.gridAligned {
                    warnings.append(
                        "\(p.title) is outside the safe ±8% stretch window; Auto kept its native tempo and used clean phrase-aligned handoffs for it."
                    )
                }
            }
        }

        var slots = slotsIn
        func totalSeconds() -> Double { slots.reduce(0) { $0 + Double($1.bars) * barSec } }
        var shrinkPass = 2
        while totalSeconds() > tuning.maxTimelineSeconds, shrinkPass >= 1 {
            var shrunk = false
            for i in slots.indices where slots[i].shrinkPriority >= shrinkPass && slots[i].bars > 4 {
                slots[i].bars = slots[i].bars == 16 ? 8 : 4
                shrunk = true
                if totalSeconds() <= tuning.maxTimelineSeconds { break }
            }
            if !shrunk { shrinkPass -= 1 }
        }

        // ── Pass 1: choose sections and lay slots on the bar grid ──
        var placed: [PlacedSlot] = []
        var usedRanges: [UUID: [(Double, Double)]] = [:]
        var cursor = 0.0
        var skippedIntroNoted = Set<UUID>()
        var lowConfidenceNoted = Set<UUID>()

        for slot in slots {
            let profile = ordered[slot.songIdx]
            let fit = fits[slot.songIdx] ?? AutoTempo.Fit(ratio: 1, gridAligned: false, halfOrDoubleTime: false)
            let used = usedRanges[profile.songID] ?? []

            let labelChain: [[AutoCandidateSection.Label]]
            switch slot.role {
            case .teaser: labelChain = [[.teaser], [.chorus], [.groove]]
            case .chorus: labelChain = [[.chorus], [.groove], [.teaser]]
            case .groove: labelChain = [[.groove], [.chorus], [.breakdown]]
            case .build: labelChain = [[.build], [.groove]]
            case .breakdown: labelChain = [[.breakdown], [.groove], [.chorus]]
            case .ending: labelChain = [[.ending], [.chorus], [.groove]]
            case .intro: labelChain = [[.intro], [.groove]]
            }

            var section: AutoCandidateSection?
            for labels in labelChain {
                if let s = profile.best(
                    labels,
                    tuning: tuning,
                    used: used,
                    allowReuse: slot.isReturn || labels != labelChain[0]
                ) {
                    section = s
                    break
                }
            }
            guard let section else {
                warnings.append(
                    "No usable \(slot.role.rawValue) section found in \(profile.title); skipped that appearance."
                )
                decisions.append(
                    AutoDecision(
                        kind: .skippedWeakSection,
                        songTitle: profile.title,
                        detail: slot.role.rawValue
                    )
                )
                continue
            }

            var bars = slot.bars
            let songDuration = profile.analysis.durationSeconds
            let availableSeconds = (songDuration - 0.15 - section.startSeconds) / max(fit.ratio, 0.0001)
            while bars > minBars, Double(bars) * barSec > availableSeconds {
                bars -= minBars
            }
            guard Double(bars) * barSec <= availableSeconds, bars >= 2 else {
                warnings.append(
                    "\(profile.title) ran out of material for a \(slot.role.rawValue) section; skipped it."
                )
                decisions.append(
                    AutoDecision(
                        kind: .skippedWeakSection,
                        songTitle: profile.title,
                        detail: "\(slot.role.rawValue) (insufficient material)"
                    )
                )
                continue
            }
            if bars < slot.bars {
                decisions.append(
                    AutoDecision(
                        kind: .shortenedForMaterial,
                        songTitle: profile.title,
                        detail: "\(slot.role.rawValue) to \(bars) bars"
                    )
                )
            }

            // Shorten weak low-energy grooves that aren't serving contrast.
            if slot.role == .groove, section.energy < 0.35, section.hook < 0.45, bars > 4 {
                bars = 4
                decisions.append(
                    AutoDecision(
                        kind: .shortenedLowEnergySection,
                        songTitle: profile.title,
                        detail: "groove to 4 bars"
                    )
                )
            }

            let reused = used.contains { range in
                min(section.endSeconds, range.1) - max(section.startSeconds, range.0) > section.durationSeconds * 0.5
            }

            // Returns must vary — different source, energy, or transition.
            // Never emit the exact same clip solely to pad handoff count.
            var entry = slot.entry
            var energy = slot.energy
            if reused, slot.isReturn {
                if entry == .none || entry == .cleanCrossfade {
                    entry = .hardHypeCut
                }
                energy = min(1, energy + 0.08)
            }

            // Intentional micro-pause before a hard hype cut (≤ 1/4 beat).
            if entry == .hardHypeCut, !profile.lowConfidence, cursor > 0 {
                let pause = min(tuning.maxIntentionalPauseBeats * beatSec, beatSec * 0.25)
                if pause > 0.001 {
                    intentionalGaps.append(
                        AutoIntentionalGap(
                            start: cursor,
                            end: cursor + pause,
                            reason: "pre-drop pause"
                        )
                    )
                    cursor += pause
                }
            }

            let duration = Double(bars) * barSec
            var mutableSlot = slot
            mutableSlot.entry = entry
            mutableSlot.energy = energy
            placed.append(
                PlacedSlot(
                    slot: mutableSlot,
                    section: section,
                    timelineStart: cursor,
                    timelineDuration: duration,
                    tempoRatio: fit.ratio,
                    reusedSection: reused
                )
            )
            usedRanges[profile.songID, default: []].append(
                (section.startSeconds, section.startSeconds + duration * fit.ratio)
            )
            cursor += duration

            if slot.role == .groove || slot.role == .teaser,
               !skippedIntroNoted.contains(profile.songID),
               let intro = profile.analysis.introCandidate,
               intro.durationSeconds > barSec * 2 {
                skippedIntroNoted.insert(profile.songID)
                decisions.append(
                    AutoDecision(kind: .skippedIntro, songTitle: profile.title, detail: nil)
                )
            }
        }
        guard placed.count >= 2 else { return nil }

        // Duo alternation: target ≥3 handoffs without inventing tiny clips.
        if mode == .mashup, ordered.count == 2 {
            let handoffs = countHandoffs(placed)
            if handoffs < 3 {
                decisions.append(
                    AutoDecision(
                        kind: .duoAlternationFallback,
                        songTitle: nil,
                        detail: "Could not reach A → B → A → B without incomplete sections — kept the cleanest valid alternation."
                    )
                )
                warnings.append(
                    "Fewer than three song handoffs — duration or analysis confidence prevented a full A → B → A → B without incomplete sections."
                )
            }
        }

        // Low-confidence degrade: force safe handoffs around unreliable songs.
        for i in placed.indices {
            let profile = ordered[placed[i].slot.songIdx]
            if profile.lowConfidence, placed[i].slot.entry != .none {
                placed[i].slot.entry = .cleanCrossfade
                if lowConfidenceNoted.insert(profile.songID).inserted {
                    decisions.append(
                        AutoDecision(
                            kind: .usedLowConfidenceFallback,
                            songTitle: profile.title,
                            detail: nil
                        )
                    )
                }
            }
        }

        // ── Pass 2: emit placements, effects, and coordinated SFX ──
        var placements: [AutoClipPlacement] = []
        var sfx: [AutoSFXEvent] = []
        var transitionsUsed: [AutoTransitionRecipe] = []
        var lastMajorSFXTime = -100.0
        let majorSFXSpacing = mode == .remix
            ? tuning.remixMajorSFXSpacing
            : tuning.mashupMajorSFXSpacing

        func addSFX(_ id: String, at t: Double, purpose: String) {
            guard t >= 0 else { return }
            sfx.append(AutoSFXEvent(assetID: id, timelineStart: t, purpose: purpose))
        }
        func addSFXEnding(_ id: String, at t: Double, purpose: String) {
            guard let def = SoundEffectLibrary.definition(for: id) else { return }
            addSFX(id, at: t - def.durationSeconds, purpose: purpose)
        }

        for (i, ps) in placed.enumerated() {
            let profile = ordered[ps.slot.songIdx]
            let prev = i > 0 ? placed[i - 1] : nil
            let next = i + 1 < placed.count ? placed[i + 1] : nil
            let isHandoff = prev != nil && prev!.slot.songIdx != ps.slot.songIdx
            let entry = ps.slot.entry
            let boundary = ps.timelineStart
            let baseVolume = 0.82 + 0.18 * ps.slot.energy
            let allowMajorSFX = boundary - lastMajorSFXTime >= majorSFXSpacing

            if i > 0 { transitionsUsed.append(entry) }

            var bodyFX = ClipEffectSettings()
            switch ps.slot.role {
            case .teaser:
                bodyFX.setLevel(28, for: MixrEffect.blur.rawValue)
                bodyFX.setLevel(14, for: MixrEffect.echo.rawValue)
                bodyFX.echoPreset = .reverse
            case .build:
                if !profile.lowConfidence {
                    bodyFX.flangerAmount = ps.slot.energy > 0.75 ? 0.26 : 0.16
                }
            case .chorus:
                bodyFX.setLevel(8, for: MixrEffect.reverb.rawValue)
                bodyFX.reverbPreset = .hall
            case .breakdown:
                bodyFX.setLevel(18, for: MixrEffect.reverb.rawValue)
                bodyFX.reverbPreset = .ambient
            case .ending:
                bodyFX.setLevel(24, for: MixrEffect.reverb.rawValue)
                bodyFX.reverbPreset = .ambient
                bodyFX.setLevel(20, for: MixrEffect.echo.rawValue)
                bodyFX.echoPreset = .classic
            case .groove, .intro:
                break
            }
            bodyFX = AutoSupportedEffects.sanitize(bodyFX)

            let headSeconds = entry == .blurReveal
                && ps.timelineDuration >= Double(minBars) * barSec + tuning.minSegmentSeconds
                ? Double(minBars) * barSec : 0
            let nextEntry = next?.slot.entry ?? .none
            let nextIsHandoff = next != nil && next!.slot.songIdx != ps.slot.songIdx
            let wantsTail = nextIsHandoff
                && [.vocalEchoOut, .flangerBuild, .atmosphericHandoff].contains(nextEntry)
            let tailSeconds = wantsTail
                && ps.timelineDuration - headSeconds >= Double(minBars) * barSec + tuning.minSegmentSeconds
                ? Double(minBars) * barSec : 0

            var segments: [(start: Double, duration: Double, fx: ClipEffectSettings, volume: Double, fadeIn: ClipTransition, fadeOut: ClipTransition)] = []

            if headSeconds > 0 {
                var headFX = bodyFX
                headFX.setLevel(45, for: MixrEffect.blur.rawValue)
                headFX = AutoSupportedEffects.sanitize(headFX)
                segments.append((
                    start: 0,
                    duration: headSeconds,
                    fx: headFX,
                    volume: baseVolume * 0.92,
                    fadeIn: ClipTransition(type: .crossfade, duration: 4),
                    fadeOut: .none
                ))
            }

            let bodyStart = headSeconds
            let bodyDuration = ps.timelineDuration - headSeconds - tailSeconds
            var bodyFadeIn: ClipTransition = headSeconds > 0 ? .none : ClipTransition(type: .crossfade, duration: 1)
            var bodyFadeOut: ClipTransition = tailSeconds > 0 ? .none : ClipTransition(type: .fadeOut, duration: 1)
            if entry == .cleanCrossfade, headSeconds == 0 {
                bodyFadeIn = ClipTransition(type: .crossfade, duration: 4)
            }
            if ps.slot.isEnding {
                bodyFadeOut = ClipTransition(type: .echoOut, duration: 6)
            } else if nextIsHandoff, nextEntry == .cleanCrossfade, tailSeconds == 0 {
                bodyFadeOut = ClipTransition(type: .fadeOut, duration: 4)
            }

            var emittedPitchMoment = false
            if mode == .remix, ps.slot.role == .breakdown, !profile.lowConfidence,
               bodyDuration >= Double(minBars) * 3 * barSec {
                let third = (bodyDuration / (Double(minBars) * barSec)).rounded(.down)
                if third >= 3 {
                    let partBars = Double(minBars) * barSec
                    let cleanA = bodyDuration - partBars * 2
                    var pitchFX = bodyFX
                    pitchFX.pitchDirection = rng.next() % 2 == 0 ? .up : .down
                    pitchFX.pitchAmount = pitchFX.pitchDirection == .up ? 0.38 : 0.28
                    pitchFX.setLevel(10, for: MixrEffect.reverb.rawValue)
                    pitchFX.reverbPreset = .smallRoom
                    pitchFX = AutoSupportedEffects.sanitize(pitchFX)

                    segments.append((bodyStart, cleanA, bodyFX, baseVolume, bodyFadeIn, .none))
                    segments.append((bodyStart + cleanA, partBars, pitchFX, baseVolume, .none, .none))
                    segments.append((bodyStart + cleanA + partBars, partBars, bodyFX, baseVolume, .none, bodyFadeOut))
                    emittedPitchMoment = true
                    decisions.append(
                        AutoDecision(
                            kind: .pitchedContrastPhrase,
                            songTitle: profile.title,
                            detail: pitchFX.pitchDirection == .up ? "Pitch Up" : "Pitch Down"
                        )
                    )
                }
            }
            if !emittedPitchMoment {
                segments.append((bodyStart, bodyDuration, bodyFX, baseVolume, bodyFadeIn, bodyFadeOut))
            }

            if tailSeconds > 0 {
                var tailFX = bodyFX
                var tailVolume = baseVolume * 0.9
                var tailFadeOut = ClipTransition(type: .fadeOut, duration: 8)
                switch nextEntry {
                case .vocalEchoOut:
                    tailFX.setLevel(28, for: MixrEffect.echo.rawValue)
                    tailFX.echoPreset = .classic
                    tailFX.setLevel(12, for: MixrEffect.reverb.rawValue)
                    tailFX.reverbPreset = .hall
                    tailFadeOut = ClipTransition(type: .echoOut, duration: 6)
                case .flangerBuild:
                    tailFX.flangerAmount = 0.32
                    tailVolume = baseVolume * 0.95
                case .atmosphericHandoff:
                    tailFX.setLevel(32, for: MixrEffect.blur.rawValue)
                    tailFX.setLevel(22, for: MixrEffect.reverb.rawValue)
                    tailFX.reverbPreset = .ambient
                default:
                    break
                }
                tailFX = AutoSupportedEffects.sanitize(tailFX)
                segments.append((
                    start: ps.timelineDuration - tailSeconds,
                    duration: tailSeconds,
                    fx: tailFX,
                    volume: tailVolume,
                    fadeIn: .none,
                    fadeOut: tailFadeOut
                ))
            }

            for seg in segments where seg.duration > 0.01 {
                placements.append(
                    AutoClipPlacement(
                        songID: profile.songID,
                        sourceStart: ps.section.startSeconds + seg.start * ps.tempoRatio,
                        timelineStart: ps.timelineStart + seg.start,
                        timelineDuration: seg.duration,
                        tempoRatio: ps.tempoRatio,
                        volume: seg.volume,
                        fadeIn: seg.fadeIn,
                        fadeOut: seg.fadeOut,
                        effects: AutoSupportedEffects.sanitize(seg.fx),
                        role: .dominant,
                        slotIndex: i
                    )
                )
            }

            // Directional overlap under mashup handoffs.
            if mode == .mashup, isHandoff, let prev,
               ![.hardHypeCut, .cleanCrossfade, .none].contains(entry) {
                let prevProfile = ordered[prev.slot.songIdx]
                let compat = AutoCompatibility.directional(
                    dominant: ps.section,
                    dominantProfile: profile,
                    support: prev.section,
                    supportProfile: prevProfile,
                    targetBPM: targetBPM,
                    tuning: tuning
                )
                let overlapSeconds = Double(compat.overlapBars) * barSec
                let prevSourceEnd = prev.section.startSeconds + prev.timelineDuration * prev.tempoRatio
                let supportAvailable = prevProfile.analysis.durationSeconds - 0.15 - prevSourceEnd

                let denseVocals = ps.section.vocal > 0.65 && prev.section.vocal > 0.65
                if denseVocals, compat.overlapBars > 0 {
                    decisions.append(
                        AutoDecision(
                            kind: .avoidedVocalOverlap,
                            songTitle: profile.title,
                            detail: prevProfile.title
                        )
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .replacedComplexOverlapWithHardCut,
                            songTitle: nil,
                            detail: profile.title
                        )
                    )
                } else if compat.overlapBars > 0,
                          overlapSeconds >= tuning.minSegmentSeconds,
                          supportAvailable >= overlapSeconds * prev.tempoRatio {
                    var supportFX = ClipEffectSettings()
                    supportFX.setLevel(32, for: MixrEffect.blur.rawValue)
                    if compat.pitchCorrectionSemitones != 0 {
                        supportFX.pitchDirection = compat.pitchCorrectionSemitones > 0 ? .up : .down
                        supportFX.pitchAmount = Double(abs(compat.pitchCorrectionSemitones)) / 12.0
                    }
                    supportFX = AutoSupportedEffects.sanitize(supportFX)
                    placements.append(
                        AutoClipPlacement(
                            songID: prevProfile.songID,
                            sourceStart: prevSourceEnd,
                            timelineStart: boundary,
                            timelineDuration: overlapSeconds,
                            tempoRatio: prev.tempoRatio,
                            volume: tuning.supportVolume,
                            fadeIn: .none,
                            fadeOut: ClipTransition(type: .fadeOut, duration: 4),
                            effects: supportFX,
                            role: .supporting,
                            slotIndex: i
                        )
                    )
                    if compat.pitchCorrectionSemitones != 0 {
                        let sign = compat.pitchCorrectionSemitones > 0 ? "+" : ""
                        decisions.append(
                            AutoDecision(
                                kind: .pitchCorrectedOverlap,
                                songTitle: prevProfile.title,
                                detail: "\(sign)\(compat.pitchCorrectionSemitones) semitones"
                            )
                        )
                    }
                } else if compat.overlapBars == 0,
                          ![.hardHypeCut, .cleanCrossfade].contains(entry),
                          !profile.lowConfidence {
                    // Low compatibility → prefer a clean cut over a muddy overlap.
                    // (Entry recipe already chosen; note the restraint.)
                }
            }

            // Coordinated SFX — denser in remix, sparingly in mashup.
            let isMajorReveal = ps.slot.isFinalPeak
                || entry == .hardHypeCut
                || (entry == .reverseEntrance && (mode == .remix || ps.slot.energy >= 0.9))

            if i > 0, allowMajorSFX {
                switch entry {
                case .hardHypeCut where mode == .remix || isMajorReveal || ps.slot.isFinalPeak:
                    let buildID = ps.slot.isFinalPeak ? "snareBuild" : "riser"
                    addSFXEnding(
                        buildID,
                        at: boundary,
                        purpose: ps.slot.isFinalPeak ? "snare build into the final drop" : "riser into the drop"
                    )
                    addSFX("impact", at: boundary, purpose: "impact on the drop downbeat")
                    if ps.slot.isFinalPeak {
                        addSFXEnding("riser", at: boundary, purpose: "riser into the final drop")
                    }
                    decisions.append(
                        AutoDecision(
                            kind: .addedRiserIntoDrop,
                            songTitle: nil,
                            detail: ps.slot.isFinalPeak ? "snare build + impact" : "riser + impact"
                        )
                    )
                    lastMajorSFXTime = boundary
                case .reverseEntrance where mode == .remix || ps.slot.energy >= 0.88:
                    addSFXEnding("reverseCymbal", at: boundary, purpose: "reverse cymbal into the hook reveal")
                    addSFX("impact", at: boundary, purpose: "impact on the new entrance")
                    lastMajorSFXTime = boundary
                case .blurReveal where mode == .remix && ps.slot.energy >= 0.9:
                    addSFX("impact", at: boundary, purpose: "impact on the reveal")
                    lastMajorSFXTime = boundary
                case .vocalEchoOut where mode == .remix:
                    if prev?.slot.role == .chorus, ps.slot.energy < prev!.slot.energy {
                        addSFX("downlifter", at: boundary, purpose: "downlifter out of the drop")
                        lastMajorSFXTime = boundary
                    }
                case .flangerBuild where mode == .remix:
                    addSFX("impact", at: boundary, purpose: "impact on the flanger release")
                    lastMajorSFXTime = boundary
                case .hardHypeCut where mode == .mashup && !isMajorReveal:
                    // Mashup: song switch is enough — skip impact on every handoff.
                    break
                default:
                    break
                }
            }

            if ps.slot.isEnding {
                addSFX("impact", at: boundary, purpose: "final hit")
                addSFX("downlifter", at: boundary + 1.05, purpose: "downlifter after the final hit")
            }

            // Remix: extra purposeful sweep out of each build.
            if mode == .remix, ps.slot.role == .build,
               boundary + ps.timelineDuration - lastMajorSFXTime >= majorSFXSpacing * 0.75 {
                addSFXEnding("airSweep", at: boundary + ps.timelineDuration, purpose: "white-noise sweep into the payoff")
            }
        }

        var sequence: [String] = []
        var sequenceTitles: [String] = []
        var handoffs = 0
        for (i, ps) in placed.enumerated() {
            let song = ordered[ps.slot.songIdx]
            let letter = letters[song.songID] ?? "?"
            sequence.append(letter)
            sequenceTitles.append(song.title)
            if i > 0, placed[i - 1].slot.songIdx != ps.slot.songIdx { handoffs += 1 }
        }

        if let final = placed.last(where: { $0.slot.isFinalPeak }) {
            let title = ordered[final.slot.songIdx].title
            if final.reusedSection {
                decisions.append(
                    AutoDecision(
                        kind: .returnedToHook,
                        songTitle: title,
                        detail: "chorus"
                    )
                )
            } else {
                decisions.append(
                    AutoDecision(
                        kind: .savedStrongestForPeak,
                        songTitle: title,
                        detail: nil
                    )
                )
            }
        }

        let sections = placed.map { ps -> AutoSelectedSection in
            AutoSelectedSection(
                songID: ps.section.songID,
                sourceStart: ps.section.startSeconds,
                sourceEnd: ps.section.startSeconds + ps.timelineDuration * ps.tempoRatio,
                phraseType: ps.section.label.rawValue,
                barCount: Int((ps.timelineDuration / barSec).rounded()),
                hookScore: ps.section.hook,
                energyScore: ps.section.energy,
                vocalDensity: ps.section.vocal,
                compatibilityRole: .dominant,
                confidence: ps.section.confidence
            )
        }
        let confidence = sections.map(\.confidence).reduce(0, +) / Double(max(sections.count, 1))

        return AutoRemixPlan(
            mode: mode,
            targetBPM: targetBPM,
            targetDuration: cursorEnd(placed),
            anchorSongIDs: [ordered[0].songID],
            selectedSections: sections,
            placements: placements,
            sfxEvents: sfx,
            intentionalGaps: intentionalGaps,
            handoffCount: handoffs,
            songLetters: letters,
            sequence: sequence,
            sequenceTitles: sequenceTitles,
            transitionsUsed: transitionsUsed,
            decisions: decisions,
            warnings: warnings,
            confidence: confidence,
            randomSeed: seed
        )
    }

    private static func countHandoffs(_ placed: [PlacedSlot]) -> Int {
        var n = 0
        for i in 1..<placed.count where placed[i].slot.songIdx != placed[i - 1].slot.songIdx {
            n += 1
        }
        return n
    }

    private static func cursorEnd(_ placed: [PlacedSlot]) -> Double {
        placed.map { $0.timelineStart + $0.timelineDuration }.max() ?? 0
    }
}
