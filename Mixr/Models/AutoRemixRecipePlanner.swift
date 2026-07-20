import Foundation

// MARK: - Recipe Planner
//
// Selects a varied, distributed set of transformations from the scored
// opportunities.
//
// HARD constraints (never relaxed):
//   • every selection independently passes its confidence, evidence,
//     vocal-safety, grid-stability, and audibility floors
//   • structural intervention budget of 2 (removals, rewinds, hook
//     returns, loops all count; SFX never count)
//   • protected/intensified/reduced/distinct hook instances are never
//     removed; the first complete hook is untouched by ANY edit
//   • a continuous ≥ 32-bar passage survives; total removal ≤ 20%
//   • spacing between interventions
//
// SOFT targets (preferences, reported when unmet, never satisfied by
// weakening a floor): 3–5 zones, ≥ 3 regions, ≥ 2 non-SFX.
enum AutoRemixRecipePlanner {

    nonisolated static let structuralBudget = 2
    nonisolated static let dspBudget = 3
    nonisolated static let maxZones = 5
    nonisolated static let structuralConfidenceFloor = 0.55
    nonisolated static let dspConfidenceFloor = 0.45
    nonisolated static let localGridFloor = 0.5
    nonisolated static let removalCapFraction = 0.2

    nonisolated static func recipe(
        from opportunities: [AutoRemixOpportunity],
        structure: AutoRemixStructureMap,
        tuning: AutoTuning = .standard,
        seed: UInt64 = 0
    ) -> AutoRemixRecipe {
        var selected: [AutoRemixOpportunity] = []
        var rejected: [AutoRemixRejectedOpportunity] = []
        let bar = structure.beatSecondsHint * 4
        let usable = structure.usableRange
        let span = max(usable.upperBound - usable.lowerBound, 1)

        func reject(_ opportunity: AutoRemixOpportunity, _ reason: AutoRejectionReason) {
            rejected.append(
                AutoRemixRejectedOpportunity(opportunity: opportunity, reason: reason, downgradedTo: nil)
            )
        }

        // Deterministic priority: score desc, anchor asc.
        let ordered = opportunities.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.anchorDownbeat < $1.anchorDownbeat
        }

        var removedSeconds = 0.0

        for candidate in ordered {
            if selected.count >= maxZones {
                reject(candidate, .budgetExhausted)
                continue
            }

            let floor = candidate.kind.isStructural ? structuralConfidenceFloor : dspConfidenceFloor
            if candidate.confidence < floor {
                reject(candidate, .belowConfidence)
                continue
            }
            if candidate.audibility.predictedDelta < candidate.audibility.minimumRequiredDelta {
                reject(candidate, .belowAudibilityFloor)
                continue
            }
            if candidate.kind.isStructural, !candidate.vocalSafe {
                reject(candidate, .vocalProtection)
                continue
            }
            if candidate.kind.isStructural {
                let edgeConfidence = min(
                    structure.localBeatConfidence(at: candidate.zoneStart),
                    structure.localBeatConfidence(at: candidate.zoneEnd)
                )
                if edgeConfidence < localGridFloor
                    || structure.gridDriftFractionOfBeat > 0.1
                       && edgeConfidence < 0.75 {
                    reject(candidate, .gridUnstable)
                    continue
                }
            }

            // Hook protection: nothing touches the protected FIRST
            // instance; structural edits never touch any protected
            // (non-near-duplicate) instance.
            var hookBlocked = false
            var notNearDuplicate = false
            for (index, instance) in structure.hookInstances.enumerated() {
                let overlaps = max(candidate.zoneStart, instance.startSeconds)
                    < min(candidate.zoneEnd, instance.endSeconds) - 0.01
                guard overlaps else { continue }
                if index == 0 {
                    hookBlocked = true
                } else if candidate.kind == .shortenRepeat, instance.differentiation != .nearDuplicate {
                    notNearDuplicate = true
                } else if candidate.kind.isStructural, candidate.kind != .loopStutter,
                          instance.isProtected {
                    hookBlocked = true
                }
            }
            if notNearDuplicate {
                reject(candidate, .notNearDuplicate)
                continue
            }
            if hookBlocked {
                reject(candidate, .hookProtected)
                continue
            }

            // Budgets.
            let structuralCount = selected.filter { $0.kind.isStructural }.count
            let dspCount = selected.filter { !$0.kind.isStructural }.count
            if candidate.kind.isStructural, structuralCount >= structuralBudget {
                reject(candidate, .budgetExhausted)
                continue
            }
            if !candidate.kind.isStructural, dspCount >= dspBudget {
                reject(candidate, .budgetExhausted)
                continue
            }

            // Variety: one use per kind.
            if selected.contains(where: { $0.kind == candidate.kind }) {
                reject(candidate, .duplicateKind)
                continue
            }

            // Spacing between intervention anchors.
            let minSpacing = (candidate.kind.isStructural ? 16.0 : 8.0) * bar
            if selected.contains(where: { abs($0.anchorDownbeat - candidate.anchorDownbeat) < minSpacing }) {
                reject(candidate, .spacing)
                continue
            }

            // Removal cap.
            if candidate.kind == .shortenRepeat || candidate.kind == .outroCompress {
                let removes = candidate.zoneDuration
                if (removedSeconds + removes) > span * removalCapFraction {
                    reject(candidate, .removalCapReached)
                    continue
                }
            }

            // A continuous ≥ 32-bar passage must survive selection.
            if bar > 0 {
                var edges: [Double] = [usable.lowerBound]
                for z in (selected + [candidate]).sorted(by: { $0.zoneStart < $1.zoneStart }) {
                    edges.append(z.zoneStart)
                    edges.append(z.zoneEnd)
                }
                edges.append(usable.upperBound)
                var longest = 0.0
                var i = 0
                while i + 1 < edges.count {
                    longest = max(longest, edges[i + 1] - edges[i])
                    i += 2
                }
                if longest < 32 * bar {
                    reject(candidate, .continuousPassageProtected)
                    continue
                }
            }

            if candidate.kind == .shortenRepeat || candidate.kind == .outroCompress {
                removedSeconds += candidate.zoneDuration
            }
            selected.append(candidate)
        }

        // ── Soft targets: report, never pad ──
        var unmet: [String] = []
        if selected.count < 3 {
            unmet.append(
                "fewer than 3 transformation zones (\(selected.count)) — no further opportunities passed their floors"
            )
        }
        let regions = Set(selected.map(\.region))
        if regions.count < 3 {
            unmet.append(
                "zones cover \(regions.count) region(s) — valid material was not spread across three"
            )
        }
        let meaningful = selected.filter { $0.kind.isMeaningfulTransformation }.count
        if meaningful < 2 {
            unmet.append("fewer than 2 non-SFX transformations (\(meaningful))")
        }

        // Ledgers: prediction recorded; portable/export stages are filled
        // by their own measurements; audition only by a human.
        var ledgers: [UUID: AudibilityLedger] = [:]
        for s in selected {
            ledgers[s.id] = AudibilityLedger(
                predictedDelta: s.audibility.predictedDelta,
                portableRenderDelta: nil,
                exportDelta: nil,
                auditioned: false
            )
        }

        return AutoRemixRecipe(
            selected: selected.sorted { $0.zoneStart < $1.zoneStart },
            rejected: rejected,
            unmetTargets: unmet,
            ledgers: ledgers
        )
    }
}
