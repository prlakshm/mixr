import Foundation

// MARK: - Club Tempo Pocket Decision
//
// Per-song / per-pair tempo for Auto Remix and mashup. Prefers keeping a
// strong existing pocket (midtempo pop, house, festival) over shoving
// everything to 128. Stretch gates protect vocals; half/double-time is
// checked before any stretch.

nonisolated enum AutoClubTempo {

    /// Recognized dance/club tempo pockets (BPM).
    enum Pocket: String, Sendable {
        case midtempoPop = "midtempo pop"
        case house = "house"
        case festival = "festival / rock"
        case other = "source pocket"
    }

    struct Decision: Sendable, Equatable {
        /// Timeline / pulse grid BPM.
        var targetBPM: Double
        /// Playback rate for the song (1.0 = native).
        var ratio: Double
        var pocket: Pocket
        /// True when alignment came from half- or double-time.
        var halfOrDoubleTime: Bool
        /// True when the vocal would be stretched beyond the safe gate.
        var vocalStretchUnsafe: Bool
        var detail: String
    }

    /// Default house pocket when the song has no strong identity tempo.
    static let housePocketRange: ClosedRange<Double> = 124...128
    static let midtempoRange: ClosedRange<Double> = 90...100
    static let festivalRange: ClosedRange<Double> = 140...150
    /// Vocal time-stretch before it sounds processed.
    static let maxVocalStretch = 0.08
    /// Instrumental / bed stretch preference.
    static let maxInstrumentalStretch = 0.15

    /// Classify a measured BPM into a pocket, if it already sits in one.
    static func classify(_ bpm: Double) -> Pocket? {
        if midtempoRange.contains(bpm) { return .midtempoPop }
        if housePocketRange.contains(bpm) || (120...130).contains(bpm) { return .house }
        if festivalRange.contains(bpm) || (135...155).contains(bpm) { return .festival }
        return nil
    }

    /// One-song club remix tempo: keep a strong pocket; otherwise land in
    /// house via stretch, double-time, or arrangement-only club-ify.
    static func remixDecision(
        songBPM: Double,
        vocalHeavy: Bool,
        maxVocalStretch: Double = maxVocalStretch,
        maxInstrumentalStretch: Double = maxInstrumentalStretch
    ) -> Decision {
        let stretchCap = vocalHeavy ? maxVocalStretch : maxInstrumentalStretch

        if let pocket = classify(songBPM) {
            return Decision(
                targetBPM: songBPM,
                ratio: 1.0,
                pocket: pocket,
                halfOrDoubleTime: false,
                vocalStretchUnsafe: false,
                detail: "kept \(pocket.rawValue) pocket at \(Int(songBPM.rounded())) BPM"
            )
        }

        // Double-time into a pocket (e.g. 64 → 128).
        let doubled = songBPM * 2
        if let pocket = classify(doubled) {
            return Decision(
                targetBPM: doubled,
                ratio: 1.0,
                pocket: pocket,
                halfOrDoubleTime: true,
                vocalStretchUnsafe: false,
                detail: "double-time feel into \(pocket.rawValue) (\(Int(songBPM.rounded())) → \(Int(doubled.rounded())) grid)"
            )
        }

        // Half-time into a pocket (e.g. 180 → 90).
        let halved = songBPM / 2
        if let pocket = classify(halved) {
            return Decision(
                targetBPM: songBPM,
                ratio: 1.0,
                pocket: pocket,
                halfOrDoubleTime: true,
                vocalStretchUnsafe: false,
                detail: "half-time relationship to \(pocket.rawValue) (\(Int(halved.rounded())) feel)"
            )
        }

        // Small stretch into the nearest house center when a few percent off.
        let houseCenter = 126.0
        let ratioToHouse = houseCenter / max(songBPM, 1)
        if abs(ratioToHouse - 1) <= stretchCap {
            return Decision(
                targetBPM: houseCenter,
                ratio: ratioToHouse,
                pocket: .house,
                halfOrDoubleTime: false,
                vocalStretchUnsafe: false,
                detail: String(
                    format: "stretched %+.0f%% into house pocket (%d → 126)",
                    (ratioToHouse - 1) * 100,
                    Int(songBPM.rounded())
                )
            )
        }

        // Far from house and stretch would wreck the vocal → keep source BPM,
        // club-ify with arrangement + energy only.
        let unsafe = vocalHeavy && abs(ratioToHouse - 1) > maxVocalStretch
        return Decision(
            targetBPM: songBPM,
            ratio: 1.0,
            pocket: .other,
            halfOrDoubleTime: false,
            vocalStretchUnsafe: unsafe,
            detail: unsafe
                ? "kept source \(Int(songBPM.rounded())) BPM — stretch to house would process the vocal"
                : "kept source \(Int(songBPM.rounded())) BPM; arrangement carries the club energy"
        )
    }

    /// Two-song mashup tempo: prefer a shared pocket; stretch the bed first;
    /// never force a vocal through an illegal stretch.
    static func mashupDecision(
        vocalBPM: Double,
        bedBPM: Double,
        maxVocalStretch: Double = maxVocalStretch,
        maxInstrumentalStretch: Double = maxInstrumentalStretch
    ) -> (targetBPM: Double, vocalRatio: Double, bedRatio: Double, ok: Bool, detail: String) {
        // Shared / near pocket: stay put (Britney-class ~93–95).
        if abs(vocalBPM - bedBPM) / max(vocalBPM, 1) <= maxInstrumentalStretch {
            let target = (vocalBPM + bedBPM) / 2
            let bedRatio = target / max(bedBPM, 1)
            let vocalRatio = target / max(vocalBPM, 1)
            if abs(vocalRatio - 1) <= maxVocalStretch,
               abs(bedRatio - 1) <= maxInstrumentalStretch {
                return (
                    target,
                    abs(vocalRatio - 1) < 0.0001 ? 1.0 : vocalRatio,
                    abs(bedRatio - 1) < 0.0001 ? 1.0 : bedRatio,
                    true,
                    String(format: "shared pocket ~%.0f BPM (bed stretch %+.0f%%, vocal %+.0f%%)",
                           target, (bedRatio - 1) * 100, (vocalRatio - 1) * 100)
                )
            }
        }

        // Half / double relationship between the pair (90 vs 180, 72 vs 144).
        for fold in [2.0, 0.5] {
            let foldedBed = bedBPM * fold
            if abs(foldedBed - vocalBPM) / max(vocalBPM, 1) <= maxVocalStretch {
                return (
                    vocalBPM,
                    1.0,
                    1.0,
                    true,
                    "half/double-time relationship — kept vocal at \(Int(vocalBPM.rounded())) BPM"
                )
            }
        }

        // Prefer bed stretch toward vocal BPM when vocal stays unstretched.
        let bedToVocal = vocalBPM / max(bedBPM, 1)
        if abs(bedToVocal - 1) <= maxInstrumentalStretch {
            return (
                vocalBPM,
                1.0,
                bedToVocal,
                true,
                String(format: "stretched bed %+.0f%% to vocal pocket %d BPM",
                       (bedToVocal - 1) * 100, Int(vocalBPM.rounded()))
            )
        }

        // Festival/rock bed over midtempo vocal: keep bed pocket, leave vocal
        // native only when ratios already align via feel — else refuse.
        if let vPocket = classify(vocalBPM), let bPocket = classify(bedBPM),
           vPocket == bPocket {
            return (vocalBPM, 1.0, 1.0, true, "same \(vPocket.rawValue) pocket — native tempos")
        }

        return (
            vocalBPM,
            1.0,
            1.0,
            false,
            "refused mashup tempo — stretch would wreck the vocal or leave the pair unlocked"
        )
    }
}
