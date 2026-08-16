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

    // MARK: - Remix (one song → streaming-length club rewrite)
    //
    // Rebuild onto an 8/16/32-bar phrase grid with a two-wave club shape:
    // intro → groove → build → drop 1 → breakdown → build 2 → drop 2 → outro.
    // Hype is subtraction then a downbeat — intentional pre-drop voids are
    // allowed. Thin songs get a pulse; slamming kits never get a second kick.

    private static func remixPlan(
        profile: AutoSongProfile,
        tuning: AutoTuning,
        seed: UInt64,
        rng: inout AutoRandom
    ) -> AutoRemixPlan? {
        let analysis = profile.analysis
        let duration = analysis.durationSeconds
        guard duration > 1 else { return nil }

        var decisions: [AutoDecision] = [
            AutoDecision(kind: .selectedAnchor, songTitle: profile.title, detail: "club remix rewrite")
        ]
        var warnings: [String] = []

        let signal = analysis.signal
        let signalTrusted = (signal?.overallConfidence ?? 0) >= 0.4
        let confident = signalTrusted
            && analysis.analysisConfidence >= tuning.lowConfidenceThreshold
            && (signal?.beatConfidence ?? (analysis.bpmIsReal ? 1.0 : 0.0)) > 0.35

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

        let meanVocal = analysis.meanVocalDensity(from: usableStart, to: usableEnd)
        let tempo = AutoClubTempo.remixDecision(
            songBPM: analysis.bpm,
            vocalHeavy: meanVocal > 0.55,
            maxVocalStretch: tuning.maxStretch,
            maxInstrumentalStretch: tuning.maxInstrumentalStretch
        )
        decisions.append(
            AutoDecision(kind: .choseClubTempo, songTitle: profile.title, detail: tempo.detail)
        )

        let flavor = AutoClubFlavor.choose(
            drumStrength: analysis.drumStrength,
            bassDensity: analysis.bassDensity,
            vocalDensity: meanVocal,
            bpm: tempo.targetBPM,
            seed: seed
        )
        decisions.append(
            AutoDecision(kind: .choseClubFlavor, songTitle: profile.title, detail: flavor.rawValue)
        )

        let pulse = AutoClubPulse.policy(
            drumStrength: analysis.drumStrength,
            bassDensity: analysis.bassDensity
        )
        if AutoClubPulse.violatesOneKickRule(policy: pulse) {
            // Defensive — policy() never emits this, but keep the invariant.
            warnings.append("One-kick rule violated; stripping written kick.")
        }
        if pulse.sourceHasClubKick {
            decisions.append(
                AutoDecision(kind: .skippedSecondKick, songTitle: profile.title, detail: pulse.detail)
            )
        } else if pulse.writesKick {
            decisions.append(
                AutoDecision(kind: .wroteClubPulse, songTitle: profile.title, detail: pulse.detail)
            )
        }

        let targetBPM = tempo.targetBPM
        let beat = 60.0 / max(targetBPM, 40)
        let bar = beat * 4
        let ratio = tempo.ratio

        // Compact streaming club shape (bars). All on phrase grid.
        let shape: [(role: AutoCandidateSection.Label, bars: Int, energy: Double, pulse: AutoClubPulse.RegionRole, entry: AutoTransitionRecipe)] = [
            (.intro, 8, 0.45, .introTease, .none),
            (.groove, 8, 0.58, .groove, .cleanCrossfade),
            (.build, 8, 0.72, .build, .flangerBuild),
            (.chorus, 16, 1.0, .drop, .hardHypeCut),          // Drop 1
            (.breakdown, 8, 0.42, .breakdown, .atmosphericHandoff),
            (.build, 8, 0.82, .build, .flangerBuild),         // Build 2 denser
            (.chorus, 16, 1.0, .drop, .hardHypeCut),          // Drop 2
            (.ending, 4, 0.55, .outro, .vocalEchoOut),
        ]

        if !confident {
            decisions.append(
                AutoDecision(
                    kind: .usedLowConfidenceFallback,
                    songTitle: profile.title,
                    detail: nil
                )
            )
            decisions.append(
                AutoDecision(
                    kind: .imposedClubEnergyCurve,
                    songTitle: profile.title,
                    detail: "filter + pulse + SFX without invented structural cuts"
                )
            )
            return lowConfidenceClubPlan(
                profile: profile,
                usableStart: usableStart,
                usableEnd: usableEnd,
                tempo: tempo,
                pulse: pulse,
                flavor: flavor,
                tuning: tuning,
                decisions: decisions,
                warnings: warnings,
                seed: seed
            )
        }

        var placements: [AutoClipPlacement] = []
        var selected: [AutoSelectedSection] = []
        var cutRecords: [AutoCutRecord] = []
        var intentionalGaps: [AutoIntentionalGap] = []
        var pulseRegions: [AutoClubPulse.Region] = []
        var sfx: [AutoSFXEvent] = []
        var transitionsUsed: [AutoTransitionRecipe] = []
        var usedRanges: [(Double, Double)] = []
        var cursor = 0.0
        var lastSourceEnd: Double?
        var dropIndex = 0

        for (slotIdx, slot) in shape.enumerated() {
            let labels: [AutoCandidateSection.Label]
            switch slot.role {
            case .intro: labels = [.intro, .groove, .teaser]
            case .groove: labels = [.groove, .teaser, .chorus]
            case .build: labels = [.build, .groove]
            case .chorus: labels = [.chorus, .teaser]
            case .breakdown: labels = [.breakdown, .groove]
            case .ending: labels = [.ending, .teaser, .chorus]
            default: labels = [slot.role]
            }

            guard var section = profile.best(labels, tuning: tuning, used: usedRanges, allowReuse: true)
                ?? fallbackSection(profile: profile, label: slot.role, bars: slot.bars, usableStart: usableStart, usableEnd: usableEnd)
            else { continue }

            // Clamp section into usable range and requested bar count.
            let wantSeconds = Double(slot.bars) * bar
            let sourceDur = wantSeconds * ratio
            if section.startSeconds < usableStart {
                section = AutoCandidateSection(
                    songID: section.songID,
                    label: section.label,
                    startSeconds: usableStart,
                    barCount: slot.bars,
                    barSeconds: section.barSeconds,
                    hook: section.hook,
                    energy: section.energy,
                    vocal: section.vocal,
                    clarity: section.clarity,
                    rhythm: section.rhythm,
                    uniqueness: section.uniqueness,
                    transitionUse: section.transitionUse,
                    confidence: section.confidence
                )
            }
            if section.startSeconds + sourceDur > usableEnd {
                let start = max(usableStart, usableEnd - sourceDur)
                section = AutoCandidateSection(
                    songID: section.songID,
                    label: section.label,
                    startSeconds: start,
                    barCount: slot.bars,
                    barSeconds: section.barSeconds,
                    hook: section.hook,
                    energy: section.energy,
                    vocal: section.vocal,
                    clarity: section.clarity,
                    rhythm: section.rhythm,
                    uniqueness: section.uniqueness,
                    transitionUse: section.transitionUse,
                    confidence: section.confidence
                )
            }

            // Build-out: last 4 bars of a build mute kick+bass.
            // Build-out: last 4 bars of a build mute kick+bass.
            let regionRole = slot.pulse
            let timelineBars = slot.bars
            var buildBodyBars = slot.bars
            if slot.role == .build, slot.bars >= 8 {
                buildBodyBars = slot.bars - 4
            }

            // Intentional pre-drop void before each hard hype cut into a drop.
            if slot.entry == .hardHypeCut, cursor > 0 {
                let voidBeats = min(tuning.preferredPredropVoidBeats, tuning.maxIntentionalPauseBeats)
                let voidSec = voidBeats * beat
                if voidSec > 0.05 {
                    intentionalGaps.append(
                        AutoIntentionalGap(start: cursor, end: cursor + voidSec, reason: "pre-drop void")
                    )
                    pulseRegions.append(
                        AutoClubPulse.Region(role: .void, timelineStart: cursor, timelineEnd: cursor + voidSec)
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .allowedPredropVoid,
                            songTitle: profile.title,
                            detail: String(format: "%.2f beats before drop", voidBeats)
                        )
                    )
                    cursor += voidSec
                }
            }

            if slot.entry != .none { transitionsUsed.append(slot.entry) }

            // Split build into body + buildOut (kick mute).
            let segments: [(bars: Int, pulse: AutoClubPulse.RegionRole, energy: Double)]
            if slot.role == .build, buildBodyBars < timelineBars {
                segments = [
                    (buildBodyBars, .build, slot.energy),
                    (timelineBars - buildBodyBars, .buildOut, slot.energy * 0.55),
                ]
            } else {
                segments = [(timelineBars, regionRole, slot.energy)]
            }

            var segCursor = cursor
            for (segIdx, seg) in segments.enumerated() {
                let segDur = Double(seg.bars) * bar
                pulseRegions.append(
                    AutoClubPulse.Region(role: seg.pulse, timelineStart: segCursor, timelineEnd: segCursor + segDur)
                )

                var fx = ClipEffectSettings()
                switch slot.role {
                case .intro:
                    fx.setLevel(42, for: MixrEffect.blur.rawValue)
                    fx.setLevel(10, for: MixrEffect.echo.rawValue)
                case .build:
                    fx.flangerAmount = seg.pulse == .buildOut ? 0.28 : (slot.energy > 0.78 ? 0.24 : 0.16)
                    fx.setLevel(seg.pulse == .buildOut ? 36 : 18, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .pingPong
                    if seg.pulse == .buildOut {
                        fx.setLevel(50, for: MixrEffect.blur.rawValue)
                    }
                case .chorus:
                    fx.setLevel(dropIndex == 0 ? 8 : 14, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = dropIndex == 0 ? .hall : .ambient
                    if dropIndex >= 1, flavor.bias.drop2AiryLayer {
                        fx.setLevel(12, for: MixrEffect.echo.rawValue)
                    }
                    if flavor.bias.vocalChopLead, dropIndex == 0 {
                        fx.setLevel(10, for: MixrEffect.blur.rawValue)
                    }
                case .breakdown:
                    fx.setLevel(22 + flavor.bias.breakdownVocalClarity * 18, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = .ambient
                    if flavor.bias.dropMidrangeSparse {
                        fx.setLevel(16, for: MixrEffect.blur.rawValue)
                    }
                case .ending:
                    fx.setLevel(24, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = .ambient
                    fx.setLevel(18, for: MixrEffect.echo.rawValue)
                default:
                    break
                }
                if pulse.duckSourceLowEnd, seg.pulse == .drop || seg.pulse == .groove || seg.pulse == .introTease {
                    fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 22), for: MixrEffect.blur.rawValue)
                }
                fx = AutoSupportedEffects.sanitize(fx)

                let sourceStart = section.startSeconds + Double(segCursor - cursor) * ratio
                var volume = AutoGainPolicy.songPlacementVolume(energy: seg.energy)
                if pulse.duckSourceLowEnd { volume *= AutoGainPolicy.pulseDuckedSongVolumeScale }

                let continues = lastSourceEnd.map { abs(sourceStart - $0) < 0.05 } ?? false
                let discontinuity = lastSourceEnd.map { abs(sourceStart - $0) > 0.05 } ?? false

                if discontinuity, let prevEnd = lastSourceEnd {
                    let isHookReturn = slot.role == .chorus
                    cutRecords.append(
                        AutoCutRecord(
                            timelineAt: segCursor,
                            sourceFrom: prevEnd,
                            sourceTo: sourceStart,
                            reason: isHookReturn ? .hookReturn : .redundantRepeat,
                            confidence: max(0.55, section.confidence),
                            expectedEnergyDeltaDB: isHookReturn ? 2.0 : 0,
                            masking: slot.entry == .hardHypeCut
                                ? .sfx(assetID: "impact")
                                : .alignedHardCut
                        )
                    )
                    if isHookReturn {
                        decisions.append(
                            AutoDecision(kind: .returnedToHook, songTitle: profile.title, detail: "drop")
                        )
                    }
                }

                var fadeIn: ClipTransition = .none
                var fadeOut: ClipTransition = .none
                if slot.entry == .hardHypeCut, segIdx == 0 {
                    fadeIn = ClipTransition(type: .crossfade, duration: 0.125)
                } else if slot.entry == .cleanCrossfade, segIdx == 0, placements.isEmpty == false {
                    fadeIn = ClipTransition(
                        type: .crossfade,
                        duration: 2,
                        curve: AutoTransitionEnvelope.equalPowerCurveName
                    )
                }
                if slot.role == .ending {
                    fadeOut = ClipTransition(type: .echoOut, duration: 6)
                }

                placements.append(
                    AutoClipPlacement(
                        songID: profile.songID,
                        sourceStart: sourceStart,
                        timelineStart: segCursor,
                        timelineDuration: segDur,
                        tempoRatio: ratio,
                        volume: volume,
                        fadeIn: fadeIn,
                        fadeOut: fadeOut,
                        effects: fx,
                        role: .dominant,
                        slotIndex: slotIdx,
                        continuesPrevious: continues && segIdx > 0
                    )
                )
                lastSourceEnd = sourceStart + segDur * ratio
                segCursor += segDur
            }

            // Coordinated SFX into drops.
            if slot.role == .chorus {
                let dropAt = placements.last(where: { $0.slotIndex == slotIdx })?.timelineStart
                    ?? cursor
                if let riser = SoundEffectLibrary.definition(for: dropIndex == 0 ? "riser" : "snareBuild"),
                   dropAt - riser.durationSeconds >= 0 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: dropIndex == 0 ? "riser" : "snareBuild",
                            timelineStart: dropAt - riser.durationSeconds,
                            purpose: dropIndex == 0 ? "riser into drop 1" : "snare roll into drop 2"
                        )
                    )
                }
                sfx.append(
                    AutoSFXEvent(assetID: "impact", timelineStart: dropAt, purpose: "impact on drop downbeat")
                )
                if dropIndex >= 1, flavor.bias.drop2AiryLayer {
                    sfx.append(
                        AutoSFXEvent(assetID: "airSweep", timelineStart: dropAt, purpose: "drop 2 airy layer")
                    )
                }
                decisions.append(
                    AutoDecision(
                        kind: .addedRiserIntoDrop,
                        songTitle: profile.title,
                        detail: dropIndex == 0 ? "riser into drop 1" : "snare into drop 2"
                    )
                )
                dropIndex += 1
            }

            selected.append(
                AutoSelectedSection(
                    songID: profile.songID,
                    sourceStart: section.startSeconds,
                    sourceEnd: section.startSeconds + wantSeconds * ratio,
                    phraseType: slot.role.rawValue,
                    barCount: slot.bars,
                    hookScore: section.hook,
                    energyScore: section.energy,
                    vocalDensity: section.vocal,
                    compatibilityRole: .dominant,
                    confidence: section.confidence
                )
            )
            usedRanges.append((section.startSeconds, section.startSeconds + wantSeconds * ratio))
            cursor = segCursor
            _ = rng.next() // keep seed progression stable across flavors
        }

        // Pulse hits are scheduled from regions at apply/render time so the
        // musical SFX list stays sparse (risers/impacts), not one event per kick.
        _ = AutoClubPulse.scheduleHits(
            regions: pulseRegions,
            policy: pulse,
            beatSeconds: beat,
            barSeconds: bar
        )

        let totalDuration = placements.map(\.timelineEnd).max() ?? cursor
        return AutoRemixPlan(
            mode: .remix,
            targetBPM: targetBPM,
            targetDuration: totalDuration,
            anchorSongIDs: [profile.songID],
            selectedSections: selected,
            placements: placements,
            sfxEvents: sfx.sorted { $0.timelineStart < $1.timelineStart },
            cutRecords: cutRecords,
            usableSourceRange: usableStart...usableEnd,
            intentionalGaps: intentionalGaps,
            pulsePolicy: pulse,
            pulseRegions: pulseRegions,
            clubFlavor: flavor,
            mashupVocalSongID: nil,
            mashupBedSongID: nil,
            handoffCount: 0,
            songLetters: [profile.songID: "A"],
            sequence: shape.map { _ in "A" },
            sequenceTitles: [profile.title],
            transitionsUsed: transitionsUsed,
            decisions: decisions,
            warnings: warnings,
            confidence: analysis.analysisConfidence,
            randomSeed: seed
        )
    }

    /// Low-confidence club path: no invented structural cuts, but still
    /// impose a filter / pulse / SFX energy curve on continuous material.
    private static func lowConfidenceClubPlan(
        profile: AutoSongProfile,
        usableStart: Double,
        usableEnd: Double,
        tempo: AutoClubTempo.Decision,
        pulse: AutoClubPulse.Policy,
        flavor: AutoClubFlavor,
        tuning: AutoTuning,
        decisions: [AutoDecision],
        warnings: [String],
        seed: UInt64
    ) -> AutoRemixPlan? {
        let targetBPM = tempo.targetBPM
        let beat = 60.0 / max(targetBPM, 40)
        let bar = beat * 4
        let ratio = tempo.ratio
        var span = usableEnd - usableStart
        if span / ratio > tuning.maxTimelineSeconds {
            span = tuning.maxTimelineSeconds * ratio
        }
        let timelineDur = span / max(ratio, 0.0001)

        // Continuous placement split into energy-curve segments (no source jumps).
        let boundaries = [0.0, 0.18, 0.32, 0.48, 0.62, 0.78, 0.92, 1.0]
        let energies: [Double] = [0.4, 0.55, 0.7, 1.0, 0.4, 0.75, 0.95, 0.5]
        var placements: [AutoClipPlacement] = []
        var pulseRegions: [AutoClubPulse.Region] = []
        var intentionalGaps: [AutoIntentionalGap] = []
        var sfx: [AutoSFXEvent] = []
        var decisions = decisions

        for i in 0..<(boundaries.count - 1) {
            let a = boundaries[i], b = boundaries[i + 1]
            var t0 = timelineDur * a
            let t1 = timelineDur * b
            // Intentional pre-drop void: open a real timeline gap before drop 1.
            // This PAUSES playback (source does not advance during the void).
            if i == 3 {
                let voidSec = min(tuning.preferredPredropVoidBeats, tuning.maxIntentionalPauseBeats) * beat
                if voidSec > 0.05, t0 > voidSec {
                    if let prev = placements.indices.last {
                        let newEnd = t0 - voidSec
                        if newEnd > placements[prev].timelineStart + tuning.minSegmentSeconds * 0.5 {
                            placements[prev].timelineDuration = newEnd - placements[prev].timelineStart
                            if let lastRegion = pulseRegions.indices.last {
                                pulseRegions[lastRegion].timelineEnd = newEnd
                            }
                        }
                    }
                    intentionalGaps.append(
                        AutoIntentionalGap(start: t0 - voidSec, end: t0, reason: "pre-drop void")
                    )
                    pulseRegions.append(
                        AutoClubPulse.Region(role: .void, timelineStart: t0 - voidSec, timelineEnd: t0)
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .allowedPredropVoid,
                            songTitle: profile.title,
                            detail: "low-confidence energy curve"
                        )
                    )
                }
            }
            let role: AutoClubPulse.RegionRole
            switch i {
            case 0: role = .introTease
            case 1: role = .groove
            case 2: role = .build
            case 3: role = .drop
            case 4: role = .breakdown
            case 5: role = .build
            case 6: role = .drop
            default: role = .outro
            }
            // Last third of each build mutes kick+bass (build-out).
            if role == .build {
                let split = t0 + (t1 - t0) * 0.5
                pulseRegions.append(AutoClubPulse.Region(role: .build, timelineStart: t0, timelineEnd: split))
                pulseRegions.append(AutoClubPulse.Region(role: .buildOut, timelineStart: split, timelineEnd: t1))
            } else {
                pulseRegions.append(AutoClubPulse.Region(role: role, timelineStart: t0, timelineEnd: t1))
            }

            var fx = ClipEffectSettings()
            if role == .introTease || role == .breakdown {
                fx.setLevel(36, for: MixrEffect.blur.rawValue)
            }
            if role == .build {
                fx.flangerAmount = 0.18
                fx.setLevel(20, for: MixrEffect.echo.rawValue)
            }
            if pulse.duckSourceLowEnd, role == .drop || role == .groove {
                fx.setLevel(24, for: MixrEffect.blur.rawValue)
            }
            fx = AutoSupportedEffects.sanitize(fx)

            var volume = AutoGainPolicy.songPlacementVolume(energy: energies[i])
            if pulse.duckSourceLowEnd { volume *= AutoGainPolicy.pulseDuckedSongVolumeScale }

            // Source follows timeline except across an intentional void, where
            // playback pauses (source does not skip ahead with the gap).
            let sourceStart: Double
            if i > 0, let prev = placements.last,
               intentionalGaps.last.map({ abs($0.end - t0) < 0.02 }) == true {
                sourceStart = prev.sourceEnd
            } else {
                sourceStart = usableStart + t0 * ratio
            }

            placements.append(
                AutoClipPlacement(
                    songID: profile.songID,
                    sourceStart: sourceStart,
                    timelineStart: t0,
                    timelineDuration: t1 - t0,
                    tempoRatio: ratio,
                    volume: volume,
                    fadeIn: i == 0 ? .none : .none,
                    fadeOut: i == boundaries.count - 2
                        ? ClipTransition(type: .fadeOut, duration: 2, curve: AutoTransitionEnvelope.equalPowerCurveName)
                        : .none,
                    effects: fx,
                    role: .dominant,
                    slotIndex: i,
                    continuesPrevious: i > 0 && (intentionalGaps.last.map { abs($0.end - t0) > 0.02 } ?? true)
                )
            )

            if role == .drop {
                let asset = i == 3 ? "riser" : "snareBuild"
                if let def = SoundEffectLibrary.definition(for: asset), t0 - def.durationSeconds >= 0 {
                    sfx.append(AutoSFXEvent(assetID: asset, timelineStart: t0 - def.durationSeconds, purpose: "energy-curve \(asset)"))
                }
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: t0, purpose: "energy-curve impact"))
            }
        }

        let hits = AutoClubPulse.scheduleHits(
            regions: pulseRegions, policy: pulse, beatSeconds: beat, barSeconds: bar
        )
        // Hits are materialized at apply/render — keep sfxEvents musical-only.
        _ = hits

        let section = AutoSelectedSection(
            songID: profile.songID,
            sourceStart: usableStart,
            sourceEnd: usableStart + span,
            phraseType: "song",
            barCount: Int((timelineDur / bar).rounded()),
            hookScore: 1.0,
            energyScore: profile.analysis.meanEnergy(from: usableStart, to: usableEnd),
            vocalDensity: profile.analysis.meanVocalDensity(from: usableStart, to: usableEnd),
            compatibilityRole: .dominant,
            confidence: profile.analysis.analysisConfidence
        )

        return AutoRemixPlan(
            mode: .remix,
            targetBPM: targetBPM,
            targetDuration: timelineDur,
            anchorSongIDs: [profile.songID],
            selectedSections: [section],
            placements: placements,
            sfxEvents: sfx.sorted { $0.timelineStart < $1.timelineStart },
            cutRecords: [],
            usableSourceRange: usableStart...(usableStart + span),
            intentionalGaps: intentionalGaps,
            pulsePolicy: pulse,
            pulseRegions: pulseRegions,
            clubFlavor: flavor,
            mashupVocalSongID: nil,
            mashupBedSongID: nil,
            handoffCount: 0,
            songLetters: [profile.songID: "A"],
            sequence: ["A"],
            sequenceTitles: [profile.title],
            transitionsUsed: [],
            decisions: decisions,
            warnings: warnings,
            confidence: profile.analysis.analysisConfidence,
            randomSeed: seed
        )
    }

    /// Fallback candidate when the catalog has no matching label.
    private static func fallbackSection(
        profile: AutoSongProfile,
        label: AutoCandidateSection.Label,
        bars: Int,
        usableStart: Double,
        usableEnd: Double
    ) -> AutoCandidateSection? {
        let bar = profile.analysis.barSeconds
        let start: Double
        switch label {
        case .intro: start = usableStart
        case .chorus, .teaser:
            start = profile.analysis.chorusOrDropCandidates.first?.startSeconds ?? usableStart + bar * 8
        case .groove:
            start = profile.analysis.verseCandidates.first?.startSeconds ?? usableStart + bar * 4
        case .build:
            start = profile.analysis.buildCandidates.first?.startSeconds
                ?? (profile.analysis.chorusOrDropCandidates.first.map { $0.startSeconds - bar * 4 } ?? usableStart)
        case .breakdown:
            start = profile.analysis.bridgeCandidate?.startSeconds ?? usableStart + (usableEnd - usableStart) * 0.7
        case .ending:
            start = max(usableStart, usableEnd - Double(bars) * bar)
        }
        let clamped = min(max(usableStart, start), max(usableStart, usableEnd - Double(bars) * bar))
        return AutoCandidateSection(
            songID: profile.songID,
            label: label,
            startSeconds: clamped,
            barCount: bars,
            barSeconds: bar,
            hook: label == .chorus ? 0.85 : 0.5,
            energy: 0.6,
            vocal: 0.5,
            clarity: 0.5,
            rhythm: profile.analysis.drumStrength,
            uniqueness: 0.5,
            transitionUse: 0.5,
            confidence: profile.analysis.analysisConfidence
        )
    }

    /// Downbeat-snapped source time of the largest sustained energy rise
    /// (mean of the next 4 s minus mean of the previous 4 s), or nil when
    /// nothing rises by at least `minRise`.
    private static func biggestEnergyRise(
        signal: SongSignalFeatures,
        analysis: SongAnalysis,
        from: Double,
        to: Double,
        minRise: Double
    ) -> Double? {
        let hop = signal.hopSeconds
        let curve = signal.energyCurve
        guard hop > 0, !curve.isEmpty, to > from else { return nil }
        let windowHops = max(1, Int(4.0 / hop))

        func mean(_ lo: Int, _ hi: Int) -> Double {
            let a = max(0, lo), b = min(curve.count, hi)
            guard b > a else { return 0 }
            var s = 0.0
            for i in a..<b { s += curve[i] }
            return s / Double(b - a)
        }

        var bestRise = 0.0
        var bestTime: Double?
        var t = from
        while t < to {
            let idx = Int(t / hop)
            let rise = mean(idx, idx + windowHops) - mean(idx - windowHops, idx)
            if rise > bestRise {
                bestRise = rise
                bestTime = t
            }
            t += 0.5
        }
        guard bestRise >= minRise, let raw = bestTime else { return nil }
        let snapped = analysis.downbeats.min { abs($0 - raw) < abs($1 - raw) } ?? raw
        return (snapped >= from && snapped <= to) ? snapped : raw
    }

    // MARK: - Mashup (2+ songs) — hook-over-bed

    private static func mashupPlan(
        profiles: [AutoSongProfile],
        tuning: AutoTuning,
        seed: UInt64,
        rng: inout AutoRandom
    ) -> AutoRemixPlan? {
        // Hook-over-bed: highest featureScore = sung hook; highest
        // anchorScore among the rest = club bed. Not equal ping-pong.
        guard let vocal = profiles.max(by: { $0.featureScore < $1.featureScore }) else { return nil }
        let bedPool = profiles.filter { $0.songID != vocal.songID }
        guard let bed = bedPool.max(by: { $0.anchorScore < $1.anchorScore }) ?? bedPool.first else {
            // Single profile somehow — shouldn't happen for mashup entry.
            return nil
        }
        let extras = profiles
            .filter { $0.songID != vocal.songID && $0.songID != bed.songID }
            .sorted { $0.featureScore > $1.featureScore }

        // Letter order: A = bed (continuity), B = vocal hook, then extras.
        var ordered = [bed, vocal] + extras

        var preDecisions: [AutoDecision] = [
            AutoDecision(
                kind: .assignedMashupRoles,
                songTitle: nil,
                detail: "Hook: \(vocal.title) over club bed: \(bed.title)"
            ),
            AutoDecision(kind: .selectedAnchor, songTitle: bed.title, detail: "club bed / continuity")
        ]
        var preWarnings: [String] = []

        // Key preference: same Camelot, then ±1, then relative — pitch the BED.
        let vocalKey = AutoKey.parse(vocal.analysis.key)
        let bedKey = AutoKey.parse(bed.analysis.key)
        let keyFit = AutoKey.bestCorrection(vocalKey, bedKey, maxShift: tuning.maxCorrectivePitchSemitones)
        if keyFit.score < 0.45 {
            preDecisions.append(
                AutoDecision(
                    kind: .refusedMashupPair,
                    songTitle: nil,
                    detail: "Keys clash beyond a safe bed pitch shift — Autofell back to phrase handoffs without a forced mashup drop."
                )
            )
            preWarnings.append(
                "Key compatibility is weak between \(vocal.title) and \(bed.title); avoided forcing a drop-on-drop mashup."
            )
        }

        let tempoPair = AutoClubTempo.mashupDecision(
            vocalBPM: vocal.analysis.bpm,
            bedBPM: bed.analysis.bpm,
            maxVocalStretch: tuning.maxStretch,
            maxInstrumentalStretch: tuning.maxInstrumentalStretch
        )
        if !tempoPair.ok {
            preDecisions.append(
                AutoDecision(
                    kind: .refusedMashupPair,
                    songTitle: nil,
                    detail: tempoPair.detail
                )
            )
            preWarnings.append(tempoPair.detail)
            // Soft refuse: still produce a conservative phrase-aligned plan
            // rather than crashing Entire Project — but do not stretch the vocal.
        }
        preDecisions.append(
            AutoDecision(
                kind: .choseClubTempo,
                songTitle: bed.title,
                detail: tempoPair.detail
            )
        )

        if ordered.count >= 6 {
            let budgetBars = Int(tuning.maxTimelineSeconds / (240.0 / bed.analysis.bpm))
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

        let targetBPM = tempoPair.ok ? tempoPair.targetBPM : AutoTempo.targetBPM(
            profiles: ordered,
            anchorID: bed.songID,
            maxStretch: tuning.maxInstrumentalStretch
        )

        let slots: [Slot]
        switch ordered.count {
        case 2: slots = duoHookOverBedSlots()
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
            preDecisions: preDecisions,
            mashupVocalID: vocal.songID,
            mashupBedID: bed.songID,
            bedTempoRatio: tempoPair.ok ? tempoPair.bedRatio : nil,
            vocalTempoRatio: tempoPair.ok ? tempoPair.vocalRatio : 1.0,
            bedPitchSemitones: keyFit.score >= 0.5 ? keyFit.shiftSemitones : 0
        )
        plan?.warnings.insert(contentsOf: preWarnings, at: 0)
        return plan
    }

    /// Hook-over-bed duo: bed owns intro/groove/builds/break; vocal lands
    /// the familiar hook ON the drop. Minimum stay 8 bars; choruses 16.
    private static func duoHookOverBedSlots() -> [Slot] {
        [
            Slot(songIdx: 0, role: .intro, bars: 8, entry: .none, energy: 0.45, shrinkPriority: 2),
            Slot(songIdx: 0, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.58),
            Slot(songIdx: 0, role: .build, bars: 8, entry: .flangerBuild, energy: 0.72),
            Slot(songIdx: 1, role: .chorus, bars: 16, entry: .hardHypeCut, energy: 1.0), // Drop 1 = vocal hook
            Slot(songIdx: 0, role: .breakdown, bars: 8, entry: .atmosphericHandoff, energy: 0.4),
            Slot(songIdx: 0, role: .build, bars: 8, entry: .flangerBuild, energy: 0.82, isReturn: true),
            Slot(songIdx: 1, role: .chorus, bars: 16, entry: .hardHypeCut, energy: 1.0, isFinalPeak: true, isReturn: true),
            Slot(songIdx: 0, role: .ending, bars: 4, entry: .vocalEchoOut, energy: 0.55, isEnding: true, shrinkPriority: 0),
        ]
    }

    /// Legacy alternation kept for 3+ song sets (bed still index 0).
    private static func duoSlots() -> [Slot] {
        duoHookOverBedSlots()
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
        preDecisions: [AutoDecision] = [],
        mashupVocalID: UUID? = nil,
        mashupBedID: UUID? = nil,
        bedTempoRatio: Double? = nil,
        vocalTempoRatio: Double? = nil,
        bedPitchSemitones: Int = 0
    ) -> AutoRemixPlan? {
        let barSec = 240.0 / max(targetBPM, 40)
        let beatSec = barSec / 4
        let minBars = barSec * 2 >= tuning.minSegmentSeconds ? 2 : 4

        var decisions: [AutoDecision] = preDecisions
        var warnings: [String] = []
        var intentionalGaps: [AutoIntentionalGap] = []
        var pulseRegions: [AutoClubPulse.Region] = []

        let letters = ordered.enumerated().reduce(into: [UUID: String]()) { dict, item in
            dict[item.element.songID] = String(UnicodeScalar(UInt8(65 + min(item.offset, 25))))
        }

        // Pulse from the bed (or first song): one-kick rule for mashups.
        let pulseSource = ordered.first(where: { $0.songID == mashupBedID }) ?? ordered[0]
        let pulse = AutoClubPulse.policy(
            drumStrength: pulseSource.analysis.drumStrength,
            bassDensity: pulseSource.analysis.bassDensity
        )
        if pulse.sourceHasClubKick {
            decisions.append(
                AutoDecision(kind: .skippedSecondKick, songTitle: pulseSource.title, detail: pulse.detail)
            )
        } else if pulse.writesKick {
            decisions.append(
                AutoDecision(kind: .wroteClubPulse, songTitle: pulseSource.title, detail: pulse.detail)
            )
        }

        var fits: [Int: AutoTempo.Fit] = [:]
        for (i, p) in ordered.enumerated() {
            let fit: AutoTempo.Fit
            if mode == .remix {
                fit = AutoTempo.Fit(ratio: 1.0, gridAligned: true, halfOrDoubleTime: false)
            } else if let vocalID = mashupVocalID, p.songID == vocalID, let vocalTempoRatio {
                fit = AutoTempo.Fit(
                    ratio: vocalTempoRatio,
                    gridAligned: abs(vocalTempoRatio - 1) <= tuning.maxStretch || abs(vocalTempoRatio - 1) < 0.0001,
                    halfOrDoubleTime: false
                )
            } else if let bedID = mashupBedID, p.songID == bedID, let bedTempoRatio {
                fit = AutoTempo.Fit(
                    ratio: bedTempoRatio,
                    gridAligned: abs(bedTempoRatio - 1) <= tuning.maxInstrumentalStretch,
                    halfOrDoubleTime: false
                )
            } else {
                fit = AutoTempo.fit(
                    songBPM: p.analysis.bpm,
                    targetBPM: targetBPM,
                    maxStretch: p.songID == mashupVocalID ? tuning.maxStretch : tuning.maxInstrumentalStretch
                )
            }
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
                        "\(p.title) is outside the safe stretch window; Auto kept its native tempo and used clean phrase-aligned handoffs for it."
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

            // Intentional pre-drop void before a hard hype cut (≤ half bar).
            if entry == .hardHypeCut, !profile.lowConfidence, cursor > 0 {
                let voidBeats = min(tuning.preferredPredropVoidBeats, tuning.maxIntentionalPauseBeats)
                let pause = voidBeats * beatSec
                if pause > 0.05 {
                    intentionalGaps.append(
                        AutoIntentionalGap(
                            start: cursor,
                            end: cursor + pause,
                            reason: "pre-drop void"
                        )
                    )
                    pulseRegions.append(
                        AutoClubPulse.Region(role: .void, timelineStart: cursor, timelineEnd: cursor + pause)
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .allowedPredropVoid,
                            songTitle: profile.title,
                            detail: String(format: "%.2f beats", voidBeats)
                        )
                    )
                    cursor += pause
                }
            }

            let duration = Double(bars) * barSec
            var mutableSlot = slot
            mutableSlot.entry = entry
            mutableSlot.energy = energy

            let pulseRole: AutoClubPulse.RegionRole
            switch slot.role {
            case .intro, .teaser: pulseRole = .introTease
            case .groove: pulseRole = .groove
            case .build: pulseRole = .build
            case .chorus: pulseRole = .drop
            case .breakdown: pulseRole = .breakdown
            case .ending: pulseRole = .outro
            }
            // Build-out mute for last 4 bars of builds ≥ 8.
            if slot.role == .build, bars >= 8 {
                let bodyBars = bars - 4
                let bodyDur = Double(bodyBars) * barSec
                pulseRegions.append(
                    AutoClubPulse.Region(role: .build, timelineStart: cursor, timelineEnd: cursor + bodyDur)
                )
                pulseRegions.append(
                    AutoClubPulse.Region(
                        role: .buildOut,
                        timelineStart: cursor + bodyDur,
                        timelineEnd: cursor + duration
                    )
                )
            } else {
                pulseRegions.append(
                    AutoClubPulse.Region(role: pulseRole, timelineStart: cursor, timelineEnd: cursor + duration)
                )
            }

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
                    // Mashup: pitch the BED only — never the star vocal.
                    let mayPitchSupport = mashupBedID == nil
                        || prevProfile.songID == mashupBedID
                    if mayPitchSupport, compat.pitchCorrectionSemitones != 0 {
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
                    if mayPitchSupport, compat.pitchCorrectionSemitones != 0 {
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

        // Pitch the BED only (never the star vocal) when a small Camelot fix helps.
        if bedPitchSemitones != 0, let bedID = mashupBedID {
            let amount = min(1.0, Double(abs(bedPitchSemitones)) / 3.0)
            for i in placements.indices where placements[i].songID == bedID {
                placements[i].effects.pitchDirection = bedPitchSemitones > 0 ? .up : .down
                placements[i].effects.pitchAmount = amount
                placements[i].effects = AutoSupportedEffects.sanitize(placements[i].effects)
            }
            if let bedTitle = ordered.first(where: { $0.songID == bedID })?.title {
                decisions.append(
                    AutoDecision(
                        kind: .pitchCorrectedOverlap,
                        songTitle: bedTitle,
                        detail: "\(bedPitchSemitones > 0 ? "+" : "")\(bedPitchSemitones) st on bed"
                    )
                )
            }
        }

        // Club pulse hits materialize at apply/render from pulseRegions.
        _ = AutoClubPulse.scheduleHits(
            regions: pulseRegions,
            policy: pulse,
            beatSeconds: beatSec,
            barSeconds: barSec
        )

        return AutoRemixPlan(
            mode: mode,
            targetBPM: targetBPM,
            targetDuration: cursorEnd(placed),
            anchorSongIDs: [ordered[0].songID],
            selectedSections: sections,
            placements: placements,
            sfxEvents: sfx.sorted { $0.timelineStart < $1.timelineStart },
            intentionalGaps: intentionalGaps,
            pulsePolicy: pulse,
            pulseRegions: pulseRegions,
            clubFlavor: nil,
            mashupVocalSongID: mashupVocalID,
            mashupBedSongID: mashupBedID,
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
