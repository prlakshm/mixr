import Foundation

// MARK: - Club Recipe Flavors
//
// Artist *instincts* parameterized as arrangement bias — not illegal
// sound-alikes. Chosen from measured texture + a stable seed.

nonisolated enum AutoClubFlavor: String, Sendable, CaseIterable {
    case calvin = "Sparse piano / vocal / bass"
    case guetta = "Vocal + electronic drop"
    case avicii = "Four-bar harmonic loop"
    case marshmello = "Humable chop drop"
    case snake = "Chant / aggressive low end"

    /// Bias knobs the planner applies.
    struct Bias: Sendable {
        /// Extra blur on breakdown (sung chorus lives in the break).
        var breakdownVocalClarity: Double
        /// Drop keeps one lead idea — reduce midrange stacking.
        var dropMidrangeSparse: Bool
        /// Drop 2 adds an airy layer (reverb/hats) rather than a new hook.
        var drop2AiryLayer: Bool
        /// Prefer vocal-chop style short teaser on drop.
        var vocalChopLead: Bool
        /// Allow half-time pulse on drop.
        var halfTimeDrop: Bool
        /// Aggressive sub weight on drop.
        var aggressiveLowEnd: Bool
    }

    var bias: Bias {
        switch self {
        case .calvin:
            return Bias(
                breakdownVocalClarity: 0.85,
                dropMidrangeSparse: true,
                drop2AiryLayer: false,
                vocalChopLead: false,
                halfTimeDrop: false,
                aggressiveLowEnd: false
            )
        case .guetta:
            return Bias(
                breakdownVocalClarity: 0.55,
                dropMidrangeSparse: true,
                drop2AiryLayer: false,
                vocalChopLead: false,
                halfTimeDrop: false,
                aggressiveLowEnd: true
            )
        case .avicii:
            return Bias(
                breakdownVocalClarity: 0.9,
                dropMidrangeSparse: true,
                drop2AiryLayer: true,
                vocalChopLead: false,
                halfTimeDrop: false,
                aggressiveLowEnd: false
            )
        case .marshmello:
            return Bias(
                breakdownVocalClarity: 0.4,
                dropMidrangeSparse: true,
                drop2AiryLayer: true,
                vocalChopLead: true,
                halfTimeDrop: false,
                aggressiveLowEnd: false
            )
        case .snake:
            return Bias(
                breakdownVocalClarity: 0.35,
                dropMidrangeSparse: true,
                drop2AiryLayer: false,
                vocalChopLead: true,
                halfTimeDrop: true,
                aggressiveLowEnd: true
            )
        }
    }

    /// Pick a flavor from song texture + seed (deterministic).
    static func choose(
        drumStrength: Double,
        bassDensity: Double,
        vocalDensity: Double,
        bpm: Double,
        seed: UInt64
    ) -> AutoClubFlavor {
        if bpm >= 140, bassDensity > 0.55 { return .snake }
        if vocalDensity > 0.7, drumStrength < 0.5 { return .calvin }
        if vocalDensity > 0.65, drumStrength > 0.6 { return .guetta }
        if drumStrength > 0.55, vocalDensity > 0.45 { return .marshmello }
        var rng = AutoRandom(seed: seed ^ 0xC1B_F1A7)
        let all = AutoClubFlavor.allCases
        let idx = Int(rng.next() % UInt64(all.count))
        return all[idx]
    }
}
