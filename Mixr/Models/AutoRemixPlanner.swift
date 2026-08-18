import Foundation

// MARK: - Auto Remix Planner
//
// Generates an AutoRemixPlan from the project's songs:
//
//   1 song   → REMIX: club phrase-grid rewrite + thin-song pulse
//   2…5 songs → MASHUP: one club bed + rotating hooks on the two-wave
//                club shape; complementary vocal stacks on drops OK
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
        /// Repeat the same ~8-bar title chorus (do not walk 16 source bars
        /// into verse 2). Timeline still fills 16 bars before Drop 1.
        var holdTitleChorus = false
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

        let byID = Dictionary(profiles.map { ($0.songID, $0) }, uniquingKeysWith: { first, _ in first })
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
            drumStrength: profile.pulseDrumStrength,
            bassDensity: analysis.bassDensity,
            bpm: analysis.bpm,
            analysisConfidence: analysis.analysisConfidence
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
        if profile.stems.drums != nil {
            decisions.append(
                AutoDecision(
                    kind: .usedStemSidecar,
                    songTitle: profile.title,
                    detail: "kick energy from drums.wav"
                )
            )
        }

        let targetBPM = tempo.targetBPM
        let beat = 60.0 / max(targetBPM, 40)
        let bar = beat * 4
        let ratio = tempo.ratio

        // Xirex grammar: opening uncut → one complete hook → 2-bar pivot
        // wallpaper → Drop 1 hard cut. Cut earlier (~bar 18): no long groove
        // runway after the hook is already done.
        let shape: [(role: AutoCandidateSection.Label, bars: Int, energy: Double, pulse: AutoClubPulse.RegionRole, entry: AutoTransitionRecipe)] = [
            (.intro, 8, 0.45, .introTease, .none),
            (.chorus, 8, 0.88, .groove, .none),                 // title hook (hard cut, no fade-in)
            (.build, 2, 0.70, .buildOut, .flangerBuild),      // pivot wallpaper window
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
            case .intro: labels = [.intro, .groove] // never teaser — protect title
            case .groove: labels = [.groove, .chorus]
            case .build: labels = [.build, .groove]
            // First complete A hook stays chorus/groove — never a 2–4 bar title teaser.
            case .chorus:
                labels = slot.entry == .hardHypeCut ? [.chorus, .teaser] : [.chorus, .groove]
            case .breakdown: labels = [.breakdown, .groove]
            case .ending: labels = [.ending, .teaser, .chorus]
            default: labels = [slot.role]
            }

            guard var section = profile.best(labels, tuning: tuning, used: usedRanges, allowReuse: true)
                ?? fallbackSection(profile: profile, label: slot.role, bars: slot.bars, usableStart: usableStart, usableEnd: usableEnd)
            else { continue }

            // Protect opening: intro always starts at the record head.
            if slot.role == .intro {
                section = AutoCandidateSection(
                    songID: section.songID,
                    label: .intro,
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

            // Drop slots (hard hype): strongest chorus islands ≥8 bars.
            // First complete hook (pulse .groove / clean crossfade) keeps the
            // record playing — never a title teaser or mid-song jump that
            // chops the first “Oops”.
            if slot.role == .chorus {
                let hooks = profile.candidates
                    .filter { ($0.label == .chorus || $0.label == .teaser) && $0.barCount >= 8 }
                    .sorted { $0.hook > $1.hook }
                if slot.entry == .hardHypeCut {
                    if dropIndex < hooks.count {
                        section = hooks[dropIndex]
                    } else if let bestHook = hooks.first {
                        section = bestHook
                    }
                } else if slot.pulse == .groove {
                    let start = lastSourceEnd ?? usableStart
                    section = AutoCandidateSection(
                        songID: section.songID,
                        label: .chorus,
                        startSeconds: min(start, max(usableStart, usableEnd - Double(slot.bars) * bar * ratio)),
                        barCount: slot.bars,
                        barSeconds: section.barSeconds,
                        hook: max(section.hook, 0.85),
                        energy: slot.energy,
                        vocal: section.vocal,
                        clarity: section.clarity,
                        rhythm: section.rhythm,
                        uniqueness: section.uniqueness,
                        transitionUse: section.transitionUse,
                        confidence: section.confidence
                    )
                }
            }

            // Clamp section into usable range and requested bar count.
            let wantSeconds = Double(slot.bars) * bar
            let sourceDur = wantSeconds * ratio

            // One-song club rewrite stays source-forward except justified
            // hook returns on the drop. Random rewinds get deleted by the
            // validator and leave audible holes — the opposite of busy.
            if slot.role != .chorus,
               let last = lastSourceEnd,
               section.startSeconds < last - 0.05 {
                let advanced = min(last, max(usableStart, usableEnd - sourceDur))
                section = AutoCandidateSection(
                    songID: section.songID,
                    label: section.label,
                    startSeconds: max(usableStart, advanced),
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
                // Never rewind a non-chorus slot just to fit length — shorten
                // into the remaining source instead (avoids validator holes).
                let floor = (slot.role == .chorus)
                    ? usableStart
                    : (lastSourceEnd ?? usableStart)
                let start = max(floor, usableEnd - sourceDur)
                let clampedStart = min(max(usableStart, start), max(usableStart, usableEnd - bar * 2))
                section = AutoCandidateSection(
                    songID: section.songID,
                    label: section.label,
                    startSeconds: clampedStart,
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

            // No 1-beat pre-drop void. Pivot Drop 1 is loop + hard cut at
            // full clip volume. Auto must not emit `allowedPredropVoid` on
            // the same plan as `pivotWallpaperLoop` (crate bounce flags
            // that pair as a quiet Drop 1 hole).

            if slot.entry != .none { transitionsUsed.append(slot.entry) }

            // Xirex 1–2 bar pivot window: no dominant audio here — grains land
            // when Drop 1 emits (after the completed hook phrase).
            if slot.role == .build, slot.bars <= 4, slot.pulse == .buildOut {
                let dur = Double(slot.bars) * bar
                pulseRegions.append(
                    AutoClubPulse.Region(role: .buildOut, timelineStart: cursor, timelineEnd: cursor + dur)
                )
                cursor += dur
                continue
            }

            // Split build into body + buildOut (kick mute).
            let segments: [(bars: Int, pulse: AutoClubPulse.RegionRole, energy: Double)]
            if slot.role == .build, buildBodyBars < timelineBars {
                segments = [
                    (buildBodyBars, .build, slot.energy * 0.85),
                    // Build-out: kick mute / filter — keep audible energy (not dead air).
                    (timelineBars - buildBodyBars, .buildOut, 0.52),
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
                    // Two-deck: intros stay the record — light HPF only.
                    fx.setLevel(28, for: MixrEffect.blur.rawValue)
                case .build:
                    fx.flangerAmount = seg.pulse == .buildOut ? 0.36 : (slot.energy > 0.78 ? 0.30 : 0.22)
                    fx.setLevel(seg.pulse == .buildOut ? 42 : 18, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .pingPong
                    if seg.pulse == .buildOut {
                        // Filter sweep into the void/drop — mix window only.
                        fx.setLevel(58, for: MixrEffect.blur.rawValue)
                        fx.setLevel(20, for: MixrEffect.reverb.rawValue)
                        fx.reverbPreset = .hall
                    } else {
                        fx.setLevel(18, for: MixrEffect.blur.rawValue)
                    }
                case .chorus:
                    // Filter opens on the downbeat — Diplo energy lives here.
                    fx.setLevel(dropIndex == 0 ? 6 : 10, for: MixrEffect.blur.rawValue)
                    fx.setLevel(dropIndex == 0 ? 12 : 16, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = dropIndex == 0 ? .hall : .ambient
                    fx.setLevel(dropIndex == 0 ? 8 : 12, for: MixrEffect.echo.rawValue)
                    if dropIndex >= 1, flavor.bias.drop2AiryLayer {
                        fx.setLevel(14, for: MixrEffect.reverb.rawValue)
                    }
                    if flavor.bias.aggressiveLowEnd {
                        fx.flangerAmount = max(fx.flangerAmount, 0.12)
                    }
                case .breakdown:
                    fx.setLevel(28 + flavor.bias.breakdownVocalClarity * 22, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = .ambient
                    fx.setLevel(12, for: MixrEffect.blur.rawValue)
                case .ending:
                    fx.setLevel(22, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = .ambient
                case .groove:
                    // One deck: the record, maybe light HPF — no echo wallpaper.
                    fx.setLevel(12, for: MixrEffect.blur.rawValue)
                default:
                    break
                }
                if pulse.duckSourceLowEnd, seg.pulse == .drop || seg.pulse == .groove || seg.pulse == .introTease {
                    fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 22), for: MixrEffect.blur.rawValue)
                }
                fx = AutoSupportedEffects.sanitize(fx)

                let sourceStart = section.startSeconds + Double(segCursor - cursor) * ratio
                var volume = AutoGainPolicy.songPlacementVolume(energy: seg.energy)
                if slot.entry == .hardHypeCut, seg.pulse == .drop {
                    volume = AutoGainPolicy.incomingDropVolume
                }
                // Blur ducks low end on pulse; do not also quiet drop/build volumes.
                if pulse.duckSourceLowEnd, seg.pulse == .groove || seg.pulse == .introTease {
                    volume *= AutoGainPolicy.pulseDuckedSongVolumeScale
                }

                let continues = lastSourceEnd.map { abs(sourceStart - $0) < 0.05 } ?? false
                let discontinuity = lastSourceEnd.map { abs(sourceStart - $0) > 0.05 } ?? false

                if discontinuity, let prevEnd = lastSourceEnd {
                    let isHookReturn = slot.role == .chorus
                    let prevVol = placements.last?.volume ?? volume
                    let volDeltaDB = abs(20 * log10(max(volume, 0.05) / max(prevVol, 0.05)))
                    let prevBlur = placements.last?.effects.level(for: "blur") ?? 0
                    let fxFloor = (prevBlur >= 28 || fx.level(for: "blur") >= 28) ? 6.0 : 0.0
                    let endingFloor = slot.role == .ending ? 6.0 : 0.0
                    cutRecords.append(
                        AutoCutRecord(
                            timelineAt: segCursor,
                            sourceFrom: prevEnd,
                            sourceTo: sourceStart,
                            reason: isHookReturn ? .hookReturn : .redundantRepeat,
                            confidence: max(0.55, section.confidence),
                            expectedEnergyDeltaDB: isHookReturn
                                ? (slot.entry == .hardHypeCut ? max(8.0, volDeltaDB) : max(2.0, volDeltaDB))
                                : max(volDeltaDB, fxFloor, endingFloor),
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
                // Xirex: hard cut into the hook — no fade-in / volume ramp.
                if slot.entry == .hardHypeCut, segIdx == 0 {
                    fadeIn = .none
                } else if slot.entry == .cleanCrossfade, segIdx == 0, placements.isEmpty == false {
                    fadeIn = ClipTransition(
                        type: .crossfade,
                        duration: 2,
                        curve: AutoTransitionEnvelope.equalPowerCurveName
                    )
                }
                if slot.role == .ending {
                    fadeOut = ClipTransition(type: .echoOut, duration: 8)
                } else if slot.role == .build, seg.pulse == .buildOut, slot.bars >= 8 {
                    // Long builds may echo out; the 1–2 bar pivot window is grains only.
                    fadeOut = ClipTransition(type: .echoOut, duration: 4)
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

            // Coordinated club SFX — diet on the Xirex pivot join.
            let segEnd = segCursor
            if slot.role == .build, slot.bars >= 8 {
                let buildEnd = segEnd
                if let snare = SoundEffectLibrary.definition(for: "snareBuild"),
                   buildEnd - snare.durationSeconds >= cursor {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "snareBuild",
                            timelineStart: buildEnd - snare.durationSeconds,
                            purpose: "snare roll through build-out"
                        )
                    )
                }
                if let riser = SoundEffectLibrary.definition(for: "riser"),
                   buildEnd - riser.durationSeconds >= cursor {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "riser",
                            timelineStart: buildEnd - riser.durationSeconds,
                            purpose: "riser into the drop"
                        )
                    )
                }
            }

            if slot.role == .groove || slot.role == .intro {
                // Two-deck: verses/grooves stay one deck — no clap wallpaper.
            }

            if slot.role == .chorus, slot.entry == .hardHypeCut {
                let dropAt = placements.last(where: { $0.slotIndex == slotIdx })?.timelineStart
                    ?? cursor
                // Pivot Drop 1: one impact slam only. No riser/tape/crash pile.
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: dropAt, purpose: "impact on drop downbeat"))
                if dropIndex > 0 {
                    let cymbalCount = sfx.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }.count
                    if cymbalCount < 2 {
                        sfx.append(AutoSFXEvent(assetID: "crash", timelineStart: dropAt, purpose: "crash punctuation on drop"))
                    }
                }
                decisions.append(
                    AutoDecision(
                        kind: .addedRiserIntoDrop,
                        songTitle: profile.title,
                        detail: dropIndex == 0
                            ? "pivot hard-cut slam (impact only)"
                            : "drop 2 flip (impact)"
                    )
                )
                // Xirex pivot wallpaper before Drop 1 only.
                if dropIndex == 0,
                   let phrase = placements.last(where: {
                       $0.role == .dominant && $0.slotIndex != slotIdx
                   }) {
                    appendPivotWallpaperLoop(
                        completedPhrase: phrase,
                        dropTimelineStart: dropAt,
                        deckATitle: profile.title,
                        deckBTitle: profile.title,
                        barSec: bar,
                        beatSec: beat,
                        tuning: tuning,
                        grainStem: profile.stems.hasVocals ? .vocals : nil,
                        placements: &placements,
                        pulseRegions: &pulseRegions,
                        intentionalGaps: &intentionalGaps,
                        decisions: &decisions
                    )
                }
                dropIndex += 1
            }

            if slot.role == .breakdown {
                let breakAt = cursor
                sfx.append(
                    AutoSFXEvent(assetID: "downlifter", timelineStart: breakAt, purpose: "downlifter into breakdown")
                )
            }

            if slot.role == .ending {
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: cursor, purpose: "final hit"))
                sfx.append(
                    AutoSFXEvent(assetID: "downlifter", timelineStart: cursor + 0.8, purpose: "downlifter out")
                )
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
            barSeconds: bar,
            halfTimeDrop: flavor.bias.halfTimeDrop
        )

        // Blend verse→build joins with equal-power. Club drops stay hard
        // cuts (pivot Drop 1, hook-return Drop 2) — never a quiet void and
        // never an equal-power fade-in that dives energy after the slam.
        blendAdjacentHandoffs(
            placements: &placements,
            intentionalGaps: intentionalGaps,
            pulseRegions: pulseRegions,
            songDurations: [profile.songID: analysis.durationSeconds],
            barSec: bar,
            beatSec: beat,
            tuning: tuning,
            cutRecords: &cutRecords
        )

        stripVoidsWhenDrop1HasPivot(
            placements: placements,
            beatSec: beat,
            barSec: bar,
            decisions: &decisions,
            intentionalGaps: &intentionalGaps,
            pulseRegions: &pulseRegions
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
            randomSeed: seed,
            stemsBySongID: [profile.songID: profile.stems]
        )
    }

    /// Low-confidence club path: still uses the compact phrase-grid TIMELINE
    /// (Drop 1 at bar 24) and jumps source to the strongest hook island for
    /// drops. We avoid inventing decorative mid-verse cuts, but "no cuts" must
    /// not mean "play 50 bars of verse before the drop."
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

        // Xirex-ish low-conf shape: opening → first hook → 2-bar pivot → Drop 1 (~bar 18).
        struct Seg {
            var role: AutoClubPulse.RegionRole
            var bars: Int
            var energy: Double
        }
        let shape: [Seg] = [
            .init(role: .introTease, bars: 8, energy: 0.42),
            .init(role: .groove, bars: 8, energy: 0.80), // first complete hook listen-through
            .init(role: .buildOut, bars: 2, energy: 0.50), // pivot wallpaper window
            .init(role: .drop, bars: 16, energy: 1.00),
            .init(role: .breakdown, bars: 8, energy: 0.40),
            .init(role: .build, bars: 4, energy: 0.70),
            .init(role: .buildOut, bars: 4, energy: 0.48),
            .init(role: .drop, bars: 16, energy: 1.00),
            .init(role: .outro, bars: 4, energy: 0.45),
        ]

        // Strongest chorus / teaser islands for Drop 1 and Drop 2.
        let hooks = profile.candidates
            .filter { ($0.label == .chorus || $0.label == .teaser) && $0.barCount >= 8 }
            .sorted { $0.hook > $1.hook }
        let hook1 = hooks.first?.startSeconds
            ?? profile.analysis.chorusOrDropCandidates.first?.startSeconds
            ?? max(usableStart, usableStart + (usableEnd - usableStart) * 0.28)
        let hook2 = hooks.dropFirst().first?.startSeconds
            ?? hooks.first.map { $0.startSeconds + Double($0.barCount) * $0.barSeconds }
            ?? hook1

        var placements: [AutoClipPlacement] = []
        var pulseRegions: [AutoClubPulse.Region] = []
        var intentionalGaps: [AutoIntentionalGap] = []
        var cutRecords: [AutoCutRecord] = []
        var sfx: [AutoSFXEvent] = []
        var decisions = decisions
        var cursor = 0.0
        var lastSourceEnd: Double?
        var dropIndex = 0
        var cymbalPunctuation = 0  // crash+reverseCymbal cap (≤2)

        for (i, seg) in shape.enumerated() {
            let segDur = Double(seg.bars) * bar
            let t0 = cursor
            let t1 = cursor + segDur

            let role = seg.role
            pulseRegions.append(AutoClubPulse.Region(role: role, timelineStart: t0, timelineEnd: t1))

            var fx = ClipEffectSettings()
            if role == .introTease {
                fx.setLevel(28, for: MixrEffect.blur.rawValue)
            }
            if role == .breakdown {
                fx.setLevel(36, for: MixrEffect.blur.rawValue)
                fx.setLevel(28, for: MixrEffect.reverb.rawValue)
                fx.reverbPreset = .ambient
            }
            if role == .groove {
                fx.setLevel(12, for: MixrEffect.blur.rawValue)
            }
            if role == .build {
                fx.flangerAmount = 0.26
                fx.setLevel(18, for: MixrEffect.echo.rawValue)
                fx.echoPreset = .pingPong
                fx.setLevel(18, for: MixrEffect.blur.rawValue)
            }
            if role == .buildOut {
                fx.flangerAmount = 0.34
                fx.setLevel(56, for: MixrEffect.blur.rawValue)
                fx.setLevel(36, for: MixrEffect.echo.rawValue)
                fx.echoPreset = .pingPong
                fx.setLevel(18, for: MixrEffect.reverb.rawValue)
            }
            if role == .drop {
                fx.setLevel(8, for: MixrEffect.blur.rawValue)
                fx.setLevel(14, for: MixrEffect.reverb.rawValue)
                fx.reverbPreset = .hall
                fx.setLevel(8, for: MixrEffect.echo.rawValue)
            }
            if pulse.duckSourceLowEnd, role == .drop || role == .groove {
                fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 24), for: MixrEffect.blur.rawValue)
            }
            fx = AutoSupportedEffects.sanitize(fx)

            var volume = AutoGainPolicy.songPlacementVolume(energy: seg.energy)
            if role == .drop {
                volume = AutoGainPolicy.incomingDropVolume
            }
            if pulse.duckSourceLowEnd, role == .groove || role == .introTease {
                volume *= AutoGainPolicy.pulseDuckedSongVolumeScale
            }

            // Source: continuous through tease/build; JUMP to hook on drops.
            // First complete-hook listen-through (pre-pivot groove@0.80) also
            // jumps to the strongest hook — then plays it continuous once.
            let sourceStart: Double
            let sourceContinuous: Bool
            let isFirstHookPass = role == .groove && seg.energy >= 0.78 && dropIndex == 0
            if role == .drop || isFirstHookPass {
                let hookStart = dropIndex == 0 ? hook1 : hook2
                let clamped = min(max(usableStart, hookStart), max(usableStart, usableEnd - segDur * ratio))
                sourceStart = clamped
                sourceContinuous = false
                if role == .drop, let prevEnd = lastSourceEnd, abs(clamped - prevEnd) > 0.05 {
                    cutRecords.append(
                        AutoCutRecord(
                            timelineAt: t0,
                            sourceFrom: prevEnd,
                            sourceTo: clamped,
                            reason: .hookReturn,
                            confidence: max(0.55, profile.analysis.analysisConfidence),
                            expectedEnergyDeltaDB: 8.0,
                            masking: .sfx(assetID: "impact")
                        )
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .returnedToHook,
                            songTitle: profile.title,
                            detail: String(format: "low-conf Drop %d → hook @%.1fs", dropIndex + 1, clamped)
                        )
                    )
                }
            } else if role == .buildOut, seg.bars <= 4, dropIndex == 0 {
                // Pivot window — no dominant audio; grains added at drop.
                pulseRegions.append(AutoClubPulse.Region(role: role, timelineStart: t0, timelineEnd: t1))
                cursor = t1
                continue
            } else if let prev = lastSourceEnd {
                sourceStart = role == .introTease ? usableStart : prev
                sourceContinuous = role != .introTease
            } else {
                sourceStart = usableStart
                sourceContinuous = false
            }

            var fadeOut: ClipTransition = .none
            if role == .outro {
                fadeOut = ClipTransition(
                    type: .echoOut,
                    duration: 6,
                    curve: AutoTransitionEnvelope.equalPowerCurveName
                )
            } else if role == .buildOut || role == .build {
                fadeOut = ClipTransition(type: .echoOut, duration: 4)
            }

            placements.append(
                AutoClipPlacement(
                    songID: profile.songID,
                    sourceStart: sourceStart,
                    timelineStart: t0,
                    timelineDuration: segDur,
                    tempoRatio: ratio,
                    volume: volume,
                    fadeIn: .none,
                    fadeOut: fadeOut,
                    effects: fx,
                    role: .dominant,
                    slotIndex: i,
                    continuesPrevious: sourceContinuous
                )
            )
            lastSourceEnd = sourceStart + segDur * ratio

            // Two-deck: SFX only in mix window / on the drop — not groove wallpaper.
            if role == .buildOut, !(seg.bars <= 4 && dropIndex == 0) {
                // Non-pivot build-outs may carry snare/riser into a plain drop.
                if let snare = SoundEffectLibrary.definition(for: "snareBuild"), t1 - snare.durationSeconds >= t0 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "snareBuild",
                            timelineStart: t1 - snare.durationSeconds,
                            purpose: "snare through build-out"
                        )
                    )
                }
                if let riser = SoundEffectLibrary.definition(for: "riser"),
                   t1 - riser.durationSeconds >= t0 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "riser",
                            timelineStart: t1 - riser.durationSeconds,
                            purpose: "riser into the drop"
                        )
                    )
                }
            }
            if role == .drop {
                // Pivot Drop 1: impact slam only. Drop 2 may keep light crash.
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: t0, purpose: "impact on drop"))
                if dropIndex > 0, cymbalPunctuation < 2 {
                    sfx.append(AutoSFXEvent(assetID: "crash", timelineStart: t0, purpose: "crash punctuation on drop"))
                    cymbalPunctuation += 1
                }
                if dropIndex == 0,
                   let phrase = placements.last(where: {
                       $0.role == .dominant && $0.timelineEnd <= t0 + 0.05
                   }) {
                    appendPivotWallpaperLoop(
                        completedPhrase: phrase,
                        dropTimelineStart: t0,
                        deckATitle: profile.title,
                        deckBTitle: profile.title,
                        barSec: bar,
                        beatSec: beat,
                        tuning: tuning,
                        grainStem: profile.stems.hasVocals ? .vocals : nil,
                        placements: &placements,
                        pulseRegions: &pulseRegions,
                        intentionalGaps: &intentionalGaps,
                        decisions: &decisions
                    )
                }
                dropIndex += 1
            }
            if role == .breakdown {
                sfx.append(AutoSFXEvent(assetID: "downlifter", timelineStart: t0, purpose: "downlifter into breakdown"))
            }
            if role == .outro {
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: t0, purpose: "final hit"))
            }

            cursor = t1
        }

        _ = AutoClubPulse.scheduleHits(
            regions: pulseRegions,
            policy: pulse,
            beatSeconds: beat,
            barSeconds: bar,
            halfTimeDrop: flavor.bias.halfTimeDrop
        )

        stripVoidsWhenDrop1HasPivot(
            placements: placements,
            beatSec: beat,
            barSec: bar,
            decisions: &decisions,
            intentionalGaps: &intentionalGaps,
            pulseRegions: &pulseRegions
        )

        let timelineDur = cursor
        let section = AutoSelectedSection(
            songID: profile.songID,
            sourceStart: usableStart,
            sourceEnd: min(usableEnd, lastSourceEnd ?? usableStart),
            phraseType: "song",
            barCount: Int((timelineDur / bar).rounded()),
            hookScore: hooks.first?.hook ?? 0.8,
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
            sequence: ["A"],
            sequenceTitles: [profile.title],
            transitionsUsed: [],
            decisions: decisions,
            warnings: warnings,
            confidence: profile.analysis.analysisConfidence,
            randomSeed: seed,
            stemsBySongID: [profile.songID: profile.stems]
        )
    }

    /// Carve a pre-drop void from the end of the previous bar so the drop
    /// remains on a downbeat (bar boundary). Does not advance the cursor.
    private static func carvePredropVoid(
        voidStart: Double,
        dropStart: Double,
        placements: inout [AutoClipPlacement],
        pulseRegions: inout [AutoClubPulse.Region],
        intentionalGaps: inout [AutoIntentionalGap],
        minSegmentSeconds: Double
    ) {
        if let idx = placements.indices.last {
            let newDur = voidStart - placements[idx].timelineStart
            if newDur >= minSegmentSeconds {
                placements[idx].timelineDuration = newDur
            }
        }
        for i in pulseRegions.indices where pulseRegions[i].timelineEnd > voidStart + 0.001 {
            if pulseRegions[i].timelineStart >= voidStart - 0.001 {
                pulseRegions[i].timelineEnd = pulseRegions[i].timelineStart
            } else {
                pulseRegions[i].timelineEnd = voidStart
            }
        }
        pulseRegions.removeAll { $0.timelineEnd - $0.timelineStart < 0.02 }
        intentionalGaps.append(
            AutoIntentionalGap(start: voidStart, end: dropStart, reason: "pre-drop void")
        )
        pulseRegions.append(
            AutoClubPulse.Region(role: .void, timelineStart: voidStart, timelineEnd: dropStart)
        )
    }

    /// Xirex pivot wallpaper: after Deck A’s chorus/hook plays COMPLETE,
    /// loop the last 1-beat grain 4–8× (1–2 bars; default 8× = 2 bars) with
    /// rising HPF, then hard-cut into Deck B. Not echo throws, not 1/8 spam,
    /// not intro chops. Volume stays loud — blur thins the kick, it does not duck.
    private static func appendPivotWallpaperLoop(
        completedPhrase: AutoClipPlacement,
        dropTimelineStart: Double,
        deckATitle: String?,
        deckBTitle: String?,
        barSec: Double,
        beatSec: Double,
        tuning: AutoTuning,
        grainStem: AutoStemKind? = nil,
        placements: inout [AutoClipPlacement],
        pulseRegions: inout [AutoClubPulse.Region],
        intentionalGaps: inout [AutoIntentionalGap],
        decisions: inout [AutoDecision]
    ) {
        let repeats = tuning.pivotWallpaperBeats
        let loopDur = tuning.pivotWindowSeconds(barSec: barSec)
        let loopStart = dropTimelineStart - loopDur
        guard loopStart >= 0.05 else { return }

        // Pivot join owns this downbeat — never keep a 1-beat void beside
        // the wallpaper (that hole is the old quiet song-switch).
        clearPredropVoidOnPivotJoin(
            dropTimelineStart: dropTimelineStart,
            intentionalGaps: &intentionalGaps,
            pulseRegions: &pulseRegions
        )

        // Grain = last 1 beat of a COMPLETED line (must have already sounded).
        // If the phrase is a title teaser / sub-8-bar chop, skip the loop
        // rather than slicing the first “Oops” — keep playing through the
        // reserved window so the song-switch join does not go quiet.
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
        let grainSource = AutoPivotWord.lastBeatGrainSource(
            phraseSourceStart: completedPhrase.sourceStart,
            phraseSourceEnd: phraseEnd,
            beatSec: beatSec,
            tempoRatio: completedPhrase.tempoRatio
        )

        // Trim Deck A dominants out of the loop window (wallpaper owns it).
        for i in placements.indices where placements[i].role == .dominant {
            let p = placements[i]
            if p.timelineStart < loopStart, p.timelineEnd > loopStart + 0.01 {
                let newDur = loopStart - p.timelineStart
                if newDur >= tuning.minSegmentSeconds * 0.5 {
                    placements[i].timelineDuration = newDur
                    placements[i].fadeOut = ClipTransition(type: .none, duration: 0)
                }
            } else if p.timelineStart >= loopStart - 0.01, p.timelineStart < dropTimelineStart {
                placements[i].timelineDuration = 0
            }
        }
        placements.removeAll { $0.timelineDuration < 0.05 }

        // Pulse: kick out through the thinned stutter.
        pulseRegions.removeAll {
            $0.timelineEnd > loopStart + 0.01 && $0.timelineStart < dropTimelineStart - 0.01
        }
        pulseRegions.append(
            AutoClubPulse.Region(role: .buildOut, timelineStart: loopStart, timelineEnd: dropTimelineStart)
        )

        let pivot = AutoPivotWord.preferredPivot(
            deckATitle: deckATitle ?? "",
            deckBTitle: deckBTitle ?? deckATitle ?? ""
        )

        for i in 0..<repeats {
            let t0 = loopStart + Double(i) * beatSec
            // Rising HPF: thin/tinny through the 1–2 bars. Volume stays up.
            let blur = 40.0 + (30.0 * Double(i) / Double(max(repeats - 1, 1)))
            var fx = ClipEffectSettings()
            fx.setLevel(blur, for: MixrEffect.blur.rawValue)
            fx = AutoSupportedEffects.sanitize(fx)

            placements.append(
                AutoClipPlacement(
                    songID: completedPhrase.songID,
                    sourceStart: grainSource,
                    timelineStart: t0,
                    timelineDuration: beatSec,
                    tempoRatio: completedPhrase.tempoRatio,
                    volume: AutoGainPolicy.pivotGrainVolume,
                    fadeIn: ClipTransition(type: .none, duration: 0),
                    fadeOut: ClipTransition(type: .none, duration: 0),
                    effects: fx,
                    role: .supporting,
                    slotIndex: completedPhrase.slotIndex,
                    overlapsPreviousSeconds: beatSec,
                    stemKind: grainStem
                )
            )
        }

        decisions.append(
            AutoDecision(
                kind: .pivotWallpaperLoop,
                songTitle: deckATitle,
                detail: String(
                    format: "%d×1-beat%@%@ → hard cut @%.1fs",
                    repeats,
                    pivot.map { " “\($0)”" } ?? "",
                    grainStem == .vocals ? " vocal-stem" : "",
                    dropTimelineStart
                )
            )
        )
        if grainStem == .vocals {
            decisions.append(
                AutoDecision(
                    kind: .usedStemSidecar,
                    songTitle: deckATitle,
                    detail: "pivot grain from vocals.wav"
                )
            )
        }
    }

    /// A 1-beat void next to pivot wallpaper is the old quiet hole.
    /// Strip it from the plan when the join is loop + hard cut.
    private static func clearPredropVoidOnPivotJoin(
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

    /// Crate bounce flags `pivotWallpaperLoop` + `allowedPredropVoid` as a
    /// quiet Drop 1 hole even when the gap was meant for Drop 2. If Drop 1
    /// has a pivot join, strip every pre-drop void from the plan.
    private static func stripVoidsWhenDrop1HasPivot(
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

    /// Keep Deck A playing through a reserved pivot window when we skip the
    /// last-word loop — no quiet hole just to switch songs.
    private static func fillPivotWindowWithoutLoop(
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

    /// 8-bar chorus continuation from `from` (snapped to a downbeat). Nil
    /// when the source cannot host a complete line — caller must skip.
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

    /// First complete Deck A hook for a mashup: jump to the bed's **title**
    /// chorus island (measured energy-rise entrance). Never continue from
    /// the intro into verse, and never lock to `chorusOrDropCandidates.first`
    /// when that snap is a repeated prechorus (~40s on Oops).
    private static func bedFirstCompleteChorusSection(
        profile: AutoSongProfile,
        used: [(Double, Double)],
        bars: Int,
        energy: Double,
        tuning: AutoTuning
    ) -> AutoCandidateSection? {
        // Title chorus is ~8 bars (Oops). A 16-bar request used to walk source
        // linearly into verse 2 — callers fill 16 timeline bars via a hold slot.
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
            title: profile.title
        )

        func overlapsUsed(_ start: Double, bars: Int) -> Bool {
            let end = start + Double(bars) * bar
            return used.contains { range in
                let overlap = min(end, range.1) - max(start, range.0)
                return overlap > Double(bars) * bar * 0.5
            }
        }

        // Whisper lyrics.json is the source of truth: place at the lyric snap
        // (at-or-before). Do not substitute a later catalog chorus (50.38 → 50.5).
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

        // No usable energy shape: pick the highest-hook chorus that is not
        // glued to the intro tail (that glue is the 28% prechorus snap).
        let unglued = pool.filter { $0.startSeconds > introEnd + bar * 1.5 }
        let ranked = (unglued.isEmpty ? pool : unglued).sorted { $0.hook > $1.hook }
        return ranked.first
    }

    /// Best cameo-chop guest to own Drop 1 when full-hook stretch fails.
    private static func bestCameoDrop1Guest(
        cameos: [AutoSongProfile],
        bed: AutoSongProfile,
        targetBPM: Double,
        tuning: AutoTuning
    ) -> AutoSongProfile? {
        cameos.max { a, b in
            let ia = AutoMashability.bestIsland(
                guest: a, bed: bed, wantBars: 16, targetBPM: targetBPM, tuning: tuning
            )?.score ?? AutoStemRoleProxy.hookScore(for: a)
            let ib = AutoMashability.bestIsland(
                guest: b, bed: bed, wantBars: 16, targetBPM: targetBPM, tuning: tuning
            )?.score ?? AutoStemRoleProxy.hookScore(for: b)
            return ia < ib
        }
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

    // MARK: - Mashup (2…5 songs) — one bed, rotating hooks on the club shape

    private static func mashupPlan(
        profiles: [AutoSongProfile],
        tuning: AutoTuning,
        seed: UInt64,
        rng: inout AutoRandom
    ) -> AutoRemixPlan? {
        // Cap the club rewrite at five songs — extras are dropped by confidence.
        var pool = profiles
        if pool.count > 5 {
            pool.sort { $0.analysis.analysisConfidence > $1.analysis.analysisConfidence }
            let dropped = Array(pool.suffix(from: 5))
            pool = Array(pool.prefix(5))
            // Re-sort later after role assignment; keep decisions below.
            _ = dropped
        }

        // ONE club bed: prefer the pocket that keeps guests legal, then
        // same-pocket groove/kit vs strongest-hook vocal (not raw drum max).
        guard let bed = chooseClubBed(pool: pool, tuning: tuning) else { return nil }
        let guests = pool.filter { $0.songID != bed.songID }

        let tempoSeed = AutoClubTempo.mashupDecision(
            vocalBPM: guests.first?.analysis.bpm ?? bed.analysis.bpm,
            bedBPM: bed.analysis.bpm,
            maxVocalStretch: tuning.maxStretch,
            maxInstrumentalStretch: tuning.maxInstrumentalStretch
        )
        let targetBPM = tempoSeed.ok ? tempoSeed.targetBPM : AutoTempo.targetBPM(
            profiles: pool,
            anchorID: bed.songID,
            maxStretch: tuning.maxInstrumentalStretch
        )

        var preDecisions: [AutoDecision] = [
            AutoDecision(kind: .selectedAnchor, songTitle: bed.title, detail: "club bed / one kick+bass owner")
        ]
        var preWarnings: [String] = []
        if profiles.count > 5 {
            preWarnings.append("Capped mashup at 5 songs for a streaming-length club rewrite.")
            for p in profiles where !pool.contains(where: { $0.songID == p.songID }) {
                preDecisions.append(
                    AutoDecision(kind: .excludedLowConfidenceSong, songTitle: p.title, detail: "over the 5-song club mashup cap")
                )
            }
        }

        // Gate every guest; rank full-hook candidates by AutoMashup hook-role
        // proxy + featureScore (star topline ≠ max drums).
        var fullHooks: [AutoSongProfile] = []
        var cameos: [AutoSongProfile] = []
        for guest in guests.sorted(by: {
            AutoStemRoleProxy.hookScore(for: $0) > AutoStemRoleProxy.hookScore(for: $1)
        }) {
            let verdict = AutoMashupCompat.hookGate(
                hook: guest, bed: bed, targetBPM: targetBPM, tuning: tuning
            )
            switch verdict.gate {
            case .fullHook:
                fullHooks.append(guest)
            case .cameoChop:
                cameos.append(guest)
                preDecisions.append(
                    AutoDecision(kind: .usedCameoOnly, songTitle: guest.title, detail: verdict.detail)
                )
            case .skip:
                preDecisions.append(
                    AutoDecision(kind: .skippedIncompatibleHook, songTitle: guest.title, detail: verdict.detail)
                )
                preWarnings.append("Skipped \(guest.title): \(verdict.detail)")
            }
        }

        // Prefer the guest whose best 8–16 bar island mashability vs the bed
        // wins (AutoMashUpper local mashability — not whole-song stretch).
        if fullHooks.count > 1 {
            fullHooks.sort { a, b in
                let ia = AutoMashability.bestIsland(
                    guest: a, bed: bed, wantBars: 16, targetBPM: targetBPM, tuning: tuning
                )?.score ?? AutoStemRoleProxy.hookScore(for: a)
                let ib = AutoMashability.bestIsland(
                    guest: b, bed: bed, wantBars: 16, targetBPM: targetBPM, tuning: tuning
                )?.score ?? AutoStemRoleProxy.hookScore(for: b)
                return ia > ib
            }
        }

        // Drop 1 = strongest full hook; Drop 2 = next (or bed chorus flip on duo).
        // Stretch-failed guests (cameoChop) still own Drop 1 as phrase islands
        // at native tempo — never demote them to post-drop groove slots only.
        var drop1: AutoSongProfile?
        if let first = fullHooks.first {
            drop1 = first
        } else if let cameo = bestCameoDrop1Guest(
            cameos: cameos,
            bed: bed,
            targetBPM: targetBPM,
            tuning: tuning
        ) {
            drop1 = cameo
            cameos.removeAll { $0.songID == cameo.songID }
            preDecisions.append(
                AutoDecision(
                    kind: .usedCameoOnly,
                    songTitle: cameo.title,
                    detail: "phrase-chop Drop 1 at native tempo (stretch gate failed)"
                )
            )
        }
        let drop2Candidate = fullHooks.dropFirst().first
        // Surplus full hooks become cameos (rotate islands, don't stack).
        if fullHooks.count > 2 {
            cameos.append(contentsOf: fullHooks.suffix(from: 2))
        }
        // Energy matching: ballads prefer breakdown runway.
        var breakdownCameo: AutoSongProfile?
        var grooveCameo: AutoSongProfile?
        var outroCameo: AutoSongProfile?
        var remainingCameos = cameos
        if let soft = remainingCameos.first(where: { AutoMashupCompat.needsBreakdownRunway(guest: $0, bed: bed) }) {
            breakdownCameo = soft
            remainingCameos.removeAll { $0.songID == soft.songID }
            preDecisions.append(
                AutoDecision(
                    kind: .usedCameoOnly,
                    songTitle: soft.title,
                    detail: "breakdown runway (energy match)"
                )
            )
        }
        if let g = remainingCameos.first {
            grooveCameo = g
            remainingCameos.removeFirst()
        }
        if let o = remainingCameos.first {
            outroCameo = o
            remainingCameos.removeFirst()
        }
        // Any leftover cameos → outro teaser chain (still ≥8 bars each when placed).
        if breakdownCameo == nil, let soft = remainingCameos.first {
            breakdownCameo = soft
            remainingCameos.removeFirst()
        }

        // ordered indices: 0 = bed, then drop1, drop2 (if guest), then cameos used in slots.
        var ordered: [AutoSongProfile] = [bed]
        if let drop1 { ordered.append(drop1) }
        let drop2IsBedFlip = drop2Candidate == nil && drop1 != nil
        if let drop2Candidate { ordered.append(drop2Candidate) }
        var indexOf: [UUID: Int] = [bed.songID: 0]
        for (i, p) in ordered.enumerated() where i > 0 { indexOf[p.songID] = i }
        func ensureIndex(_ p: AutoSongProfile) -> Int {
            if let i = indexOf[p.songID] { return i }
            ordered.append(p)
            let i = ordered.count - 1
            indexOf[p.songID] = i
            return i
        }
        let grooveIdx = grooveCameo.map { ensureIndex($0) }
        let breakIdx = breakdownCameo.map { ensureIndex($0) }
        let outroIdx = outroCameo.map { ensureIndex($0) }
        for leftover in remainingCameos { _ = ensureIndex(leftover) }

        let drop1Idx = drop1.map { indexOf[$0.songID]! }
        let drop2Idx: Int = {
            if let d = drop2Candidate { return indexOf[d.songID]! }
            return 0 // bed chorus flip
        }()

        // Hook-replace default: one guest melody on the drop. Optional
        // call-and-response is gated (≤8 bars) — never dual-vocal wallpaper.
        func vocalEnough(_ idx: Int) -> Bool {
            let p = ordered[idx]
            return p.analysis.meanVocalDensity(from: 0, to: p.analysis.durationSeconds) >= 0.35
                || p.featureScore >= 0.45
        }
        func pickOverlay(excluding lead: Int?, prefer: [Int?]) -> Int? {
            var seen = Set<Int>()
            if let lead { seen.insert(lead) }
            for candidate in prefer {
                guard let idx = candidate, !seen.contains(idx), vocalEnough(idx) else { continue }
                seen.insert(idx)
                return idx
            }
            return nil
        }
        let drop1OverlayIdx: Int? = tuning.allowCallAndResponseOverlay
            ? pickOverlay(
                excluding: drop1Idx,
                prefer: [
                    drop2Candidate.map { indexOf[$0.songID]! },
                    grooveIdx, breakIdx, outroIdx,
                ]
            )
            : nil
        let drop2OverlayIdx: Int? = tuning.allowCallAndResponseOverlay
            ? pickOverlay(
                excluding: drop2Idx,
                prefer: [drop1Idx, outroIdx, grooveIdx, breakIdx]
            )
            : nil

        let roleDetail: String
        if let drop1, let drop2Candidate {
            roleDetail = "Bed: \(bed.title); Drop 1: \(drop1.title); Drop 2: \(drop2Candidate.title)"
        } else if let drop1 {
            roleDetail = "Bed: \(bed.title); Drop 1: \(drop1.title); Drop 2: \(bed.title) hook flip"
        } else {
            roleDetail = "Bed: \(bed.title) — no compatible full vocal hook; bed carries both drops"
            preWarnings.append("No guest passed the full-hook gate; bed material carries the drops.")
        }
        preDecisions.insert(
            AutoDecision(kind: .assignedMashupRoles, songTitle: nil, detail: roleDetail),
            at: 0
        )

        // Bed pitch from strongest drop hook when available.
        let pitchPartner = drop1 ?? drop2Candidate
        let keyFit = AutoKey.bestCorrection(
            AutoKey.parse(pitchPartner?.analysis.key),
            AutoKey.parse(bed.analysis.key),
            maxShift: tuning.maxCorrectivePitchSemitones
        )
        let bedPitch = (pitchPartner != nil && keyFit.score >= 0.5) ? keyFit.shiftSemitones : 0

        let bedTempo = AutoClubTempo.mashupDecision(
            vocalBPM: drop1?.analysis.bpm ?? bed.analysis.bpm,
            bedBPM: bed.analysis.bpm,
            maxVocalStretch: tuning.maxStretch,
            maxInstrumentalStretch: tuning.maxInstrumentalStretch
        )
        preDecisions.append(
            AutoDecision(kind: .choseClubTempo, songTitle: bed.title, detail: bedTempo.detail)
        )
        if !bedTempo.ok {
            preWarnings.append(bedTempo.detail)
        }

        let slots = nSongClubMashupSlots(
            drop1Idx: drop1Idx,
            drop2Idx: drop2Idx,
            drop2IsBedFlip: drop2IsBedFlip || drop1 == nil,
            grooveCameoIdx: grooveIdx,
            breakdownCameoIdx: breakIdx,
            outroCameoIdx: outroIdx
        )

        // Per-guest vocal stretch from the hook gate (Drop 1 + Drop 2 + cameos).
        let resolvedBPM = bedTempo.ok ? bedTempo.targetBPM : targetBPM
        var guestTempoRatios: [UUID: Double] = [:]
        for guest in ordered where guest.songID != bed.songID {
            let v = AutoMashupCompat.hookGate(
                hook: guest, bed: bed, targetBPM: resolvedBPM, tuning: tuning
            )
            guestTempoRatios[guest.songID] = v.vocalRatio
        }
        let vocalTempoRatio = drop1.flatMap { guestTempoRatios[$0.songID] }

        var plan = buildPlan(
            mode: .mashup,
            slots: slots,
            ordered: ordered,
            targetBPM: resolvedBPM,
            tuning: tuning,
            seed: seed,
            rng: &rng,
            preDecisions: preDecisions,
            mashupVocalID: drop1?.songID,
            mashupBedID: bed.songID,
            bedTempoRatio: bedTempo.ok ? bedTempo.bedRatio : nil,
            vocalTempoRatio: vocalTempoRatio,
            bedPitchSemitones: bedPitch,
            guestTempoRatios: guestTempoRatios,
            mashupDrop2ID: drop2IsBedFlip || drop1 == nil ? bed.songID : drop2Candidate?.songID,
            drop1VocalOverlayIdx: drop1OverlayIdx,
            drop2VocalOverlayIdx: drop2OverlayIdx
        )
        plan?.warnings.insert(contentsOf: preWarnings, at: 0)
        _ = rng.next()
        return plan
    }

    /// Choose the club bed for an N-song mashup.
    /// - Same pocket duo: star topline = vocal, partner = bed. Never assign
    ///   bed by raw max drumConfidence (BOMT 1.00 must not beat Oops 0.71).
    /// - Cross-pocket / N>2: prefer a bed whose native pocket the arrangement
    ///   will actually keep (no parking a 144 festival bed at 95).
    private static func chooseClubBed(
        pool: [AutoSongProfile],
        tuning: AutoTuning
    ) -> AutoSongProfile? {
        guard !pool.isEmpty else { return nil }
        if pool.count == 1 { return pool[0] }

        // Locked gold-standard pair in any N-song crate: Oops = bed when BOMT is present.
        if let locked = AutoMashupRoleLock.britneyBed(in: pool) {
            return locked
        }

        if pool.count == 2 {
            let a = pool[0], b = pool[1]
            let pa = AutoClubTempo.classify(a.analysis.bpm)
            let pb = AutoClubTempo.classify(b.analysis.bpm)
            if let pa, let pb, pa == pb {
                return samePocketDuoBed(a, b)
            }
        }

        return pool.max { bedFitness($0, pool: pool, tuning: tuning) < bedFitness($1, pool: pool, tuning: tuning) }
    }

    /// Same-pocket duo bed. Midtempo pop pairs (Britney-class) often measure
    /// similar — or even skewed — vocal density. Bed = groove partner via
    /// soft-capped drums + bass (AutoMashup role proxy spirit: bed ≠ max
    /// drumConfidence). Vocal density must NOT invert Oops↔BOMT; the hotter
    /// raw drum bus is usually the radio single that rides Drop 1.
    private static func samePocketDuoBed(_ a: AutoSongProfile, _ b: AutoSongProfile) -> AutoSongProfile {
        func grooveBed(_ p: AutoSongProfile) -> Double {
            // Soft-cap so drum 1.00 cannot beat a 0.71 groove partner.
            let drum = min(p.analysis.drumStrength, 0.72)
            let bass = p.analysis.bassDensity
            let softPrefer = (1.0 - min(1.0, p.analysis.drumStrength)) * 0.35
            // Tiny vocal term as tie-break only — never enough to flip 1.00 vs 0.71.
            let vocal = p.analysis.meanVocalDensity(from: 0, to: p.analysis.durationSeconds)
            return drum * 0.30 + bass * 0.40 + softPrefer - vocal * 0.05
        }
        return grooveBed(a) >= grooveBed(b) ? a : b
    }

    /// Bed fitness across pockets: must keep the bed's native pocket on the
    /// timeline. A festival bed that would resolve to a midtempo median is
    /// disqualified (all-5 crate → no 144 song parked at 95).
    private static func bedFitness(
        _ candidate: AutoSongProfile,
        pool: [AutoSongProfile],
        tuning: AutoTuning
    ) -> Double {
        let guests = pool.filter { $0.songID != candidate.songID }
        let bedBPM = candidate.analysis.bpm
        let pocket = AutoClubTempo.classify(bedBPM)
        let pocketRank: Double
        switch pocket {
        case .festival: pocketRank = 1.0
        case .house: pocketRank = 0.95
        case .midtempoPop: pocketRank = 0.55
        case .other: pocketRank = 0.4
        case nil: pocketRank = 0.35
        }

        // Will AutoTempo.targetBPM actually keep this bed's pocket?
        let resolvedTarget = AutoTempo.targetBPM(
            profiles: pool,
            anchorID: candidate.songID,
            maxStretch: tuning.maxInstrumentalStretch
        )
        let keepsPocket = abs(resolvedTarget - bedBPM) / max(bedBPM, 1) <= 0.10
        let pocketKeepScore: Double = keepsPocket ? 1.0 : 0.05

        var guestScore = 0.0
        for g in guests {
            let decision = AutoClubTempo.mashupDecision(
                vocalBPM: g.analysis.bpm,
                bedBPM: bedBPM,
                maxVocalStretch: tuning.maxStretch,
                maxInstrumentalStretch: tuning.maxInstrumentalStretch
            )
            if decision.ok, abs(decision.targetBPM - bedBPM) / max(bedBPM, 1) <= 0.10 {
                guestScore += 1.0
            } else if decision.ok {
                guestScore += 0.25
            } else {
                // Cameo at native tempo — fine, but does not justify yanking the bed.
                guestScore += 0.35
            }
        }
        let guestNorm = guestScore / Double(max(guests.count, 1))

        // Soft-cap drums so raw 1.00 cannot dominate bed choice.
        let groove = min(candidate.analysis.drumStrength, 0.72) * 0.10
            + candidate.analysis.bassDensity * 0.08
        let meanVocal = candidate.analysis.meanVocalDensity(
            from: 0, to: candidate.analysis.durationSeconds
        )
        let instrumental = (1.0 - min(1, meanVocal)) * 0.10
        let conf = candidate.analysis.analysisConfidence * 0.05

        return pocketKeepScore * 0.40
            + pocketRank * 0.20
            + guestNorm * 0.22
            + groove
            + instrumental
            + conf
    }

    /// Legacy single-song bed heuristic (tests / debugging).
    private static func bedScore(_ p: AutoSongProfile) -> Double {
        bedFitness(p, pool: [p], tuning: .standard)
    }

    /// Two-wave club shape for N-song mashups. Indices into `ordered`
    /// (0 = bed). Min stay 8 bars; hooks prefer 16. No 4-bar ping-pong.
    /// Xirex: bed intro → complete bed chorus (16 bars) → 2-bar pivot → guest Drop 1
    /// (~bar 24). Groove cameos move after Drop 1 so the join stays early.
    private static func nSongClubMashupSlots(
        drop1Idx: Int?,
        drop2Idx: Int,
        drop2IsBedFlip: Bool,
        grooveCameoIdx: Int?,
        breakdownCameoIdx: Int?,
        outroCameoIdx: Int?
    ) -> [Slot] {
        var slots: [Slot] = [
            Slot(songIdx: 0, role: .intro, bars: 6, entry: .none, energy: 0.45, shrinkPriority: 2),
        ]
        // Complete Deck A title chorus BEFORE pivot: 8 bars + 8-bar HOLD of
        // the same island (16 timeline bars). Do not linearly walk 16 source
        // bars from the title downbeat into verse 2 (“you see my problem is this”).
        slots.append(Slot(
            songIdx: 0, role: .chorus, bars: 8, entry: .none, energy: 0.88,
            shrinkPriority: 0
        ))
        slots.append(Slot(
            songIdx: 0, role: .chorus, bars: 8, entry: .none, energy: 0.88,
            shrinkPriority: 0, holdTitleChorus: true
        ))
        // 2-bar pivot window — replaced with 1-beat wallpaper grains at emit time.
        slots.append(Slot(songIdx: 0, role: .build, bars: 2, entry: .flangerBuild, energy: 0.72, shrinkPriority: 1))

        if let d1 = drop1Idx {
            slots.append(Slot(songIdx: d1, role: .chorus, bars: 16, entry: .hardHypeCut, energy: 1.0))
        } else {
            slots.append(Slot(songIdx: 0, role: .chorus, bars: 16, entry: .hardHypeCut, energy: 1.0))
        }

        // Optional groove cameo after the first join (not before — keeps Drop 1 early).
        if let g = grooveCameoIdx {
            slots.append(Slot(songIdx: g, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.55))
        }

        if let b = breakdownCameoIdx {
            slots.append(Slot(songIdx: b, role: .breakdown, bars: 8, entry: .atmosphericHandoff, energy: 0.38))
        } else {
            slots.append(Slot(songIdx: 0, role: .breakdown, bars: 8, entry: .atmosphericHandoff, energy: 0.4))
        }

        slots.append(Slot(songIdx: 0, role: .build, bars: 8, entry: .flangerBuild, energy: 0.82, isReturn: true))
        slots.append(
            Slot(
                songIdx: drop2Idx,
                role: .chorus,
                bars: 16,
                entry: .hardHypeCut,
                energy: 1.0,
                isFinalPeak: true,
                isReturn: drop2IsBedFlip || (drop1Idx.map { $0 == drop2Idx } ?? false)
            )
        )

        if let o = outroCameoIdx {
            slots.append(Slot(songIdx: o, role: .teaser, bars: 8, entry: .vocalEchoOut, energy: 0.5, isEnding: true, shrinkPriority: 0))
        } else {
            slots.append(Slot(songIdx: 0, role: .ending, bars: 8, entry: .vocalEchoOut, energy: 0.55, isEnding: true, shrinkPriority: 0))
        }
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
        bedPitchSemitones: Int = 0,
        guestTempoRatios: [UUID: Double] = [:],
        mashupDrop2ID: UUID? = nil,
        drop1VocalOverlayIdx: Int? = nil,
        drop2VocalOverlayIdx: Int? = nil
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
            drumStrength: pulseSource.pulseDrumStrength,
            bassDensity: pulseSource.analysis.bassDensity,
            bpm: pulseSource.analysis.bpm,
            analysisConfidence: pulseSource.analysis.analysisConfidence
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
        if pulseSource.stems.drums != nil {
            decisions.append(
                AutoDecision(
                    kind: .usedStemSidecar,
                    songTitle: pulseSource.title,
                    detail: "kick energy from drums.wav"
                )
            )
        }

        // Mashup club flavor — Diplo default when pop vocals sit on a club bed.
        let vocalDensity = ordered.map {
            $0.analysis.meanVocalDensity(from: 0, to: $0.analysis.durationSeconds)
        }.max() ?? 0.5
        let mashupFlavor = AutoClubFlavor.choose(
            drumStrength: pulseSource.analysis.drumStrength,
            bassDensity: pulseSource.analysis.bassDensity,
            vocalDensity: vocalDensity,
            bpm: targetBPM,
            seed: seed ^ 0xD1_F10
        )
        decisions.append(
            AutoDecision(kind: .choseClubFlavor, songTitle: pulseSource.title, detail: mashupFlavor.rawValue)
        )

        var fits: [Int: AutoTempo.Fit] = [:]
        for (i, p) in ordered.enumerated() {
            let fit: AutoTempo.Fit
            if mode == .remix {
                fit = AutoTempo.Fit(ratio: 1.0, gridAligned: true, halfOrDoubleTime: false)
            } else if let bedID = mashupBedID, p.songID == bedID, let bedTempoRatio {
                fit = AutoTempo.Fit(
                    ratio: bedTempoRatio,
                    gridAligned: abs(bedTempoRatio - 1) <= tuning.maxInstrumentalStretch,
                    halfOrDoubleTime: false
                )
            } else if let guestRatio = guestTempoRatios[p.songID] {
                // Drop 1 / Drop 2 / cameo guests — gate-approved stretch only.
                fit = AutoTempo.Fit(
                    ratio: guestRatio,
                    gridAligned: abs(guestRatio - 1) <= tuning.maxStretch + 0.0001,
                    halfOrDoubleTime: false
                )
            } else if let vocalID = mashupVocalID, p.songID == vocalID, let vocalTempoRatio {
                fit = AutoTempo.Fit(
                    ratio: vocalTempoRatio,
                    gridAligned: abs(vocalTempoRatio - 1) <= tuning.maxStretch || abs(vocalTempoRatio - 1) < 0.0001,
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
        // Mashups keep ≥8-bar identity stays (no 4-bar ping-pong).
        let barFloor = mode == .mashup ? 8 : 4
        var shrinkPass = 2
        while totalSeconds() > tuning.maxTimelineSeconds, shrinkPass >= 1 {
            var shrunk = false
            for i in slots.indices where slots[i].shrinkPriority >= shrinkPass && slots[i].bars > barFloor {
                slots[i].bars = slots[i].bars == 16 ? 8 : barFloor
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
            let isFirstCompleteAHook = mode == .mashup
                && slot.songIdx == 0
                && slot.role == .chorus
                && slot.entry != .hardHypeCut
                && !slot.isReturn
                && !slot.holdTitleChorus
            switch slot.role {
            case .teaser: labelChain = [[.teaser], [.chorus], [.groove]]
            case .chorus:
                // First complete Deck A hook never falls through to a 2–4 bar
                // title teaser. Skip the loop later if no last-word grain.
                if isFirstCompleteAHook {
                    labelChain = [[.chorus], [.groove]]
                } else {
                    labelChain = [[.chorus], [.groove], [.teaser]]
                }
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

            // Title-chorus hold: replay the same 8-bar island (not verse 2).
            if mode == .mashup, slot.holdTitleChorus, slot.role == .chorus {
                if let prior = placed.last(where: {
                    $0.slot.songIdx == slot.songIdx
                        && $0.slot.role == .chorus
                        && !$0.slot.holdTitleChorus
                        && $0.slot.entry != .hardHypeCut
                }) {
                    section = AutoCandidateSection(
                        songID: prior.section.songID,
                        label: .chorus,
                        startSeconds: prior.section.startSeconds,
                        barCount: 8,
                        barSeconds: prior.section.barSeconds,
                        hook: prior.section.hook,
                        energy: prior.section.energy,
                        vocal: prior.section.vocal,
                        clarity: prior.section.clarity,
                        rhythm: prior.section.rhythm,
                        uniqueness: prior.section.uniqueness,
                        transitionUse: prior.section.transitionUse,
                        confidence: prior.section.confidence
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .returnedToHook,
                            songTitle: profile.title,
                            detail: String(
                                format: "title chorus hold @%.1fs (repeat 8-bar island, not verse-2 walk)",
                                prior.section.startSeconds
                            )
                        )
                    )
                }
            }
            if isFirstCompleteAHook {
                let introEnd = profile.analysis.introCandidate?.endSeconds ?? barSec * 8
                let phrase = profile.analysis.phraseBoundaries.count >= 2
                    ? max(barSec * 4, profile.analysis.phraseBoundaries[1] - profile.analysis.phraseBoundaries[0])
                    : barSec * 8
                let measuredEntrance = AutoChorusIsland.bestEntrance(
                    signal: profile.analysis.signal,
                    downbeats: profile.analysis.downbeats,
                    barSeconds: barSec,
                    duration: profile.analysis.durationSeconds,
                    introEnd: introEnd,
                    phraseSeconds: phrase,
                    title: profile.title
                )
                if let chorus = bedFirstCompleteChorusSection(
                    profile: profile,
                    used: used,
                    bars: slot.bars,
                    energy: slot.energy,
                    tuning: tuning
                ) {
                    section = chorus
                    let rawList: String
                    if let sig = profile.analysis.signal {
                        rawList = AutoChorusIsland.titleEntranceCandidates(
                            signal: sig,
                            downbeats: profile.analysis.downbeats,
                            barSeconds: barSec,
                            duration: profile.analysis.durationSeconds,
                            introEnd: introEnd,
                            phraseSeconds: phrase,
                            title: profile.title
                        )
                        .map { String(format: "%.1f", $0.startSeconds) }
                        .joined(separator: ",")
                    } else {
                        rawList = ""
                    }
                    let dump = AutoChorusIsland.bedHookDecisionDump(
                        profile: profile,
                        measured: measuredEntrance,
                        chosenStart: chorus.startSeconds
                    )
                    let tokensDump = AutoChorusIsland.titleTokensDump(profile.title)
                    let lyricDump = AutoChorusIsland.lyricHookDump(profile.analysis.signal)
                    decisions.append(
                        AutoDecision(
                            kind: .selectedAnchor,
                            songTitle: profile.title,
                            detail: String(
                                format: "bed complete hook @%.2fs entry=%@ (title-hook onset after prechorus, hard cut, not prechorus/tail/verse-2) | %@ | raw=[%@] | %@ | %@",
                                chorus.startSeconds,
                                slot.entry.rawValue,
                                dump,
                                rawList,
                                tokensDump,
                                lyricDump
                            )
                        )
                    )
                } else {
                    let lastUsedEnd = used.map(\.1).max()
                    let bad = section.map { $0.barCount < 8 || $0.label == .teaser } ?? true
                    let rewind = section.flatMap { s in lastUsedEnd.map { s.startSeconds < $0 - 0.05 } } ?? false
                    let beforeChorus = section.map {
                        let anchor = profile.analysis.chorusOrDropCandidates.first?.startSeconds ?? 0
                        return $0.startSeconds + barSec * 1.0 < anchor - 0.05
                    } ?? true
                    if section == nil || bad || rewind || beforeChorus {
                        let from = lastUsedEnd ?? max(0, profile.analysis.introCandidate?.startSeconds ?? 0)
                        if let complete = completePhraseSection(
                            profile: profile,
                            from: from,
                            bars: max(8, slot.bars),
                            energy: slot.energy
                        ) {
                            section = complete
                        } else if bad {
                            section = nil
                        }
                    }
                }
            }

            // AutoMashUpper (Davies 2014): mashability is LOCAL — snap drop
            // vocals to the best 8–16 bar island over the bed (beat-offset
            // search), not a whole-song stretch of the star vocal.
            if mode == .mashup, slot.role == .chorus,
               let bedID = mashupBedID, profile.songID != bedID,
               let bedProfile = ordered.first(where: { $0.songID == bedID }),
               let island = AutoMashability.bestIsland(
                   guest: profile,
                   bed: bedProfile,
                   wantBars: max(8, slot.bars),
                   targetBPM: targetBPM,
                   tuning: tuning,
                   titleEntranceOnly: profile.songID == mashupVocalID && !slot.isReturn
               ),
               let base = section {
                let isDrop1Vocal = profile.songID == mashupVocalID && !slot.isReturn && !slot.isFinalPeak
                let placedStart = isDrop1Vocal
                    ? AutoMashability.drop1GuestStart(guest: profile, island: island)
                    : island.guestStart
                section = AutoCandidateSection(
                    songID: base.songID,
                    label: base.label,
                    startSeconds: placedStart,
                    barCount: max(base.barCount, island.bars),
                    barSeconds: base.barSeconds,
                    hook: max(base.hook, island.score),
                    energy: base.energy,
                    vocal: base.vocal,
                    clarity: base.clarity,
                    rhythm: max(base.rhythm, island.rhythmic),
                    uniqueness: base.uniqueness,
                    transitionUse: base.transitionUse,
                    confidence: base.confidence
                )
                let titleStr = AutoChorusIsland.bestEntrance(
                    signal: profile.analysis.signal,
                    downbeats: profile.analysis.downbeats,
                    barSeconds: profile.analysis.barSeconds,
                    duration: profile.analysis.durationSeconds,
                    introEnd: profile.analysis.introCandidate?.endSeconds ?? barSec * 8,
                    phraseSeconds: profile.analysis.phraseBoundaries.count >= 2
                        ? max(barSec * 4, profile.analysis.phraseBoundaries[1] - profile.analysis.phraseBoundaries[0])
                        : barSec * 8,
                    title: profile.title
                ).map { String(format: "%.1f", $0.startSeconds) } ?? "nil"
                let catalog = profile.analysis.chorusOrDropCandidates
                    .map { String(format: "%.1f", $0.startSeconds) }
                    .joined(separator: ",")
                if isDrop1Vocal {
                    decisions.append(
                        AutoDecision(
                            kind: .selectedAnchor,
                            songTitle: profile.title,
                            detail: String(
                                format: "Drop 1 guest placed @%.1fs (titleEntrance=%@ mashability=%.1f chorusOrDrop=[%@]) over bed @%.1fs (score %.2f) %@ %@",
                                placedStart, titleStr, island.guestStart, catalog, island.bedStart, island.score,
                                AutoChorusIsland.titleTokensDump(profile.title),
                                AutoChorusIsland.lyricHookDump(profile.analysis.signal)
                            )
                        )
                    )
                } else {
                    decisions.append(
                        AutoDecision(
                            kind: .selectedAnchor,
                            songTitle: profile.title,
                            detail: String(
                                format: "AutoMashUpper island @%.1fs over bed @%.1fs (score %.2f)",
                                island.guestStart, island.bedStart, island.score
                            )
                        )
                    )
                }
            }

            guard var section = section else {
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

            // Protect Deck A opening: intro always starts at the record head
            // (never a mid-song teaser chop of the title).
            if slot.role == .intro {
                let open = max(0, profile.analysis.introCandidate?.startSeconds ?? 0)
                if abs(section.startSeconds - open) > 0.05 || section.startSeconds > barSec * 2 {
                    section = AutoCandidateSection(
                        songID: section.songID,
                        label: .intro,
                        startSeconds: open,
                        barCount: section.barCount,
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
            }

            // Xirex: reserve the 1–2 bar pivot wallpaper window on the timeline
            // (no dominant island). Grains are emitted when Drop 1 lands.
            if mode == .mashup, slot.role == .build, slot.bars <= 4, !slot.isReturn {
                let dur = Double(slot.bars) * barSec
                pulseRegions.append(
                    AutoClubPulse.Region(
                        role: .buildOut,
                        timelineStart: cursor,
                        timelineEnd: cursor + dur
                    )
                )
                cursor += dur
                continue
            }

            var bars = slot.bars
            let songDuration = profile.analysis.durationSeconds
            let availableSeconds = (songDuration - 0.15 - section.startSeconds) / max(fit.ratio, 0.0001)
            let identityFloor = mode == .mashup ? max(minBars, 8) : minBars
            while bars > identityFloor, Double(bars) * barSec > availableSeconds {
                bars -= minBars
            }
            // Mashups: skip rather than emit a sub-8-bar island (intro tease may be 6 bars).
            if mode == .mashup, bars < 8, slot.role != .intro {
                warnings.append(
                    "\(profile.title) lacked 8 bars for \(slot.role.rawValue); skipped to avoid a 4-bar switch."
                )
                decisions.append(
                    AutoDecision(
                        kind: .skippedWeakSection,
                        songTitle: profile.title,
                        detail: "\(slot.role.rawValue) (under 8-bar identity floor)"
                    )
                )
                continue
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
            // Mashups keep the 8-bar identity floor.
            if mode != .mashup, slot.role == .groove, section.energy < 0.35, section.hook < 0.45, bars > 4 {
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
            if reused, slot.isReturn, !slot.holdTitleChorus {
                if entry == .none || entry == .cleanCrossfade {
                    entry = .hardHypeCut
                }
                energy = min(1, energy + 0.08)
            }

            // No 1-beat pre-drop void. Pivot Drop 1 is loop + hard cut at full
            // clip volume; a void next to `pivotWallpaperLoop` is the quiet
            // hole crate bounce flags. Drop 2 is also a hard cut / impact.

            let duration = Double(bars) * barSec
            var mutableSlot = slot
            mutableSlot.entry = entry
            mutableSlot.energy = energy

            let pulseRole: AutoClubPulse.RegionRole
            switch slot.role {
            case .intro, .teaser: pulseRole = .introTease
            case .groove: pulseRole = .groove
            case .build: pulseRole = .build
            case .chorus:
                // Only hard-hype hook-replace is a Drop. The bed's completed
                // chorus before the pivot stays "the record" (groove pulse).
                pulseRole = entry == .hardHypeCut ? .drop : .groove
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

        // Club mashups rotate hooks across islands — do not invent 4-bar
        // ping-pong just to inflate handoff count.
        if mode == .mashup {
            let shortStay = placed.contains { $0.timelineDuration + 0.001 < Double(8) * barSec && !$0.slot.isEnding }
            if shortStay {
                warnings.append(
                    "A mashup island landed under 8 bars after material limits — prefer fewer islands over 4-bar switches."
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
            let isIncomingDrop = entry == .hardHypeCut && ps.slot.role == .chorus
            let baseVolume = isIncomingDrop
                ? AutoGainPolicy.incomingDropVolume
                : (0.82 + 0.18 * ps.slot.energy)
            let allowMajorSFX = boundary - lastMajorSFXTime >= majorSFXSpacing

            if i > 0 { transitionsUsed.append(entry) }

            // Xirex 1–2 bar pivot window: no dominant bed audio — wallpaper grains
            // are placed when Drop 1 emits (after the completed chorus phrase).
            let isPivotWindow = mode == .mashup
                && ps.slot.role == .build
                && ps.slot.bars <= 4
                && !ps.slot.isReturn
            if isPivotWindow {
                lastMajorSFXTime = boundary
                continue
            }

            var bodyFX = ClipEffectSettings()
            switch ps.slot.role {
            case .teaser:
                bodyFX.setLevel(34, for: MixrEffect.blur.rawValue)
                bodyFX.setLevel(20, for: MixrEffect.echo.rawValue)
                bodyFX.echoPreset = .reverse
            case .build:
                if !profile.lowConfidence {
                    bodyFX.flangerAmount = ps.slot.energy > 0.75 ? 0.34 : 0.24
                    bodyFX.setLevel(28, for: MixrEffect.echo.rawValue)
                    bodyFX.echoPreset = .pingPong
                    bodyFX.setLevel(22, for: MixrEffect.blur.rawValue)
                }
            case .chorus:
                bodyFX.setLevel(12, for: MixrEffect.reverb.rawValue)
                bodyFX.reverbPreset = .hall
                bodyFX.setLevel(14, for: MixrEffect.echo.rawValue)
            case .breakdown:
                bodyFX.setLevel(28, for: MixrEffect.reverb.rawValue)
                bodyFX.reverbPreset = .ambient
                bodyFX.setLevel(24, for: MixrEffect.echo.rawValue)
                bodyFX.echoPreset = .classic
            case .ending:
                bodyFX.setLevel(30, for: MixrEffect.reverb.rawValue)
                bodyFX.reverbPreset = .ambient
                bodyFX.setLevel(28, for: MixrEffect.echo.rawValue)
                bodyFX.echoPreset = .classic
            case .groove, .intro:
                bodyFX.setLevel(12, for: MixrEffect.echo.rawValue)
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
                    fadeIn: ClipTransition(
                        type: .crossfade,
                        duration: 4,
                        curve: AutoTransitionEnvelope.equalPowerCurveName
                    ),
                    fadeOut: .none
                ))
            }

            let bodyStart = headSeconds
            let bodyDuration = ps.timelineDuration - headSeconds - tailSeconds
            let equalPower = AutoTransitionEnvelope.equalPowerCurveName
            // Never fade both neighbors toward silence — equal-power crossfade
            // keeps energy continuous through handoffs (void is the only hole).
            var bodyFadeIn: ClipTransition = headSeconds > 0
                ? .none
                : ClipTransition(type: .crossfade, duration: 2, curve: equalPower)
            var bodyFadeOut: ClipTransition = tailSeconds > 0
                ? .none
                : ClipTransition(type: .crossfade, duration: 2, curve: equalPower)
            if entry == .cleanCrossfade, headSeconds == 0 {
                bodyFadeIn = ClipTransition(type: .crossfade, duration: 4, curve: equalPower)
            }
            // Title-hook chorus (first complete A hook + 8+8 hold): hard cut.
            // A crossfade on this slot eats the identifiable opening word.
            let isTitleHookSlot = mode == .mashup
                && ps.slot.role == .chorus
                && entry != .hardHypeCut
                && !ps.slot.isFinalPeak
                && (ps.slot.holdTitleChorus || (ps.slot.songIdx == 0 && !ps.slot.isReturn))
            if isTitleHookSlot, headSeconds == 0 {
                bodyFadeIn = .hardCut
            }
            // Xirex: hard cut into the hook-replace drop (no crossfade, no fade-in).
            if entry == .hardHypeCut, headSeconds == 0 {
                bodyFadeIn = .hardCut
                bodyFadeOut = next == nil
                    ? bodyFadeOut
                    : ClipTransition(type: .crossfade, duration: 2, curve: equalPower)
            }
            // Song-switch into a hard cut: outgoing stays at full clip volume
            // through the join (no fade-to-silence just to change records).
            if nextIsHandoff, nextEntry == .hardHypeCut, tailSeconds == 0 {
                bodyFadeOut = .none
            }
            if ps.slot.isEnding {
                bodyFadeOut = ClipTransition(type: .echoOut, duration: 6)
            } else if nextIsHandoff, nextEntry == .cleanCrossfade, tailSeconds == 0 {
                bodyFadeOut = ClipTransition(type: .crossfade, duration: 4, curve: equalPower)
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

            if isTitleHookSlot {
                decisions.append(
                    AutoDecision(
                        kind: .selectedAnchor,
                        songTitle: profile.title,
                        detail: String(
                            format: "title-hook clip src=%.2fs t=%.1fs entry=%@ fadeIn=%@ fadeDur=%.2f %@ %@",
                            ps.section.startSeconds,
                            ps.timelineStart,
                            entry.rawValue,
                            bodyFadeIn.type.rawValue,
                            bodyFadeIn.duration,
                            AutoChorusIsland.titleTokensDump(profile.title),
                            AutoChorusIsland.lyricHookDump(profile.analysis.signal)
                        )
                    )
                )
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
                let hookVocalStem = mode == .mashup
                    && ps.slot.role == .chorus
                    && entry == .hardHypeCut
                    && mashupBedID != profile.songID
                    && profile.stems.hasVocals
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
                        slotIndex: i,
                        stemKind: hookVocalStem ? .vocals : nil
                    )
                )
            }

            // Club mashup drops: bed under the hook (hook-replace) + optional
            // short call-and-response. Xirex pivot wallpaper before Drop 1 only
            // (hard cut into hook-replace) — never on the bed's own complete chorus.
            if mode == .mashup, ps.slot.role == .chorus {
                if !ps.slot.isFinalPeak,
                   entry == .hardHypeCut,
                   let bedID = mashupBedID,
                   let bedTitle = ordered.first(where: { $0.songID == bedID })?.title,
                   let phrase = placements.last(where: {
                       $0.songID == bedID
                           && $0.role == .dominant
                           && $0.timelineEnd <= ps.timelineStart + 0.05
                   }) {
                    let bedStems = ordered.first(where: { $0.songID == bedID })?.stems
                    appendPivotWallpaperLoop(
                        completedPhrase: phrase,
                        dropTimelineStart: ps.timelineStart,
                        deckATitle: bedTitle,
                        deckBTitle: profile.title,
                        barSec: barSec,
                        beatSec: beatSec,
                        tuning: tuning,
                        grainStem: (bedStems?.hasVocals ?? false) ? .vocals : nil,
                        placements: &placements,
                        pulseRegions: &pulseRegions,
                        intentionalGaps: &intentionalGaps,
                        decisions: &decisions
                    )
                }
                appendMashupDropStacks(
                    lead: ps,
                    leadProfile: profile,
                    leadSlotIndex: i,
                    ordered: ordered,
                    fits: fits,
                    mashupBedID: mashupBedID,
                    overlaySongIdx: ps.slot.isFinalPeak ? drop2VocalOverlayIdx : drop1VocalOverlayIdx,
                    dropLabel: ps.slot.isFinalPeak ? "Drop 2" : "Drop 1",
                    barSec: barSec,
                    tuning: tuning,
                    usedRanges: &usedRanges,
                    placements: &placements,
                    decisions: &decisions
                )
            }

            // Directional overlap under mashup handoffs (non-drop recipes).
            // Vocals may overlap with ducking; reject only dual kick/bass full mixes.
            if mode == .mashup, isHandoff, let prev,
               ![.hardHypeCut, .cleanCrossfade, .none].contains(entry) {
                let prevProfile = ordered[prev.slot.songIdx]
                let dualBass = profile.analysis.bassDensity > 0.65
                    && prevProfile.analysis.bassDensity > 0.65
                    && profile.analysis.drumStrength > 0.65
                    && prevProfile.analysis.drumStrength > 0.65
                    && ps.slot.role == .chorus && prev.slot.role == .chorus

                if dualBass {
                    decisions.append(
                        AutoDecision(
                            kind: .rejectedDualBassStack,
                            songTitle: profile.title,
                            detail: "vs \(prevProfile.title)"
                        )
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .replacedComplexOverlapWithHardCut,
                            songTitle: nil,
                            detail: profile.title
                        )
                    )
                } else {
                    let compat = AutoCompatibility.directional(
                        dominant: ps.section,
                        dominantProfile: profile,
                        support: prev.section,
                        supportProfile: prevProfile,
                        targetBPM: targetBPM,
                        tuning: tuning
                    )
                    // Mixxx AutoDJ phrase match: overlap = outro∩intro, not a hole.
                    let stretchFar = abs((fits[ps.slot.songIdx]?.ratio ?? 1) - 1) > tuning.maxStretch * 0.9
                        || abs((fits[prev.slot.songIdx]?.ratio ?? 1) - 1) > tuning.maxInstrumentalStretch * 0.9
                    let phrase = AutoPhraseMatch.plan(
                        outgoingDuration: min(prev.timelineDuration, barSec * 4),
                        incomingIntroDuration: min(ps.timelineDuration, barSec * 4),
                        beatSeconds: beatSec,
                        barSeconds: barSec,
                        bpmAligned: (fits[ps.slot.songIdx]?.gridAligned ?? false)
                            && (fits[prev.slot.songIdx]?.gridAligned ?? false),
                        stretchFar: stretchFar
                    )
                    let overlapSeconds = max(
                        Double(max(compat.overlapBars, 1)) * barSec * 0.5,
                        phrase.overlapSeconds
                    )
                    let prevSourceEnd = prev.section.startSeconds + prev.timelineDuration * prev.tempoRatio
                    let supportAvailable = prevProfile.analysis.durationSeconds - 0.15 - prevSourceEnd
                    let denseVocals = ps.section.vocal > 0.55 && prev.section.vocal > 0.55
                    let allowOverlap = (compat.overlapBars > 0 || denseVocals || phrase.preferLongCrossfade)
                        && overlapSeconds >= tuning.minSegmentSeconds
                        && supportAvailable >= overlapSeconds * prev.tempoRatio

                    if phrase.preferTapeStop {
                        addSFX("tapeStop", at: max(0, boundary - 0.3), purpose: "Mixxx-style spinback into far-BPM join")
                    }

                    if allowOverlap {
                        var supportFX = ClipEffectSettings()
                        var supportVol = tuning.supportVolume
                        if denseVocals {
                            supportFX.setLevel(34, for: MixrEffect.blur.rawValue)
                            supportVol = tuning.duckedVocalSupportVolume
                            decisions.append(
                                AutoDecision(
                                    kind: .duckedSupportingVocal,
                                    songTitle: prevProfile.title,
                                    detail: "under \(profile.title)"
                                )
                            )
                        } else {
                            supportFX.setLevel(22, for: MixrEffect.blur.rawValue)
                        }
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
                                timelineDuration: min(overlapSeconds, ps.timelineDuration),
                                tempoRatio: prev.tempoRatio,
                                volume: supportVol,
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
                    }
                }
            }

            // Coordinated SFX — Drop 1 after pivot is diet (impact slam only).
            let isDropReveal = ps.slot.role == .chorus && entry == .hardHypeCut

            if i > 0, (allowMajorSFX || isDropReveal) {
                switch entry {
                case .hardHypeCut where isDropReveal || mode == .remix || ps.slot.isFinalPeak:
                    let isDrop1 = isDropReveal && !ps.slot.isFinalPeak
                    let pivotJoin = isDrop1 && decisions.contains { $0.kind == .pivotWallpaperLoop }
                        || isDrop1 && placements.contains {
                            $0.role == .supporting
                                && abs($0.timelineDuration - beatSec) < beatSec * 0.4
                                && $0.timelineStart >= boundary - tuning.pivotLookbackSeconds(barSec: barSec)
                                && $0.timelineStart < boundary - 0.02
                        }
                    // Pivot join: one slam. Plain Drop 2 / non-pivot: impact (+ optional crash).
                    addSFX("impact", at: boundary, purpose: "impact on the drop downbeat")
                    if !pivotJoin, !isDrop1 {
                        let cymbalCount = sfx.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }.count
                        if cymbalCount < 2 {
                            addSFX("crash", at: boundary, purpose: "crash punctuation on drop")
                        }
                    }
                    decisions.append(
                        AutoDecision(
                            kind: .addedRiserIntoDrop,
                            songTitle: nil,
                            detail: pivotJoin
                                ? "pivot hard-cut slam (impact only)"
                                : (ps.slot.isFinalPeak ? "drop 2 flip impact" : "drop slam")
                        )
                    )
                    lastMajorSFXTime = boundary
                case .reverseEntrance where mode == .remix || ps.slot.energy >= 0.88:
                    addSFX("impact", at: boundary, purpose: "impact on the new entrance")
                    lastMajorSFXTime = boundary
                case .blurReveal where mode == .remix && ps.slot.energy >= 0.85:
                    addSFX("impact", at: boundary, purpose: "impact on the reveal")
                    lastMajorSFXTime = boundary
                case .vocalEchoOut where mode == .remix || mode == .mashup:
                    if prev?.slot.role == .chorus, ps.slot.energy < prev!.slot.energy {
                        addSFX("downlifter", at: boundary, purpose: "downlifter out of the drop")
                        lastMajorSFXTime = boundary
                    }
                case .flangerBuild where mode == .remix || mode == .mashup:
                    // Skip SFX on the 1–2 bar pivot window — grains + Drop 1 slam own it.
                    if ps.slot.bars >= 8 {
                        addSFXEnding("snareBuild", at: boundary + ps.timelineDuration, purpose: "snare through the build")
                        addSFXEnding("riser", at: boundary + ps.timelineDuration, purpose: "riser through the build")
                        lastMajorSFXTime = boundary + ps.timelineDuration
                    }
                case .atmosphericHandoff:
                    addSFX("downlifter", at: boundary, purpose: "downlifter into breakdown")
                    lastMajorSFXTime = boundary
                case .cleanCrossfade:
                    // Two-deck: no clap wallpaper on verse/groove handoffs.
                    break
                default:
                    break
                }
            }

            if ps.slot.isEnding {
                addSFX("impact", at: boundary, purpose: "final hit")
                addSFX("downlifter", at: boundary + 1.05, purpose: "downlifter after the final hit")
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

        // Continuous energy through verse handoffs. Club drops stay hard cuts
        // at full clip volume (no 1-beat void, no equal-power fade-in).
        var songDurations: [UUID: Double] = [:]
        for p in ordered {
            songDurations[p.songID] = p.analysis.durationSeconds
        }
        var cutRecords: [AutoCutRecord] = []
        blendAdjacentHandoffs(
            placements: &placements,
            intentionalGaps: intentionalGaps,
            pulseRegions: pulseRegions,
            songDurations: songDurations,
            barSec: barSec,
            beatSec: beatSec,
            tuning: tuning,
            cutRecords: &cutRecords
        )

        // Club pulse hits materialize at apply/render from pulseRegions.
        _ = AutoClubPulse.scheduleHits(
            regions: pulseRegions,
            policy: pulse,
            beatSeconds: beatSec,
            barSeconds: barSec,
            halfTimeDrop: mashupFlavor.bias.halfTimeDrop
        )

        stripVoidsWhenDrop1HasPivot(
            placements: placements,
            beatSec: beatSec,
            barSec: barSec,
            decisions: &decisions,
            intentionalGaps: &intentionalGaps,
            pulseRegions: &pulseRegions
        )

        return AutoRemixPlan(
            mode: mode,
            targetBPM: targetBPM,
            targetDuration: cursorEnd(placed),
            anchorSongIDs: [ordered[0].songID],
            selectedSections: sections,
            placements: placements,
            sfxEvents: sfx.sorted { $0.timelineStart < $1.timelineStart },
            cutRecords: cutRecords,
            intentionalGaps: intentionalGaps,
            pulsePolicy: pulse,
            pulseRegions: pulseRegions,
            clubFlavor: mashupFlavor,
            mashupVocalSongID: mashupVocalID,
            mashupDrop2SongID: mashupDrop2ID,
            mashupBedSongID: mashupBedID,
            handoffCount: handoffs,
            songLetters: letters,
            sequence: sequence,
            sequenceTitles: sequenceTitles,
            transitionsUsed: transitionsUsed,
            decisions: decisions,
            warnings: warnings,
            confidence: confidence,
            randomSeed: seed,
            stemsBySongID: Dictionary(uniqueKeysWithValues: ordered.map { ($0.songID, $0.stems) })
        )
    }

    /// Equal-power overlaps on verse→build joins. Club drops (pivot Drop 1,
    /// hook-return Drop 2) stay hard cuts at full clip volume — no quiet
    /// void and no equal-power fade-in.
    private static func blendAdjacentHandoffs(
        placements: inout [AutoClipPlacement],
        intentionalGaps: [AutoIntentionalGap],
        pulseRegions: [AutoClubPulse.Region],
        songDurations: [UUID: Double],
        barSec: Double,
        beatSec: Double,
        tuning: AutoTuning,
        cutRecords: inout [AutoCutRecord]
    ) {
        let equalPower = AutoTransitionEnvelope.equalPowerCurveName
        // Prefer 1 bar of overlap; Mixxx AutoDJ lengthens when both sides
        // have long phrase material and BPM is aligned.
        let overlapSec = max(tuning.minSegmentSeconds, min(barSec, beatSec * 4))
        let overlapBeats = overlapSec / max(beatSec, 0.001)

        let dominantIdxs = placements.indices
            .filter { placements[$0].role == .dominant }
            .sorted { placements[$0].timelineStart < placements[$1].timelineStart }

        for (prevIdx, nextIdx) in zip(dominantIdxs, dominantIdxs.dropFirst()) {
            let prev = placements[prevIdx]
            let next = placements[nextIdx]

            // Legacy pre-drop void (must not be present on a pivoted plan).
            let voidBeforeNext = intentionalGaps.contains { abs($0.end - next.timelineStart) < 0.05 }
            if voidBeforeNext { continue }

            // Xirex pivot hard cut: 1-beat grains fill the window before the
            // drop — do NOT invent an equal-power fade-in (quiet → gradual).
            let lookback = tuning.pivotLookbackSeconds(barSec: barSec)
            let pivotWindow = tuning.pivotWindowSeconds(barSec: barSec)
            let pivotBeforeNext = placements.contains { g in
                g.role == .supporting
                    && abs(g.timelineDuration - beatSec) < beatSec * 0.4
                    && g.timelineStart >= next.timelineStart - lookback
                    && g.timelineStart < next.timelineStart - 0.02
                    && g.timelineEnd <= next.timelineStart + 0.08
            }
            if pivotBeforeNext {
                placements[nextIdx].fadeIn = .none
                placements[nextIdx].volume = max(
                    placements[nextIdx].volume,
                    AutoGainPolicy.incomingDropVolume
                )
                // Trim any dominant that spilled into the loop window.
                if prev.timelineEnd > next.timelineStart - pivotWindow + 0.1 {
                    let trimmed = (next.timelineStart - pivotWindow) - prev.timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        placements[prevIdx].timelineDuration = trimmed
                        placements[prevIdx].fadeOut = .none
                    }
                }
                continue
            }

            // Drop 1 / Drop 2: hard cut at full clip volume. Do not invent
            // an equal-power fade (that dive appeared after the Drop 2 void
            // was removed) and do not park a 1-beat quiet hole.
            if AutoRemixDiagnostics.incomingIsClubDrop(
                pulseRegions: pulseRegions,
                timelineStart: next.timelineStart
            ) {
                if placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        placements[prevIdx].timelineDuration = trimmed
                    }
                }
                placements[prevIdx].fadeOut = .none
                placements[nextIdx].fadeIn = .none
                placements[nextIdx].volume = max(
                    placements[nextIdx].volume,
                    AutoGainPolicy.incomingDropVolume
                )
                let sourceJump = abs(next.sourceStart - prev.sourceEnd) > 0.05
                if sourceJump {
                    if let i = cutRecords.firstIndex(where: { abs($0.timelineAt - next.timelineStart) < 0.1 }) {
                        if AutoRemixDiagnostics.isEqualPowerMasking(cutRecords[i].masking) {
                            cutRecords[i].masking = .sfx(assetID: "impact")
                            cutRecords[i].expectedEnergyDeltaDB = max(
                                cutRecords[i].expectedEnergyDeltaDB, 8.0
                            )
                        }
                    } else {
                        cutRecords.append(
                            AutoCutRecord(
                                timelineAt: next.timelineStart,
                                sourceFrom: prev.sourceEnd,
                                sourceTo: next.sourceStart,
                                reason: .hookReturn,
                                confidence: 0.7,
                                expectedEnergyDeltaDB: 8.0,
                                masking: .sfx(assetID: "impact")
                            )
                        )
                    }
                }
                continue
            }

            // Source-continuous neighbors (energy-curve / no-cut path): do not
            // invent an overlap cut — that would manufacture internal edits.
            let sourceContinuous = abs(next.sourceStart - (
                prev.sourceStart + prev.timelineDuration * prev.tempoRatio
            )) < 0.05 || next.continuesPrevious
            if sourceContinuous {
                continue
            }

            // Title-chorus hold: rewind to the same 8-bar island — hard cut.
            // Do not linearly extend the previous clip into verse 2.
            let titleHoldRewind = prev.songID == next.songID
                && next.sourceStart < prev.sourceEnd - 0.05
                && abs(next.sourceStart - prev.sourceStart) < barSec * 0.75
            if titleHoldRewind {
                if placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        placements[prevIdx].timelineDuration = trimmed
                    }
                }
                placements[prevIdx].fadeOut = .hardCut
                placements[nextIdx].fadeIn = .hardCut
                cutRecords.append(
                    AutoCutRecord(
                        timelineAt: next.timelineStart,
                        sourceFrom: prev.sourceEnd,
                        sourceTo: next.sourceStart,
                        reason: .hookReturn,
                        confidence: 0.75,
                        expectedEnergyDeltaDB: 2.0,
                        masking: .alignedHardCut
                    )
                )
                continue
            }

            // Same-song jump into a title-hook island: hard cut. A crossfade
            // on this join eats the identifiable opening word on every song.
            let titleHookJump = prev.songID == next.songID
                && next.sourceStart > prev.sourceEnd + barSec * 0.25
                && next.timelineDuration >= barSec * 7.5
                && prev.timelineStart <= barSec * 10
                && !AutoRemixDiagnostics.incomingIsClubDrop(
                    pulseRegions: pulseRegions,
                    timelineStart: next.timelineStart
                )
            if titleHookJump {
                if placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        placements[prevIdx].timelineDuration = trimmed
                    }
                }
                placements[prevIdx].fadeOut = .hardCut
                placements[nextIdx].fadeIn = .hardCut
                cutRecords.append(
                    AutoCutRecord(
                        timelineAt: next.timelineStart,
                        sourceFrom: prev.sourceEnd,
                        sourceTo: next.sourceStart,
                        reason: .hookReturn,
                        confidence: 0.8,
                        expectedEnergyDeltaDB: 3.0,
                        masking: .alignedHardCut
                    )
                )
                continue
            }

            // Different songs: never overlap two dominants (dual full mixes).
            // Switch by a hard cut at full clip volume — no fade-in from silence.
            if prev.songID != next.songID {
                if placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        placements[prevIdx].timelineDuration = trimmed
                    }
                }
                placements[prevIdx].fadeOut = .hardCut
                placements[nextIdx].fadeIn = .hardCut
                placements[nextIdx].volume = max(
                    placements[nextIdx].volume,
                    AutoGainPolicy.incomingDropVolume
                )
                let hasSupport = placements.contains {
                    $0.role == .supporting
                        && $0.songID == prev.songID
                        && $0.timelineStart < next.timelineStart + overlapSec
                        && $0.timelineEnd > next.timelineStart + 0.05
                }
                if !hasSupport {
                    let songDur = songDurations[prev.songID] ?? .infinity
                    let srcStart = placements[prevIdx].sourceStart
                        + placements[prevIdx].timelineDuration * placements[prevIdx].tempoRatio
                    if srcStart + overlapSec * prev.tempoRatio <= songDur - 0.05 {
                        var supportFX = ClipEffectSettings()
                        supportFX.setLevel(22, for: MixrEffect.blur.rawValue)
                        placements.append(
                            AutoClipPlacement(
                                songID: prev.songID,
                                sourceStart: srcStart,
                                timelineStart: next.timelineStart,
                                timelineDuration: min(overlapSec, next.timelineDuration),
                                tempoRatio: prev.tempoRatio,
                                volume: max(0.78, tuning.supportVolume + 0.30),
                                fadeIn: .none,
                                fadeOut: ClipTransition(
                                    type: .crossfade, duration: overlapBeats, curve: equalPower
                                ),
                                effects: AutoSupportedEffects.sanitize(supportFX),
                                role: .supporting,
                                slotIndex: next.slotIndex
                            )
                        )
                    }
                }
                continue
            }

            // Same-song already overlapping enough.
            if next.timelineStart < prev.timelineEnd - overlapSec * 0.5 {
                if placements[nextIdx].overlapsPreviousSeconds < 0.01 {
                    let existing = prev.timelineEnd - next.timelineStart
                    if existing > 0.05 {
                        placements[nextIdx].overlapsPreviousSeconds = existing
                        placements[prevIdx].fadeOut = ClipTransition(
                            type: .crossfade, duration: existing / max(beatSec, 0.001), curve: equalPower
                        )
                        placements[nextIdx].fadeIn = ClipTransition(
                            type: .crossfade, duration: existing / max(beatSec, 0.001), curve: equalPower
                        )
                    }
                }
                continue
            }

            // Same song: source room to extend the previous clip through the join.
            let songDur = songDurations[prev.songID] ?? .infinity
            let extraSource = overlapSec * prev.tempoRatio
            guard prev.sourceEnd + extraSource <= songDur - 0.05 else { continue }

            let join = next.timelineStart
            placements[prevIdx].timelineDuration = (join + overlapSec) - prev.timelineStart
            placements[prevIdx].fadeOut = ClipTransition(
                type: .crossfade, duration: overlapBeats, curve: equalPower
            )
            placements[nextIdx].fadeIn = ClipTransition(
                type: .crossfade, duration: overlapBeats, curve: equalPower
            )
            placements[nextIdx].overlapsPreviousSeconds = overlapSec

            if abs(next.sourceStart - prev.sourceEnd) > 0.05 {
                let hasRecord = cutRecords.contains { abs($0.timelineAt - join) < 0.1 }
                if !hasRecord {
                    cutRecords.append(
                        AutoCutRecord(
                            timelineAt: join,
                            sourceFrom: prev.sourceEnd,
                            sourceTo: next.sourceStart,
                            reason: .redundantRepeat,
                            confidence: 0.7,
                            expectedEnergyDeltaDB: 0,
                            masking: .equalPowerCrossfade(seconds: overlapSec)
                        )
                    )
                } else if let i = cutRecords.firstIndex(where: { abs($0.timelineAt - join) < 0.1 }) {
                    cutRecords[i].masking = .equalPowerCrossfade(seconds: overlapSec)
                }
            }
        }
    }

    private static func fadesTowardSilence(_ t: ClipTransition) -> Bool {
        switch t.type {
        case .fadeOut, .echoOut: return true
        default: return false
        }
    }

    /// Bed under the drop (one kick/bass) + optional second vocal overlay.
    /// Vocals may stack; dual full-mix kick/sub stacks are refused.
    private static func appendMashupDropStacks(
        lead: PlacedSlot,
        leadProfile: AutoSongProfile,
        leadSlotIndex: Int,
        ordered: [AutoSongProfile],
        fits: [Int: AutoTempo.Fit],
        mashupBedID: UUID?,
        overlaySongIdx: Int?,
        dropLabel: String,
        barSec: Double,
        tuning: AutoTuning,
        usedRanges: inout [UUID: [(Double, Double)]],
        placements: inout [AutoClipPlacement],
        decisions: inout [AutoDecision]
    ) {
        // Soften lead lows when a slamming guest sits over the bed kick.
        // Skip when the guest is already a vocal stem (no kick in the file).
        if let bedID = mashupBedID, leadProfile.songID != bedID,
           !leadProfile.stems.hasVocals,
           leadProfile.analysis.bassDensity > 0.55 || leadProfile.analysis.drumStrength > 0.65 {
            for i in placements.indices where placements[i].slotIndex == leadSlotIndex
                && placements[i].songID == leadProfile.songID
                && placements[i].role == .dominant {
                var fx = placements[i].effects
                fx.setLevel(
                    max(fx.level(for: MixrEffect.blur.rawValue), 24),
                    for: MixrEffect.blur.rawValue
                )
                placements[i].effects = AutoSupportedEffects.sanitize(fx)
            }
        }

        // Bed groove under the vocal drop — owns kick/bass when lead is a guest.
        // Prefer AutoMashUpper island bedStart when mashability found a beat offset.
        if let bedID = mashupBedID,
           leadProfile.songID != bedID,
           let bedIdx = ordered.firstIndex(where: { $0.songID == bedID }) {
            let bed = ordered[bedIdx]
            let bedFit = fits[bedIdx] ?? AutoTempo.Fit(ratio: 1, gridAligned: true, halfOrDoubleTime: false)
            let used = usedRanges[bed.songID] ?? []
            let island = AutoMashability.bestIsland(
                guest: leadProfile,
                bed: bed,
                wantBars: max(8, Int((lead.timelineDuration / max(barSec, 0.001)).rounded())),
                targetBPM: 240.0 / max(barSec, 0.001),
                tuning: tuning
            )
            var section = bed.best(
                [.groove, .chorus, .build],
                tuning: tuning,
                used: used,
                allowReuse: true
            )
            if let island, let base = section {
                section = AutoCandidateSection(
                    songID: base.songID,
                    label: base.label,
                    startSeconds: island.bedStart,
                    barCount: base.barCount,
                    barSeconds: base.barSeconds,
                    hook: base.hook,
                    energy: base.energy,
                    vocal: base.vocal,
                    clarity: base.clarity,
                    rhythm: base.rhythm,
                    uniqueness: base.uniqueness,
                    transitionUse: base.transitionUse,
                    confidence: base.confidence
                )
            }
            if let section {
                let dualBass = !leadProfile.stems.hasVocals
                    && bed.analysis.bassDensity > 0.65
                    && leadProfile.analysis.bassDensity > 0.7
                    && bed.analysis.drumStrength > 0.7
                    && leadProfile.analysis.drumStrength > 0.7
                if dualBass {
                    decisions.append(
                        AutoDecision(
                            kind: .rejectedDualBassStack,
                            songTitle: bed.title,
                            detail: "under \(leadProfile.title) on \(dropLabel)"
                        )
                    )
                } else if bed.stems.hasInstrumental {
                    for kind in bed.stems.instrumentalKinds {
                        let vol: Double
                        switch kind {
                        case .drums: vol = 0.92
                        case .bass: vol = 0.88
                        default: vol = 0.74
                        }
                        placements.append(
                            AutoClipPlacement(
                                songID: bed.songID,
                                sourceStart: section.startSeconds,
                                timelineStart: lead.timelineStart,
                                timelineDuration: lead.timelineDuration,
                                tempoRatio: bedFit.ratio,
                                volume: vol,
                                fadeIn: ClipTransition(type: .none, duration: 0),
                                fadeOut: ClipTransition(type: .none, duration: 0),
                                effects: AutoSupportedEffects.sanitize(ClipEffectSettings()),
                                role: .supporting,
                                slotIndex: leadSlotIndex,
                                overlapsPreviousSeconds: lead.timelineDuration,
                                stemKind: kind
                            )
                        )
                    }
                    usedRanges[bed.songID, default: []].append(
                        (section.startSeconds, section.startSeconds + lead.timelineDuration * bedFit.ratio)
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .hookReplace,
                            songTitle: leadProfile.title,
                            detail: "guest vocal stem / bed drums+bass+other under \(dropLabel)"
                        )
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .usedStemSidecar,
                            songTitle: bed.title,
                            detail: "bed instrumental stems under \(dropLabel)"
                        )
                    )
                    if leadProfile.stems.hasVocals {
                        decisions.append(
                            AutoDecision(
                                kind: .usedStemSidecar,
                                songTitle: leadProfile.title,
                                detail: "hook-replace from vocals.wav"
                            )
                        )
                    }
                } else {
                    var bedFX = ClipEffectSettings()
                    // Hook-replace: bed keeps kick/bass; carve bed vocal hard
                    // so the guest melody is the only voice (HPF/blur fallback).
                    let midCarve: Double = lead.section.vocal > 0.35 ? 48 : 40
                    bedFX.setLevel(midCarve, for: MixrEffect.blur.rawValue)
                    bedFX = AutoSupportedEffects.sanitize(bedFX)
                    placements.append(
                        AutoClipPlacement(
                            songID: bed.songID,
                            sourceStart: section.startSeconds,
                            timelineStart: lead.timelineStart,
                            timelineDuration: lead.timelineDuration,
                            tempoRatio: bedFit.ratio,
                            // Bed deck stays present under the hook (DJ layering).
                            volume: max(0.78, tuning.supportVolume + 0.30),
                            fadeIn: ClipTransition(
                                type: .crossfade,
                                duration: 2,
                                curve: AutoTransitionEnvelope.equalPowerCurveName
                            ),
                            fadeOut: ClipTransition(
                                type: .crossfade,
                                duration: 2,
                                curve: AutoTransitionEnvelope.equalPowerCurveName
                            ),
                            effects: bedFX,
                            role: .supporting,
                            slotIndex: leadSlotIndex
                        )
                    )
                    usedRanges[bed.songID, default: []].append(
                        (section.startSeconds, section.startSeconds + lead.timelineDuration * bedFit.ratio)
                    )
                    decisions.append(
                        AutoDecision(
                            kind: .hookReplace,
                            songTitle: leadProfile.title,
                            detail: "guest in / bed vocal out under \(dropLabel)"
                        )
                    )
                }
            }
        }

        // Optional call-and-response only (≤8 bars) — never full-drop dual vocals.
        guard let overlayIdx = overlaySongIdx,
              overlayIdx >= 0, overlayIdx < ordered.count,
              tuning.allowCallAndResponseOverlay else { return }
        let overlay = ordered[overlayIdx]
        guard overlay.songID != leadProfile.songID else { return }

        // Refuse overlay if it would be a second slamming full-mix kit.
        if overlay.analysis.drumStrength > 0.75 && overlay.analysis.bassDensity > 0.7
            && leadProfile.analysis.drumStrength > 0.7 && leadProfile.analysis.bassDensity > 0.65 {
            decisions.append(
                AutoDecision(
                    kind: .rejectedDualBassStack,
                    songTitle: overlay.title,
                    detail: "full-mix overlay under \(leadProfile.title)"
                )
            )
            return
        }

        let overlayFit = fits[overlayIdx] ?? AutoTempo.Fit(ratio: 1, gridAligned: true, halfOrDoubleTime: false)
        let used = usedRanges[overlay.songID] ?? []
        guard let section = overlay.best(
            [.teaser, .chorus, .groove],
            tuning: tuning,
            used: used,
            allowReuse: true
        ) else { return }

        let entryBars = max(0, min(tuning.vocalOverlayEntryBars, 8))
        var overlayBars = max(4, min(tuning.vocalOverlayBars, 8))
        let availableBars = Int((lead.timelineDuration / max(barSec, 0.001)).rounded(.down)) - entryBars
        overlayBars = min(overlayBars, max(4, availableBars))
        let start = lead.timelineStart + Double(entryBars) * barSec
        let duration = Double(overlayBars) * barSec
        guard duration >= tuning.minSegmentSeconds,
              start + duration <= lead.timelineStart + lead.timelineDuration + 0.05 else { return }

        let dense = section.vocal > 0.55 && lead.section.vocal > 0.55
        var fx = ClipEffectSettings()
        let volume: Double
        if dense {
            fx.setLevel(36, for: MixrEffect.blur.rawValue)
            fx.setLevel(12, for: MixrEffect.reverb.rawValue)
            fx.reverbPreset = .hall
            volume = tuning.duckedVocalSupportVolume
            decisions.append(
                AutoDecision(
                    kind: .duckedSupportingVocal,
                    songTitle: overlay.title,
                    detail: "call-response under \(leadProfile.title) on \(dropLabel)"
                )
            )
        } else {
            fx.setLevel(16, for: MixrEffect.blur.rawValue)
            volume = tuning.supportVolume
        }
        if overlay.analysis.drumStrength > 0.55 || overlay.analysis.bassDensity > 0.55 {
            fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 40), for: MixrEffect.blur.rawValue)
        }
        fx = AutoSupportedEffects.sanitize(fx)

        placements.append(
            AutoClipPlacement(
                songID: overlay.songID,
                sourceStart: section.startSeconds,
                timelineStart: start,
                timelineDuration: duration,
                tempoRatio: overlayFit.ratio,
                volume: volume,
                fadeIn: ClipTransition(type: .crossfade, duration: 2),
                fadeOut: ClipTransition(type: .fadeOut, duration: 4),
                effects: fx,
                role: .supporting,
                slotIndex: leadSlotIndex,
                overlapsPreviousSeconds: duration,
                stemKind: overlay.stems.hasVocals ? .vocals : nil
            )
        )
        usedRanges[overlay.songID, default: []].append(
            (section.startSeconds, section.startSeconds + duration * overlayFit.ratio)
        )
        decisions.append(
            AutoDecision(
                kind: .stackedVocalOverlay,
                songTitle: overlay.title,
                detail: "\(overlayBars) bars call-response on \(dropLabel) under \(leadProfile.title)"
            )
        )
        if overlay.stems.hasVocals {
            decisions.append(
                AutoDecision(
                    kind: .usedStemSidecar,
                    songTitle: overlay.title,
                    detail: "call-response from vocals.wav"
                )
            )
        }
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
