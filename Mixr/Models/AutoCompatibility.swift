import Foundation

// MARK: - Harmonic Key Model

/// Parses stored key strings ("D#m", "G", "F# minor", "Bb major") and
/// scores harmonic-mixing compatibility, including the smallest corrective
/// pitch shift that would make a pairing work.
nonisolated enum AutoKey {

    struct Parsed: Equatable, Sendable {
        var pitchClass: Int   // 0 = C … 11 = B
        var isMinor: Bool
    }

    static func parse(_ raw: String?) -> Parsed? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        var minor = false
        let lower = s.lowercased()
        if lower.hasSuffix(" minor") { minor = true; s = String(s.dropLast(6)) }
        else if lower.hasSuffix(" major") { s = String(s.dropLast(6)) }
        else if s.count > 1, s.hasSuffix("m") { minor = true; s = String(s.dropLast()) }
        s = s.trimmingCharacters(in: .whitespaces)

        let names: [String: Int] = [
            "C": 0, "C#": 1, "DB": 1, "D": 2, "D#": 3, "EB": 3, "E": 4, "F": 5,
            "F#": 6, "GB": 6, "G": 7, "G#": 8, "AB": 8, "A": 9, "A#": 10, "BB": 10, "B": 11,
        ]
        guard let pc = names[s.uppercased()] else { return nil }
        return Parsed(pitchClass: pc, isMinor: minor)
    }

    /// Compatibility of two keys as-is, 0…1 (Camelot-style neighborhood).
    static func score(_ a: Parsed, _ b: Parsed) -> Double {
        let diff = ((b.pitchClass - a.pitchClass) % 12 + 12) % 12
        if a.isMinor == b.isMinor {
            switch diff {
            case 0: return 1.0            // same key
            case 5, 7: return 0.85        // adjacent on the circle of fifths
            case 2, 10: return 0.5        // two steps out
            default: return 0.22
            }
        }
        // Relative major/minor: A minor ↔ C major (minor pc = major pc + 9).
        let relative = a.isMinor ? (a.pitchClass + 3) % 12 : (a.pitchClass + 9) % 12
        if b.pitchClass == relative { return 0.92 }
        if diff == 0 { return 0.62 }      // parallel major/minor
        return 0.22
    }

    /// Best (score, semitone shift of `b`) within ±maxShift semitones —
    /// each corrective semitone costs a little, so the smallest successful
    /// change always wins ties.
    static func bestCorrection(
        _ a: Parsed?,
        _ b: Parsed?,
        maxShift: Int
    ) -> (score: Double, shiftSemitones: Int) {
        guard let a, let b else { return (0.5, 0) }   // unknown key: neutral, no shift
        var best = (score: score(a, b), shiftSemitones: 0)
        guard maxShift > 0 else { return best }
        for shift in -maxShift...maxShift where shift != 0 {
            let shifted = Parsed(
                pitchClass: ((b.pitchClass + shift) % 12 + 12) % 12,
                isMinor: b.isMinor
            )
            let s = score(a, shifted) - 0.05 * Double(abs(shift))
            if s > best.score + 0.001 { best = (s, shift) }
        }
        return best
    }
}

// MARK: - Tempo Fit

nonisolated enum AutoTempo {

    struct Fit: Sendable {
        /// Playback rate to apply (1.0 = keep native tempo).
        var ratio: Double
        /// True when the song's bars land on the target grid (either
        /// stretched into it, or naturally via half/double time).
        var gridAligned: Bool
        /// True when a confident half-/double-time relationship carries
        /// the alignment instead of stretching.
        var halfOrDoubleTime: Bool
    }

    /// How a song locks to the target BPM within the safe stretch window.
    static func fit(songBPM: Double, targetBPM: Double, maxStretch: Double) -> Fit {
        let r = targetBPM / max(songBPM, 1)
        if abs(r - 1) <= maxStretch {
            return Fit(ratio: abs(r - 1) < 0.0001 ? 1.0 : r, gridAligned: true, halfOrDoubleTime: false)
        }
        // Half/double time: bars still align every 1–2 target bars.
        for fold in [2.0, 0.5] where abs(r / fold - 1) <= maxStretch {
            let folded = r / fold
            return Fit(ratio: abs(folded - 1) < 0.0001 ? 1.0 : folded, gridAligned: true, halfOrDoubleTime: true)
        }
        return Fit(ratio: 1.0, gridAligned: false, halfOrDoubleTime: false)
    }

    /// Target BPM for a multi-song set: prefer a shared pocket, otherwise
    /// the anchor when most songs can lock, otherwise the median.
    static func targetBPM(profiles: [AutoSongProfile], anchorID: UUID, maxStretch: Double) -> Double {
        let bpms = profiles.map(\.analysis.bpm)
        guard let anchorBPM = profiles.first(where: { $0.songID == anchorID })?.analysis.bpm else {
            return bpms.sorted()[bpms.count / 2]
        }
        if let pocket = AutoClubTempo.classify(anchorBPM) {
            let samePocket = bpms.filter { AutoClubTempo.classify($0) == pocket }
            if samePocket.count >= max(1, bpms.count / 2) { return anchorBPM }
        }
        let locked = bpms.filter { fit(songBPM: $0, targetBPM: anchorBPM, maxStretch: maxStretch).gridAligned }
        if Double(locked.count) >= Double(bpms.count) * 0.5 { return anchorBPM }
        return bpms.sorted()[bpms.count / 2]
    }
}

// MARK: - Directional Compatibility

/// Directional pairing verdict: how well `support` works UNDER `dominant`.
/// A ↦ B and B ↦ A are evaluated independently — a vocal-heavy section
/// can ride over a sparse groove even when the reverse pairing fails.
struct AutoDirectionalCompat: Sendable {
    var score: Double
    /// Corrective pitch to apply to the SUPPORTING side, semitones.
    var pitchCorrectionSemitones: Int
    /// Recommended overlap length; 0 = use a clean phrase-aligned handoff.
    var overlapBars: Int
}

nonisolated enum AutoCompatibility {

    static func directional(
        dominant: AutoCandidateSection,
        dominantProfile: AutoSongProfile,
        support: AutoCandidateSection,
        supportProfile: AutoSongProfile,
        targetBPM: Double,
        tuning: AutoTuning
    ) -> AutoDirectionalCompat {
        // Harmonic: allow small corrective shifts on the support side only.
        let keyA = AutoKey.parse(dominantProfile.analysis.key)
        let keyB = AutoKey.parse(supportProfile.analysis.key)
        let harmonic = AutoKey.bestCorrection(keyA, keyB, maxShift: tuning.maxCorrectivePitchSemitones)

        // Rhythmic/tempo: both must sit on the target grid for a real overlap.
        let fitA = AutoTempo.fit(songBPM: dominantProfile.analysis.bpm, targetBPM: targetBPM, maxStretch: tuning.maxStretch)
        let fitB = AutoTempo.fit(songBPM: supportProfile.analysis.bpm, targetBPM: targetBPM, maxStretch: tuning.maxStretch)
        let tempoScore: Double = (fitA.gridAligned && fitB.gridAligned) ? 1.0 : 0.25

        // Vocal collision: one dominant vocal source at a time.
        let vocalScore = max(0, 1 - max(0, dominant.vocal + support.vocal - 1.1))

        // Bass collision: two bass-heavy drops can't share the low end.
        let bothDrops = dominant.label == .chorus && support.label == .chorus
        let bassLoad = dominantProfile.analysis.bassDensity + supportProfile.analysis.bassDensity
        let bassScore: Double = bothDrops && bassLoad > 1.3 ? 0.3 : 1.0

        // Spectral balance: a sparse support reads better under a full mix.
        let spectralScore = max(0, 1 - max(0, dominant.energy + support.energy - 1.35))

        let confidence = min(dominant.confidence, support.confidence)
        let score = harmonic.score * 0.30
            + tempoScore * 0.25
            + vocalScore * 0.20
            + bassScore * 0.13
            + spectralScore * 0.12
        let weighted = score * (0.6 + 0.4 * confidence)

        var overlapBars = 0
        if weighted >= tuning.minOverlapScore, fitA.gridAligned, fitB.gridAligned,
           confidence >= tuning.lowConfidenceThreshold {
            overlapBars = weighted >= 0.72 ? 2 : 1
        }

        // If only an extreme shift would rescue the harmony, don't overlap.
        let correction = harmonic.score >= 0.5 ? harmonic.shiftSemitones : 0
        if abs(correction) > tuning.maxCorrectivePitchSemitones { overlapBars = 0 }

        return AutoDirectionalCompat(
            score: weighted,
            pitchCorrectionSemitones: overlapBars > 0 ? correction : 0,
            overlapBars: overlapBars
        )
    }
}

// MARK: - N-song mashup hook gates

/// How an added song may appear over the club bed.
nonisolated enum AutoMashupHookGate: String, Sendable {
    /// Full 8–16 bar vocal hook on a drop or cameo island.
    case fullHook
    /// Short teaser / chop only (key or stretch is borderline).
    case cameoChop
    /// Do not place as a lead vocal.
    case skip
}

nonisolated enum AutoMashupCompat {

    struct Verdict: Sendable {
        var gate: AutoMashupHookGate
        var keyScore: Double
        var vocalRatio: Double
        var detail: String
    }

    /// Per-added-song compatibility vs the chosen club bed.
    static func hookGate(
        hook: AutoSongProfile,
        bed: AutoSongProfile,
        targetBPM: Double,
        tuning: AutoTuning
    ) -> Verdict {
        // Prefer Camelot same / ±1 / relative (via AutoKey.score + ≤2 st fix).
        let key = AutoKey.bestCorrection(
            AutoKey.parse(bed.analysis.key),
            AutoKey.parse(hook.analysis.key),
            maxShift: min(2, tuning.maxCorrectivePitchSemitones)
        )
        let fit = AutoTempo.fit(
            songBPM: hook.analysis.bpm,
            targetBPM: targetBPM,
            maxStretch: tuning.maxStretch
        )
        let stretchOK = fit.gridAligned && abs(fit.ratio - 1) <= tuning.maxStretch + 0.0001
        let vocalRatio = stretchOK ? fit.ratio : 1.0

        if key.score < 0.40 {
            return Verdict(gate: .skip, keyScore: key.score, vocalRatio: 1, detail: "key clash beyond Camelot neighborhood / ±2 st")
        }
        if !stretchOK {
            // Far stretch — allow a short chop at native tempo only if key is OK.
            if key.score >= 0.5 {
                return Verdict(gate: .cameoChop, keyScore: key.score, vocalRatio: 1,
                               detail: "stretch gate failed — cameo chop at native tempo")
            }
            return Verdict(gate: .skip, keyScore: key.score, vocalRatio: 1, detail: "stretch would wreck the vocal")
        }
        if key.score < 0.5 {
            return Verdict(gate: .cameoChop, keyScore: key.score, vocalRatio: vocalRatio,
                           detail: "weak Camelot — short cameo only")
        }
        if abs(key.shiftSemitones) > 2 {
            return Verdict(gate: .cameoChop, keyScore: key.score, vocalRatio: vocalRatio,
                           detail: "vocal pitch would exceed ±2 st — cameo only")
        }
        return Verdict(gate: .fullHook, keyScore: key.score, vocalRatio: vocalRatio,
                       detail: "full hook over bed")
    }

    /// True when a guest should land in the breakdown runway (ballad / low energy
    /// against a peak-time bed) rather than a slam drop.
    static func needsBreakdownRunway(guest: AutoSongProfile, bed: AutoSongProfile) -> Bool {
        let guestE = guest.analysis.meanEnergy(from: 0, to: guest.analysis.durationSeconds)
        let bedE = bed.analysis.meanEnergy(from: 0, to: bed.analysis.durationSeconds)
        return guestE < 0.45 && bedE > 0.65
    }
}
