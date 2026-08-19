import Foundation

// MARK: - Club Recipe Flavors
//
// Artist *instincts* parameterized as arrangement bias — not illegal
// sound-alikes and never copyrighted samples. Chosen from measured
// texture + a stable seed. Product lock: default toward festival hype
// (Diplo / Guetta / Snake), not a polite Calvin radio edit.

nonisolated enum AutoClubFlavor: String, Sendable, CaseIterable {
    case calvin = "Sparse piano / vocal / bass"
    case guetta = "Vocal + electronic drop"
    case avicii = "Four-bar harmonic loop"
    case marshmello = "Humable chop drop"
    case snake = "Chant / aggressive low end"
    /// Diplo / Major Lazer / Jack Ü instincts — maximalist festival hype,
    /// void-then-slam drops, global-bass DNA, vocal chops over a rolling bed.
    case diplo = "Maximalist festival / global-bass"

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
        /// Allow half-time pulse on drop (dancehall / global-bass feel).
        var halfTimeDrop: Bool
        /// Aggressive sub weight on drop.
        var aggressiveLowEnd: Bool
        /// Pile coordinated SFX on every drop (tape stop + snare + air +
        /// impact + crash + clap) — never a polite two-whoosh edit.
        var maximalistStacks: Bool
        /// FX ride as groove (echo throws / filter open / reverse) not garnish.
        var fxAsGroove: Bool
    }

    var bias: Bias {
        switch self {
        case .calvin:
            // Sparse midrange on the drop is this recipe's identity.
            return Bias(
                breakdownVocalClarity: 0.85,
                dropMidrangeSparse: true,
                drop2AiryLayer: false,
                vocalChopLead: false,
                halfTimeDrop: false,
                aggressiveLowEnd: false,
                maximalistStacks: false,
                fxAsGroove: false
            )
        case .guetta:
            return Bias(
                breakdownVocalClarity: 0.55,
                dropMidrangeSparse: false,
                drop2AiryLayer: true,
                vocalChopLead: false,
                halfTimeDrop: false,
                aggressiveLowEnd: true,
                maximalistStacks: true,
                fxAsGroove: true
            )
        case .avicii:
            return Bias(
                breakdownVocalClarity: 0.9,
                dropMidrangeSparse: false,
                drop2AiryLayer: true,
                vocalChopLead: false,
                halfTimeDrop: false,
                aggressiveLowEnd: false,
                maximalistStacks: false,
                fxAsGroove: true
            )
        case .marshmello:
            return Bias(
                breakdownVocalClarity: 0.4,
                dropMidrangeSparse: false,
                drop2AiryLayer: true,
                vocalChopLead: true,
                halfTimeDrop: false,
                aggressiveLowEnd: false,
                maximalistStacks: true,
                fxAsGroove: true
            )
        case .snake:
            return Bias(
                breakdownVocalClarity: 0.35,
                dropMidrangeSparse: false,
                drop2AiryLayer: true,
                vocalChopLead: true,
                halfTimeDrop: true,
                aggressiveLowEnd: true,
                maximalistStacks: true,
                fxAsGroove: true
            )
        case .diplo:
            // Maximalist festival / Major Lazer / Jack Ü instincts.
            return Bias(
                breakdownVocalClarity: 0.45,
                dropMidrangeSparse: false,
                drop2AiryLayer: true,
                vocalChopLead: true,
                halfTimeDrop: true,
                aggressiveLowEnd: true,
                maximalistStacks: true,
                fxAsGroove: true
            )
        }
    }

    /// Pick a flavor from song texture + seed (deterministic).
    /// Hype lock: bias toward Diplo / Guetta / Snake. Calvin only for
    /// clearly sparse piano-ballad sources — not the Auto Remix default.
    static func choose(
        drumStrength: Double,
        bassDensity: Double,
        vocalDensity: Double,
        bpm: Double,
        seed: UInt64
    ) -> AutoClubFlavor {
        // Festival / trap-adjacent → Snake or Diplo.
        if bpm >= 140, bassDensity > 0.55 {
            return (seed % 2 == 0) ? .snake : .diplo
        }
        // Dancehall / global-bass midtempo pocket with real drums → Diplo.
        if bpm >= 90, bpm <= 110, drumStrength > 0.55, bassDensity > 0.35 {
            return .diplo
        }
        // Pop vocals over a club bed (Britney / t.A.T.u. crate) → Diplo.
        if vocalDensity > 0.5, drumStrength > 0.55, bassDensity > 0.3 {
            return .diplo
        }
        // Vocal + electronic drop → Guetta.
        if vocalDensity > 0.65, drumStrength > 0.55 {
            return .guetta
        }
        // Hummable chop identity.
        if drumStrength > 0.55, vocalDensity > 0.45, bpm >= 120, bpm < 140 {
            return .marshmello
        }
        // Sparse Calvin ONLY for clear piano-ballad texture.
        if vocalDensity > 0.75, drumStrength < 0.35, bassDensity < 0.35 {
            return .calvin
        }
        // Default hype pool — never land on Calvin by RNG.
        var rng = AutoRandom(seed: seed ^ 0xC1B_F1A7)
        let hypePool: [AutoClubFlavor] = [.diplo, .guetta, .snake, .marshmello, .avicii]
        let idx = Int(rng.next() % UInt64(hypePool.count))
        return hypePool[idx]
    }
}
