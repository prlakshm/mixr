#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Auto Remix Plan
//
// The plan-first contract for Auto's Entire Project scope:
//
//   AutoSectionCatalog  → scored candidate sections per song
//   AutoRemixPlanner    → AutoRemixPlan (placements + effect/SFX events)
//   AutoRemixValidator  → repaired plan + warnings (never applies invalid)
//   AutoRemixApplier    → concrete MixrTrack clip arrays
//
// Timed effect automation is not yet supported by the clip model, so the
// planner emits placements that are ALREADY split at effect boundaries
// (head / body / tail segments) and stores the closest equivalent
// clip-level ClipEffectSettings on each segment.

enum AutoRemixMode: String, Sendable {
    case remix = "Remix"
    case mashup = "Mashup"
}

enum AutoPlacementRole: String, Sendable {
    case dominant
    case supporting
    case transition
}

/// The six transition vocabularies Auto composes handoffs from, plus the
/// low-confidence fallback. One primary recipe per handoff — never a stack.
enum AutoTransitionRecipe: String, Sendable, CaseIterable {
    case blurReveal = "Blur Reveal"
    case vocalEchoOut = "Vocal Echo-Out"
    case reverseEntrance = "Reverse Entrance"
    case flangerBuild = "Flanger Build"
    case atmosphericHandoff = "Atmospheric Handoff"
    case hardHypeCut = "Hard Hype Cut"
    case cleanCrossfade = "Clean Crossfade"
    case none = "None"
}

// MARK: - Structured Decisions

/// Concrete planning choices recorded during plan generation / repair.
/// User-facing copy is derived from these — never reconstructed by guessing
/// from the final clip list.
enum AutoDecisionKind: String, Sendable, Equatable {
    case skippedWeakSection
    case shortenedLowEnergySection
    case returnedToHook
    case avoidedVocalOverlap
    case usedLowConfidenceFallback
    case selectedAnchor
    case replacedComplexOverlapWithHardCut
    case addedRiserIntoDrop
    case removedInvalidSFX
    case repairedTimelineGap
    case beatmatchedSong
    case shortenedForMaterial
    case skippedIntro
    case pitchedContrastPhrase
    case pitchCorrectedOverlap
    case savedStrongestForPeak
    case duoAlternationFallback
    case excludedLowConfidenceSong
    case choseClubTempo
    case wroteClubPulse
    case skippedSecondKick
    case imposedClubEnergyCurve
    case assignedMashupRoles
    case refusedMashupPair
    case allowedPredropVoid
    case choseClubFlavor
    case usedCameoOnly
    case skippedIncompatibleHook
}

struct AutoDecision: Sendable, Equatable {
    var kind: AutoDecisionKind
    /// Display name of the song involved, when relevant.
    var songTitle: String?
    /// Compact detail (role name, bar count, pitch semitones, purpose, …).
    var detail: String?

    /// Concise sentence for the summary sheet.
    var userFacingSentence: String {
        let song = songTitle ?? "a song"
        switch kind {
        case .skippedWeakSection:
            return "Skipped \(song)'s \(detail ?? "weak section")."
        case .shortenedLowEnergySection:
            return "Shortened \(song)'s low-energy \(detail ?? "section")."
        case .returnedToHook:
            return "Returned to \(song)'s \(detail ?? "hook") for the final peak."
        case .avoidedVocalOverlap:
            return "Avoided overlapping dense vocals between \(song)\(detail.map { " and \($0)" } ?? "")."
        case .usedLowConfidenceFallback:
            return "Used clean phrase-aligned handoffs for \(song) due to low analysis confidence."
        case .selectedAnchor:
            return "Selected \(song) as the anchor\(detail.map { " (\($0))" } ?? "")."
        case .replacedComplexOverlapWithHardCut:
            return "Replaced a complex overlap with a hard cut\(detail.map { " before \($0)" } ?? "")."
        case .addedRiserIntoDrop:
            return "Used a \(detail ?? "riser") into the drop."
        case .removedInvalidSFX:
            return "Removed an invalid SFX event\(detail.map { " (\($0))" } ?? "")."
        case .repairedTimelineGap:
            return "Repaired an accidental timeline gap\(detail.map { " — \($0)" } ?? "")."
        case .beatmatchedSong:
            if let detail { return "Beatmatched \(song) \(detail)." }
            return "Beatmatched \(song)."
        case .shortenedForMaterial:
            return "Shortened \(song)'s \(detail ?? "section") to fit available material."
        case .skippedIntro:
            return "Skipped \(song)'s intro and led with its strongest material."
        case .pitchedContrastPhrase:
            return "Pitched a short \(song) phrase for contrast\(detail.map { " (\($0))" } ?? "")."
        case .pitchCorrectedOverlap:
            return "Pitch-corrected \(song)'s overlap\(detail.map { " by \($0)" } ?? "") for key compatibility."
        case .savedStrongestForPeak:
            return "Saved \(song)'s strongest section for the final peak."
        case .duoAlternationFallback:
            return detail
                ?? "Could not reach the full A → B → A → B alternation without incomplete sections."
        case .excludedLowConfidenceSong:
            return "Excluded \(song): \(detail ?? "not enough timeline for a recognizable phrase")."
        case .choseClubTempo:
            return "Club tempo for \(song): \(detail ?? "pocket decision")."
        case .wroteClubPulse:
            return "Wrote a club pulse under \(song)\(detail.map { " — \($0)" } ?? "")."
        case .skippedSecondKick:
            return "Skipped a second kick on \(song)\(detail.map { " — \($0)" } ?? "")."
        case .imposedClubEnergyCurve:
            return "Imposed a club energy curve on \(song)\(detail.map { " — \($0)" } ?? "")."
        case .assignedMashupRoles:
            return detail ?? "Assigned mashup roles (hook vs club bed)."
        case .refusedMashupPair:
            return detail ?? "Refused a mashup pairing that would wreck the vocal."
        case .allowedPredropVoid:
            return "Left an intentional pre-drop void\(detail.map { " (\($0))" } ?? "")."
        case .choseClubFlavor:
            return "Club flavor: \(detail ?? "festival rewrite")."
        case .usedCameoOnly:
            return "Used \(song) as a short cameo\(detail.map { " — \($0)" } ?? "") rather than a full vocal drop."
        case .skippedIncompatibleHook:
            return "Skipped \(song) as a full hook\(detail.map { ": \($0)" } ?? "")."
        }
    }
}

// MARK: - Selected Section

/// One scored source section the planner chose to use.
struct AutoSelectedSection: Sendable {
    var songID: UUID
    var sourceStart: Double
    var sourceEnd: Double
    var phraseType: String        // "chorus", "groove", "build", …
    var barCount: Int
    var hookScore: Double
    var energyScore: Double
    var vocalDensity: Double
    var compatibilityRole: AutoPlacementRole
    var confidence: Double
}

// MARK: - Clip Placement

/// One concrete clip the applier will create. All times in seconds
/// (source side and timeline side); the applier converts to units.
struct AutoClipPlacement: Sendable {
    var songID: UUID
    /// Seconds into the source audio where this clip's content begins.
    var sourceStart: Double
    var timelineStart: Double
    var timelineDuration: Double
    /// Playback rate (beatmatch stretch). Source consumed =
    /// timelineDuration × tempoRatio.
    var tempoRatio: Double
    var volume: Double
    var fadeIn: ClipTransition
    var fadeOut: ClipTransition
    var effects: ClipEffectSettings
    var role: AutoPlacementRole
    /// Which arrangement slot this segment belongs to (for validation
    /// and the summary). Head/body/tail splits share one slotIndex so the
    /// summary treats them as a single song appearance.
    var slotIndex: Int
    /// True when this placement continues the SAME source material
    /// sample-exactly from the previous placement of this song (a segment
    /// split made only to change effects). Continuous edges get no fades
    /// of any kind — the audio underneath is continuous.
    var continuesPrevious: Bool = false
    /// > 0 when this placement deliberately OVERLAPS the previous
    /// placement of the same song by this many timeline seconds for a
    /// true equal-power crossfade. The validator only permits same-song
    /// overlap that is declared here.
    var overlapsPreviousSeconds: Double = 0

    nonisolated var timelineEnd: Double { timelineStart + timelineDuration }
    nonisolated var sourceDuration: Double { timelineDuration * tempoRatio }
    nonisolated var sourceEnd: Double { sourceStart + sourceDuration }
}

// MARK: - Internal Cut Record

/// Why an internal cut exists. There is no "variety" case on purpose —
/// cutting merely to add variety is not a valid reason.
enum AutoCutReason: String, Sendable, Equatable {
    /// Removes material that repeats already-heard content.
    case redundantRepeat
    /// Trims detected silence or DJ intro/outro filler at the edges.
    case edgeTrim
    /// An explicitly requested return to the hook for a final peak.
    case hookReturn
}

/// How a cut's transition is audibly covered.
enum AutoCutMasking: Equatable, Sendable {
    /// Equal-power overlap of the outgoing and incoming song regions.
    case equalPowerCrossfade(seconds: Double)
    /// A specific SFX (riser / impact / fill) carries the join.
    case sfx(assetID: String)
    /// An effect tail (echo throw, reverb bloom) fills the join.
    case effectTail
    /// Downbeat-aligned hard cut with an anti-click microfade —
    /// only valid when the join's energy profile already matches.
    case alignedHardCut
}

/// Structured record of one internal cut. Validation REJECTS any source
/// discontinuity that has no matching record, insufficient confidence,
/// or no masking strategy.
struct AutoCutRecord: Sendable {
    /// Timeline seconds where the incoming material starts.
    var timelineAt: Double
    /// Source seconds where the outgoing material stops.
    var sourceFrom: Double
    /// Source seconds where the incoming material starts.
    var sourceTo: Double
    var reason: AutoCutReason
    /// Analysis confidence backing this cut, 0…1.
    var confidence: Double
    /// Expected short-term energy change across the join, dB
    /// (0 = energy-preserving).
    var expectedEnergyDeltaDB: Double
    var masking: AutoCutMasking
}

// MARK: - SFX Event

struct AutoSFXEvent: Sendable {
    var assetID: String
    /// Timeline seconds where the asset starts.
    var timelineStart: Double
    /// Why it exists — surfaces in the summary ("riser into the drop").
    var purpose: String

    nonisolated var duration: Double {
        SoundEffectLibrary.definition(for: assetID)?.durationSeconds ?? 0
    }
    nonisolated var timelineEnd: Double { timelineStart + duration }
}

// MARK: - Intentional Silence

/// A deliberate gap the validator must not close (pre-drop pause, etc.).
struct AutoIntentionalGap: Sendable, Equatable {
    var start: Double
    var end: Double
    var reason: String

    nonisolated var length: Double { end - start }
}

// MARK: - Plan

struct AutoRemixPlan: Sendable {
    var id = UUID()
    var mode: AutoRemixMode
    var targetBPM: Double
    var targetDuration: Double
    var anchorSongIDs: [UUID]
    var selectedSections: [AutoSelectedSection]
    var placements: [AutoClipPlacement]
    var sfxEvents: [AutoSFXEvent]
    /// Structured record for EVERY internal cut (source discontinuity).
    /// A cut without a record here is invalid.
    var cutRecords: [AutoCutRecord] = []
    /// Source range the one-song remix draws from after evidence-based
    /// edge trimming. nil for mashups.
    var usableSourceRange: ClosedRange<Double>? = nil
    /// Deliberate micro-pauses / intentional silence the validator preserves.
    /// Club remix uses this for the pre-drop void (hype = subtraction).
    var intentionalGaps: [AutoIntentionalGap] = []
    /// Club pulse policy for the arrangement (one-kick rule).
    var pulsePolicy: AutoClubPulse.Policy? = nil
    /// Pulse regions on the timeline (mute kick in build-out / void / break).
    var pulseRegions: [AutoClubPulse.Region] = []
    /// Recipe flavor bias (Calvin / Guetta / … instincts).
    var clubFlavor: AutoClubFlavor? = nil
    /// Mashup: song chosen as Drop 1 sung hook (nil for one-song remix).
    var mashupVocalSongID: UUID? = nil
    /// Mashup: song chosen as Drop 2 flip hook (nil when unused).
    var mashupDrop2SongID: UUID? = nil
    /// Mashup: song chosen as the club bed (nil for one-song remix).
    var mashupBedSongID: UUID? = nil
    /// Song-change count between consecutive dominant slots.
    var handoffCount: Int
    /// Arrangement letter per song (anchor = "A").
    var songLetters: [UUID: String]
    /// Slot-order letters, e.g. ["A","B","A","C","B"].
    var sequence: [String]
    /// Slot-order song titles for the summary sheet.
    var sequenceTitles: [String] = []
    var transitionsUsed: [AutoTransitionRecipe]
    var decisions: [AutoDecision]
    var warnings: [String]
    var confidence: Double
    /// Retained for deterministic re-runs / debugging (not shown in the UI sheet).
    var randomSeed: UInt64

    nonisolated var beatSeconds: Double { 60.0 / max(targetBPM, 40) }
    nonisolated var barSeconds: Double { beatSeconds * 4 }
    /// One eighth note at the target tempo.
    nonisolated var eighthNoteSeconds: Double { beatSeconds * 0.5 }
}

// MARK: - User-Facing Summary

struct AutoRemixSummary: Equatable, Sendable {
    var modeTitle: String
    var targetBPM: Int
    var anchorNames: [String]
    /// Prefer song titles: "Song A → Song B → Song A → Song B"
    var sequence: String
    var handoffCount: Int
    /// "A — Song Title" lines.
    var songLegend: [String]
    var transitionRecipes: [String]
    var effectsUsed: [String]
    var sfxUsed: [String]
    var decisions: [String]
    var warnings: [String]
    /// Debug metadata — not shown on the summary sheet.
    var randomSeed: UInt64
}

// MARK: - Tuning

/// Every arrangement heuristic in one place. Weights are starting
/// heuristics, not fixed musical truths — tune freely.
struct AutoTuning: Sendable {
    // SectionValue weights (sum ≈ 1).
    var hookWeight = 0.30
    var energyWeight = 0.20
    var clarityWeight = 0.15
    var rhythmWeight = 0.15
    var uniquenessWeight = 0.10
    var transitionWeight = 0.10

    /// Max pitch-preserving tempo stretch for beatmatching (±) — vocal gate.
    var maxStretch = AutoClubTempo.maxVocalStretch
    /// Instrumental / bed stretch preference for mashups.
    var maxInstrumentalStretch = AutoClubTempo.maxInstrumentalStretch
    /// Supporting source gain during overlaps (≈ −7 dB).
    var supportVolume = 0.45
    /// Minimum directional-compatibility score before Auto risks an overlap.
    var minOverlapScore = 0.55
    /// Analysis confidence below this → energy-curve club-ify without invented cuts.
    var lowConfidenceThreshold = 0.5
    /// Max corrective pitch on a supporting overlap / bed, semitones.
    /// Mashup pitches the BED, not the star vocal — keep ≤ ~2.
    var maxCorrectivePitchSemitones = 2
    /// Timeline budget for the arrangement (streaming-length club rewrite).
    var maxTimelineSeconds = 232.0
    /// Longest unintended silence tolerated between clips (beats).
    /// 0.5 beat = one eighth note at the target BPM.
    var maxGapBeats = 0.5
    /// Max length of a deliberate pre-drop void (beats). Half-bar = 2.
    var maxIntentionalPauseBeats = 2.0
    /// Preferred pre-drop void length (beats) when confidence supports it.
    var preferredPredropVoidBeats = 1.0
    /// Minimum clip segment length in timeline seconds (model minimum ≈3.7 s).
    var minSegmentSeconds: Double = MixrTimeline.seconds(fromUnits: MixrTimeline.minClipLengthUnits) + 0.05

    /// Remix: seconds between major coordinated SFX moments (~2–4 / min).
    var remixMajorSFXSpacing = 16.0
    /// Mashup: sparser SFX — song changes already create excitement.
    var mashupMajorSFXSpacing = 24.0

    static let standard = AutoTuning()
}

// MARK: - Effect whitelist

/// Only the currently supported effect ids may appear on Auto-generated clips.
enum AutoSupportedEffects {
    /// String ids match `MixrEffect.rawValue` (reverb / echo / pitchUp / flanger / blur).
    static let levelKeys: Set<String> = [
        "reverb", "echo", "pitchUp", "flanger", "blur",
    ]

    /// Drops retired / unknown keys (Bass Boost, Stutter, …).
    static func sanitize(_ settings: ClipEffectSettings) -> ClipEffectSettings {
        var out = settings
        out.levels = out.levels.filter { levelKeys.contains($0.key) }
        out.migrateLegacyEffectKeys()
        out.levels = out.levels.filter { levelKeys.contains($0.key) }
        return out
    }
}

// MARK: - Seeded RNG (SplitMix64)

/// Deterministic generator so a plan's randomSeed reproduces the result.
struct AutoRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
