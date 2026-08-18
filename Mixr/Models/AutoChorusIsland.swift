import Foundation

// MARK: - Title-chorus entrance
//
// Heuristic `chorusOrDropCandidates.first` is a duration-fraction snap
// (often ~28% → the phrase *before* the title chorus). Prechorus that
// happens twice (Oops “I'm not that innocent” ~20s and ~40s) looks like
// a chorus island to `.first`. Measured energy *rise* at a downbeat is
// what actually starts “Oops I did it again” / “hit me baby one more time”.

nonisolated enum AutoChorusIsland {

    struct Entrance: Sendable {
        var startSeconds: Double
        var score: Double
        var rise: Double
        var energyAfter: Double
        var vocalAfter: Double
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

    /// Ranked chorus *entrances* (downbeat-snapped) in the first ~40% of
    /// the song — where the first title hook lives. Empty when the signal
    /// is too flat to prefer one island over another.
    static func entrances(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double
    ) -> [Entrance] {
        guard hasUsableEnergyShape(signal), barSeconds > 0.05, duration > barSeconds * 16 else {
            return []
        }
        let lo = max(barSeconds * 8, min(introEnd, barSeconds * 16) * 0.35)
        let hi = min(duration * 0.42, duration - barSeconds * 8)
        guard hi > lo + barSeconds else { return [] }

        let beats = downbeats.filter { $0 >= lo - 0.02 && $0 <= hi + 0.02 }
        let grid = beats.isEmpty
            ? stride(from: lo, through: hi, by: barSeconds).map { $0 }
            : beats

        var ranked: [Entrance] = []
        for t in grid {
            let riseWin = 4.0
            let after = mean(signal.energyCurve, hop: signal.hopSeconds, from: t, to: t + riseWin)
            let before = mean(signal.energyCurve, hop: signal.hopSeconds, from: t - riseWin, to: t)
            let rise = after - before
            let vocal = mean(
                signal.vocalPresenceCurve.isEmpty ? signal.energyCurve : signal.vocalPresenceCurve,
                hop: signal.hopSeconds,
                from: t,
                to: t + barSeconds * 4
            )
            let novelty = mean(signal.noveltyCurve, hop: signal.hopSeconds, from: t - 0.3, to: t + 0.6)
            // Title chorus: lift into a loud, sung 8-bar. Prechorus already
            // sitting at medium energy scores a near-zero rise.
            let score = max(0, rise) * 0.52 + after * 0.22 + vocal * 0.18 + novelty * 0.08
            ranked.append(
                Entrance(startSeconds: t, score: score, rise: rise, energyAfter: after, vocalAfter: vocal)
            )
        }
        ranked.sort { $0.score > $1.score }
        // Unique islands ≥ 6 bars apart (don't keep every downbeat of one chorus).
        var unique: [Entrance] = []
        for e in ranked {
            if unique.contains(where: { abs($0.startSeconds - e.startSeconds) < barSeconds * 6 }) {
                continue
            }
            unique.append(e)
            if unique.count >= 4 { break }
        }
        return unique
    }

    static func bestEntrance(
        signal: SongSignalFeatures?,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double
    ) -> Entrance? {
        guard let signal else { return nil }
        return entrances(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd
        ).first
    }

    /// Chorus sections rebuilt from measured entrances (first + a later repeat).
    static func refineChoruses(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        phraseSeconds: Double,
        duration: Double,
        introEnd: Double,
        outroStart: Double
    ) -> (SongSection, SongSection)? {
        let hits = entrances(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd
        )
        guard let first = hits.first, first.rise >= 0.06 || first.score >= 0.45 else {
            return nil
        }
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
