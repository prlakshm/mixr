import Foundation

// MARK: - Transformation Opportunities
//
// The judgment layer's vocabulary: phrase-aligned, evidence-backed
// proposals for transforming a one-song remix, scored from MEASURED
// features. SFX never count as a transformation on their own — they may
// only reinforce a selected zone.

/// Supported transformation families. `isStructural` marks edits that
/// change source topology (they consume the structural intervention
/// budget: removals, rewinds, loops, reordering).
enum AutoTransformationKind: String, CaseIterable, Sendable, Equatable {
    case filteredBuild        // filtered reveal / build into an entrance
    case echoThrow            // echo throw on a phrase ending
    case partialDropout       // deep attenuation + filter before a return
    case shortenRepeat        // remove redundant bars from a repeat
    case hookReturn           // justified return to earlier hook material
    case loopStutter          // brief beat-synchronous loop
    case outroCompress        // shortened / compressed outro
    case finalChorusLift      // intensify a differentiated final hook
    case sfxAccent            // riser/impact reinforcing another zone

    nonisolated var isStructural: Bool {
        switch self {
        case .shortenRepeat, .hookReturn, .loopStutter, .outroCompress: true
        case .filteredBuild, .echoThrow, .partialDropout, .finalChorusLift, .sfxAccent: false
        }
    }

    /// True for kinds that count toward the non-SFX transformation target.
    nonisolated var isMeaningfulTransformation: Bool {
        self != .sfxAccent
    }
}

/// One piece of evidence backing an opportunity. `measured` separates
/// signal-derived values from duration-fraction heuristics in the report.
struct AutoRemixEvidence: Sendable, Equatable {
    var name: String
    var value: Double
    var measured: Bool
}

/// The audible feature a transformation is expected to change, and how
/// it is measured on rendered PCM.
enum AudibleFeature: String, Sendable, Equatable {
    case hfEnergy         // high-frequency energy over the zone
    case rmsLevel         // short-term level over the zone
    case echoTailEnergy   // energy in the bar after the zone
    case durationChange   // bars removed / repeated (plan-level)
    case rhythmDensity    // onsets per bar over the zone
}

/// The audibility contract every selected transformation must carry:
/// what should audibly change, by how much, and the floor below which
/// the transformation must be strengthened or rejected.
struct AudibilityContract: Sendable {
    var musicalJustification: String
    var expectedConsequence: String
    var measuredFeature: AudibleFeature
    /// Predicted change from the zone's measured content, dB
    /// (bars for durationChange).
    var predictedDelta: Double
    /// Selection floor for `predictedDelta`.
    var minimumRequiredDelta: Double
}

/// Verification ledger: prediction, portable-render measurement,
/// AVFoundation-export measurement, and human audition are SEPARATE
/// stages — passing an earlier stage never marks a later one done.
struct AudibilityLedger: Sendable {
    var predictedDelta: Double
    /// Filled by the portable A/B render (approximate effect models).
    var portableRenderDelta: Double?
    /// Filled only by the Mac/Xcode A/B export step — nil = PENDING.
    var exportDelta: Double?
    /// Set only by a human listening pass — never by code.
    var auditioned: Bool = false
}

/// One scored, phrase-aligned transformation proposal.
struct AutoRemixOpportunity: Sendable, Identifiable {
    var id: UUID = UUID()
    var kind: AutoTransformationKind
    /// Source seconds of the affected zone (phrase-aligned).
    var zoneStart: Double
    var zoneEnd: Double
    /// Measured downbeat the transformation anchors to.
    var anchorDownbeat: Double
    /// Index of the structural region containing the anchor.
    var region: Int
    var score: Double
    var confidence: Double
    /// True when vocal evidence clears the zone for hard edits.
    var vocalSafe: Bool
    var evidence: [AutoRemixEvidence]
    var audibility: AudibilityContract

    nonisolated var zoneDuration: Double { zoneEnd - zoneStart }
}

// MARK: - Recipe

/// Why a candidate was not selected. Every rejection is reported.
enum AutoRejectionReason: String, Sendable, Equatable {
    case belowConfidence
    case belowAudibilityFloor
    case vocalProtection
    case gridUnstable
    case budgetExhausted
    case spacing
    case hookProtected
    case duplicateKind
    case notNearDuplicate
    case continuousPassageProtected
    case removalCapReached
}

struct AutoRemixRejectedOpportunity: Sendable {
    var opportunity: AutoRemixOpportunity
    var reason: AutoRejectionReason
    /// Set when the opportunity was downgraded to a safer kind instead
    /// of dropped (e.g. structural → DSP under grid instability).
    var downgradedTo: AutoTransformationKind?
}

/// The selected transformation set plus the full audit trail.
struct AutoRemixRecipe: Sendable {
    var selected: [AutoRemixOpportunity]
    var rejected: [AutoRemixRejectedOpportunity]
    /// Soft targets that could not be met with valid material, with the
    /// reason each was missed (never satisfied by weakening floors).
    var unmetTargets: [String]
    /// Audibility ledger per selected opportunity id.
    var ledgers: [UUID: AudibilityLedger] = [:]

    nonisolated var structuralCount: Int {
        selected.filter { $0.kind.isStructural }.count
    }
    nonisolated var meaningfulCount: Int {
        selected.filter { $0.kind.isMeaningfulTransformation }.count
    }

    nonisolated static let empty = AutoRemixRecipe(selected: [], rejected: [], unmetTargets: [])
}
