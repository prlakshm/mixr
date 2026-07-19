import Foundation

// MARK: - Recipe Planner
//
// Selects a varied, distributed set of transformations from the scored
// opportunities.
//
// HARD constraints (never relaxed):
//   • every selected transformation independently passes its confidence,
//     evidence, vocal-safety, grid-stability, and audibility floors
//   • structural intervention budget (removals, rewinds, hook returns,
//     loops, reordering count; SFX never count)
//   • first complete hook instance untouched; intensified / reduced /
//     structurally distinct hook instances protected from removal
//   • one continuous ≥32-bar passage untouched; total removal cap
//   • spacing between interventions
//
// SOFT targets (preferences, reported when unmet, never used to select
// or strengthen a weak transformation):
//   • 3–5 zones, ≥3 regions, ≥2 non-SFX transformations
enum AutoRemixRecipePlanner {

    /// BASELINE STUB: selects nothing and reports every target unmet —
    /// the transformation layer supplies the real planner.
    nonisolated static func recipe(
        from opportunities: [AutoRemixOpportunity],
        structure: AutoRemixStructureMap,
        tuning: AutoTuning = .standard,
        seed: UInt64 = 0
    ) -> AutoRemixRecipe {
        AutoRemixRecipe(
            selected: [],
            rejected: [],
            unmetTargets: [
                "no transformation zones selected (recipe planner not implemented)",
            ]
        )
    }
}
