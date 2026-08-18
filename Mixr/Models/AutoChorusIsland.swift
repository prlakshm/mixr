import Foundation

// MARK: - Title-chorus entrance
//
// Heuristic `chorusOrDropCandidates.first` is a duration-fraction snap
// (often ~28% → the phrase *before* the title chorus). Prechorus that
// happens twice (Oops “I'm not that innocent” ~20s and ~40s) looks like
// a chorus island to `.first`. Measured energy *rise* at a downbeat is
// what actually starts “Oops I did it again” / “hit me baby one more time”.
//
// Real crate: prechorus @40.4s can qualify before title @46s on time sort.
// Cluster nearby lifts and take the **peak** in the first cluster (title
// chorus), not the earliest downbeat in that lift window.

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

    /// Chorus *entrances* (downbeat-snapped) in the first ~40% of the song.
    /// Returns cluster peaks in time order — first peak is the title chorus.
    static func entrances(
        signal: SongSignalFeatures,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double? = nil
    ) -> [Entrance] {
        guard hasUsableEnergyShape(signal), barSeconds > 0.05, duration > barSeconds * 16 else {
            return []
        }
        let phrase = max(barSeconds * 4, phraseSeconds ?? barSeconds * 8)
        let lo = max(barSeconds * 8, min(introEnd, barSeconds * 16) * 0.35)
        let hi = min(duration * 0.42, duration - barSeconds * 8)
        guard hi > lo + barSeconds else { return [] }

        let beats = downbeats.filter { $0 >= lo - 0.02 && $0 <= hi + 0.02 }
        let grid = beats.isEmpty
            ? stride(from: lo, through: hi, by: barSeconds).map { $0 }
            : beats

        var sampled: [Entrance] = []
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
            let score = max(0, rise) * 0.52 + after * 0.22 + vocal * 0.18 + novelty * 0.08
            sampled.append(
                Entrance(startSeconds: t, score: score, rise: rise, energyAfter: after, vocalAfter: vocal)
            )
        }
        guard !sampled.isEmpty else { return [] }

        let peakEnergy = sampled.map(\.energyAfter).max() ?? 0
        let titleEnergyFloor = max(0.58, peakEnergy * 0.72)

        let qualifying = sampled
            .filter { qualifiesAsTitleEntrance($0, titleEnergyFloor: titleEnergyFloor) }
            .sorted { $0.startSeconds < $1.startSeconds }

        return clusterPeaks(qualifying, phraseSeconds: phrase, barSeconds: barSeconds)
    }

    /// First title-chorus peak after the intro — real Oops ~46s, not prechorus ~40.4s.
    static func bestEntrance(
        signal: SongSignalFeatures?,
        downbeats: [Double],
        barSeconds: Double,
        duration: Double,
        introEnd: Double,
        phraseSeconds: Double? = nil
    ) -> Entrance? {
        guard let signal else { return nil }
        return entrances(
            signal: signal,
            downbeats: downbeats,
            barSeconds: barSeconds,
            duration: duration,
            introEnd: introEnd,
            phraseSeconds: phraseSeconds
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
            introEnd: introEnd,
            phraseSeconds: phraseSeconds
        )
        guard let first = hits.first else { return nil }
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

    /// Group qualifying lifts within one phrase; keep the loudest peak per group.
    private static func clusterPeaks(
        _ qualifying: [Entrance],
        phraseSeconds: Double,
        barSeconds: Double
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
            cluster.max(by: { a, b in
                if abs(a.energyAfter - b.energyAfter) > 0.015 { return a.energyAfter < b.energyAfter }
                if abs(a.rise - b.rise) > 0.02 { return a.rise < b.rise }
                return a.startSeconds < b.startSeconds
            })!
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

    private static func qualifiesAsTitleEntrance(_ e: Entrance, titleEnergyFloor: Double) -> Bool {
        let liftOK = e.rise >= 0.06 || e.score >= 0.45
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
