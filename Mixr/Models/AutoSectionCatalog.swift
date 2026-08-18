import Foundation

// MARK: - Candidate Section

/// One phrase-aligned edit candidate inside a song, with the component
/// scores that feed the tunable SectionValue heuristic.
struct AutoCandidateSection: Sendable {
    /// Selection roles the planner requests by name.
    enum Label: String, Sendable {
        case teaser      // 2–4 bars of the hook — instant recognizability
        case chorus      // full chorus / drop
        case groove      // verse / rhythmic identity
        case build       // pre-chorus riser bars
        case breakdown   // bridge / contrast
        case ending      // outro material for the final hit
        case intro       // kept only so "skipped intro" decisions are honest
    }

    let songID: UUID
    let label: Label
    /// Seconds into the source, snapped to a downbeat.
    let startSeconds: Double
    /// Bars at the song's NATIVE tempo.
    let barCount: Int
    /// Seconds per bar at the song's native tempo.
    let barSeconds: Double

    // Component scores, 0…1.
    let hook: Double
    let energy: Double
    let vocal: Double          // vocal density estimate over the range
    let clarity: Double        // vocal/melodic clarity
    let rhythm: Double
    let uniqueness: Double
    let transitionUse: Double
    let confidence: Double

    var endSeconds: Double { startSeconds + Double(barCount) * barSeconds }
    var durationSeconds: Double { Double(barCount) * barSeconds }

    /// Tunable SectionValue: 30% hook, 20% energy, 15% clarity,
    /// 15% rhythm, 10% uniqueness, 10% transition usefulness.
    func value(_ t: AutoTuning) -> Double {
        hook * t.hookWeight
            + energy * t.energyWeight
            + clarity * t.clarityWeight
            + rhythm * t.rhythmWeight
            + uniqueness * t.uniquenessWeight
            + transitionUse * t.transitionWeight
    }
}

// MARK: - Song Profile

/// Everything the planner knows about one song: analysis, scored
/// candidates, and role affinities.
struct AutoSongProfile: Sendable {
    let songID: UUID
    let title: String
    let analysis: SongAnalysis
    let candidates: [AutoCandidateSection]
    /// Fit as the rhythmic/structural anchor.
    let anchorScore: Double
    /// Fit as the vocal/hook feature.
    let featureScore: Double
    /// Offline Demucs sidecars when present (empty → full mix).
    var stems: AutoStemSet = .empty
    /// Kick/drum energy measured from the drums stem (nil if unread).
    /// Pulse uses `max(analysis.drumStrength, stemDrumStrength)` so a quiet
    /// Demucs file cannot invent a second kick on a kit the full mix already
    /// measured as slamming. Bed/hook roles keep full-mix `drumStrength`.
    var stemDrumStrength: Double? = nil

    var lowConfidence: Bool { analysis.analysisConfidence < AutoTuning.standard.lowConfidenceThreshold }

    /// One-kick pulse input: never weaker than the full-mix drum reading.
    var pulseDrumStrength: Double {
        max(analysis.drumStrength, stemDrumStrength ?? 0)
    }

    /// Best unused candidate for a label, by SectionValue. `used` ranges
    /// are (start, end) source intervals already placed; overlap > 50%
    /// counts as reuse and is deprioritized (never forbidden — returns
    /// can deliberately reuse a hook with a different treatment).
    func best(
        _ labels: [AutoCandidateSection.Label],
        tuning: AutoTuning,
        used: [(Double, Double)],
        allowReuse: Bool = true
    ) -> AutoCandidateSection? {
        let pool = candidates.filter { labels.contains($0.label) }
        guard !pool.isEmpty else { return nil }

        func overlapsUsed(_ c: AutoCandidateSection) -> Bool {
            used.contains { range in
                let overlap = min(c.endSeconds, range.1) - max(c.startSeconds, range.0)
                return overlap > c.durationSeconds * 0.5
            }
        }

        if let fresh = pool.filter({ !overlapsUsed($0) }).max(by: { $0.value(tuning) < $1.value(tuning) }) {
            return fresh
        }
        guard allowReuse else { return nil }
        return pool.max { $0.value(tuning) < $1.value(tuning) }
    }
}

// MARK: - Catalog Builder

enum AutoSectionCatalog {

    /// Builds the scored candidate catalog for one song track.
    static func profile(
        track: MixrTrack,
        tuning: AutoTuning = .standard,
        signal: SongSignalFeatures? = nil
    ) -> AutoSongProfile {
        let stems = AutoStemResolver.resolve(track: track, tuning: tuning)
        let enrichedSignal = stems.vocals.map { vocalsURL in
            AutoStemVocalCurve.merge(
                into: signal,
                vocalsURL: vocalsURL,
                durationHint: track.durationSeconds,
                bpmHint: track.bpm.map(Double.init)
            )
        } ?? signal
        let analysis = SongAnalyzer.analyze(track: track, signal: enrichedSignal)
        let stemDrumStrength = AutoStemKickEnergy.drumStrength(from: stems.drums)
        // Do not overwrite analysis.drumStrength — bed/hook scoring and the
        // Britney title/groove lock must keep full-mix curves. Pulse reads
        // stemDrumStrength separately.
        let bar = analysis.barSeconds
        let duration = analysis.durationSeconds
        let confidence = analysis.analysisConfidence

        var candidates: [AutoCandidateSection] = []

        /// Snaps a source time down to the nearest downbeat so every
        /// candidate starts on beat one.
        func snapDown(_ t: Double) -> Double {
            analysis.downbeats.last { $0 <= t + 0.01 } ?? 0
        }

        /// Emits a candidate when it fits inside the song.
        func add(
            _ label: AutoCandidateSection.Label,
            start rawStart: Double,
            bars: Int,
            hook: Double,
            uniqueness: Double,
            transitionUse: Double
        ) {
            let start = max(0, snapDown(rawStart))
            let end = start + Double(bars) * bar
            guard bars >= 2, end <= duration + 0.25 else { return }
            let energy = analysis.meanEnergy(from: start, to: end)
            let vocal = analysis.meanVocalDensity(from: start, to: end)
            candidates.append(
                AutoCandidateSection(
                    songID: track.id,
                    label: label,
                    startSeconds: start,
                    barCount: bars,
                    barSeconds: bar,
                    hook: hook,
                    energy: energy,
                    vocal: vocal,
                    // Clarity: vocals read clearly when present but not buried
                    // in a maximal-energy wall.
                    clarity: min(1, vocal * 0.7 + (1 - abs(energy - 0.75)) * 0.3),
                    rhythm: analysis.drumStrength,
                    uniqueness: uniqueness,
                    transitionUse: transitionUse,
                    confidence: confidence
                )
            )
        }

        // ── Choruses / drops: the payoff material ──
        for (i, chorus) in analysis.chorusOrDropCandidates.enumerated() {
            let localEnergy = analysis.meanEnergy(from: chorus.startSeconds, to: chorus.endSeconds)
            let localVocal = analysis.meanVocalDensity(from: chorus.startSeconds, to: chorus.endSeconds)
            let rise: Double
            if let signal = analysis.signal, AutoChorusIsland.hasUsableEnergyShape(signal) {
                let after = AutoChorusIsland.mean(
                    signal.energyCurve, hop: signal.hopSeconds,
                    from: chorus.startSeconds, to: chorus.startSeconds + 4
                )
                let before = AutoChorusIsland.mean(
                    signal.energyCurve, hop: signal.hopSeconds,
                    from: chorus.startSeconds - 4, to: chorus.startSeconds
                )
                rise = max(0, after - before)
            } else {
                rise = 0
            }
            // Measured lift outranks catalog order (`.first` used to win at 0.92).
            let hookScore = min(1, 0.48 + localEnergy * 0.22 + localVocal * 0.12 + rise * 0.28 - Double(i) * 0.02)
            add(.chorus, start: chorus.startSeconds, bars: 8, hook: hookScore, uniqueness: 0.85, transitionUse: 0.55)
            if chorus.durationSeconds >= bar * 15 {
                add(.chorus, start: chorus.startSeconds, bars: 16, hook: hookScore, uniqueness: 0.8, transitionUse: 0.45)
            }
            // Teaser: the first 4 bars of the hook — instant recognizability.
            add(.teaser, start: chorus.startSeconds, bars: 4, hook: min(1, hookScore + 0.04), uniqueness: 0.7, transitionUse: 0.9)
        }

        // ── Pre-chorus builds ──
        for build in analysis.buildCandidates {
            add(.build, start: build.startSeconds, bars: 4, hook: 0.45, uniqueness: 0.6, transitionUse: 0.95)
        }

        // ── Verses: groove / identity material ──
        for (i, verse) in analysis.verseCandidates.enumerated() {
            // Second verses are the classic skip: same information, less lift.
            let uniqueness = i == 0 ? 0.75 : 0.4
            add(.groove, start: verse.startSeconds, bars: 8, hook: 0.5, uniqueness: uniqueness, transitionUse: 0.7)
            if verse.durationSeconds >= bar * 5 {
                add(.groove, start: verse.startSeconds, bars: 4, hook: 0.48, uniqueness: uniqueness, transitionUse: 0.8)
            }
        }

        // ── Bridge → breakdown / contrast ──
        if let bridge = analysis.bridgeCandidate {
            add(.breakdown, start: bridge.startSeconds, bars: 8, hook: 0.42, uniqueness: 0.8, transitionUse: 0.85)
            add(.breakdown, start: bridge.startSeconds, bars: 4, hook: 0.42, uniqueness: 0.8, transitionUse: 0.9)
        }

        // ── Outro → ending hits ──
        if let outro = analysis.outroCandidate {
            add(.ending, start: outro.startSeconds, bars: 4, hook: 0.3, uniqueness: 0.5, transitionUse: 0.85)
        }

        // ── Intro: low-value on purpose (kept for honest decision notes) ──
        if let intro = analysis.introCandidate, intro.durationSeconds >= bar * 4 {
            add(.intro, start: intro.startSeconds, bars: 4, hook: 0.15, uniqueness: 0.4, transitionUse: 0.6)
        }

        // ── Role affinities ──
        let meanEnergy = analysis.meanEnergy(from: 0, to: duration)
        let meanVocal = analysis.meanVocalDensity(from: 0, to: duration)
        let bestHook = candidates.map(\.hook).max() ?? 0.5
        let bpmTrust = analysis.bpmIsReal ? (analysis.bpmConfidence ?? 1.0) : 0.2
        let anchorScore = meanEnergy * 0.4 + analysis.drumStrength * 0.3 + bpmTrust * 0.3
        let featureScore = bestHook * 0.5 + meanVocal * 0.3 + (analysis.key != nil ? 0.2 : 0.06)

        return AutoSongProfile(
            songID: track.id,
            title: track.title,
            analysis: analysis,
            candidates: candidates,
            anchorScore: anchorScore,
            featureScore: featureScore,
            stems: stems,
            stemDrumStrength: stemDrumStrength
        )
    }
}
