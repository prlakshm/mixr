import Foundation

// MARK: - Ported mashup heuristics (reimplemented in Swift)
//
// Sources (ideas only — no vendored Python/Demucs/Mixxx JS):
//   • AutoMashUpper — Davies et al., IEEE TASLP 2014: mashability is LOCAL
//     per phrase (harmonic / rhythmic / spectral balance); search beat
//     offsets; transform to fit (pitch/stretch the bed, not the star vocal).
//   • AutoMashup 2025 — ax-le/automashup (BSD-3, GRETSI/arXiv 2508.06516):
//     explicit stem *roles* before mixing; compatibility is directional
//     (COCOLA). Mixr has no Demucs — use SongSignalFeatures vocal/bass/drum
//     curves as role proxies.
//   • Mixxx AutoDJ / midiAutoDJ phrase matching (behavior reimplemented):
//     transition = outro∩intro overlap; if intro > outro, delay the incoming
//     so the intro *ends* when the outro ends; similar BPM + long transition
//     → smooth crossfade; short + different BPM → spinback/tape-stop.

// MARK: - Stem role proxies (AutoMashup 2025 — no Demucs)

nonisolated enum AutoStemRoleProxy: String, Sendable {
    case bed
    case hook
    case mixed

    /// Bed fitness from drum/bass ownership vs vocal presence.
    /// Soft-caps raw drumConfidence so a star single at 1.00 cannot steal
    /// the bed from a groove partner at 0.71 (Britney crate lock).
    static func bedScore(for profile: AutoSongProfile) -> Double {
        let analysis = profile.analysis
        let vocal = analysis.meanVocalDensity(from: 0, to: analysis.durationSeconds)
        let drum = min(analysis.drumStrength, 0.72)
        let bass = analysis.bassDensity
        // Signal curves when present (AutoMashup role proxy without stems).
        var curveVocal = vocal
        var curveBass = bass
        if let signal = analysis.signal, !signal.vocalPresenceCurve.isEmpty {
            curveVocal = mean(signal.vocalPresenceCurve)
            if !signal.bassEnergyCurve.isEmpty {
                curveBass = mean(signal.bassEnergyCurve)
            }
        }
        let softPrefer = (1.0 - min(1.0, analysis.drumStrength)) * 0.20
        return drum * 0.32 + curveBass * 0.48 + (1.0 - min(1, curveVocal)) * 0.20 + softPrefer
    }

    /// Hook / Drop-1 vocal fitness — high vocal presence, not max drums.
    static func hookScore(for profile: AutoSongProfile) -> Double {
        let analysis = profile.analysis
        var vocal = analysis.meanVocalDensity(from: 0, to: analysis.durationSeconds)
        var bass = analysis.bassDensity
        if let signal = analysis.signal, !signal.vocalPresenceCurve.isEmpty {
            vocal = mean(signal.vocalPresenceCurve)
            if !signal.bassEnergyCurve.isEmpty {
                bass = mean(signal.bassEnergyCurve)
            }
        }
        // Star topline: vocal + hook affinity; penalize bed-like bass ownership.
        return vocal * 0.55 + profile.featureScore * 0.30 + (1.0 - min(1, bass)) * 0.15
    }

    static func classify(_ profile: AutoSongProfile) -> AutoStemRoleProxy {
        let bed = bedScore(for: profile)
        let hook = hookScore(for: profile)
        if bed > hook + 0.06 { return .bed }
        if hook > bed + 0.06 { return .hook }
        return .mixed
    }

    private static func mean(_ curve: [Double]) -> Double {
        guard !curve.isEmpty else { return 0.5 }
        return curve.reduce(0, +) / Double(curve.count)
    }
}

// MARK: - Locked mashup pair (title/groove)

/// Product locks that measurement must not invert. Stem kick energy is for
/// pulse/one-kick only — it does not crown the club bed.
nonisolated enum AutoMashupRoleLock {
    static func isOopsTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("oops") || t.contains("did it again")
    }

    static func isBOMTTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("baby one more time") || t.contains("hit me baby")
    }

    /// Oops I Did It Again = bed when paired with Baby One More Time.
    static func britneyBed(in pool: [AutoSongProfile]) -> AutoSongProfile? {
        let oops = pool.first { isOopsTitle($0.title) }
        let bomt = pool.first { isBOMTTitle($0.title) }
        guard let oops, bomt != nil else { return nil }
        return oops
    }
}

// MARK: - Local mashability (AutoMashUpper 2014)

/// Best 8–16 bar island pairing between a guest hook phrase and a bed
/// groove — mashability is LOCAL, not whole-song (Davies et al. 2014).
struct AutoMashabilityIsland: Sendable {
    var guestStart: Double
    var bedStart: Double
    var bars: Int
    var score: Double
    var harmonic: Double
    var rhythmic: Double
    var spectral: Double
}

nonisolated enum AutoMashability {

    /// Search chorus/teaser islands on `guest` against groove/chorus islands
    /// on `bed`, trying beat offsets on the bed. Asymmetric: scores how the
    /// guest sits *over* the bed (pitch/stretch the bed elsewhere).
    static func bestIsland(
        guest: AutoSongProfile,
        bed: AutoSongProfile,
        wantBars: Int = 16,
        targetBPM: Double,
        tuning: AutoTuning
    ) -> AutoMashabilityIsland? {
        let bars = max(8, min(16, wantBars))
        let guestPhrases = guest.candidates.filter {
            ($0.label == .chorus || $0.label == .teaser || $0.label == .groove)
                && $0.barCount >= min(8, bars)
        }
        let bedPhrases = bed.candidates.filter {
            ($0.label == .groove || $0.label == .chorus || $0.label == .build)
                && $0.barCount >= 4
        }
        guard !guestPhrases.isEmpty, !bedPhrases.isEmpty else { return nil }

        let bedBeat = bed.analysis.barSeconds / 4.0
        let guestBeat = guest.analysis.barSeconds / 4.0
        let windowSec = Double(bars) * (240.0 / max(targetBPM, 40))

        // Harmonic under bed transposition (AutoMashUpper: chroma × key shift).
        let harmonic = AutoKey.bestCorrection(
            AutoKey.parse(guest.analysis.key),
            AutoKey.parse(bed.analysis.key),
            maxShift: tuning.maxCorrectivePitchSemitones
        )

        let guestFit = AutoTempo.fit(
            songBPM: guest.analysis.bpm, targetBPM: targetBPM, maxStretch: tuning.maxStretch
        )
        let bedFit = AutoTempo.fit(
            songBPM: bed.analysis.bpm, targetBPM: targetBPM, maxStretch: tuning.maxInstrumentalStretch
        )
        let rhythmicBase: Double = (guestFit.gridAligned && bedFit.gridAligned) ? 1.0
            : (guestFit.gridAligned || bedFit.gridAligned) ? 0.55 : 0.25

        let guestTitleStart = AutoChorusIsland.bestEntrance(
            signal: guest.analysis.signal,
            downbeats: guest.analysis.downbeats,
            barSeconds: guest.analysis.barSeconds,
            duration: guest.analysis.durationSeconds,
            introEnd: guest.analysis.introCandidate?.endSeconds ?? guest.analysis.barSeconds * 8
        )?.startSeconds

        var best: AutoMashabilityIsland?

        for g in guestPhrases {
            let gStart = g.startSeconds
            let gDur = min(windowSec, g.durationSeconds)
            guard gDur >= Double(min(8, bars)) * guestBeat * 3.5 else { continue }

            for b in bedPhrases {
                // Beat-offset search on the bed phrase (AutoMashUpper).
                let maxOffsets = max(1, min(bars * 4, Int((b.durationSeconds / max(bedBeat, 0.05)).rounded())))
                for offset in 0..<maxOffsets {
                    let bStart = b.startSeconds + Double(offset) * bedBeat
                    guard bStart + gDur <= bed.analysis.durationSeconds + 0.25 else { continue }

                    let gBass = sectionBass(guest, from: gStart, to: gStart + gDur)
                    let bBass = sectionBass(bed, from: bStart, to: bStart + gDur)
                    // Spectral balance: refuse two bass-heavy drops (AutoMashUpper).
                    let spectral = max(0.15, 1.0 - max(0, gBass + bBass - 1.15))

                    let energyCorr = energyCorrelation(
                        a: guest.analysis, aStart: gStart,
                        b: bed.analysis, bStart: bStart,
                        duration: gDur,
                        step: max(guestBeat, bedBeat) * 0.5
                    )
                    // Prefer complementary energy (hook over rolling bed), not identical walls.
                    let rhythmic = rhythmicBase * (0.55 + 0.45 * (1.0 - abs(energyCorr - 0.25)))

                    let hookBoost = g.label == .chorus ? 0.08 : 0
                    let titleBoost: Double
                    if let guestTitleStart, abs(gStart - guestTitleStart) <= guest.analysis.barSeconds * 2 {
                        titleBoost = 0.16
                    } else {
                        titleBoost = 0
                    }
                    let score = harmonic.score * 0.40
                        + rhythmic * 0.35
                        + spectral * 0.25
                        + hookBoost
                        + titleBoost

                    if best == nil || score > (best?.score ?? 0) + 0.001 {
                        best = AutoMashabilityIsland(
                            guestStart: gStart,
                            bedStart: bStart,
                            bars: bars,
                            score: score,
                            harmonic: harmonic.score,
                            rhythmic: rhythmic,
                            spectral: spectral
                        )
                    }
                }
            }
        }
        return best
    }

    private static func sectionBass(_ profile: AutoSongProfile, from: Double, to: Double) -> Double {
        if let signal = profile.analysis.signal, !signal.bassEnergyCurve.isEmpty {
            return meanCurve(signal.bassEnergyCurve, hop: signal.hopSeconds, from: from, to: to)
        }
        // Proxy: bass density × local energy.
        return profile.analysis.bassDensity * profile.analysis.meanEnergy(from: from, to: to)
    }

    private static func meanCurve(_ curve: [Double], hop: Double, from: Double, to: Double) -> Double {
        guard hop > 0, !curve.isEmpty else { return 0.5 }
        let lo = max(0, Int(from / hop))
        let hi = min(curve.count - 1, Int(to / hop))
        guard hi >= lo else { return 0.5 }
        var sum = 0.0
        for i in lo...hi { sum += curve[i] }
        return sum / Double(hi - lo + 1)
    }

    /// Cheap beat-window energy correlation (−1…1 style, clamped 0…1).
    private static func energyCorrelation(
        a: SongAnalysis, aStart: Double,
        b: SongAnalysis, bStart: Double,
        duration: Double,
        step: Double
    ) -> Double {
        var pairs: [(Double, Double)] = []
        var t = 0.0
        let stepSec = max(0.2, step)
        while t + stepSec * 0.5 < duration {
            let ea = a.meanEnergy(from: aStart + t, to: aStart + t + stepSec)
            let eb = b.meanEnergy(from: bStart + t, to: bStart + t + stepSec)
            pairs.append((ea, eb))
            t += stepSec
        }
        guard pairs.count >= 2 else { return 0.5 }
        let meanA = pairs.map(\.0).reduce(0, +) / Double(pairs.count)
        let meanB = pairs.map(\.1).reduce(0, +) / Double(pairs.count)
        var num = 0.0, denA = 0.0, denB = 0.0
        for (ea, eb) in pairs {
            let da = ea - meanA
            let db = eb - meanB
            num += da * db
            denA += da * da
            denB += db * db
        }
        let den = (denA * denB).squareRoot()
        guard den > 1e-9 else { return 0.5 }
        return min(1, max(0, (num / den + 1) * 0.5))
    }
}

// MARK: - Phrase handoff (Mixxx AutoDJ behavior)

/// How to overlap an outgoing phrase with an incoming phrase so the join
/// is outro∩intro — not a hole then a new block.
struct AutoPhraseHandoff: Sendable {
    /// Temporal overlap (seconds) with equal-power crossfade when beatmatched.
    var overlapSeconds: Double
    /// Delay the incoming start so a long intro finishes with the outro.
    var incomingDelaySeconds: Double
    /// Short + different BPM → tape-stop / spinback accent (Mixxx GSoC hybrid).
    var preferTapeStop: Bool
    /// Similar BPM + long transition → smooth crossfade.
    var preferLongCrossfade: Bool
}

nonisolated enum AutoPhraseMatch {

    /// Mixxx AutoDJ-style phrase matching.
    /// - Transition length ≈ overlap of outro + intro material.
    /// - If incoming intro is longer than outgoing outro, delay incoming so
    ///   the intro *ends* when the outro ends (drop on time).
    /// - If BPM is far apart, keep overlap short and prefer tape-stop SFX
    ///   instead of wrecking the vocal with stretch.
    static func plan(
        outgoingDuration: Double,
        incomingIntroDuration: Double,
        beatSeconds: Double,
        barSeconds: Double,
        bpmAligned: Bool,
        stretchFar: Bool
    ) -> AutoPhraseHandoff {
        let outro = max(beatSeconds, outgoingDuration)
        let intro = max(beatSeconds, incomingIntroDuration)
        let naturalOverlap = min(outro, intro)

        var delay = 0.0
        // Incoming intro longer than outgoing outro → start later so endings meet.
        if intro > outro + beatSeconds * 0.5 {
            delay = intro - outro
        }

        let longOK = bpmAligned && !stretchFar && naturalOverlap >= barSeconds * 0.75
        let overlap: Double
        if longOK {
            overlap = min(barSeconds * 2, max(barSeconds, naturalOverlap))
        } else if bpmAligned {
            overlap = min(barSeconds, max(beatSeconds * 2, naturalOverlap * 0.5))
        } else {
            // Far BPM: cameo-style short join + FX cover (tape stop).
            overlap = max(beatSeconds, min(beatSeconds * 2, naturalOverlap * 0.35))
        }

        return AutoPhraseHandoff(
            overlapSeconds: overlap,
            incomingDelaySeconds: delay,
            preferTapeStop: stretchFar || !bpmAligned,
            preferLongCrossfade: longOK
        )
    }
}
