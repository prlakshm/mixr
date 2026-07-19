import Foundation

// MARK: - Opportunity Generator
//
// Scans the whole song and proposes phrase-aligned transformation
// opportunities from measured evidence: repeat similarity (gated by
// removability class), energy rises/falls, novelty, vocal windows and
// phrase endings, structural boundaries, and 8/16/32-bar completions.
// Every opportunity carries typed evidence, a confidence, and an
// audibility contract predicted from the zone's own measured content.

enum AutoRemixOpportunityGenerator {

    /// BASELINE STUB: proposes nothing — the transformation layer
    /// supplies the real generator.
    nonisolated static func opportunities(
        structure: AutoRemixStructureMap,
        analysis: SongAnalysis,
        tuning: AutoTuning = .standard
    ) -> [AutoRemixOpportunity] {
        []
    }
}
