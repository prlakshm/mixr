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
        guard barSeconds > 0.05, duration > barSeconds * 16 else {
            return nil
        }
        let phrase = max(barSeconds * 4, phraseSeconds ?? barSeconds * 8)
        // Whisper lyrics.json title-hook onset wins over energy islands.
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
        guard hasUsableEnergyShape(signal) else { return nil }
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
        let measuredStr = measured.map { String(format: "%.2f", $0.startSeconds) } ?? "nil"
        let chosenStr = chosenStart.map { String(format: "%.2f", $0) } ?? "nil"
        let stem = profile.stems.hasVocals ? "stem=vocals" : "stem=none"
        let lyric = profile.analysis.signal?.lyricTitleHookStart
            .map { String(format: "lyric=%.2f", $0) } ?? "lyric=none"
        return "chorusOrDrop=[\(chorusSecs)] measured=\(measuredStr) chosen=\(chosenStr) catalog=[\(catalog)] \(stem) \(lyric)"
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
        let hook = AutoPivotWord.hookTokens(in: title)
        guard !hook.all.isEmpty else { return 0 }
        let afterIntro = t - introEnd
        // After a verse/prechorus phrase, through a late first chorus — not
        // a song-specific second mark.
        guard afterIntro >= phraseSeconds * 1.28 && afterIntro <= phraseSeconds * 2.80 else {
            return 0
        }
        var boost = max(0, vocal - 0.46) * 0.18 + max(0, vocalRise) * 0.16 + novelty * 0.05
        if hook.hasLexiconRare {
            boost += min(0.16, Double(hook.distinctive.count) * 0.06)
        } else if hook.hasDistinctivePhrase {
            boost += 0.08
        }
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

    /// Bounce dump: title tokens actually considered for the hook island.
    static func titleTokensDump(_ title: String?) -> String {
        AutoPivotWord.hookTokens(in: title ?? "").dump
    }

    static func lyricHookDump(_ signal: SongSignalFeatures?) -> String {
        signal?.lyricTitleHookStart.map { String(format: "lyric=%.2f", $0) } ?? "lyric=none"
    }

    /// First isolated-vocal onset of a title/hook line after the prechorus.
    /// Uses Whisper `lyrics.json` `titleHookStart` when present (snapped to the
    /// downbeat of that word). Else title/hook tokens + energy islands.
    static func titleHookOnset(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double,
        title: String?,
        leadIn: TitleHookLeadIn = .oneBeat
    ) -> Double? {
        if let lyric = snapLyricTitleHook(
            signal: signal, downbeats: downbeats, barSeconds: barSeconds, leadIn: leadIn
        ) {
            return lyric
        }
        return energyTitleHookOnset(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds,
            title: title
        )
    }

    /// Whisper word onset → title-hook clip start.
    /// Clip start = **one beat before** `titleHookStart` (nearest downbeat
    /// within ~1 beat, never a full bar / earlier catalog peak). The title
    /// token lands in the first ~1–2s. Drop 1 guest uses the same one-beat
    /// pad (Hit me lock).
    enum TitleHookLeadIn: Sendable {
        /// Lyric minus one beat, snapped at-or-before (never after, never a bar early).
        case oneBeat
        /// Same as `oneBeat` — previous *beat*, not previous bar.
        case previousDownbeat
    }

    static func snapLyricTitleHook(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        leadIn: TitleHookLeadIn = .oneBeat
    ) -> Double? {
        guard let t = signal.lyricTitleHookStart, t >= 0, barSeconds > 0.05 else {
            return nil
        }
        return titleHookClipStart(lyric: t, downbeats: downbeats, barSeconds: barSeconds, leadIn: leadIn)
    }

    /// Title-hook clip start = previous **beat** before the lyric word.
    /// Never after the word. Never a full bar early.
    static func titleHookClipStart(
        lyric: Double,
        downbeats: [Double],
        barSeconds: Double,
        leadIn: TitleHookLeadIn = .oneBeat
    ) -> Double {
        let beat = barSeconds / 4
        let padded = max(0, lyric - beat)
        switch leadIn {
        case .oneBeat, .previousDownbeat:
            // Prefer a downbeat within ~1 beat of the pad, at or before the
            // word. Reject bar-grid hits a full bar back (48.0 vs 50.38).
            let near = downbeats.filter { db in
                db <= lyric - beat * 0.5
                    && abs(db - padded) <= beat * 1.05
            }
            if let db = near.max() {
                return max(0, min(db, padded))
            }
            return padded
        }
    }

    /// Lyric word onset → hard-cut. Snap to a downbeat **at or before** `t`,
    /// never after (a later downbeat cuts the title word: 50.38 → 50.5).
    /// If the previous downbeat is a full bar back, keep `t`.
    static func snapLyricWordOnset(
        _ t: Double,
        downbeats: [Double],
        barSeconds: Double
    ) -> Double {
        guard barSeconds > 0.05 else { return t }
        let before = downbeats.filter { $0 <= t + 0.02 }
        if let db = before.max(), t - db <= barSeconds * 0.45 {
            return db
        }
        return t
    }

    /// Energy-island fallback when `lyrics.json` is missing.
    private static func energyTitleHookOnset(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double,
        title: String?
    ) -> Double? {
        let tokens = AutoPivotWord.hookTokens(in: title ?? "")
        let vocal = hookVocalCurve(signal)
        guard vocal.count >= 8, signal.hopSeconds > 0, barSeconds > 0.05 else { return nil }
        let lo = max(introEnd, barSeconds * 8)
        let hi = min(duration * 0.42, duration - barSeconds * 8)
        guard hi > lo + barSeconds * 4 else { return nil }

        let beats = downbeats.filter { $0 >= lo - 0.02 && $0 <= hi - barSeconds * 2 }
        let onsets = onsetPeaks(curve: vocal, hop: signal.hopSeconds, lo: lo, hi: hi - barSeconds * 2)
        var grid = beats + onsets.map(\.t)
        if grid.count < 4 {
            grid += stride(from: lo, through: hi - barSeconds * 2, by: barSeconds).map { $0 }
        }
        grid = Array(Set(grid.map { ($0 * 100).rounded() / 100 })).sorted()
        guard !grid.isEmpty else { return nil }

        struct Island {
            var t: Double
            var mean1: Double
            var mean8: Double
            var vocalRise: Double
            var energyAfter: Double
            var energy8: Double
            var energyDip: Double
            var energyLastBar: Double
            var energyRise: Double
            var novelty: Double
            var onsetCount: Int
            var firstOnsetStrength: Double
            var alignment: Double
        }

        let hop = signal.hopSeconds
        var scored: [Island] = []
        for t in grid {
            let m1 = mean(vocal, hop: hop, from: t, to: t + barSeconds)
            let m8 = mean(vocal, hop: hop, from: t, to: t + barSeconds * 8)
            let vocalBefore = mean(vocal, hop: hop, from: t - barSeconds * 4, to: t)
            let energyAfter = mean(signal.energyCurve, hop: hop, from: t, to: t + barSeconds)
            let energy8 = mean(signal.energyCurve, hop: hop, from: t, to: t + barSeconds * 8)
            var energyDip = 1.0
            var u = t + barSeconds
            while u <= t + barSeconds * 5.5 {
                energyDip = min(energyDip, mean(signal.energyCurve, hop: hop, from: u, to: u + barSeconds))
                u += barSeconds * 0.5
            }
            let energyBefore = mean(signal.energyCurve, hop: hop, from: t - barSeconds * 4, to: t)
            let energyLastBar = mean(signal.energyCurve, hop: hop, from: t - barSeconds, to: t)
            let novelty = mean(signal.noveltyCurve, hop: hop, from: t - 0.15, to: t + 0.6)
            let localPeaks = onsetPeaks(
                curve: vocal, hop: hop, lo: t, hi: t + min(0.90, barSeconds * 0.5)
            )
            scored.append(
                Island(
                    t: t,
                    mean1: m1,
                    mean8: m8,
                    vocalRise: m1 - vocalBefore,
                    energyAfter: energyAfter,
                    energy8: energy8,
                    energyDip: energyDip,
                    energyLastBar: energyLastBar,
                    energyRise: energyAfter - energyBefore,
                    novelty: novelty,
                    onsetCount: localPeaks.count,
                    firstOnsetStrength: localPeaks.min(by: { $0.t < $1.t })?.strength ?? 0,
                    alignment: 0
                )
            )
        }
        let best8 = scored.map(\.mean8).max() ?? 0
        guard best8 >= 0.28 else { return nil }

        let vocalFloor = max(0.32, best8 * 0.62)
        let chorusLike = scored.filter { $0.mean8 >= vocalFloor && $0.mean1 >= 0.28 }
        guard !chorusLike.isEmpty else { return nil }

        // Chorus island = 8-bar high-vocal hold AFTER a dip. Later bars of
        // the same hold (“you think I'm in love”) are not new islands.
        func vocalBefore(_ s: Island) -> Double { s.mean1 - s.vocalRise }
        func isPlateauStart(_ s: Island) -> Bool {
            let before = vocalBefore(s)
            let alreadyInHold = before >= s.mean8 * 0.90
                && s.vocalRise < 0.06
                && s.energyLastBar >= s.energyAfter * 0.92
            if alreadyInHold { return false }
            // 4-bar energy spike with a hole before the real 8-bar chorus.
            if s.energyDip + 0.08 < s.energyAfter && s.energyDip < s.energyAfter * 0.88 {
                return false
            }
            let lastBarLift = s.energyAfter >= s.energyLastBar + 0.08
            return lastBarLift
                || before < s.mean8 * 0.92
                || s.energyRise >= 0.05
                || s.vocalRise >= 0.05
        }

        var starts = chorusLike.filter(isPlateauStart)
        if starts.isEmpty { starts = chorusLike }
        // Pickup / prechorus: a stronger chorus plateau starts 1–5 bars later.
        starts = starts.filter { s in
            !starts.contains { later in
                later.t > s.t + barSeconds * 0.5
                    && later.t <= s.t + barSeconds * 5.5
                    && later.energyAfter >= s.energyAfter + 0.03
                    && later.energy8 >= s.energy8 * 0.97
            }
        }
        if starts.isEmpty {
            let raw = chorusLike.filter(isPlateauStart)
            if let best = raw.max(by: { $0.energy8 < $1.energy8 }) {
                starts = [best]
            } else {
                starts = chorusLike
            }
        }
        let peakEnergy = starts.map(\.energyAfter).max() ?? (chorusLike.map(\.energyAfter).max() ?? 0)
        let peakEnergy8 = starts.map(\.energy8).max() ?? peakEnergy
        let peakStart8 = starts.map(\.mean8).max() ?? best8

        for i in starts.indices {
            let s = starts[i]
            starts[i].alignment = distinctiveOpeningAlignment(
                IslandProxy(
                    t: s.t,
                    mean1: s.mean1,
                    mean8: s.mean8,
                    vocalRise: s.vocalRise,
                    energyAfter: s.energyAfter,
                    energy8: s.energy8,
                    energyLastBar: s.energyLastBar,
                    energyRise: s.energyRise,
                    novelty: s.novelty,
                    onsetCount: s.onsetCount,
                    firstOnsetStrength: s.firstOnsetStrength
                ),
                tokens: tokens,
                peakEnergy: max(peakEnergy, peakEnergy8),
                bestVocal8: peakStart8,
                phraseSeconds: phraseSeconds,
                introEnd: introEnd
            )
        }

        let islandAnchor: Double
        if tokens.all.isEmpty {
            islandAnchor = chorusLike.min(by: { $0.t < $1.t })!.t
        } else {
            let bestAlign = starts.map(\.alignment).max() ?? 0
            let cutoff = max(0.08, bestAlign * 0.72)
            let aligned = starts
                .filter { $0.alignment >= cutoff }
                .sorted { $0.t < $1.t }
            if let first = aligned.first {
                islandAnchor = first.t
            } else if let best = starts.max(by: { $0.alignment < $1.alignment }), best.alignment > 0 {
                islandAnchor = best.t
            } else {
                let chorusEnergy = starts.filter { $0.energyAfter >= max(0.50, peakEnergy * 0.82) }
                islandAnchor = (chorusEnergy.isEmpty ? starts : chorusEnergy).min(by: { $0.t < $1.t })!.t
            }
        }

        let anchorRow = chorusLike.min(by: { abs($0.t - islandAnchor) < abs($1.t - islandAnchor) })!
        // Catalog / energy peak inside the hold is not the entrance — walk
        // back to the first downbeat of this 8-bar high-vocal run.
        let island = earliestPlateauEntrance(
            from: islandAnchor,
            anchorMean8: anchorRow.mean8,
            anchorEnergy8: anchorRow.energy8,
            vocal: vocal,
            energy: signal.energyCurve,
            hop: hop,
            barSeconds: barSeconds,
            downbeats: downbeats,
            lo: lo,
            grid: grid
        )

        // Opening word = FIRST stem onset at the island downbeat, not the
        // last attack in 0.9s (`peaks.max` by t skips the title word).
        let wordHi = island + min(0.90, barSeconds * 0.38)
        let peaks = onsetPeaks(curve: vocal, hop: hop, lo: island, hi: wordHi)
        let raw = peaks.min(by: { $0.t < $1.t })?.t ?? island
        return snapForwardOrKeep(
            raw,
            downbeats: downbeats,
            barSeconds: barSeconds,
            minSeconds: island
        )
    }

    /// First downbeat of an 8-bar high-vocal plateau — not the energy/catalog
    /// peak later in the same chorus (“I did it again” @50.5 vs “Oops” @48).
    private static func earliestPlateauEntrance(
        from anchor: Double,
        anchorMean8: Double,
        anchorEnergy8: Double,
        vocal: [Double],
        energy: [Double],
        hop: Double,
        barSeconds: Double,
        downbeats: [Double],
        lo: Double,
        grid: [Double]
    ) -> Double {
        let vocalHold = max(0.28, anchorMean8 * 0.80)
        let energyHold = max(0.48, anchorEnergy8 * 0.78)
        var candidates = downbeats.filter { $0 >= lo - 0.02 && $0 <= anchor + 0.02 }
        candidates += grid.filter { $0 >= anchor - barSeconds * 7.5 && $0 <= anchor + 0.02 }
        candidates = Array(Set(candidates.map { ($0 * 100).rounded() / 100 })).sorted()

        // Walk anchor backward: first downbeat that still satisfies the hold.
        for t in candidates.filter({ $0 <= anchor + 0.02 }).sorted(by: >) {
            let m8 = mean(vocal, hop: hop, from: t, to: t + barSeconds * 8)
            let m1 = mean(vocal, hop: hop, from: t, to: t + barSeconds)
            let e8 = mean(energy, hop: hop, from: t, to: t + barSeconds * 8)
            guard m8 >= vocalHold && m1 >= 0.24 && e8 >= energyHold else { continue }
            return t
        }
        return anchor
    }

    /// Lift from prechorus into chorus — not a verse bar that stays flat.
    private static func hasPrechorusDip(_ island: IslandProxy) -> Bool {
        island.energyAfter >= island.energyLastBar + 0.05
            || island.vocalRise >= 0.06
            || island.novelty >= 0.30
    }

    /// Opening-bar score from title tokens + local attack/lift. Generic verse
    /// fillers do not win unless they co-occur as a distinctive phrase.
    private struct IslandProxy {
        var t: Double
        var mean1: Double
        var mean8: Double
        var vocalRise: Double
        var energyAfter: Double
        var energy8: Double
        var energyLastBar: Double
        var energyRise: Double
        var novelty: Double
        var onsetCount: Int
        var firstOnsetStrength: Double
    }

    private static func distinctiveOpeningAlignment(
        _ island: IslandProxy,
        tokens: AutoPivotWord.TitleHookTokens,
        peakEnergy: Double,
        bestVocal8: Double,
        phraseSeconds: Double,
        introEnd: Double
    ) -> Double {
        // Prechorus that swallows the chorus: opening bar colder than the 8-bar.
        guard island.mean1 >= island.mean8 * 0.68 else { return 0 }

        let chorusFloor = max(0.50, peakEnergy * 0.82)
        let verseLike = island.energyAfter < chorusFloor || island.energy8 < max(0.48, peakEnergy * 0.78)
        let afterVerse = island.t >= introEnd + phraseSeconds * 0.75

        var score = 0.0
        score += max(0, island.energyRise) * 0.40
        score += max(0, island.vocalRise) * 0.22
        score += island.novelty * 0.20
        score += min(0.22, island.firstOnsetStrength * 0.30)
        if afterVerse { score += 0.04 }

        // Title tokens (never emptied) need a CHORUS plateau after prechorus,
        // not the first time a filler word is sung in a verse.
        if verseLike { return 0 }

        if tokens.hasLexiconRare {
            guard island.t >= introEnd + phraseSeconds * 1.12 else { return 0 }
            guard hasPrechorusDip(island) || island.novelty >= 0.28 else { return 0 }
            guard island.energyAfter >= max(0.55, peakEnergy * 0.82) else { return 0 }
            score += island.novelty * 0.12
        }

        if tokens.hasDistinctivePhrase && !tokens.hasLexiconRare {
            guard island.t >= introEnd + phraseSeconds * 1.72 else { return 0 }
            guard hasPrechorusDip(island) else { return 0 }
            guard island.mean8 >= max(0.32, bestVocal8 * 0.82) else { return 0 }
            guard island.energyAfter >= max(0.55, peakEnergy * 0.86) else { return 0 }
            if island.onsetCount >= 2 { score += 0.08 }
            score += min(0.14, Double(tokens.distinctive.count) * 0.035)
        }

        // Hook phrase not in the title (pivotLexicon extras like “hit”):
        // chorus hold after prechorus, with a real opening attack.
        if !tokens.extras.isEmpty {
            guard hasPrechorusDip(island) else { return 0 }
            if tokens.extras.contains("hit") {
                guard island.firstOnsetStrength >= 0.08 else { return 0 }
                score += min(0.30, island.firstOnsetStrength * 0.50)
            } else {
                score += min(0.16, island.firstOnsetStrength * 0.35)
            }
        }

        if tokens.genericOnly {
            if !afterVerse { return 0 }
            score *= 0.45
        }

        return score
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
