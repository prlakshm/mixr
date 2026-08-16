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
            drumStrength: analysis.drumStrength,
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

            // Drop slots: prefer the strongest chorus / title-line island
            // (AutoSectionCatalog hook score), not a verse disguised as chorus.
            // Drop 2 uses the next-best hook (or flips the same hook).
            if slot.role == .chorus {
                let hooks = profile.candidates
                    .filter { ($0.label == .chorus || $0.label == .teaser) && $0.barCount >= 8 }
                    .sorted { $0.hook > $1.hook }
                if dropIndex < hooks.count {
                    section = hooks[dropIndex]
                } else if let bestHook = hooks.first {
                    section = bestHook
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

            // Intentional pre-drop void: last beat(s) of the previous bar.
            // Drop stays on the downbeat (bar boundary) — do not shift cursor.
            if slot.entry == .hardHypeCut, cursor > 0 {
                let voidBeats = min(tuning.preferredPredropVoidBeats, tuning.maxIntentionalPauseBeats)
                let voidSec = voidBeats * beat
                if voidSec > 0.05, cursor > voidSec {
                    let dropStart = cursor
                    let voidStart = dropStart - voidSec
                    carvePredropVoid(
                        voidStart: voidStart,
                        dropStart: dropStart,
                        placements: &placements,
                        pulseRegions: &pulseRegions,
                        intentionalGaps: &intentionalGaps,
                        minSegmentSeconds: tuning.minSegmentSeconds
                    )
                    if let last = placements.last {
                        lastSourceEnd = last.sourceStart + last.timelineDuration * last.tempoRatio
                    }
                    decisions.append(
                        AutoDecision(
                            kind: .allowedPredropVoid,
                            songTitle: profile.title,
                            detail: String(format: "%.2f beats before drop (drop on downbeat)", voidBeats)
                        )
                    )
                }
            }

            if slot.entry != .none { transitionsUsed.append(slot.entry) }

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
                    fx.setLevel(48, for: MixrEffect.blur.rawValue)
                    fx.setLevel(16, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .classic
                case .build:
                    fx.flangerAmount = seg.pulse == .buildOut ? 0.36 : (slot.energy > 0.78 ? 0.30 : 0.22)
                    fx.setLevel(seg.pulse == .buildOut ? 42 : 24, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .pingPong
                    if seg.pulse == .buildOut {
                        // Filter sweep into the void/drop — busy, not polite.
                        fx.setLevel(58, for: MixrEffect.blur.rawValue)
                        fx.setLevel(20, for: MixrEffect.reverb.rawValue)
                        fx.reverbPreset = .hall
                    } else {
                        fx.setLevel(flavor.bias.fxAsGroove ? 26 : 18, for: MixrEffect.blur.rawValue)
                    }
                    if flavor.bias.fxAsGroove {
                        fx.setLevel(max(fx.level(for: MixrEffect.echo.rawValue), 32), for: MixrEffect.echo.rawValue)
                    }
                case .chorus:
                    // Filter opens on the downbeat — drop is brighter than build-out.
                    fx.setLevel(dropIndex == 0 ? 6 : 10, for: MixrEffect.blur.rawValue)
                    fx.setLevel(dropIndex == 0 ? 12 : 18, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = dropIndex == 0 ? .hall : .ambient
                    fx.setLevel(dropIndex == 0 ? 10 : 16, for: MixrEffect.echo.rawValue)
                    if dropIndex >= 1, flavor.bias.drop2AiryLayer {
                        fx.setLevel(20, for: MixrEffect.echo.rawValue)
                        fx.setLevel(16, for: MixrEffect.reverb.rawValue)
                    }
                    if flavor.bias.vocalChopLead, dropIndex == 0 {
                        fx.setLevel(14, for: MixrEffect.blur.rawValue)
                    }
                    if flavor.bias.aggressiveLowEnd {
                        fx.flangerAmount = max(fx.flangerAmount, 0.12)
                    }
                    if flavor.bias.fxAsGroove {
                        // Echo throws on the vocal / filter open as groove, not garnish.
                        fx.setLevel(max(fx.level(for: MixrEffect.echo.rawValue), 18), for: MixrEffect.echo.rawValue)
                        fx.echoPreset = .pingPong
                    }
                case .breakdown:
                    fx.setLevel(28 + flavor.bias.breakdownVocalClarity * 22, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = .ambient
                    fx.setLevel(22, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .classic
                    // Atmosphere bloom — not a muted midrange hole.
                    if flavor.bias.dropMidrangeSparse {
                        fx.setLevel(20, for: MixrEffect.blur.rawValue)
                    } else {
                        fx.setLevel(12, for: MixrEffect.blur.rawValue)
                    }
                case .ending:
                    fx.setLevel(28, for: MixrEffect.reverb.rawValue)
                    fx.reverbPreset = .ambient
                    fx.setLevel(26, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .classic
                case .groove:
                    fx.setLevel(10, for: MixrEffect.echo.rawValue)
                default:
                    break
                }
                if pulse.duckSourceLowEnd, seg.pulse == .drop || seg.pulse == .groove || seg.pulse == .introTease {
                    fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 22), for: MixrEffect.blur.rawValue)
                }
                fx = AutoSupportedEffects.sanitize(fx)

                let sourceStart = section.startSeconds + Double(segCursor - cursor) * ratio
                var volume = AutoGainPolicy.songPlacementVolume(energy: seg.energy)
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
                    fadeOut = ClipTransition(type: .echoOut, duration: 8)
                } else if slot.role == .build, seg.pulse == .buildOut {
                    // Echo throw out of the build into the void/drop.
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

            // Coordinated club SFX stacks — builds/drops/breaks stay busy.
            // One-shots overlap on extra SFX rows at apply time.
            let segEnd = segCursor
            if slot.role == .build {
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
                // Filter open is clip FX blur on build-out — not an airSweep whoosh.
            }

            if slot.role == .groove || slot.role == .intro {
                // Keep the early arrangement busy — clap fills, not cymbal spam.
                let mid = cursor + Double(slot.bars) * bar * 0.5
                sfx.append(AutoSFXEvent(assetID: "clapFill", timelineStart: mid, purpose: "groove clap fill"))
            }

            if slot.role == .chorus {
                let dropAt = placements.last(where: { $0.slotIndex == slotIdx })?.timelineStart
                    ?? cursor
                let dropEnd = placements.last(where: { $0.slotIndex == slotIdx })?.timelineEnd
                    ?? (cursor + Double(slot.bars) * bar)
                // Diplo hype: snare + riser + impact + tape — crash only as
                // rare punctuation (≤1 per drop, ≤2 total with reverseCymbal).
                let stackHard = flavor.bias.maximalistStacks
                if stackHard || dropIndex == 0 {
                    if let riser = SoundEffectLibrary.definition(for: "riser"),
                       dropAt - riser.durationSeconds >= 0,
                       !sfx.contains(where: {
                           $0.assetID == "riser" && abs(($0.timelineStart + riser.durationSeconds) - dropAt) < 0.35
                       }) {
                        sfx.append(
                            AutoSFXEvent(
                                assetID: "riser",
                                timelineStart: dropAt - riser.durationSeconds,
                                purpose: "riser into drop"
                            )
                        )
                    }
                }
                if stackHard || dropIndex >= 1 {
                    if let snare = SoundEffectLibrary.definition(for: "snareBuild"),
                       dropAt - snare.durationSeconds >= 0,
                       !sfx.contains(where: {
                           $0.assetID == "snareBuild"
                               && abs(($0.timelineStart + snare.durationSeconds) - dropAt) < 0.35
                       }) {
                        sfx.append(
                            AutoSFXEvent(
                                assetID: "snareBuild",
                                timelineStart: dropAt - snare.durationSeconds,
                                purpose: "snare roll into drop"
                            )
                        )
                    }
                }
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: dropAt, purpose: "impact on drop downbeat"))
                let cymbalCount = sfx.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }.count
                if cymbalCount < 2 {
                    sfx.append(AutoSFXEvent(assetID: "crash", timelineStart: dropAt, purpose: "crash punctuation on drop"))
                }
                if stackHard || flavor.bias.vocalChopLead || dropIndex >= 1 {
                    sfx.append(AutoSFXEvent(assetID: "clapFill", timelineStart: dropAt, purpose: "clap fill on drop"))
                }
                // Tape stop into the slam — Diplo void-then-pile instinct.
                if stackHard || dropIndex >= 1 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "tapeStop",
                            timelineStart: max(0, dropAt - 0.35),
                            purpose: "tape stop into drop"
                        )
                    )
                }
                // Mid-drop fill so a 16-bar drop stays hyped (no mid-drop crash).
                let midDrop = dropAt + (dropEnd - dropAt) * 0.5
                sfx.append(AutoSFXEvent(assetID: "clapFill", timelineStart: midDrop, purpose: "mid-drop clap fill"))
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: midDrop, purpose: "mid-drop impact"))
                decisions.append(
                    AutoDecision(
                        kind: .addedRiserIntoDrop,
                        songTitle: profile.title,
                        detail: stackHard
                            ? "maximalist drop stack (\(flavor.rawValue))"
                            : (dropIndex == 0 ? "riser+impact drop 1" : "snare+impact drop 2")
                    )
                )
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

        // Blend every join except the intentional pre-drop void — equal-power
        // overlaps so verse→build→drop stays continuous (void is the only hole).
        blendAdjacentHandoffs(
            placements: &placements,
            intentionalGaps: intentionalGaps,
            songDurations: [profile.songID: analysis.durationSeconds],
            barSec: bar,
            beatSec: beat,
            tuning: tuning,
            cutRecords: &cutRecords
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

        // Same compact shape as the confident path — intro 8 + groove 8 +
        // build 8 → Drop 1 at bar 24 (not 48% of a long song).
        struct Seg {
            var role: AutoClubPulse.RegionRole
            var bars: Int
            var energy: Double
        }
        let shape: [Seg] = [
            .init(role: .introTease, bars: 8, energy: 0.42),
            .init(role: .groove, bars: 8, energy: 0.55),
            .init(role: .build, bars: 4, energy: 0.65),
            .init(role: .buildOut, bars: 4, energy: 0.50),
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

            if seg.role == .drop, t0 > beat {
                let voidSec = min(tuning.preferredPredropVoidBeats, tuning.maxIntentionalPauseBeats) * beat
                if voidSec > 0.05 {
                    let dropStart = t0
                    let voidStart = dropStart - voidSec
                    carvePredropVoid(
                        voidStart: voidStart,
                        dropStart: dropStart,
                        placements: &placements,
                        pulseRegions: &pulseRegions,
                        intentionalGaps: &intentionalGaps,
                        minSegmentSeconds: tuning.minSegmentSeconds
                    )
                    if let last = placements.last {
                        lastSourceEnd = last.sourceStart + last.timelineDuration * last.tempoRatio
                    }
                    if dropIndex == 0 {
                        decisions.append(
                            AutoDecision(
                                kind: .allowedPredropVoid,
                                songTitle: profile.title,
                                detail: "low-confidence club shape (drop on downbeat)"
                            )
                        )
                    }
                }
            }

            let role = seg.role
            pulseRegions.append(AutoClubPulse.Region(role: role, timelineStart: t0, timelineEnd: t1))

            var fx = ClipEffectSettings()
            if role == .introTease || role == .breakdown {
                fx.setLevel(role == .breakdown ? 40 : 36, for: MixrEffect.blur.rawValue)
                fx.setLevel(role == .breakdown ? 32 : 14, for: MixrEffect.reverb.rawValue)
                fx.reverbPreset = .ambient
                if role == .breakdown {
                    fx.setLevel(24, for: MixrEffect.echo.rawValue)
                    fx.echoPreset = .classic
                }
            }
            if role == .build {
                fx.flangerAmount = 0.26
                fx.setLevel(26, for: MixrEffect.echo.rawValue)
                fx.echoPreset = .pingPong
                fx.setLevel(flavor.bias.fxAsGroove ? 26 : 18, for: MixrEffect.blur.rawValue)
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
                fx.setLevel(12, for: MixrEffect.echo.rawValue)
            }
            if pulse.duckSourceLowEnd, role == .drop || role == .groove {
                fx.setLevel(max(fx.level(for: MixrEffect.blur.rawValue), 24), for: MixrEffect.blur.rawValue)
            }
            fx = AutoSupportedEffects.sanitize(fx)

            var volume = AutoGainPolicy.songPlacementVolume(energy: seg.energy)
            if pulse.duckSourceLowEnd, role == .groove || role == .introTease {
                volume *= AutoGainPolicy.pulseDuckedSongVolumeScale
            }

            // Source: continuous through tease/build; JUMP to hook on drops.
            let sourceStart: Double
            let sourceContinuous: Bool
            if role == .drop {
                let hookStart = dropIndex == 0 ? hook1 : hook2
                let clamped = min(max(usableStart, hookStart), max(usableStart, usableEnd - segDur * ratio))
                sourceStart = clamped
                sourceContinuous = false
                if let prevEnd = lastSourceEnd, abs(clamped - prevEnd) > 0.05 {
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
            } else if let prev = lastSourceEnd {
                sourceStart = prev
                sourceContinuous = true
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
                    fadeIn: role == .drop ? ClipTransition(type: .crossfade, duration: 0.125) : .none,
                    fadeOut: fadeOut,
                    effects: fx,
                    role: .dominant,
                    slotIndex: i,
                    continuesPrevious: sourceContinuous
                )
            )
            lastSourceEnd = sourceStart + segDur * ratio

            // Diplo hype: snare/riser/impact/tape — not a crash every join.
            if role == .groove || role == .introTease {
                sfx.append(AutoSFXEvent(assetID: "clapFill", timelineStart: t0 + segDur * 0.5, purpose: "groove clap fill"))
            }
            if role == .build || role == .buildOut {
                if let snare = SoundEffectLibrary.definition(for: "snareBuild"), t1 - snare.durationSeconds >= t0 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "snareBuild",
                            timelineStart: t1 - snare.durationSeconds,
                            purpose: "snare through build"
                        )
                    )
                }
                if role == .buildOut, let riser = SoundEffectLibrary.definition(for: "riser"),
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
                if let snare = SoundEffectLibrary.definition(for: "snareBuild"), t0 - snare.durationSeconds >= 0 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "snareBuild",
                            timelineStart: t0 - snare.durationSeconds,
                            purpose: "snare into drop"
                        )
                    )
                }
                if let riser = SoundEffectLibrary.definition(for: "riser"), t0 - riser.durationSeconds >= 0 {
                    sfx.append(
                        AutoSFXEvent(
                            assetID: "riser",
                            timelineStart: t0 - riser.durationSeconds,
                            purpose: "riser into drop"
                        )
                    )
                }
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: t0, purpose: "impact on drop"))
                if cymbalPunctuation < 2 {
                    sfx.append(AutoSFXEvent(assetID: "crash", timelineStart: t0, purpose: "crash punctuation on drop"))
                    cymbalPunctuation += 1
                }
                sfx.append(AutoSFXEvent(assetID: "clapFill", timelineStart: t0, purpose: "clap fill on drop"))
                sfx.append(
                    AutoSFXEvent(
                        assetID: "tapeStop",
                        timelineStart: max(0, t0 - 0.35),
                        purpose: "tape stop into drop"
                    )
                )
                let mid = t0 + segDur * 0.45
                sfx.append(AutoSFXEvent(assetID: "clapFill", timelineStart: mid, purpose: "mid-drop clap"))
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: mid, purpose: "mid-drop impact"))
                dropIndex += 1
            }
            if role == .breakdown {
                sfx.append(AutoSFXEvent(assetID: "downlifter", timelineStart: t0, purpose: "downlifter into breakdown"))
            }
            if role == .outro {
                sfx.append(AutoSFXEvent(assetID: "impact", timelineStart: t0, purpose: "final hit"))
                sfx.append(AutoSFXEvent(assetID: "downlifter", timelineStart: min(t1 - 0.5, t0 + 1.0), purpose: "outro downlifter"))
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
            randomSeed: seed
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
        let drop1 = fullHooks.first
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

        // Rotate which guest vocals stack on drop 1 vs drop 2.
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
        let drop1OverlayIdx = pickOverlay(
            excluding: drop1Idx,
            prefer: [
                drop2Candidate.map { indexOf[$0.songID]! },
                grooveIdx, breakIdx, outroIdx,
                drop2IsBedFlip ? nil : Optional(drop2Idx),
            ]
        )
        let drop2OverlayIdx = pickOverlay(
            excluding: drop2Idx,
            prefer: [
                drop1Idx, // rotate: Drop 1 hook returns as chant under Drop 2
                outroIdx, grooveIdx, breakIdx,
            ]
        )

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
    private static func nSongClubMashupSlots(
        drop1Idx: Int?,
        drop2Idx: Int,
        drop2IsBedFlip: Bool,
        grooveCameoIdx: Int?,
        breakdownCameoIdx: Int?,
        outroCameoIdx: Int?
    ) -> [Slot] {
        var slots: [Slot] = [
            Slot(songIdx: 0, role: .intro, bars: 8, entry: .none, energy: 0.45, shrinkPriority: 2),
        ]
        if let g = grooveCameoIdx {
            slots.append(Slot(songIdx: g, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.55))
        } else {
            slots.append(Slot(songIdx: 0, role: .groove, bars: 8, entry: .cleanCrossfade, energy: 0.58))
        }
        slots.append(Slot(songIdx: 0, role: .build, bars: 8, entry: .flangerBuild, energy: 0.72))

        if let d1 = drop1Idx {
            slots.append(Slot(songIdx: d1, role: .chorus, bars: 16, entry: .hardHypeCut, energy: 1.0))
        } else {
            slots.append(Slot(songIdx: 0, role: .chorus, bars: 16, entry: .hardHypeCut, energy: 1.0))
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
            // Min identity stay is 8 bars — no 4-bar outro ping.
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
            drumStrength: pulseSource.analysis.drumStrength,
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
                   tuning: tuning
               ),
               let base = section {
                section = AutoCandidateSection(
                    songID: base.songID,
                    label: base.label,
                    startSeconds: island.guestStart,
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
            let identityFloor = mode == .mashup ? max(minBars, 8) : minBars
            while bars > identityFloor, Double(bars) * barSec > availableSeconds {
                bars -= minBars
            }
            // Mashups: skip rather than emit a sub-8-bar island.
            if mode == .mashup, bars < 8 {
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
            if reused, slot.isReturn {
                if entry == .none || entry == .cleanCrossfade {
                    entry = .hardHypeCut
                }
                energy = min(1, energy + 0.08)
            }

            // Intentional pre-drop void: last beat(s) of the previous bar.
            // Drop stays on the downbeat — do not advance cursor past the bar line.
            if entry == .hardHypeCut, !profile.lowConfidence, cursor > 0 {
                let voidBeats = min(tuning.preferredPredropVoidBeats, tuning.maxIntentionalPauseBeats)
                let pause = voidBeats * beatSec
                if pause > 0.05, cursor > pause {
                    let dropStart = cursor
                    let voidStart = dropStart - pause
                    if let idx = placed.indices.last {
                        let newDur = voidStart - placed[idx].timelineStart
                        if newDur >= tuning.minSegmentSeconds {
                            placed[idx].timelineDuration = newDur
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
                    decisions.append(
                        AutoDecision(
                            kind: .allowedPredropVoid,
                            songTitle: profile.title,
                            detail: String(format: "%.2f beats (drop on downbeat)", voidBeats)
                        )
                    )
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
            let baseVolume = 0.82 + 0.18 * ps.slot.energy
            let allowMajorSFX = boundary - lastMajorSFXTime >= majorSFXSpacing

            if i > 0 { transitionsUsed.append(entry) }

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

            // Club mashup drops: bed under the hook (one kick/bass) + optional
            // second vocal chant/harmony (Bollywood stack). Vocals may overlap.
            if mode == .mashup, ps.slot.role == .chorus {
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

            // Coordinated SFX — denser in remix; mashup drops still get a
            // riser→impact deck so the third layer overlaps the outgoing phrase.
            let isDropReveal = ps.slot.role == .chorus && entry == .hardHypeCut

            if i > 0, (allowMajorSFX || isDropReveal) {
                switch entry {
                case .hardHypeCut where isDropReveal || mode == .remix || ps.slot.isFinalPeak:
                    let stackHard = mashupFlavor.bias.maximalistStacks
                    let buildID = ps.slot.isFinalPeak || stackHard ? "snareBuild" : "riser"
                    // Riser/snare overlaps the outgoing phrase into the downbeat.
                    addSFXEnding(
                        buildID,
                        at: boundary,
                        purpose: ps.slot.isFinalPeak ? "snare build into the final drop" : "riser into the drop"
                    )
                    if stackHard || ps.slot.isFinalPeak {
                        addSFXEnding("riser", at: boundary, purpose: "riser stacked into the drop")
                        addSFXEnding("snareBuild", at: boundary, purpose: "snare stacked into the drop")
                    }
                    addSFX("impact", at: boundary, purpose: "impact on the drop downbeat")
                    let cymbalCount = sfx.filter { $0.assetID == "crash" || $0.assetID == "reverseCymbal" }.count
                    if cymbalCount < 2 {
                        addSFX("crash", at: boundary, purpose: "crash punctuation on drop")
                    }
                    if stackHard || ps.slot.isFinalPeak || mode == .remix {
                        addSFX("clapFill", at: boundary, purpose: "clap fill on the drop")
                    }
                    if stackHard || ps.slot.isFinalPeak {
                        addSFX("tapeStop", at: max(0, boundary - 0.35), purpose: "tape stop into drop")
                    }
                    decisions.append(
                        AutoDecision(
                            kind: .addedRiserIntoDrop,
                            songTitle: nil,
                            detail: ps.slot.isFinalPeak ? "snare+riser+impact" : "riser+impact"
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
                    addSFXEnding("snareBuild", at: boundary + ps.timelineDuration, purpose: "snare through the build")
                    addSFXEnding("riser", at: boundary + ps.timelineDuration, purpose: "riser through the build")
                    addSFX("impact", at: boundary + ps.timelineDuration, purpose: "impact off the build")
                    lastMajorSFXTime = boundary + ps.timelineDuration
                case .atmosphericHandoff:
                    addSFX("downlifter", at: boundary, purpose: "downlifter into breakdown")
                    lastMajorSFXTime = boundary
                case .cleanCrossfade where mode == .remix:
                    // No airSweep/crash on polite handoffs — Diplo density is
                    // snare/impact/tape on drops, not a whoosh every 8 bars.
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

        // Continuous energy through handoffs — equal-power overlaps everywhere
        // except the intentional pre-drop void. Bed stays under the hook drop.
        var songDurations: [UUID: Double] = [:]
        for p in ordered {
            songDurations[p.songID] = p.analysis.durationSeconds
        }
        var cutRecords: [AutoCutRecord] = []
        blendAdjacentHandoffs(
            placements: &placements,
            intentionalGaps: intentionalGaps,
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
            randomSeed: seed
        )
    }

    /// Equal-power overlaps on every dominant join except the intentional
    /// pre-drop void. Keeps continuous energy through verse→build→drop;
    /// the only quiet hole is the 1-beat void into a drop.
    private static func blendAdjacentHandoffs(
        placements: inout [AutoClipPlacement],
        intentionalGaps: [AutoIntentionalGap],
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

            // Keep the pre-drop void as the only intentional hole.
            let voidBeforeNext = intentionalGaps.contains { abs($0.end - next.timelineStart) < 0.05 }
            if voidBeforeNext { continue }

            // Source-continuous neighbors (energy-curve / no-cut path): do not
            // invent an overlap cut — that would manufacture internal edits.
            let sourceContinuous = abs(next.sourceStart - (
                prev.sourceStart + prev.timelineDuration * prev.tempoRatio
            )) < 0.05 || next.continuesPrevious
            if sourceContinuous {
                continue
            }

            // Different songs: never overlap two dominants (dual full mixes).
            // Layer the outgoing as a supporting deck under the incoming.
            if prev.songID != next.songID {
                if placements[prevIdx].timelineEnd > next.timelineStart + 0.05 {
                    let trimmed = next.timelineStart - placements[prevIdx].timelineStart
                    if trimmed >= tuning.minSegmentSeconds * 0.5 {
                        placements[prevIdx].timelineDuration = trimmed
                    }
                }
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
                                volume: tuning.supportVolume,
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
                placements[nextIdx].fadeIn = ClipTransition(
                    type: .crossfade, duration: overlapBeats, curve: equalPower
                )
                placements[nextIdx].overlapsPreviousSeconds = max(
                    placements[nextIdx].overlapsPreviousSeconds, overlapSec
                )
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
        if let bedID = mashupBedID, leadProfile.songID != bedID,
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
                let dualBass = bed.analysis.bassDensity > 0.65
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
                } else {
                    var bedFX = ClipEffectSettings()
                    // Frequency-split layering: bed keeps kick/bass audible;
                    // HPF/blur mids so the vocal sits on top — never mute the bed.
                    let midCarve: Double = lead.section.vocal > 0.45 ? 34 : 22
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
                }
            }
        }

        // Second vocal: chant / title line / harmony for 4–16 bars.
        guard let overlayIdx = overlaySongIdx,
              overlayIdx >= 0, overlayIdx < ordered.count else { return }
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
        var overlayBars = max(4, min(tuning.vocalOverlayBars, 16))
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
                    detail: "under \(leadProfile.title) on \(dropLabel)"
                )
            )
        } else {
            fx.setLevel(16, for: MixrEffect.blur.rawValue)
            volume = tuning.supportVolume
        }
        // Extra HPF when overlay still carries drum weight.
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
                slotIndex: leadSlotIndex
            )
        )
        usedRanges[overlay.songID, default: []].append(
            (section.startSeconds, section.startSeconds + duration * overlayFit.ratio)
        )
        decisions.append(
            AutoDecision(
                kind: .stackedVocalOverlay,
                songTitle: overlay.title,
                detail: "\(overlayBars) bars on \(dropLabel) under \(leadProfile.title)"
            )
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
