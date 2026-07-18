import Foundation

// MARK: - Transition Envelope Model
//
// SINGLE SOURCE OF TRUTH for clip gain envelopes at transitions.
//
// Pure math over value types — no AVFoundation — so the exact same curves
// drive live playback (MixrPlaybackEngine tick), offline export
// (MixrExportRenderer render blocks), and the portable test mixdown
// (AutoOfflineMixdown). Live and export MUST NOT diverge from this model;
// ClipEffectDSP.transitionEnvelope delegates here.
//
// Curve names stored on ClipTransition.curve:
//   "linear"     — legacy straight-line fade
//   "equalPower" — sin/cos constant-power crossfade halves
nonisolated enum AutoTransitionEnvelope {

    /// Curve identifier for equal-power fades (ClipTransition.curve).
    static let equalPowerCurveName = "equalPower"

    /// Anti-click microfade applied at clip edges that have no explicit
    /// fade and are NOT source-continuous with their neighbor (seconds).
    /// 8 ms sits inside the required 5–20 ms window.
    static let microfadeSeconds = 0.008

    /// Evaluation context for one clip edge: whether the adjacent clip on
    /// the same track continues the same source material sample-exactly
    /// (segment split for effects, not a musical cut).
    struct Continuity {
        var previous: Bool
        var next: Bool

        nonisolated init(previous: Bool = false, next: Bool = false) {
            self.previous = previous
            self.next = next
        }

        nonisolated static let isolated = Continuity()
    }

    /// Gain (0…1) plus transient echo send boost for one clip at time `t`.
    struct Value {
        var gain: Double
        var echoBoost: Double
    }

    // MARK: Curve primitives

    /// Fade-in shape at progress x (0…1).
    static func fadeInGain(progress x: Double, curve: String) -> Double {
        let clamped = min(1, max(0, x))
        if curve == equalPowerCurveName {
            return sin(clamped * .pi / 2)
        }
        return clamped
    }

    /// Fade-out shape at remaining-progress x (1 → clip fully audible,
    /// 0 → clip edge).
    static func fadeOutGain(progress x: Double, curve: String) -> Double {
        let clamped = min(1, max(0, x))
        if curve == equalPowerCurveName {
            return sin(clamped * .pi / 2)   // cos(π/2·(1−x)) == sin(π/2·x)
        }
        return clamped
    }

    // MARK: Envelope

    /// Envelope for a clip spanning [clipStart, clipEnd) timeline seconds.
    /// Fade durations are in BEATS at `bpm` (matching ClipTransition).
    ///
    /// Rules:
    ///  • Explicit crossfade/auto in → shaped ramp from the clip edge.
    ///  • Explicit fadeOut/crossfade/auto out → shaped ramp into the edge.
    ///  • echoOut → gentle 30% dip plus echo send boost (unchanged).
    ///  • Source-continuous edges get NO fade of any kind — the audio is
    ///    sample-continuous by construction and any dip would notch it.
    ///  • Non-continuous edges with no explicit fade get an anti-click
    ///    microfade (5–20 ms) so hard cuts never click.
    static func envelope(
        transitionIn: ClipTransition,
        transitionOut: ClipTransition,
        clipStart: Double,
        clipEnd: Double,
        at t: Double,
        bpm: Double,
        continuity: Continuity = .isolated
    ) -> Value {
        let clipLen = max(0.01, clipEnd - clipStart)
        let beat = 60.0 / max(bpm, 1)

        var gain = 1.0
        var echoBoost = 0.0

        // ── Entering edge ──
        if !continuity.previous {
            switch transitionIn.type {
            case .crossfade, .auto:
                let dur = min(transitionIn.duration * beat, clipLen * 0.5)
                if dur > 0.01 {
                    gain *= fadeInGain(progress: (t - clipStart) / dur, curve: transitionIn.curve)
                }
            case .none, .fadeOut, .echoOut:
                // Hard entrance: anti-click microfade only.
                let dur = min(microfadeSeconds, clipLen * 0.5)
                if dur > 0.0005, t - clipStart < dur {
                    gain *= min(1.0, max(0.0, (t - clipStart) / dur))
                }
            }
        }

        // ── Leaving edge ──
        if !continuity.next {
            let outDur = min(transitionOut.duration * beat, clipLen * 0.5)
            switch transitionOut.type {
            case .fadeOut, .crossfade, .auto:
                if outDur > 0.01 {
                    gain *= fadeOutGain(progress: (clipEnd - t) / outDur, curve: transitionOut.curve)
                }
            case .echoOut:
                if outDur > 0.01 {
                    let k = min(1.0, max(0.0, 1.0 - (clipEnd - t) / outDur))
                    echoBoost = k * 32.0
                    gain *= 1.0 - 0.30 * k
                }
            case .none:
                let dur = min(microfadeSeconds, clipLen * 0.5)
                if dur > 0.0005, clipEnd - t < dur {
                    gain *= min(1.0, max(0.0, (clipEnd - t) / dur))
                }
            }
        }

        return Value(gain: gain, echoBoost: echoBoost)
    }
}
