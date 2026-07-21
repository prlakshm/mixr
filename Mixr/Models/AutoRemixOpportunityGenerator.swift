import Foundation

// MARK: - Opportunity Generator
//
// Scans the whole song and proposes phrase-aligned transformation
// opportunities from MEASURED evidence: repeat similarity (gated by
// removability class and hook differentiation), energy rises and falls,
// vocal phrase endings and instrumental windows, and structural edges.
// Every opportunity carries typed evidence, a confidence, and an
// audibility contract predicted from the zone's own measured content —
// a transformation the listener could not hear is proposed weak and the
// recipe planner rejects it.
//
// Similarity is NEVER redundancy by itself: shorten candidates on
// vocal-heavy non-hook material are emitted vocal-unsafe so the recipe
// planner records the vocalProtection rejection; hook instances are
// shorten-eligible only when classified nearDuplicate.

enum AutoRemixOpportunityGenerator {

    nonisolated static func opportunities(
        structure: AutoRemixStructureMap,
        analysis: SongAnalysis,
        tuning: AutoTuning = .standard
    ) -> [AutoRemixOpportunity] {
        guard let signal = analysis.signal, !structure.phrases.isEmpty else { return [] }

        var out: [AutoRemixOpportunity] = []
        let bar = analysis.barSeconds
        let usable = structure.usableRange
        // Opportunity confidence is the CALIBRATED analysis confidence —
        // NOT overallConfidence × beatConfidence, which compounds toward
        // zero on real audio (two ~0.6 signals → 0.36, below every
        // selection floor). Real songs measure analysisConfidence ≈
        // 0.55–1.0. Per-cut beat/phrase reliability is enforced
        // separately by the recipe planner's LOCAL grid check, so this
        // number should reflect overall trust, not be double-penalised.
        let base = max(analysis.analysisConfidence, signal.overallConfidence)
        let hop = signal.hopSeconds

        func energyMean(_ from: Double, _ to: Double) -> Double {
            guard hop > 0, !signal.energyCurve.isEmpty, to > from else { return 0 }
            let lo = max(0, Int(from / hop))
            let hi = min(signal.energyCurve.count - 1, Int(to / hop))
            guard hi >= lo else { return 0 }
            var s = 0.0
            for i in lo...hi { s += signal.energyCurve[i] }
            return s / Double(hi - lo + 1)
        }
        func vocalMean(_ from: Double, _ to: Double) -> Double {
            guard hop > 0, !signal.vocalPresenceCurve.isEmpty, to > from else { return 0 }
            let lo = max(0, Int(from / hop))
            let hi = min(signal.vocalPresenceCurve.count - 1, Int(to / hop))
            guard hi >= lo else { return 0 }
            var s = 0.0
            for i in lo...hi { s += signal.vocalPresenceCurve[i] }
            return s / Double(hi - lo + 1)
        }

        // ── Boundary-anchored DSP opportunities at every phrase edge ──
        for phrase in structure.phrases.dropFirst() {
            let t = phrase.startSeconds
            let rise = energyMean(t, t + 4) - energyMean(t - 4, t)
            let region = structure.regionIndex(of: t)

            // Filtered build into a measured lift.
            if rise >= 0.15, t - bar * 4 >= usable.lowerBound + bar * 4 {
                let zoneStart = t - bar * 4
                let zoneEnergy = energyMean(zoneStart, t)
                let zoneDensity = structure.phrase(at: zoneStart)?.onsetDensity ?? 0
                // Predicted HF change from the zone's own transient/level
                // content: a dull, quiet zone predicts a change nobody
                // would hear.
                let predicted = 16.0 * min(1.0, zoneEnergy * (0.3 + zoneDensity))
                out.append(
                    AutoRemixOpportunity(
                        kind: .filteredBuild,
                        zoneStart: zoneStart,
                        zoneEnd: t,
                        anchorDownbeat: t,
                        region: region,
                        score: 0.55 + min(0.35, rise),
                        confidence: base,
                        vocalSafe: true,
                        evidence: [
                            AutoRemixEvidence(name: "energyRise", value: rise, measured: true),
                            AutoRemixEvidence(name: "zoneEnergy", value: zoneEnergy, measured: true),
                        ],
                        audibility: AudibilityContract(
                            musicalJustification: "measured energy rise into a phrase entrance",
                            expectedConsequence: "high frequencies sweep closed then reopen at the entrance",
                            measuredFeature: .hfEnergy,
                            predictedDelta: predicted,
                            minimumRequiredDelta: 3.0
                        )
                    )
                )
            }

            // Echo throw on a vocal phrase ending.
            let vocalBefore = vocalMean(t - bar * 4, t)
            let vocalAfter = vocalMean(t, t + bar * 4)
            if vocalBefore >= 0.45, vocalAfter <= vocalBefore * 0.5,
               t - bar >= usable.lowerBound {
                let predicted = -8.0 - (1 - min(1, vocalBefore)) * 6
                out.append(
                    AutoRemixOpportunity(
                        kind: .echoThrow,
                        zoneStart: t - bar,
                        zoneEnd: t,
                        anchorDownbeat: t,
                        region: region,
                        score: 0.6 + min(0.2, vocalBefore - vocalAfter),
                        confidence: base,
                        vocalSafe: true,
                        evidence: [
                            AutoRemixEvidence(name: "vocalPhraseEnd", value: vocalBefore - vocalAfter, measured: true)
                        ],
                        audibility: AudibilityContract(
                            musicalJustification: "vocal phrase ends into an instrumental window",
                            expectedConsequence: "the last phrase echoes into the next section",
                            measuredFeature: .echoTailEnergy,
                            predictedDelta: predicted,
                            minimumRequiredDelta: -20.0
                        )
                    )
                )
            }

            // Partial dropout (deep attenuation + filter) before a return.
            if rise >= 0.2, t - bar >= usable.lowerBound + bar * 8 {
                out.append(
                    AutoRemixOpportunity(
                        kind: .partialDropout,
                        zoneStart: t - bar * 0.5,
                        zoneEnd: t,
                        anchorDownbeat: t,
                        region: region,
                        score: 0.5 + min(0.3, rise),
                        confidence: base,
                        vocalSafe: vocalMean(t - bar * 0.5, t) < 0.45,
                        evidence: [
                            AutoRemixEvidence(name: "energyRise", value: rise, measured: true)
                        ],
                        audibility: AudibilityContract(
                            musicalJustification: "strong measured return after the boundary",
                            expectedConsequence: "the song drops away for two beats and slams back",
                            measuredFeature: .rmsLevel,
                            predictedDelta: 12.0 * min(1, energyMean(t - bar * 0.5, t) + 0.3),
                            minimumRequiredDelta: 6.0
                        )
                    )
                )
            }
        }

        // ── Shorten candidates: contiguous repeats of earlier material ──
        // Emitted for ANY repeated run so vocal-protected rejections are
        // visible in the report; eligibility is enforced by the planner.
        out.append(contentsOf: shortenCandidates(structure: structure, analysis: analysis, base: base))

        // ── Hook-anchored treatments ──
        if let first = structure.hookInstances.first {
            for instance in structure.hookInstances.dropFirst() {
                let region = structure.regionIndex(of: instance.startSeconds)
                let isFinal = instance.endSeconds >= (structure.hookInstances.map(\.endSeconds).max() ?? 0) - 0.01

                if instance.differentiation == .intensified, isFinal {
                    // Enhance the differentiated final hook: intensity arc.
                    out.append(
                        AutoRemixOpportunity(
                            kind: .finalChorusLift,
                            zoneStart: instance.startSeconds,
                            zoneEnd: instance.endSeconds,
                            anchorDownbeat: instance.startSeconds,
                            region: region,
                            score: 0.72,
                            confidence: base,
                            vocalSafe: true,
                            evidence: [
                                AutoRemixEvidence(name: "hookIntensified", value: 1, measured: true)
                            ],
                            audibility: AudibilityContract(
                                musicalJustification: "final hook is measurably intensified — enhance, never remove",
                                expectedConsequence: "the final chorus gains an audible effect arc",
                                measuredFeature: .echoTailEnergy,
                                predictedDelta: -12.0,
                                minimumRequiredDelta: -22.0
                            )
                        )
                    )
                    // Beat-synchronous entrance loop.
                    out.append(
                        AutoRemixOpportunity(
                            kind: .loopStutter,
                            zoneStart: instance.startSeconds,
                            zoneEnd: instance.startSeconds + bar,
                            anchorDownbeat: instance.startSeconds,
                            region: region,
                            score: 0.58,
                            confidence: base,
                            vocalSafe: true,
                            evidence: [
                                AutoRemixEvidence(name: "hookIntensified", value: 1, measured: true)
                            ],
                            audibility: AudibilityContract(
                                musicalJustification: "stutter the intensified hook entrance",
                                expectedConsequence: "the hook's first bar repeats before it lands",
                                measuredFeature: .durationChange,
                                predictedDelta: 1,
                                minimumRequiredDelta: 1
                            )
                        )
                    )
                }
                _ = first
            }

            // Hook return: only when the song ends far from its last hook.
            if let lastHookEnd = structure.hookInstances.map(\.endSeconds).max(),
               usable.upperBound - lastHookEnd > bar * 24 {
                out.append(
                    AutoRemixOpportunity(
                        kind: .hookReturn,
                        zoneStart: first.startSeconds,
                        zoneEnd: first.startSeconds + bar * 8,
                        anchorDownbeat: usable.upperBound - bar * 8,
                        region: structure.regions.count - 1,
                        score: 0.5,
                        confidence: base * 0.9,
                        vocalSafe: true,
                        evidence: [
                            AutoRemixEvidence(name: "hookAbsenceAtEnd", value: 1, measured: true)
                        ],
                        audibility: AudibilityContract(
                            musicalJustification: "song ends far from its strongest material",
                            expectedConsequence: "the hook returns once for the close",
                            measuredFeature: .durationChange,
                            predictedDelta: 8,
                            minimumRequiredDelta: 4
                        )
                    )
                )
            }
        }

        // Deterministic order: score desc, then anchor.
        return out.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.anchorDownbeat < $1.anchorDownbeat
        }
    }

    // MARK: Shorten / outro candidates

    nonisolated private static func shortenCandidates(
        structure: AutoRemixStructureMap,
        analysis: SongAnalysis,
        base: Double
    ) -> [AutoRemixOpportunity] {
        var out: [AutoRemixOpportunity] = []
        let phrases = structure.phrases
        let bar = analysis.barSeconds
        guard phrases.count > 4 else { return [] }

        // Hook instances: shorten only near-duplicates (never the
        // protected first, never intensified/reduced/distinct).
        for instance in structure.hookInstances.dropFirst()
        where instance.differentiation == .nearDuplicate && instance.phraseIndices.count >= 2 {
            let cutPhrases = Array(instance.phraseIndices.suffix(2))
            let zoneStart = phrases[cutPhrases[0]].startSeconds
            let zoneEnd = phrases[cutPhrases[cutPhrases.count - 1]].endSeconds
            out.append(
                shortenOpportunity(
                    zoneStart: zoneStart, zoneEnd: zoneEnd,
                    structure: structure, bar: bar, base: base,
                    similarity: 0.9,
                    vocalSafe: true,
                    evidenceName: "nearDuplicateHook"
                )
            )
        }

        // Repeated non-hook runs: instrumental repeats are safe; vocal
        // repeats are emitted UNSAFE so the rejection is auditable.
        var i = 0
        while i < phrases.count {
            let phrase = phrases[i]
            defer { i += 1 }
            guard phrase.removability == .instrumental || phrase.removability == .vocalDistinct
            else { continue }
            // Best similarity to strictly earlier material of same class.
            var bestSim = 0.0
            for j in 0..<i where phrases[j].removability == phrase.removability {
                bestSim = max(bestSim, structure.similarity[i][j])
            }
            guard bestSim >= AutoRemixStructureMapBuilder.repeatSimilarity else { continue }
            // Contiguous run of repeated phrases (≥ 2 units = 8 bars).
            var runEnd = i
            while runEnd + 1 < phrases.count,
                  phrases[runEnd + 1].removability == phrase.removability,
                  (0..<i).contains(where: {
                      structure.similarity[runEnd + 1][$0] >= AutoRemixStructureMapBuilder.repeatSimilarity
                  }) {
                runEnd += 1
            }
            guard runEnd > i else { continue }
            out.append(
                shortenOpportunity(
                    zoneStart: phrases[i].startSeconds,
                    zoneEnd: phrases[runEnd].endSeconds,
                    structure: structure, bar: bar, base: base,
                    similarity: bestSim,
                    vocalSafe: phrase.removability == .instrumental,
                    evidenceName: phrase.removability == .instrumental
                        ? "repeatedInstrumental" : "repeatedVocalAccompaniment"
                )
            )
            i = runEnd
        }

        // Outro compression: trailing low-energy run ≥ 8 bars.
        let outroPhrases = phrases.suffix(while: { $0.removability == .outro })
        if outroPhrases.count >= 2, let firstOutro = outroPhrases.first {
            let zoneStart = firstOutro.startSeconds + bar * AutoRemixStructureMapBuilder.phraseBars
            let zoneEnd = phrases.last!.endSeconds
            if zoneEnd - zoneStart >= bar * 4 {
                out.append(
                    AutoRemixOpportunity(
                        kind: .outroCompress,
                        zoneStart: zoneStart,
                        zoneEnd: zoneEnd,
                        anchorDownbeat: zoneStart,
                        region: structure.regionIndex(of: zoneStart),
                        score: 0.55,
                        confidence: base,
                        vocalSafe: true,
                        evidence: [
                            AutoRemixEvidence(name: "decayingOutro", value: 1, measured: true)
                        ],
                        audibility: AudibilityContract(
                            musicalJustification: "long decaying outro after the final hook",
                            expectedConsequence: "the outro resolves in half the time",
                            measuredFeature: .durationChange,
                            predictedDelta: (zoneEnd - zoneStart) / bar,
                            minimumRequiredDelta: 4
                        )
                    )
                )
            }
        }

        return out
    }

    nonisolated private static func shortenOpportunity(
        zoneStart: Double,
        zoneEnd: Double,
        structure: AutoRemixStructureMap,
        bar: Double,
        base: Double,
        similarity: Double,
        vocalSafe: Bool,
        evidenceName: String
    ) -> AutoRemixOpportunity {
        AutoRemixOpportunity(
            kind: .shortenRepeat,
            zoneStart: zoneStart,
            zoneEnd: zoneEnd,
            anchorDownbeat: zoneStart,
            region: structure.regionIndex(of: zoneStart),
            score: 0.55 + 0.35 * similarity,
            confidence: base * similarity,
            vocalSafe: vocalSafe,
            evidence: [
                AutoRemixEvidence(name: evidenceName, value: similarity, measured: true)
            ],
            audibility: AudibilityContract(
                musicalJustification: "repeats earlier material (similarity \(String(format: "%.2f", similarity)))",
                expectedConsequence: "the arrangement tightens by \(Int(((zoneEnd - zoneStart) / bar).rounded())) bars",
                measuredFeature: .durationChange,
                predictedDelta: (zoneEnd - zoneStart) / bar,
                minimumRequiredDelta: 4
            )
        )
    }
}

private extension Array {
    /// Trailing elements matching a predicate (order preserved).
    func suffix(while predicate: (Element) -> Bool) -> [Element] {
        var out: [Element] = []
        for element in reversed() {
            if predicate(element) { out.append(element) } else { break }
        }
        return out.reversed()
    }
}
