import Foundation

// MARK: - Title-chorus entrance
//
// Heuristic `chorusOrDropCandidates.first` is a duration-fraction snap
// (often ~28% → the phrase *before* the title chorus). Real crate paths:
//   • time-first → prechorus @40.4s (03370e8; cuts “Oops”)
//   • global energy floor from verse 2 @65.7s → skips title @46s (591bef3)
//
// First title chorus: cap the search window before verse 2, compute the
// energy floor from that window only, boost vocal/title-token onset, and
// within a lift cluster pick the **first title downbeat** (~46s), not
// prechorus (~40s) or chorus tail (~50.5s).

nonisolated enum AutoChorusIsland {

    struct Entrance: Sendable {
        var startSeconds: Double
        var score: Double
        var rise: Double
        var energyAfter: Double
        var vocalAfter: Double
        var titleBoost: Double
    }

    /// True when the energy curve actually varies — flat crate stubs cannot
    /// relocate a chorus, so callers keep the phrase-fraction fallback.
    static func hasUsableEnergyShape(_ signal: SongSignalFeatures) -> Bool {
        guard signal.energyCurve.count >= 8 else { return false }
        let mean = signal.energyCurve.reduce(0, +) / Double(signal.energyCurve.count)
        var varSum = 0.0
        for v in signal.energyCurve {
            let d = v - mean
            varSum += d * d
        }
        return varSum / Double(signal.energyCurve.count) >= 0.004
    }

    /// First **title** chorus entrance — isolated-vocal onset of a title/hook
    /// line after the prechorus, not verse 2. When a vocal stem is present,
    /// that onset wins over full-mix energy that peaks on a chorus tail.
    static func firstTitleEntrance(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double? = nil,
        title: String? = nil
    ) -> Entrance? {
        guard hasUsableEnergyShape(signal), barSeconds > 0.05, duration > barSeconds * 16 else {
            return nil
        }
        let phrase = max(barSeconds * 4, phraseSeconds ?? barSeconds * 8)
        let lo = max(barSeconds * 8, min(introEnd, barSeconds * 16) * 0.35)
        let globalHi = min(duration * 0.42, duration - barSeconds * 8)
        let hi = firstTitleWindowHi(
            introEnd: introEnd,
            phraseSeconds: phrase,
            barSeconds: barSeconds,
            duration: duration,
            globalHi: globalHi
        )
        guard hi > lo + barSeconds else { return nil }

        if let hook = titleHookEntrance(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phrase,
            title: title
        ) {
            return hook
        }

        if let stem = stemTitleOnsetEntrance(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            introEnd: introEnd,
            phraseSeconds: phrase,
            title: title,
            lo: lo,
            hi: hi
        ) {
            return stem
        }

        let sampled = sampleGrid(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            lo: lo,
            hi: hi,
            introEnd: introEnd,
            phraseSeconds: phrase,
            title: title
        )
        guard !sampled.isEmpty else { return nil }

        // Floor from THIS window only — never let verse-2 energy @65s exclude ~46s.
        let peakEnergy = sampled.map(\.energyAfter).max() ?? 0
        let titleEnergyFloor = max(0.55, peakEnergy * 0.68)

        let qualifying = sampled
            .filter { qualifiesAsTitleEntrance($0, titleEnergyFloor: titleEnergyFloor) }
            .sorted { $0.startSeconds < $1.startSeconds }

        return clusterPeaks(
            qualifying,
            phraseSeconds: phrase,
            barSeconds: barSeconds,
            titleOnset: true
        ).first
    }

    /// Bounce-visible dump: chorus candidates, measured entrance, catalog pool.
    static func bedHookDecisionDump(
        profile: AutoSongProfile,
        measured: Entrance?,
        chosenStart: Double?
    ) -> String {
        let chorusSecs = profile.analysis.chorusOrDropCandidates
            .map { String(format: "%.1f", $0.startSeconds) }
            .joined(separator: ",")
        let catalog = profile.candidates
            .filter { $0.label == .chorus }
            .sorted { $0.startSeconds < $1.startSeconds }
            .map { String(format: "%.1f(h%.2f)", $0.startSeconds, $0.hook) }
            .joined(separator: ",")
        let measuredStr = measured.map { String(format: "%.1f", $0.startSeconds) } ?? "nil"
        let chosenStr = chosenStart.map { String(format: "%.1f", $0) } ?? "nil"
        let stem = profile.stems.hasVocals ? "stem=vocals" : "stem=none"
        return "chorusOrDrop=[\(chorusSecs)] measured=\(measuredStr) chosen=\(chosenStr) catalog=[\(catalog)] \(stem)"
    }

    /// Raw qualifying downbeats in the first-title window (debug / bounce score).
    static func titleEntranceCandidates(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double? = nil,
        title: String? = nil
    ) -> [Entrance] {
        guard hasUsableEnergyShape(signal), barSeconds > 0.05 else { return [] }
        let phrase = max(barSeconds * 4, phraseSeconds ?? barSeconds * 8)
        let lo = max(barSeconds * 8, min(introEnd, barSeconds * 16) * 0.35)
        let globalHi = min(duration * 0.42, duration - barSeconds * 8)
        let hi = firstTitleWindowHi(
            introEnd: introEnd,
            phraseSeconds: phrase,
            barSeconds: barSeconds,
            duration: duration,
            globalHi: globalHi
        )
        guard hi > lo + barSeconds else { return [] }
        let sampled = sampleGrid(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            lo: lo,
            hi: hi,
            introEnd: introEnd,
            phraseSeconds: phrase,
            title: title
        )
        let peakEnergy = sampled.map(\.energyAfter).max() ?? 0
        let titleEnergyFloor = max(0.55, peakEnergy * 0.68)
        return sampled
            .filter { qualifiesAsTitleEntrance($0, titleEnergyFloor: titleEnergyFloor) }
            .sorted { $0.startSeconds < $1.startSeconds }
    }

    /// All chorus entrance peaks (full early-song window) — for repeat chorus / refine c2.
    static func entrances(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double? = nil,
        title: String? = nil
    ) -> [Entrance] {
        guard hasUsableEnergyShape(signal), barSeconds > 0.05, duration > barSeconds * 16 else {
            return []
        }
        let phrase = max(barSeconds * 4, phraseSeconds ?? barSeconds * 8)
        let lo = max(barSeconds * 8, min(introEnd, barSeconds * 16) * 0.35)
        let hi = min(duration * 0.42, duration - barSeconds * 8)
        guard hi > lo + barSeconds else { return [] }

        let sampled = sampleGrid(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            lo: lo,
            hi: hi,
            introEnd: introEnd,
            phraseSeconds: phrase,
            title: title
        )
        guard !sampled.isEmpty else { return [] }

        let peakEnergy = sampled.map(\.energyAfter).max() ?? 0
        let titleEnergyFloor = max(0.55, peakEnergy * 0.68)

        let qualifying = sampled
            .filter { qualifiesAsTitleEntrance($0, titleEnergyFloor: titleEnergyFloor) }
            .sorted { $0.startSeconds < $1.startSeconds }

        return clusterPeaks(
            qualifying,
            phraseSeconds: phrase,
            barSeconds: barSeconds,
            titleOnset: false
        )
    }

    static func bestEntrance(
        signal: SongSignalFeatures?,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double? = nil,
        title: String? = nil
    ) -> Entrance? {
        guard let signal else { return nil }
        return firstTitleEntrance(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            title: title
        )
    }

    /// Chorus sections rebuilt from measured entrances (first + a later repeat).
    static func refineChoruses(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        phraseSeconds: Double,
        duration: Double,
        introEnd: Double,
        outroStart: Double,
        title: String? = nil
    ) -> (SongSection, SongSection)? {
        guard let first = firstTitleEntrance(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            title: title
        ) else {
            return nil
        }
        let hits = entrances(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            title: title
        )
        let c1Start = first.startSeconds
        let c1End = min(outroStart, c1Start + phraseSeconds)
        let chorus1 = SongSection(kind: .chorus, startSeconds: c1Start, endSeconds: c1End)

        let later = hits.first { $0.startSeconds >= c1Start + phraseSeconds * 1.5 }
        let c2Start: Double
        if let later {
            c2Start = later.startSeconds
        } else {
            let fallback = downbeats.last { $0 <= duration * 0.60 + 0.01 } ?? (c1Start + phraseSeconds * 2)
            c2Start = max(c1End, fallback)
        }
        let c2End = min(outroStart, c2Start + phraseSeconds)
        let chorus2 = SongSection(kind: .chorus, startSeconds: c2Start, endSeconds: max(c2Start + barSeconds * 4, c2End))
        return (chorus1, chorus2)
    }

    // MARK: - Internals

    /// Upper bound for the **first** title chorus — after verse/prechorus,
    /// before verse 2. Phrase-relative, not a song-specific second mark.
    private static func firstTitleWindowHi(
        introEnd: Double,
        phraseSeconds: Double,
        barSeconds: Double,
        duration: Double,
        globalHi: Double
    ) -> Double {
        let afterVerse = introEnd + phraseSeconds * 3.2
        let barLimited = introEnd + barSeconds * 24
        let fraction = duration * 0.40
        return min(globalHi, afterVerse, barLimited, fraction)
    }

    private static func sampleGrid(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        lo: Double,
        hi: Double,
        introEnd: Double,
        phraseSeconds: Double,
        title: String?
    ) -> [Entrance] {
        let beats = downbeats.filter { $0 >= lo - 0.02 && $0 <= hi + 0.02 }
        let grid = beats.isEmpty
            ? stride(from: lo, through: hi, by: barSeconds).map { $0 }
            : beats

        var sampled: [Entrance] = []
        for t in grid {
            let riseWin = 4.0
            let stemCurve = signal.stemVocalPresenceCurve
            let vocalCurve: [Double]
            if !stemCurve.isEmpty {
                vocalCurve = stemCurve
            } else {
                vocalCurve = signal.vocalPresenceCurve.isEmpty ? signal.energyCurve : signal.vocalPresenceCurve
            }
            let after = mean(signal.energyCurve, hop: signal.hopSeconds, from: t, to: t + riseWin)
            let before = mean(signal.energyCurve, hop: signal.hopSeconds, from: t - riseWin, to: t)
            let rise = after - before
            let vocal = mean(vocalCurve, hop: signal.hopSeconds, from: t, to: t + barSeconds * 4)
            let vocalBefore = mean(vocalCurve, hop: signal.hopSeconds, from: t - riseWin, to: t)
            let vocalRise = vocal - vocalBefore
            let novelty = mean(signal.noveltyCurve, hop: signal.hopSeconds, from: t - 0.3, to: t + 0.6)
            let titleBoost = titleChorusBoost(
                title: title,
                t: t,
                introEnd: introEnd,
                phraseSeconds: phraseSeconds,
                vocal: vocal,
                vocalRise: vocalRise,
                novelty: novelty
            )
            let score = max(0, rise) * 0.44 + after * 0.18 + vocal * 0.22 + max(0, vocalRise) * 0.10
                + novelty * 0.06 + titleBoost
            sampled.append(
                Entrance(
                    startSeconds: t,
                    score: score,
                    rise: rise,
                    energyAfter: after,
                    vocalAfter: vocal,
                    titleBoost: titleBoost
                )
            )
        }
        return sampled
    }

    /// Title-line onset proxy from metadata tokens + vocal lift (no Python / ASR).
    private static func titleChorusBoost(
        title: String?,
        t: Double,
        introEnd: Double,
        phraseSeconds: Double,
        vocal: Double,
        vocalRise: Double,
        novelty: Double
    ) -> Double {
        guard let title, !title.isEmpty else { return 0 }
        let tokens = Set(AutoPivotWord.tokens(in: title))
        guard !tokens.isEmpty else { return 0 }
        let afterIntro = t - introEnd
        // After a verse/prechorus phrase, through a late first chorus — not
        // a song-specific second mark.
        guard afterIntro >= phraseSeconds * 1.28 && afterIntro <= phraseSeconds * 2.80 else {
            return 0
        }
        var boost = max(0, vocal - 0.46) * 0.18 + max(0, vocalRise) * 0.16 + novelty * 0.05
        let lexiconHits = tokens.filter { AutoPivotWord.pivotLexicon.contains($0) }.count
        boost += min(0.14, Double(lexiconHits) * 0.045)
        return boost
    }

    /// Group qualifying lifts within one phrase.
    private static func clusterPeaks(
        _ qualifying: [Entrance],
        phraseSeconds: Double,
        barSeconds: Double,
        titleOnset: Bool
    ) -> [Entrance] {
        guard !qualifying.isEmpty else { return [] }
        var clusters: [[Entrance]] = []
        var current = [qualifying[0]]
        for e in qualifying.dropFirst() {
            if e.startSeconds - (current.last?.startSeconds ?? 0) <= phraseSeconds * 0.85 {
                current.append(e)
            } else {
                clusters.append(current)
                current = [e]
            }
        }
        clusters.append(current)

        let peaks = clusters.map { cluster -> Entrance in
            if titleOnset {
                return titleOnsetEntrance(in: cluster)
            }
            return cluster.max(by: { a, b in a.score < b.score })!
        }

        var unique: [Entrance] = []
        for e in peaks {
            if unique.contains(where: { abs($0.startSeconds - e.startSeconds) < barSeconds * 6 }) {
                continue
            }
            unique.append(e)
            if unique.count >= 4 { break }
        }
        return unique
    }

    /// Isolated-vocal (or vocal-presence) curve for title-hook detection.
    private static func hookVocalCurve(_ signal: SongSignalFeatures) -> [Double] {
        if signal.stemVocalPresenceCurve.count >= 8 { return signal.stemVocalPresenceCurve }
        if signal.vocalPresenceCurve.count >= 8 { return signal.vocalPresenceCurve }
        return signal.energyCurve
    }

    /// First isolated-vocal onset of a title/hook line after the prechorus.
    /// Phrase-relative: first 8-bar high-vocal island, then the last attack in
    /// the opening beat (skip pickup), snapped forward — never earlier.
    static func titleHookOnset(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double,
        title: String?
    ) -> Double? {
        _ = title
        let vocal = hookVocalCurve(signal)
        guard vocal.count >= 8, signal.hopSeconds > 0, barSeconds > 0.05 else { return nil }
        let lo = max(introEnd, barSeconds * 8)
        let hi = min(duration * 0.42, duration - barSeconds * 8)
        guard hi > lo + barSeconds * 4 else { return nil }

        let beats = downbeats.filter { $0 >= lo - 0.02 && $0 <= hi - barSeconds * 2 }
        let onsets = onsetPeaks(curve: vocal, hop: signal.hopSeconds, lo: lo, hi: hi - barSeconds * 2).map(\.t)
        var grid = beats + onsets
        if grid.count < 4 {
            grid += stride(from: lo, through: hi - barSeconds * 2, by: barSeconds).map { $0 }
        }
        grid = Array(Set(grid.map { ($0 * 100).rounded() / 100 })).sorted()
        guard !grid.isEmpty else { return nil }

        let oneBar = barSeconds
        var scored: [(t: Double, mean1: Double, mean8: Double)] = []
        for t in grid {
            let m1 = mean(vocal, hop: signal.hopSeconds, from: t, to: t + oneBar)
            let m8 = mean(vocal, hop: signal.hopSeconds, from: t, to: t + barSeconds * 8)
            scored.append((t, m1, m8))
        }
        let best8 = scored.map(\.mean8).max() ?? 0
        guard best8 >= 0.28 else { return nil }

        let longIslands = scored.filter { $0.mean8 >= best8 * 0.88 }
        let best1 = longIslands.map(\.mean1).max() ?? 0
        guard best1 >= 0.28 else { return nil }

        let chorusLike = longIslands
            .filter { $0.mean1 >= best1 * 0.93 }
            .sorted { $0.t < $1.t }
        guard let first = chorusLike.first else { return nil }

        var cluster = [first]
        for s in chorusLike.dropFirst() {
            if s.t - (cluster.last?.t ?? 0) <= barSeconds * 2.2 {
                cluster.append(s)
            } else {
                break
            }
        }
        let island = cluster.min(by: { $0.t < $1.t })!.t

        let wordHi = island + min(0.90, barSeconds * 0.38)
        let peaks = onsetPeaks(curve: vocal, hop: signal.hopSeconds, lo: island, hi: wordHi)
        let raw = peaks.max(by: { $0.t < $1.t })?.t ?? island
        return snapForwardOrKeep(
            raw,
            downbeats: downbeats,
            barSeconds: barSeconds,
            minSeconds: island
        )
    }

    private static func titleHookEntrance(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double,
        title: String?
    ) -> Entrance? {
        guard let snapped = titleHookOnset(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            title: title
        ) else { return nil }
        let vocal = hookVocalCurve(signal)
        let vocalAfter = mean(vocal, hop: signal.hopSeconds, from: snapped, to: snapped + barSeconds * 4)
        let vocalBefore = mean(vocal, hop: signal.hopSeconds, from: snapped - 4, to: snapped)
        let titleBoost = titleChorusBoost(
            title: title,
            t: snapped,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            vocal: vocalAfter,
            vocalRise: vocalAfter - vocalBefore,
            novelty: 0.5
        )
        return Entrance(
            startSeconds: snapped,
            score: vocalAfter * 0.7 + titleBoost,
            rise: vocalAfter - vocalBefore,
            energyAfter: mean(signal.energyCurve, hop: signal.hopSeconds, from: snapped, to: snapped + 4),
            vocalAfter: vocalAfter,
            titleBoost: max(titleBoost, 0.12)
        )
    }

    /// Local maxima on a vocal/stem rise curve.
    private static func onsetPeaks(
        curve: [Double],
        hop: Double,
        lo: Double,
        hi: Double
    ) -> [(t: Double, strength: Double)] {
        guard curve.count >= 8, hop > 0, hi > lo else { return [] }
        var onset = [Double](repeating: 0, count: curve.count)
        for i in 1..<curve.count {
            onset[i] = max(0, curve[i] - curve[i - 1])
        }
        let sorted = onset.sorted()
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.90))]
        let threshold = max(0.08, p90 * 0.42)
        var peaks: [(t: Double, strength: Double)] = []
        for i in 2..<(curve.count - 2) {
            let t = Double(i) * hop
            guard t >= lo && t <= hi else { continue }
            let o = onset[i]
            guard o >= threshold else { continue }
            if o >= onset[i - 1] && o >= onset[i + 1] && o >= onset[i - 2] && o >= onset[i + 2] {
                peaks.append((t, o))
            }
        }
        return peaks
    }

    /// First isolated-vocal onset peak in `[lo, hi]` (local maxima on stem rise).
    private static func firstStemOnsetPeak(
        signal: SongSignalFeatures,
        lo: Double,
        hi: Double
    ) -> Double? {
        onsetPeaks(curve: signal.stemVocalPresenceCurve, hop: signal.hopSeconds, lo: lo, hi: hi)
            .min(by: { $0.t < $1.t })?.t
    }

    /// First isolated-vocal onset in `[lo, hi]`, nearest downbeat.
    static func stemOnsetInBand(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        lo: Double,
        hi: Double
    ) -> Double? {
        guard let first = firstStemOnsetPeak(signal: signal, lo: lo, hi: hi) else { return nil }
        return snapDownbeat(first, downbeats: downbeats, barSeconds: barSeconds)
    }

    /// First downbeat of the title chorus in a lift — not prechorus, not tail line.
    private static func titleOnsetEntrance(in cluster: [Entrance]) -> Entrance {
        let withTitle = cluster.filter { $0.titleBoost >= 0.035 }
        if let first = withTitle.min(by: { $0.startSeconds < $1.startSeconds }) {
            return first
        }
        let peakE = cluster.map(\.energyAfter).max() ?? 0
        let nearPeak = cluster.filter { $0.energyAfter >= peakE * 0.86 && $0.titleBoost > 0.01 }
        if let first = nearPeak.min(by: { $0.startSeconds < $1.startSeconds }) {
            return first
        }
        let maxRise = cluster.map(\.rise).max() ?? 0
        let riseOnset = cluster.filter { $0.rise >= max(0.06, maxRise * 0.70) }
        if let first = riseOnset.min(by: { $0.startSeconds < $1.startSeconds }) {
            return first
        }
        return cluster.min(by: { $0.startSeconds < $1.startSeconds })!
    }

    /// Title-line onset from isolated vocal stem — first sharp rise in the
    /// title window, snapped to downbeat. Beats full-mix tail peaks @50.5s.
    private static func stemTitleOnsetEntrance(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        introEnd: Double,
        phraseSeconds: Double,
        title: String?,
        lo: Double,
        hi: Double
    ) -> Entrance? {
        let stem = signal.stemVocalPresenceCurve
        guard stem.count >= 8, signal.hopSeconds > 0 else { return nil }

        var onset = [Double](repeating: 0, count: stem.count)
        for i in 1..<stem.count {
            onset[i] = max(0, stem[i] - stem[i - 1])
        }
        let sorted = onset.sorted()
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.90))]
        let threshold = max(0.08, p90 * 0.42)

        var peaks: [(t: Double, strength: Double)] = []
        for i in 2..<(stem.count - 2) {
            let t = Double(i) * signal.hopSeconds
            guard t >= lo && t <= hi else { continue }
            let o = onset[i]
            guard o >= threshold else { continue }
            if o >= onset[i - 1] && o >= onset[i + 1] && o >= onset[i - 2] && o >= onset[i + 2] {
                peaks.append((t, o))
            }
        }
        guard !peaks.isEmpty else { return nil }

        let titleLo = introEnd + phraseSeconds * 1.20
        let titleHi = introEnd + phraseSeconds * 1.55
        let inTitleWindow = peaks.filter { $0.t >= titleLo && $0.t <= titleHi }
        let pool = inTitleWindow.isEmpty ? peaks : inTitleWindow
        guard let first = pool.min(by: { $0.t < $1.t }) else { return nil }

        let snapped = snapDownbeatTitleLine(
            peak: first.t,
            downbeats: downbeats,
            barSeconds: barSeconds,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            lo: lo,
            hi: hi
        )
        let vocalAfter = mean(stem, hop: signal.hopSeconds, from: snapped, to: snapped + barSeconds * 4)
        let vocalBefore = mean(stem, hop: signal.hopSeconds, from: snapped - 4, to: snapped)
        let titleBoost = titleChorusBoost(
            title: title,
            t: snapped,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            vocal: vocalAfter,
            vocalRise: vocalAfter - vocalBefore,
            novelty: 0.5
        )
        return Entrance(
            startSeconds: snapped,
            score: first.strength * 0.6 + vocalAfter * 0.3 + titleBoost,
            rise: vocalAfter - vocalBefore,
            energyAfter: mean(signal.energyCurve, hop: signal.hopSeconds, from: snapped, to: snapped + 4),
            vocalAfter: vocalAfter,
            titleBoost: max(titleBoost, 0.12)
        )
    }

    private static func snapDownbeat(_ t: Double, downbeats: [Double], barSeconds: Double) -> Double {
        if let db = downbeats.min(by: { abs($0 - t) < abs($1 - t) }), abs(db - t) <= barSeconds * 0.6 {
            return db
        }
        if barSeconds > 0 {
            return (t / barSeconds).rounded() * barSeconds
        }
        return t
    }

    /// Nearest downbeat to `peak`, never before `minSeconds` (avoids verse/prechorus snap-back).
    private static func snapDownbeatAtOrAfter(
        _ peak: Double,
        downbeats: [Double],
        barSeconds: Double,
        minSeconds: Double
    ) -> Double {
        let eligible = downbeats.filter { $0 >= minSeconds - 0.02 }.sorted()
        if !eligible.isEmpty {
            if let nearest = eligible.min(by: { abs($0 - peak) < abs($1 - peak) }),
               abs(nearest - peak) <= barSeconds * 0.55 {
                return nearest
            }
            if let after = eligible.first(where: { $0 >= peak - 0.08 && $0 <= peak + barSeconds * 0.45 }) {
                return after
            }
            return eligible.min(by: { abs($0 - peak) < abs($1 - peak) })!
        }
        if barSeconds > 0 {
            let grid = (peak / barSeconds).rounded() * barSeconds
            return max(minSeconds, grid)
        }
        return max(peak, minSeconds)
    }

    /// Hard-cut on the title word: never snap earlier into pickup. If the next
    /// downbeat is more than a beat away, keep the onset itself.
    private static func snapForwardOrKeep(
        _ peak: Double,
        downbeats: [Double],
        barSeconds: Double,
        minSeconds: Double
    ) -> Double {
        let t = max(peak, minSeconds)
        let after = downbeats.filter { $0 >= t - 0.05 }.sorted()
        if let db = after.first, db <= t + barSeconds * 0.35 {
            return db
        }
        return t
    }

    /// Snap stem title onset to the downbeat that uncuts “Oops” (~44.5–45.5s on
    /// real Oops) — not prechorus @43.0 (e75d4fc) and not body-late @50.5s.
    private static func snapDownbeatTitleLine(
        peak: Double,
        downbeats: [Double],
        barSeconds: Double,
        introEnd: Double,
        phraseSeconds: Double,
        lo: Double,
        hi: Double
    ) -> Double {
        let titleBody = introEnd + phraseSeconds * 1.22
        let candidates = downbeats
            .filter { $0 >= max(lo, titleBody - barSeconds * 0.15) && $0 <= hi + barSeconds }
            .sorted()
        guard !candidates.isEmpty else {
            return snapDownbeat(max(peak - 0.15, titleBody), downbeats: downbeats, barSeconds: barSeconds)
        }

        // Peak in the opening of the bar (title on the downbeat).
        if let inBar = candidates.first(where: { peak >= $0 - 0.05 && peak <= $0 + barSeconds * 0.38 }) {
            return inBar
        }
        // Peak leads the body downbeat by ≤650ms (“Oops” ~0.5s before @45.5s).
        if let led = candidates.first(where: { peak >= $0 - 0.65 && peak < $0 - 0.02 }) {
            return led
        }
        // Otherwise first title-body downbeat near the peak.
        if let after = candidates.filter({ $0 >= titleBody && $0 <= peak + barSeconds * 0.45 }).min() {
            return after
        }
        return candidates.min(by: { abs($0 - peak) < abs($1 - peak) })!
    }

    /// Downbeat of the bar that **contains** t (legacy / full-mix helpers).
    private static func snapDownbeatContaining(
        _ t: Double,
        downbeats: [Double],
        barSeconds: Double,
        lo: Double,
        hi: Double
    ) -> Double {
        let sorted = downbeats.filter { $0 >= lo - barSeconds && $0 <= hi + barSeconds }.sorted()
        if !sorted.isEmpty {
            if let barStart = sorted.last(where: { $0 <= t + 0.04 }) {
                let barEnd = sorted.first(where: { $0 > barStart + 0.01 })
                    ?? (barStart + barSeconds)
                if t < barEnd - 0.02 {
                    return barStart
                }
            }
        }
        if barSeconds > 0 {
            let grid = floor(t / barSeconds) * barSeconds
            return max(lo, grid)
        }
        return t
    }

    private static func qualifiesAsTitleEntrance(_ e: Entrance, titleEnergyFloor: Double) -> Bool {
        let liftOK = e.rise >= 0.05 || e.score >= 0.42
        return liftOK && e.energyAfter >= titleEnergyFloor
    }

    static func mean(_ curve: [Double], hop: Double, from: Double, to: Double) -> Double {
        guard hop > 0, !curve.isEmpty, to > from else { return 0 }
        let lo = max(0, Int(from / hop))
        let hi = min(curve.count - 1, Int((to - hop * 0.01) / hop))
        guard hi >= lo else { return curve[min(curve.count - 1, max(0, lo))] }
        var sum = 0.0
        for i in lo...hi { sum += curve[i] }
        return sum / Double(hi - lo + 1)
    }
}
