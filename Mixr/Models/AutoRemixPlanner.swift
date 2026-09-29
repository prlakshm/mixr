import Foundation

// MARK: - Auto Remix Planner
//
// Builds an AutoRemixPlan from MEASURED song structure (SongStructure:
// tracked beats, Viterbi downbeats, phrase grid, SSM sections, bar energy).
//
//   1 song   → DJ EDIT: the song in source order, with 3–5 evidence-backed
//              transformation zones on high confidence — hook preview or
//              intro trim, redundant-repeat removal (seamless bar-matched
//              jump), filter-opening breakdown, extended high-pass build
//              into the final drop (riser + impact on the downbeat), and an
//              echo-out ending. Medium confidence keeps the audio
//              continuous (effects + edge trims); low confidence leaves the
//              song essentially untouched.
//   2+ songs → MASHUP: even airtime, round-robin appearances. Each
//              appearance is ONE source-continuous run (lead-in phrase →
//              hook/drop), so the song's own build carries into its payoff.
//              Handoffs are phrase-aligned and beatmatched: 2–8-bar
//              equal-power blends with an EQ bass swap, high-pass builds
//              that drop on the downbeat, or an echo slam when tempos or
//              beat grids can't lock. Songs are loudness-matched.
//
// Every edit records its evidence; the confidence ladder in AGENTS.md
// decides how aggressive the plan may be.

enum AutoRemixPlanner {

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

        let contexts = songTracks.map { track -> SongContext in
            let profile = AutoSectionCatalog.profile(track: track, tuning: tuning, signal: signals[track.id])
            return SongContext(profile: profile, track: track, tuning: tuning)
        }

        let plan: AutoRemixPlan?
        if contexts.count == 1 {
            plan = remixPlan(contexts[0], tuning: tuning, seed: seed)
        } else {
            plan = mashupPlan(contexts, tuning: tuning, seed: seed)
        }
        guard var plan else { return nil }
        for c in contexts where c.track.bpm == nil && c.structure != nil {
            plan.measuredTrackBPMs[c.id] = c.engineTrackBPM
        }
        let byID = Dictionary(uniqueKeysWithValues: contexts.map { ($0.id, $0.profile) })
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
            for edge in [p.fadeIn, p.fadeOut] {
                switch edge.filter {
                case .bassSwap: effectNames.insert("Bass Swap")
                case .highPassSweep: effectNames.insert("High-Pass Build")
                case .lowPassSweep: effectNames.insert("Filter Sweep")
                case nil: break
                }
                if edge.type == .echoOut { effectNames.insert("Echo Out") }
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

    // MARK: - Song context + confidence ladder

    enum Tier: Int, Comparable {
        case low, medium, high
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    struct SongContext {
        let profile: AutoSongProfile
        let track: MixrTrack
        let structure: SongStructure?
        let signal: SongSignalFeatures?
        let tier: Tier

        var id: UUID { profile.songID }
        var title: String { profile.title }
        var analysis: SongAnalysis { profile.analysis }
        var duration: Double { profile.analysis.durationSeconds }
        var bpm: Double { structure?.bpm ?? profile.analysis.bpm }

        init(profile: AutoSongProfile, track: MixrTrack, tuning: AutoTuning) {
            self.profile = profile
            self.track = track
            signal = profile.analysis.signal
            structure = profile.analysis.signal?.structure
            tier = Self.tier(profile: profile, tuning: tuning)
        }

        /// AGENTS.md confidence ladder, from measured evidence only.
        static func tier(profile: AutoSongProfile, tuning: AutoTuning) -> Tier {
            guard let signal = profile.analysis.signal, let st = signal.structure,
                  signal.overallConfidence >= 0.4
            else { return .low }
            let overall = profile.analysis.analysisConfidence
            if overall >= 0.58, st.tempoStability >= 0.5, st.downbeatConfidence >= 0.3,
               st.structureConfidence >= 0.5, profile.analysis.durationSeconds >= 150 {
                return .high
            }
            if overall >= tuning.lowConfidenceThreshold, st.structureConfidence >= 0.45 {
                return .medium
            }
            return .low
        }

        /// Source seconds of bar `i` (grid-extrapolated past the ends).
        func barTime(_ i: Int) -> Double {
            structure?.barTime(i) ?? Double(i) * profile.analysis.barSeconds
        }

        var barCount: Int { structure?.bars.count ?? Int(duration / profile.analysis.barSeconds) }

        /// Mean bar energy over [a, b) (0…1).
        func energy(_ a: Int, _ b: Int) -> Double {
            guard let bars = structure?.bars, !bars.isEmpty else { return 0.5 }
            let lo = max(0, min(a, bars.count - 1)), hi = max(lo + 1, min(b, bars.count))
            return bars[lo..<hi].map(\.energy).reduce(0, +) / Double(hi - lo)
        }

        func vocal(_ a: Int, _ b: Int) -> Double {
            guard let bars = structure?.bars, !bars.isEmpty else { return 0.5 }
            let lo = max(0, min(a, bars.count - 1)), hi = max(lo + 1, min(b, bars.count))
            return bars[lo..<hi].map(\.vocal).reduce(0, +) / Double(hi - lo)
        }

        func isPhraseStart(_ bar: Int) -> Bool {
            guard let st = structure else { return bar % 4 == 0 }
            return ((bar - st.phraseOffsetBars) % 4 + 4) % 4 == 0
        }

        /// First bar index whose downbeat is at/after the music start.
        var firstMusicBar: Int {
            let lead = signal?.leadingSilenceSeconds ?? 0
            guard let st = structure else { return 0 }
            return st.downbeats.firstIndex { $0 >= lead - 0.1 } ?? 0
        }

        /// Last bar index (exclusive) that still contains music.
        var musicEndBar: Int {
            let end = duration - (signal?.trailingSilenceSeconds ?? 0)
            guard let st = structure else { return barCount }
            let idx = st.downbeats.lastIndex { $0 < end - 0.5 } ?? (st.downbeats.count - 1)
            return min(st.bars.count, idx + 1)
        }

        /// Bar index (exclusive) after the last bar with real body — a song's
        /// fade-out tail is not material a mid-mix appearance may use.
        var loudEndBar: Int {
            guard let bars = structure?.bars, !bars.isEmpty else { return musicEndBar }
            let end = min(musicEndBar, bars.count)
            var i = end
            while i > 1, bars[i - 1].energy < 0.25 { i -= 1 }
            return max(1, i)
        }

        /// Linear gain that brings this song's body loudness to `referenceDB`.
        func loudnessGain(referenceDB: Double) -> Double {
            guard let l = signal?.bodyLoudnessDB, l > -80 else { return 1 }
            return min(1, max(0.5, pow(10, (referenceDB - l) / 20)))
        }

        /// The track BPM the engines will read (measured when missing —
        /// the applier writes it back via `measuredTrackBPMs`).
        var engineTrackBPM: Int { track.bpm ?? Int(bpm.rounded()) }

        /// Engine tempo for fade beats at playback rate `r`.
        func envelopeBPM(rate r: Double) -> Double {
            AutoTransitionEnvelope.timelineBPM(trackBPM: engineTrackBPM, playbackSpeed: r)
        }
    }

    // MARK: - Span assembly (shared by remix + mashup)

    enum Join: Equatable {
        /// First span of a song appearance (no same-song predecessor).
        case start
        /// Sample-continuous continuation of the previous span.
        case continuous
        /// Same-song internal cut: equal-power crossfade of `seconds`
        /// ending exactly on the incoming downbeat (pre-roll).
        case preRollCrossfade(Double)
    }

    struct Span {
        var sourceStart: Double
        var sourceEnd: Double
        var join: Join = .start
        /// Edge automation beyond the join fades (filters, echo-out).
        var inEdge: ClipTransition = .none
        var outEdge: ClipTransition = .none
        var effects = ClipEffectSettings()
        var cut: AutoCutRecord? = nil
    }

    /// Converts one song's spans (in play order, tempo `rate`) into gapless
    /// placements starting at `timelineStart`. Returns placements, cut
    /// records (timeline-resolved), and the timeline end.
    static func assemble(
        _ spans: [Span],
        song: SongContext,
        rate: Double,
        volume: Double,
        timelineStart: Double,
        slot: Int
    ) -> (placements: [AutoClipPlacement], cuts: [AutoCutRecord], end: Double) {
        var placements: [AutoClipPlacement] = []
        var cuts: [AutoCutRecord] = []
        var cursor = timelineStart
        let bpm = song.envelopeBPM(rate: rate)
        func beats(_ seconds: Double) -> Double {
            AutoTransitionEnvelope.beats(forSeconds: seconds, timelineBPM: bpm)
        }
        for span in spans {
            var tStart = cursor
            var srcStart = span.sourceStart
            var fadeIn = span.inEdge
            var overlap = 0.0
            var continues = false
            switch span.join {
            case .start:
                break
            case .continuous:
                continues = true
            case .preRollCrossfade(let xf):
                tStart = cursor - xf
                srcStart = span.sourceStart - xf * rate
                overlap = xf
                fadeIn = ClipTransition(
                    type: .crossfade, duration: beats(xf),
                    curve: AutoTransitionEnvelope.equalPowerCurveName, filter: span.inEdge.filter
                )
                if var prev = placements.popLast() {
                    prev.fadeOut = ClipTransition(
                        type: .crossfade, duration: beats(xf),
                        curve: AutoTransitionEnvelope.equalPowerCurveName, filter: prev.fadeOut.filter
                    )
                    placements.append(prev)
                }
            }
            let duration = (span.sourceEnd - srcStart) / rate
            guard duration > 0.05 else { continue }
            placements.append(
                AutoClipPlacement(
                    songID: song.id,
                    sourceStart: srcStart,
                    timelineStart: tStart,
                    timelineDuration: duration,
                    tempoRatio: rate,
                    volume: volume,
                    fadeIn: fadeIn,
                    fadeOut: span.outEdge,
                    effects: AutoSupportedEffects.sanitize(span.effects),
                    role: .dominant,
                    slotIndex: slot,
                    continuesPrevious: continues,
                    overlapsPreviousSeconds: overlap,
                    envelopeBPM: bpm
                )
            )
            if var cut = span.cut {
                cut.timelineAt = tStart
                cut.sourceTo = srcStart
                cuts.append(cut)
            }
            cursor = tStart + duration
        }
        return (placements, cuts, cursor)
    }

    /// Timeline downbeats carried by dominant placements.
    static func timelineDownbeats(_ placements: [AutoClipPlacement], contexts: [UUID: SongContext]) -> [Double] {
        var out: [Double] = []
        for p in placements where p.role == .dominant {
            guard let st = contexts[p.songID]?.structure else { continue }
            for d in st.downbeats where d >= p.sourceStart - 0.01 && d < p.sourceEnd - 0.01 {
                out.append(p.timelineStart + (d - p.sourceStart) / p.tempoRatio)
            }
        }
        out.sort()
        var deduped: [Double] = []
        for t in out where deduped.last.map({ t - $0 > 0.05 }) ?? true { deduped.append(t) }
        return deduped
    }

    // MARK: - SFX scheduling (single-lane SFX track: never overlap)

    struct SFXLane {
        var events: [AutoSFXEvent] = []

        /// Adds an event only if it fits without overlapping another
        /// (sliding would push hits off the beat — dropping is safer).
        @discardableResult
        mutating func add(_ id: String, at start: Double, purpose: String) -> Bool {
            guard let def = SoundEffectLibrary.definition(for: id), start >= 0 else { return false }
            let end = start + def.durationSeconds
            let clear = events.allSatisfy { e in end <= e.timelineStart + 0.01 || start >= e.timelineEnd - 0.01 }
            guard clear else { return false }
            events.append(AutoSFXEvent(assetID: id, timelineStart: start, purpose: purpose))
            return true
        }

        /// Adds an event that ENDS at `t` (risers into a downbeat).
        @discardableResult
        mutating func add(_ id: String, endingAt t: Double, purpose: String) -> Bool {
            guard let def = SoundEffectLibrary.definition(for: id) else { return false }
            return add(id, at: t - def.durationSeconds, purpose: purpose)
        }
    }

    // MARK: - One-song DJ edit

    private static func remixPlan(_ song: SongContext, tuning: AutoTuning, seed: UInt64) -> AutoRemixPlan? {
        let duration = song.duration
        guard duration > 1 else { return nil }
        var decisions: [AutoDecision] = [
            AutoDecision(kind: .selectedAnchor, songTitle: song.title, detail: "remix — \(tierName(song.tier)) confidence")
        ]
        var warnings: [String] = []
        let volume = AutoGainPolicy.preservationSongVolume

        guard let st = song.structure, song.tier > .low else {
            return continuousRemix(song, tuning: tuning, seed: seed, decisions: decisions)
        }

        let bars = st.bars
        let n = song.musicEndBar
        let barSec = st.barSeconds
        let first = song.firstMusicBar
        let ssm = SongStructureAnalyzer.selfSimilarity(bars)
        let offDiag: [Double] = {
            var v: [Double] = []
            for i in 0..<bars.count { for j in (i + 4)..<max(i + 4, bars.count) where j < bars.count { v.append(ssm[i][j]) } }
            return v.sorted()
        }()
        func pct(_ p: Double) -> Double { offDiag.isEmpty ? 1 : offDiag[Int(Double(offDiag.count - 1) * p)] }
        let repeatThreshold = pct(0.85)
        let joinThreshold = song.tier == .high ? pct(0.80) : pct(0.92)

        let choruses = st.sections(.chorus).filter { $0.barCount >= 4 && $0.endBar <= n }
        let firstChorus = choruses.first
        let finalChorus = choruses.last { $0.startBar >= max(first + 16, (firstChorus?.endBar ?? 0) + 8) }

        // ── Zone A (opening): intro trim or hook preview ──
        var startBar = first
        var preview: MeasuredSection?
        if let intro = st.sections.first, intro.label == .intro,
           intro.endBar - first >= 12, song.energy(first, intro.endBar) < 0.45 {
            // Evidence: ≥ 12 bars of low-energy lead-in. Keep its last 8.
            var s = intro.endBar - 8
            while s > first, !song.isPhraseStart(s) { s -= 1 }
            startBar = max(first, s)
            decisions.append(AutoDecision(
                kind: .trimmedIntro, songTitle: song.title,
                detail: String(format: "%d low-energy bars (energy %.2f) → 8", intro.endBar - first, song.energy(first, intro.endBar))
            ))
        } else if song.tier == .high, let c = firstChorus, c.confidence >= 0.5,
                  c.startBar - first >= 8, song.energy(c.startBar, c.startBar + 4) >= 0.6 {
            preview = c
        }

        // Filtered intro: when the opening needs no trim or preview, the
        // first phrase opens from a low-pass (DJ intro) — safe on any
        // song with a confident bar grid.
        var filteredIntroBars = 0
        if preview == nil, startBar == first, song.tier == .high {
            filteredIntroBars = 8
            while filteredIntroBars > 4, !song.isPhraseStart(first + filteredIntroBars) { filteredIntroBars -= 1 }
            if n - first < 48 { filteredIntroBars = 0 }
        }

        // ── Zone D (ending): shorten a long low-energy outro ──
        var endBar = n
        if let outro = st.sections.last, outro.label == .outro, outro.endBar >= n - 1,
           outro.barCount >= 8, song.energy(outro.startBar, outro.endBar) < 0.55 {
            endBar = min(n, outro.startBar + 4)
            decisions.append(AutoDecision(kind: .shortenedOutro, songTitle: song.title,
                                          detail: "\(outro.barCount) bars → 4 + echo-out"))
        }

        // ── Zone C (final approach): extended high-pass build ──
        var buildBar: Int?
        if let c = finalChorus, c.startBar - 4 > startBar + 8 {
            let lift = song.energy(c.startBar, c.startBar + 4) - song.energy(c.startBar - 4, c.startBar)
            if lift >= 0.12 {
                buildBar = c.startBar
            } else if lift >= 0.05 {
                buildBar = c.startBar   // weaker lift: effect-only build (no repeat)
            }
            // Land the drop where the music actually hits: a near-silent
            // break bar at the chorus start belongs to the build.
            if let b = buildBar, song.energy(b, b + 1) < 0.3, song.energy(b + 1, b + 3) > 0.6 {
                buildBar = b + 1
            }
        }
        let repeatBuild: Bool = {
            guard let b = buildBar, song.tier == .high else { return false }
            return song.energy(b, b + 4) - song.energy(b - 4, b) >= 0.12
        }()

        // ── Zone B (middle): redundant-repeat removal ──
        struct Cut { var from: Int; var to: Int; var score: Double; var join: Double }
        let protectStart = max(startBar + 16, firstChorus?.endBar ?? (startBar + 24))
        let protectEnd = (buildBar ?? endBar) - 8
        var cutCandidates: [Cut] = []
        if protectEnd - protectStart >= 8 {
            for k in protectStart...protectEnd where song.isPhraseStart(k) && k >= 1 {
                for len in [8, 4] {
                    let m = k + len
                    guard m <= protectEnd, m < n - 4 else { continue }
                    let redundant = (k..<m).allSatisfy { i in
                        (0..<max(0, i - 8)).contains { j in ssm[i][j] >= repeatThreshold }
                    }
                    guard redundant else { continue }
                    let inFinal = finalChorus.map { k < $0.endBar && m > $0.startBar } ?? false
                    guard !inFinal else { continue }
                    let join = 0.5 * (ssm[k - 1][m - 1] + ssm[k][m])
                    let dE = abs(bars[k - 1].energy - bars[m - 1].energy) + abs(bars[k].energy - bars[m].energy)
                    guard join >= joinThreshold, dE < 0.3 else { continue }
                    cutCandidates.append(Cut(from: k, to: m, score: join - 0.5 * dE + (len == 8 ? 0.03 : 0), join: join))
                }
            }
        }
        var cuts: [Cut] = []
        let maxCuts = song.tier == .high ? 1 : (cutCandidates.first.map { $0.join >= pct(0.95) } == true ? 1 : 0)
        for c in cutCandidates.sorted(by: { $0.score > $1.score }) where cuts.count < maxCuts {
            cuts.append(c)
        }

        // ── Zone B′ (breakdown): filter-opening breakdown ──
        var breakdown: MeasuredSection?
        if song.tier == .high {
            breakdown = st.sections.first { s in
                (s.label == .bridge || s.label == .breakdown)
                    && s.barCount >= 4
                    && s.startBar >= protectStart
                    && s.endBar <= (buildBar.map { $0 - 4 } ?? endBar)
                    && s.energy < 0.5
                    && !cuts.contains { c in c.from < s.endBar && c.to > s.startBar }
            }
        }

        // Timeline budget: remove further redundant phrases, then trim the end.
        func plannedBars() -> Int {
            var total = endBar - startBar + (preview == nil ? 0 : 4) + (repeatBuild ? 4 : 0)
            for c in cuts { total -= c.to - c.from }
            return total
        }
        var trimmedForBudget = false
        for c in cutCandidates.sorted(by: { $0.score > $1.score })
        where Double(plannedBars()) * barSec > tuning.maxTimelineSeconds {
            if !cuts.contains(where: { $0.from < c.to && $0.to > c.from }) { cuts.append(c) }
        }
        while Double(plannedBars()) * barSec > tuning.maxTimelineSeconds, endBar - 8 > startBar + 16 {
            endBar -= 4
            trimmedForBudget = true
        }
        if trimmedForBudget {
            decisions.append(AutoDecision(kind: .shortenedForMaterial, songTitle: song.title, detail: "ending to fit the timeline"))
        }
        cuts.sort { $0.from < $1.from }

        // ── Assemble play ranges (bar indices, play order) ──
        struct Range {
            var from: Int
            var to: Int
            var join: Join
            var inEdge: ClipTransition = .none
            var outEdge: ClipTransition = .none
            var cut: AutoCutRecord? = nil
            var isDrop = false
            var isPreview = false
        }
        let xf = min(0.5 * 60 / st.bpm, 0.12)      // pre-roll crossfade for internal cuts
        let previewXF = 60 / st.bpm                 // one beat out of the hook preview
        func t(_ b: Int) -> Double { song.barTime(b) }
        let confidence = song.analysis.analysisConfidence

        var ranges: [Range] = []
        if let p = preview {
            ranges.append(Range(from: p.startBar, to: p.startBar + 4, join: .start,
                                inEdge: ClipTransition(type: .none, duration: 14, filter: .lowPassSweep), isPreview: true))
            decisions.append(AutoDecision(kind: .hookPreview, songTitle: song.title, detail: nil))
        }
        // Body minus removed repeats.
        var bodyStart = startBar
        var bodyJoin: Join = .start
        var bodyCut: AutoCutRecord? = nil
        if let p = preview {
            bodyJoin = .preRollCrossfade(previewXF)
            bodyCut = AutoCutRecord(timelineAt: 0, sourceFrom: t(p.startBar + 4), sourceTo: t(startBar),
                                    reason: .hookPreview, confidence: confidence,
                                    expectedEnergyDeltaDB: 0, masking: .equalPowerCrossfade(seconds: previewXF))
        }
        for c in cuts {
            ranges.append(Range(from: bodyStart, to: c.from, join: bodyJoin, cut: bodyCut))
            bodyStart = c.to
            bodyJoin = .preRollCrossfade(xf)
            bodyCut = AutoCutRecord(timelineAt: 0, sourceFrom: t(c.from), sourceTo: t(c.to),
                                    reason: .redundantRepeat, confidence: min(1, c.join),
                                    expectedEnergyDeltaDB: 0, masking: .equalPowerCrossfade(seconds: xf))
            decisions.append(AutoDecision(
                kind: .removedRedundantRepeat, songTitle: song.title,
                detail: String(format: "%d bars already heard, bar-match %.2f", c.to - c.from, c.join)
            ))
        }
        ranges.append(Range(from: bodyStart, to: endBar, join: bodyJoin, cut: bodyCut))

        /// Splits the range containing `bar` so a range boundary lands on it.
        func split(at bar: Int) {
            guard let i = ranges.firstIndex(where: { !$0.isPreview && $0.from < bar && $0.to > bar }) else { return }
            var tail = ranges[i]
            tail.from = bar
            tail.join = .continuous
            tail.cut = nil
            tail.inEdge = .none
            ranges[i].to = bar
            ranges[i].outEdge = .none
            ranges.insert(tail, at: i + 1)
        }
        if filteredIntroBars > 0 {
            split(at: startBar + filteredIntroBars)
            if let i = ranges.firstIndex(where: { !$0.isPreview && $0.from == startBar }) {
                ranges[i].inEdge = ClipTransition(type: .none, duration: Double(filteredIntroBars * 4), filter: .lowPassSweep)
                decisions.append(AutoDecision(
                    kind: .fewerEditsExplained, songTitle: song.title,
                    detail: "Opened \(song.title) with a \(filteredIntroBars)-bar low-pass filter intro."
                ))
            }
        }
        if let bd = breakdown {
            split(at: bd.startBar)
            split(at: bd.endBar)
            if let i = ranges.firstIndex(where: { $0.from == bd.startBar && $0.to == bd.endBar }) {
                ranges[i].inEdge = ClipTransition(type: .none, duration: Double(bd.barCount * 4), filter: .lowPassSweep)
                decisions.append(AutoDecision(
                    kind: .fewerEditsExplained, songTitle: song.title,
                    detail: "Opened \(song.title)'s breakdown with a low-pass sweep across \(bd.barCount) bars."
                ))
            } else {
                breakdown = nil
            }
        }
        if let b = buildBar {
            split(at: b - 4)
            split(at: b)
            if let i = ranges.firstIndex(where: { $0.from == b - 4 && $0.to == b }),
               i + 1 < ranges.count, ranges[i + 1].from == b {
                let sweep = ClipTransition(type: .none, duration: 16, filter: .highPassSweep)
                if repeatBuild {
                    // Clean first pass, then the SAME phrase again draining
                    // its low end — the drop lands one phrase later.
                    ranges.insert(Range(from: b - 4, to: b, join: .preRollCrossfade(xf), outEdge: sweep,
                                        cut: AutoCutRecord(timelineAt: 0, sourceFrom: t(b), sourceTo: t(b - 4),
                                                           reason: .extendedBuild, confidence: confidence,
                                                           expectedEnergyDeltaDB: 0,
                                                           masking: .equalPowerCrossfade(seconds: xf))),
                                  at: i + 1)
                    ranges[i + 2].isDrop = true
                    decisions.append(AutoDecision(kind: .extendedBuild, songTitle: song.title, detail: "4 → 8 bars"))
                } else {
                    ranges[i].outEdge = sweep
                    ranges[i + 1].isDrop = true
                    decisions.append(AutoDecision(kind: .addedRiserIntoDrop, songTitle: song.title,
                                                  detail: "high-pass build + riser"))
                }
            } else {
                buildBar = nil
            }
        }
        ranges.removeAll { $0.to <= $0.from }

        var spans = ranges.map { r in
            Span(sourceStart: t(r.from), sourceEnd: t(r.to), join: r.join,
                 inEdge: r.inEdge, outEdge: r.outEdge, cut: r.cut)
        }
        let dropIndices = ranges.indices.filter { ranges[$0].isDrop }

        // Ending: echo-out when we end before the song does.
        let endsEarly = endBar < n - 1 || trimmedForBudget
        if endsEarly, !spans.isEmpty {
            spans[spans.count - 1].outEdge = ClipTransition(type: .echoOut, duration: 4)
            decisions.append(AutoDecision(kind: .echoOutEnding, songTitle: song.title, detail: "on the last downbeat"))
        }

        let assembled = assemble(spans, song: song, rate: 1, volume: volume, timelineStart: 0, slot: 0)
        var placements = assembled.placements
        for i in placements.indices { placements[i].slotIndex = i }

        // ── SFX: sparse, only where an arrangement change needs support ──
        var lane = SFXLane()
        var payoffTimes: [Double] = []
        for idx in dropIndices where idx < placements.count {
            let drop = placements[idx].timelineStart
            payoffTimes.append(drop)
            lane.add("riser", endingAt: drop, purpose: "riser into the drop")
            lane.add("impact", at: drop, purpose: "impact on the drop downbeat")
        }
        if preview != nil, placements.count > 1 {
            let join = placements[1].timelineStart + placements[1].overlapsPreviousSeconds
            payoffTimes.append(join)
            lane.add("reverseCymbal", endingAt: join, purpose: "reverse cymbal out of the hook preview")
        }

        // ── Zone accounting + audit ──
        let zones = [preview != nil || startBar > first || filteredIntroBars > 0, !cuts.isEmpty, breakdown != nil,
                     buildBar != nil, endsEarly].filter { $0 }.count
        if song.tier == .high, zones < 3 {
            decisions.append(AutoDecision(
                kind: .fewerEditsExplained, songTitle: song.title,
                detail: "Made \(zones) edit zone\(zones == 1 ? "" : "s"): the measured structure offered no other phrase-aligned edit with enough evidence (repeat match, energy lift, or low-energy intro/outro)."
            ))
        }
        if song.tier == .medium {
            decisions.append(AutoDecision(
                kind: .fewerEditsExplained, songTitle: song.title,
                detail: "Beat/phrase evidence was moderate, so \(song.title) stays continuous apart from filter automation and edge trims."
            ))
        }

        let usableStart = placements.first?.sourceStart ?? 0
        let usableEnd = placements.map(\.sourceEnd).max() ?? duration
        let total = placements.map(\.timelineEnd).max() ?? 0
        var plan = AutoRemixPlan(
            mode: .remix,
            targetBPM: st.bpm,
            targetDuration: total,
            anchorSongIDs: [song.id],
            selectedSections: [AutoSelectedSection(
                songID: song.id, sourceStart: usableStart, sourceEnd: usableEnd, phraseType: "song",
                barCount: Int((total / barSec).rounded()), hookScore: 1,
                energyScore: song.energy(startBar, endBar), vocalDensity: song.vocal(startBar, endBar),
                compatibilityRole: .dominant, confidence: song.analysis.analysisConfidence
            )],
            placements: placements,
            sfxEvents: lane.events.sorted { $0.timelineStart < $1.timelineStart },
            cutRecords: assembled.cuts,
            usableSourceRange: usableStart...usableEnd,
            intentionalGaps: [],
            handoffCount: 0,
            songLetters: [song.id: "A"],
            sequence: ["A"],
            sequenceTitles: [song.title],
            transitionsUsed: [],
            decisions: decisions,
            warnings: warnings,
            confidence: song.analysis.analysisConfidence,
            randomSeed: seed
        )
        plan.payoffTimes = payoffTimes
        plan.timelineDownbeats = timelineDownbeats(placements, contexts: [song.id: song])
        warnings.removeAll()
        return plan
    }

    /// Low confidence: the whole usable song, continuous. Edge silence is
    /// trimmed only from measurement; the end fades only if the budget
    /// forces it.
    private static func continuousRemix(
        _ song: SongContext, tuning: AutoTuning, seed: UInt64, decisions: [AutoDecision]
    ) -> AutoRemixPlan? {
        var decisions = decisions
        var warnings: [String] = []
        let duration = song.duration
        var usableStart = 0.0, usableEnd = duration
        if let s = song.signal, s.overallConfidence >= 0.4 {
            if s.leadingSilenceSeconds > 0.35 {
                usableStart = max(0, s.leadingSilenceSeconds - 0.15)
                decisions.append(AutoDecision(kind: .skippedIntro, songTitle: song.title,
                                              detail: String(format: "%.1fs of leading silence", s.leadingSilenceSeconds)))
            }
            if s.trailingSilenceSeconds > 0.35 {
                usableEnd = min(duration, duration - s.trailingSilenceSeconds + 0.15)
                decisions.append(AutoDecision(kind: .shortenedLowEnergySection, songTitle: song.title,
                                              detail: String(format: "trailing silence (%.1fs)", s.trailingSilenceSeconds)))
            }
        }
        if usableEnd - usableStart < max(tuning.minSegmentSeconds, 8) {
            usableStart = 0; usableEnd = duration
            warnings.append("Edge trimming would have removed too much material; kept the full source.")
        }
        var trimmed = false
        if usableEnd - usableStart > tuning.maxTimelineSeconds {
            usableEnd = usableStart + tuning.maxTimelineSeconds
            trimmed = true
            decisions.append(AutoDecision(kind: .shortenedForMaterial, songTitle: song.title, detail: "ending to fit the timeline"))
        }
        decisions.append(AutoDecision(kind: .usedLowConfidenceFallback, songTitle: song.title, detail: nil))
        let fadeOut: ClipTransition = trimmed
            ? ClipTransition(type: .fadeOut, duration: 8, curve: AutoTransitionEnvelope.equalPowerCurveName)
            : .none
        let bpm = song.envelopeBPM(rate: 1)
        let placement = AutoClipPlacement(
            songID: song.id, sourceStart: usableStart, timelineStart: 0,
            timelineDuration: usableEnd - usableStart, tempoRatio: 1,
            volume: AutoGainPolicy.preservationSongVolume, fadeIn: .none, fadeOut: fadeOut,
            effects: ClipEffectSettings(), role: .dominant, slotIndex: 0, envelopeBPM: bpm
        )
        return AutoRemixPlan(
            mode: .remix, targetBPM: song.bpm, targetDuration: usableEnd - usableStart,
            anchorSongIDs: [song.id],
            selectedSections: [AutoSelectedSection(
                songID: song.id, sourceStart: usableStart, sourceEnd: usableEnd, phraseType: "song",
                barCount: Int(((usableEnd - usableStart) / song.analysis.barSeconds).rounded()), hookScore: 1,
                energyScore: song.analysis.meanEnergy(from: usableStart, to: usableEnd),
                vocalDensity: song.analysis.meanVocalDensity(from: usableStart, to: usableEnd),
                compatibilityRole: .dominant, confidence: song.analysis.analysisConfidence
            )],
            placements: [placement], sfxEvents: [], cutRecords: [],
            usableSourceRange: usableStart...usableEnd, intentionalGaps: [], handoffCount: 0,
            songLetters: [song.id: "A"], sequence: ["A"], sequenceTitles: [song.title],
            transitionsUsed: [], decisions: decisions, warnings: warnings,
            confidence: song.analysis.analysisConfidence, randomSeed: seed
        )
    }

    private static func tierName(_ t: Tier) -> String {
        switch t { case .low: "low"; case .medium: "medium"; case .high: "high" }
    }

    // MARK: - Mashup

    /// One run of one song: lead-in phrase → payoff (hook/drop) → tail.
    struct Appearance {
        var song: Int                 // index into ordered contexts
        var entryBar: Int
        var payoffBar: Int
        var payoffEndBar: Int
        var tailBars = 0              // bars played past the payoff (blend / build / ending)
        var startsAtPayoff = false
        /// The outgoing blend overlaps the payoff's LAST bars instead of
        /// running into quieter post-payoff material.
        var blendInsidePayoff = false
    }

    private static func mashupPlan(_ songsIn: [SongContext], tuning: AutoTuning, seed: UInt64) -> AutoRemixPlan? {
        var decisions: [AutoDecision] = []
        var warnings: [String] = []

        // ── Anchor + order: anchor first, then greedy by compatibility ──
        let anchorIdx = songsIn.indices.max { a, b in
            anchorScore(songsIn[a]) < anchorScore(songsIn[b])
        } ?? 0
        var order = [anchorIdx]
        var remaining = songsIn.indices.filter { $0 != anchorIdx }
        while !remaining.isEmpty {
            let last = songsIn[order.last!]
            let next = remaining.max { a, b in
                pairScore(last, songsIn[a], tuning) < pairScore(last, songsIn[b], tuning)
            }!
            order.append(next)
            remaining.removeAll { $0 == next }
        }
        var songs = order.map { songsIn[$0] }
        decisions.append(AutoDecision(kind: .selectedAnchor, songTitle: songs[0].title, detail: "groove / beat confidence"))

        // Budget guard for large projects: drop the least confident song
        // when not every song can get a recognizable phrase.
        let targetBPM = AutoTempo.targetBPM(profiles: songs.map(\.profile), anchorID: songs[0].id, maxStretch: tuning.maxStretch)
        let targetBar = 240.0 / max(targetBPM, 40)
        let budgetBars = Int(tuning.maxTimelineSeconds / targetBar)
        while songs.count > 2, budgetBars / songs.count < 14 {
            guard let weakest = songs.dropFirst().min(by: { $0.analysis.analysisConfidence < $1.analysis.analysisConfidence }) else { break }
            songs.removeAll { $0.id == weakest.id }
            decisions.append(AutoDecision(kind: .excludedLowConfidenceSong, songTitle: weakest.title,
                                          detail: "not enough timeline for a recognizable phrase from every song"))
            warnings.append("Excluded \(weakest.title): not enough timeline for a recognizable phrase from every song, and its analysis confidence was lowest.")
        }

        // ── Tempo fits + loudness matching ──
        let fits = songs.map { AutoTempo.fit(songBPM: $0.bpm, targetBPM: targetBPM, maxStretch: tuning.maxStretch) }
        for (i, s) in songs.enumerated() {
            let fit = fits[i]
            if abs(fit.ratio - 1) > 0.0001, !fit.halfOrDoubleTime {
                let pct = (fit.ratio - 1) * 100
                decisions.append(AutoDecision(kind: .beatmatchedSong, songTitle: s.title,
                                              detail: String(format: "%+.1f%% to %.1f BPM", pct, targetBPM)))
            } else if !fit.gridAligned {
                warnings.append("\(s.title) is outside the safe ±\(Int(tuning.maxStretch * 100))% stretch window; Auto kept its native tempo and used echo-slam handoffs for it.")
            }
        }
        let reference = songs.compactMap { $0.signal?.bodyLoudnessDB }.filter { $0 > -80 }.min() ?? -12
        let gains = songs.map { $0.loudnessGain(referenceDB: reference) }
        for (i, g) in gains.enumerated() where g < 0.97 {
            decisions.append(AutoDecision(kind: .loudnessMatched, songTitle: songs[i].title,
                                          detail: String(format: "%.1f dB", 20 * log10(g))))
        }

        // ── Appearances: even airtime, round-robin ──
        let n = songs.count
        let perSong = n == 2 ? 2 : (budgetBars / n >= 40 ? 2 : 1)
        var sequence: [Int] = []
        for _ in 0..<perSong { sequence += Array(0..<n) }
        if perSong == 1, n >= 3, budgetBars - n * 20 >= 16 { sequence.append(0) }   // anchor closes
        // Let each appearance breathe: the payoff runs its measured length
        // (8 or 16 bars) and the rest of the airtime goes to the lead-in.
        // Airtime is budgeted in SECONDS: a song kept at its native tempo
        // has longer or shorter bars than the target grid.
        let appearanceSeconds = tuning.maxTimelineSeconds / Double(max(sequence.count, 1))
        func airtimeBars(_ si: Int) -> Int {
            let rate = fits[si].gridAligned ? fits[si].ratio : 1
            let bar = songs[si].structure.map { $0.barSeconds / rate } ?? targetBar
            return max(12, Int(appearanceSeconds / bar))
        }

        var used: [Int: [Int]] = [:]   // song → payoff bars used
        var apps: [Appearance] = []
        for (k, si) in sequence.enumerated() {
            let s = songs[si]
            let isLastForSong = !sequence[(k + 1)...].contains(si)
            let bars = airtimeBars(si)
            let previous = apps.last.map { (songs[$0.song], $0.payoffEndBar) }
            guard let a = appearance(for: s, index: si, used: used[si] ?? [], preferLate: isLastForSong && k > 0,
                                     payoffBars: bars >= 22 ? 16 : 8, airtimeBars: bars, isFirst: k == 0,
                                     previous: previous)
            else {
                warnings.append("No usable hook found in \(s.title); skipped that appearance.")
                decisions.append(AutoDecision(kind: .skippedWeakSection, songTitle: s.title, detail: "hook"))
                continue
            }
            used[si, default: []].append(a.payoffBar)
            apps.append(a)
        }
        guard apps.count >= 2 else { return nil }

        // ── Handoff recipes ──
        var recipes: [AutoTransitionRecipe] = []
        for k in 1..<apps.count {
            let x = songs[apps[k - 1].song], y = songs[apps[k].song]
            let fx = fits[apps[k - 1].song], fy = fits[apps[k].song]
            let lockable = fx.gridAligned && fy.gridAligned && !fx.halfOrDoubleTime && !fy.halfOrDoubleTime
                && x.tier > .low && y.tier > .low && x.structure != nil && y.structure != nil
            let tempoFits = fx.gridAligned && fy.gridAligned && !fx.halfOrDoubleTime && !fy.halfOrDoubleTime
            if !lockable {
                // Low confidence: no filter tricks — a clean, short
                // equal-power overlap when tempos fit, else an echo slam.
                recipes.append(tempoFits ? .cleanCrossfade : .echoSlam)
            } else if k == apps.count - 1 || k % 3 == 0 {
                recipes.append(.filterBuildDrop)     // tension into the final peak / variety
            } else {
                recipes.append(.beatmatchedBlend)
            }
        }

        // Tail lengths (bars played past each payoff) and entry shapes.
        for k in 0..<apps.count {
            let s = songs[apps[k].song]
            let available = max(0, (k == apps.count - 1 ? s.musicEndBar : s.loudEndBar) - apps[k].payoffEndBar)
            if k == apps.count - 1 {
                // Ending: keep up to 8 bars of outro, else 2 bars + echo-out.
                let outro = s.structure?.sections.last { $0.label == .outro && $0.startBar >= apps[k].payoffEndBar - 1 }
                apps[k].tailBars = min(available, outro != nil ? min(8, outro!.barCount) : 2)
                continue
            }
            let y = songs[apps[k + 1].song]
            switch recipes[k] {
            case .beatmatchedBlend:
                var blend = 8
                let clash = s.vocal(apps[k].payoffEndBar, apps[k].payoffEndBar + 8)
                    + y.vocal(apps[k + 1].entryBar, apps[k + 1].entryBar + 8)
                if clash > 1.0 { blend = 4 }
                if clash > 1.3 { blend = 2 }
                let key = AutoKey.bestCorrection(AutoKey.parse(s.analysis.key), AutoKey.parse(y.analysis.key), maxShift: 0).score
                if key < 0.5 { blend = min(blend, 4) }
                let payoffE = s.energy(apps[k].payoffEndBar - blend, apps[k].payoffEndBar)
                let tailE = s.energy(apps[k].payoffEndBar, apps[k].payoffEndBar + blend)
                if available < blend || tailE < payoffE - 0.35 {
                    // Mix out over the chorus's last bars rather than into a
                    // breakdown / fade the listener would hear as a hole.
                    apps[k].blendInsidePayoff = true
                    blend = min(blend, apps[k].payoffEndBar - apps[k].payoffBar - 4)
                } else {
                    blend = min(blend, available)
                }
                blend = min(blend, apps[k + 1].payoffBar - apps[k + 1].entryBar)
                if blend < 2 {
                    recipes[k] = available >= 2 ? .filterBuildDrop : .echoSlam
                    apps[k].blendInsidePayoff = false
                    apps[k].tailBars = available >= 2 ? min(4, available) : 0
                    apps[k + 1].startsAtPayoff = available >= 2
                } else {
                    apps[k].tailBars = blend
                }
            case .filterBuildDrop:
                apps[k].tailBars = min(4, available)
                apps[k + 1].startsAtPayoff = true
                if apps[k].tailBars < 2 {
                    recipes[k] = .echoSlam
                    apps[k].tailBars = 0
                    apps[k + 1].startsAtPayoff = false
                }
            case .cleanCrossfade:
                apps[k].tailBars = min(2, available)
                if apps[k].tailBars < 1 { recipes[k] = .echoSlam; apps[k].tailBars = 0 }
            default:
                // Echo slam: the outgoing throws its last beats into an echo;
                // the incoming lands on its DROP when the outgoing ends hot
                // (energy continuity), else on its lead-in downbeat.
                apps[k].tailBars = 0
                let outE = s.energy(apps[k].payoffEndBar - 4, apps[k].payoffEndBar)
                if outE >= 0.7, y.structure != nil {
                    apps[k + 1].startsAtPayoff = true
                }
            }
        }

        // ── Assemble on the timeline ──
        var placements: [AutoClipPlacement] = []
        var lane = SFXLane()
        var payoffTimes: [Double] = []
        var letters: [UUID: String] = [:]
        for (i, s) in songs.enumerated() { letters[s.id] = String(UnicodeScalar(UInt8(65 + min(i, 25)))) }
        var seqLetters: [String] = []
        var seqTitles: [String] = []
        var transitionsUsed: [AutoTransitionRecipe] = []

        var cursor = 0.0
        for (k, app) in apps.enumerated() {
            let s = songs[app.song]
            let rate = fits[app.song].gridAligned ? fits[app.song].ratio : 1
            let bpm = s.envelopeBPM(rate: rate)
            let volume = AutoGainPolicy.preservationSongVolume * gains[app.song]
            let entry = app.startsAtPayoff ? app.payoffBar : app.entryBar
            let xf = 0.04
            var src0 = s.barTime(entry)
            var t0 = cursor
            var fadeIn: ClipTransition = .none
            let incoming: AutoTransitionRecipe? = k > 0 ? recipes[k - 1] : nil
            switch incoming {
            case .beatmatchedBlend?:
                let blendBars = apps[k - 1].tailBars
                let blendSec = Double(blendBars) * targetBar
                fadeIn = ClipTransition(
                    type: .crossfade, duration: AutoTransitionEnvelope.beats(forSeconds: blendSec, timelineBPM: bpm),
                    curve: AutoTransitionEnvelope.equalPowerCurveName, filter: .bassSwap
                )
            case .cleanCrossfade?:
                let xfSec = Double(apps[k - 1].tailBars) * targetBar
                fadeIn = ClipTransition(
                    type: .crossfade, duration: AutoTransitionEnvelope.beats(forSeconds: xfSec, timelineBPM: bpm),
                    curve: AutoTransitionEnvelope.equalPowerCurveName
                )
            case .filterBuildDrop?, .echoSlam?:
                // Land ON the downbeat: tiny equal-power pre-roll so the
                // first transient hits at full level.
                src0 -= xf * rate
                t0 -= xf
                fadeIn = ClipTransition(
                    type: .crossfade, duration: AutoTransitionEnvelope.beats(forSeconds: xf, timelineBPM: bpm),
                    curve: AutoTransitionEnvelope.equalPowerCurveName
                )
            default:
                break
            }
            let endBar = min(s.barCount, app.payoffEndBar + (app.blendInsidePayoff ? 0 : app.tailBars))
            let srcEnd = s.barTime(endBar)
            let duration = (srcEnd - src0) / rate

            var fadeOut: ClipTransition = .none
            let outgoing: AutoTransitionRecipe? = k + 1 < apps.count ? recipes[k] : nil
            switch outgoing {
            case .beatmatchedBlend?:
                let blendSec = Double(app.tailBars) * targetBar
                fadeOut = ClipTransition(
                    type: .crossfade, duration: AutoTransitionEnvelope.beats(forSeconds: blendSec, timelineBPM: bpm),
                    curve: AutoTransitionEnvelope.equalPowerCurveName, filter: .bassSwap
                )
            case .filterBuildDrop?:
                let buildSec = Double(app.tailBars) * targetBar
                fadeOut = ClipTransition(
                    type: .none, duration: AutoTransitionEnvelope.beats(forSeconds: buildSec, timelineBPM: bpm),
                    filter: .highPassSweep
                )
            case .echoSlam?:
                fadeOut = ClipTransition(type: .echoOut, duration: 2)
            case .cleanCrossfade?:
                let xfSec = Double(app.tailBars) * targetBar
                fadeOut = ClipTransition(
                    type: .crossfade, duration: AutoTransitionEnvelope.beats(forSeconds: xfSec, timelineBPM: bpm),
                    curve: AutoTransitionEnvelope.equalPowerCurveName
                )
            default:
                fadeOut = ClipTransition(type: .echoOut, duration: 4)   // ending
            }

            placements.append(AutoClipPlacement(
                songID: s.id, sourceStart: src0, timelineStart: t0, timelineDuration: duration,
                tempoRatio: rate, volume: volume, fadeIn: fadeIn, fadeOut: fadeOut,
                effects: ClipEffectSettings(), role: .dominant, slotIndex: k, envelopeBPM: bpm
            ))
            seqLetters.append(letters[s.id] ?? "?")
            seqTitles.append(s.title)

            let payoffT = t0 + (s.barTime(app.payoffBar) - src0) / rate
            payoffTimes.append(payoffT)
            if let incoming { transitionsUsed.append(incoming) }

            // SFX coordinated with the handoff INTO this appearance.
            switch incoming {
            case .filterBuildDrop?:
                lane.add("riser", endingAt: payoffT, purpose: "riser into \(s.title)'s drop")
                lane.add("impact", at: payoffT, purpose: "impact on the drop downbeat")
            case .echoSlam?:
                if app.startsAtPayoff {
                    lane.add("impact", at: payoffT, purpose: "impact under the echo slam")
                }
            case .beatmatchedBlend?:
                if s.energy(app.payoffBar, app.payoffBar + 4) - s.energy(app.payoffBar - 4, app.payoffBar) >= 0.25 {
                    lane.add("reverseCymbal", endingAt: payoffT, purpose: "reverse cymbal into \(s.title)'s hook")
                }
                decisions.append(AutoDecision(kind: .bassSwapBlend, songTitle: s.title,
                                              detail: "\(apps[k - 1].tailBars) bars"))
            default:
                break
            }

            // Where the next appearance begins on the timeline.
            let payoffEndT = t0 + (s.barTime(app.payoffEndBar) - src0) / rate
            switch outgoing {
            case .beatmatchedBlend? where app.blendInsidePayoff:
                cursor = payoffEndT - Double(app.tailBars) * targetBar
            case .beatmatchedBlend?, .echoSlam?, .cleanCrossfade?:
                cursor = payoffEndT
            case .filterBuildDrop?:
                cursor = t0 + duration
            default:
                cursor = t0 + duration
            }
        }

        // Round the story: the final appearance's payoff is the peak.
        if let last = apps.last {
            let s = songs[last.song]
            decisions.append(AutoDecision(
                kind: (used[last.song]?.count ?? 0) > 1 ? .returnedToHook : .savedStrongestForPeak,
                songTitle: s.title, detail: "chorus"
            ))
        }

        var handoffs = 0
        for k in 1..<apps.count where apps[k].song != apps[k - 1].song { handoffs += 1 }
        if n == 2, handoffs < 3 {
            decisions.append(AutoDecision(kind: .duoAlternationFallback, songTitle: nil,
                                          detail: "Could not reach A → B → A → B without incomplete sections — kept the cleanest valid alternation."))
            warnings.append("Fewer than three song handoffs — duration or analysis confidence prevented a full A → B → A → B without incomplete sections.")
        }
        for s in songs where s.tier == .low {
            decisions.append(AutoDecision(kind: .usedLowConfidenceFallback, songTitle: s.title, detail: nil))
        }

        let contexts = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        let sections = zip(apps, placements).map { app, p -> AutoSelectedSection in
            let s = songs[app.song]
            return AutoSelectedSection(
                songID: s.id, sourceStart: p.sourceStart, sourceEnd: p.sourceEnd,
                phraseType: "chorus", barCount: app.payoffEndBar - app.payoffBar,
                hookScore: 0.9, energyScore: s.energy(app.payoffBar, app.payoffEndBar),
                vocalDensity: s.vocal(app.payoffBar, app.payoffEndBar), compatibilityRole: .dominant,
                confidence: s.analysis.analysisConfidence
            )
        }
        var plan = AutoRemixPlan(
            mode: .mashup,
            targetBPM: targetBPM,
            targetDuration: placements.map(\.timelineEnd).max() ?? 0,
            anchorSongIDs: [songs[0].id],
            selectedSections: sections,
            placements: placements,
            sfxEvents: lane.events.sorted { $0.timelineStart < $1.timelineStart },
            intentionalGaps: [],
            handoffCount: handoffs,
            songLetters: letters,
            sequence: seqLetters,
            sequenceTitles: seqTitles,
            transitionsUsed: transitionsUsed,
            decisions: decisions,
            warnings: warnings,
            confidence: sections.map(\.confidence).reduce(0, +) / Double(max(sections.count, 1)),
            randomSeed: seed
        )
        plan.payoffTimes = payoffTimes
        plan.timelineDownbeats = timelineDownbeats(placements, contexts: contexts)
        return plan
    }

    /// Chooses lead-in + payoff bars for one appearance of `s`.
    private static func appearance(
        for s: SongContext, index: Int, used: [Int], preferLate: Bool,
        payoffBars: Int, airtimeBars: Int, isFirst: Bool,
        previous: (song: SongContext, tailBar: Int)?
    ) -> Appearance? {
        let n = s.loudEndBar
        let first = s.firstMusicBar
        var payoffs: [(start: Int, bars: Int)] = []
        if let st = s.structure {
            payoffs = st.sections(.chorus).filter { $0.barCount >= 4 }.map { ($0.startBar, $0.barCount) }
            if payoffs.isEmpty {
                // No repeated hook: the loudest phrase-aligned 8-bar windows.
                var windows: [(Int, Double)] = []
                var b = first
                while b + 8 <= n { if s.isPhraseStart(b) { windows.append((b, s.energy(b, b + 8))) }; b += 1 }
                payoffs = windows.sorted { $0.1 > $1.1 }.prefix(2).map { ($0.0, 8) }.sorted { $0.0 < $1.0 }
            }
        } else {
            // Heuristic catalog fallback (low confidence): best chorus candidate.
            if let c = s.profile.best([.chorus], tuning: .standard, used: []) {
                let bar = Int((c.startSeconds / s.analysis.barSeconds).rounded())
                payoffs = [(bar, c.barCount)]
            }
        }
        payoffs = payoffs.filter { $0.start > first + (isFirst ? 0 : 2) && $0.start + 4 <= n }
        guard !payoffs.isEmpty else { return nil }
        let fresh = payoffs.filter { p in !used.contains(p.start) }
        let pool = fresh.isEmpty ? payoffs : fresh
        let chosen = preferLate ? pool.last! : pool.first!
        let natural = chosen.bars >= 12 ? 16 : 8
        let payoffLen = min(min(natural, payoffBars), n - chosen.start)
        let entryBars = min(16, max(4, (airtimeBars - payoffLen - 4) / 4 * 4))
        var entry = max(first, chosen.start - entryBars)
        if isFirst, chosen.start - first <= 16 { entry = first }     // start from the top
        if let previous, s.structure != nil {
            // Energy continuity: enter on the lead-in phrase whose level
            // best matches what the outgoing song is playing at the handoff
            // (longer lead-ins preferred on ties — more of the song).
            let outE = previous.song.energy(previous.tailBar - 4, previous.tailBar + 4)
            let options = stride(from: max(4, entryBars), through: 4, by: -4).map { chosen.start - $0 }.filter { $0 >= first }
            if let best = options.min(by: { a, b in
                abs(s.energy(a, a + 4) - outE) - Double(chosen.start - a) * 0.004
                    < abs(s.energy(b, b + 4) - outE) - Double(chosen.start - b) * 0.004
            }) { entry = best }
        }
        while entry > first, !s.isPhraseStart(entry) { entry -= 1 }
        // Land where the music actually hits: a near-silent break bar at
        // the start of the payoff belongs to the build, not the drop.
        var landing = chosen.start
        if s.structure != nil, s.energy(landing, landing + 1) < 0.3, s.energy(landing + 1, landing + 3) > 0.6 {
            landing += 1
        }
        return Appearance(song: index, entryBar: entry, payoffBar: landing,
                          payoffEndBar: chosen.start + max(4, payoffLen))
    }

    /// Groove anchor: steady, drum- and bass-driven, energetic material —
    /// a clean pulse alone (a piano ballad) is not a dance-floor anchor.
    private static func anchorScore(_ s: SongContext) -> Double {
        let st = s.structure
        let bass = s.structure.map { $0.bars.map(\.bass).reduce(0, +) / Double(max($0.bars.count, 1)) } ?? 0.3
        return min(1, (st?.beatConfidence ?? 0.2) * 1.5) * 0.2 + (st?.tempoStability ?? 0) * 0.15
            + s.analysis.meanEnergy(from: 0, to: s.duration) * 0.2
            + (s.signal?.drumConfidence ?? 0.3) * 0.25 + bass * 0.2
    }

    private static func pairScore(_ a: SongContext, _ b: SongContext, _ tuning: AutoTuning) -> Double {
        let fit = AutoTempo.fit(songBPM: b.bpm, targetBPM: a.bpm, maxStretch: tuning.maxStretch)
        let tempo = fit.gridAligned ? (fit.halfOrDoubleTime ? 0.6 : 1.0 - abs(fit.ratio - 1) * 4) : 0
        let key = AutoKey.bestCorrection(AutoKey.parse(a.analysis.key), AutoKey.parse(b.analysis.key), maxShift: 0).score
        return tempo * 0.6 + key * 0.4
    }
}
