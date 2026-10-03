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

    /// Gain (0…1), transient echo send boost, and DJ filter cutoffs for
    /// one clip at time `t`. Filters default to fully open.
    struct Value {
        var gain: Double
        var echoBoost: Double
        var highPassHz: Double = AutoTransitionEnvelope.openHighPassHz
        var lowPassHz: Double = AutoTransitionEnvelope.openLowPassHz
    }

    // MARK: Filter constants

    /// High-pass at rest (effectively bypassed).
    static let openHighPassHz = 20.0
    /// Low-pass at rest (effectively bypassed).
    static let openLowPassHz = 20_000.0
    /// Bass-swap crossover: below this only one song's low end sounds.
    static let bassSwapCutoffHz = 260.0
    /// Peak of a high-pass build (thin, radio-like — never silent).
    static let buildHighPassPeakHz = 1_100.0
    /// Low-pass fully closed (muffled "outside the club").
    static let closedLowPassHz = 500.0

    // MARK: Timeline tempo (shared unit for fade lengths)

    /// Fallback when a track has no BPM — identical in every consumer.
    static let defaultTrackBPM = 124

    /// Tempo at which a clip's beats pass on the TIMELINE: its native BPM
    /// times its playback rate. ClipTransition.duration (beats) and the
    /// tempo-synced echo are measured in these beats by the planner, live
    /// playback, export, and the offline mixdown alike — so a beatmatched
    /// clip's 8-beat fade is 8 beats of the mix, not of the source.
    static func timelineBPM(trackBPM: Int?, playbackSpeed: Double) -> Double {
        Double(trackBPM ?? defaultTrackBPM) * max(playbackSpeed, 0.0001)
    }

    /// Converts a desired timeline duration (seconds) into the beat count
    /// a ClipTransition must store to realize it at `timelineBPM`.
    static func beats(forSeconds seconds: Double, timelineBPM: Double) -> Double {
        seconds / (60.0 / max(timelineBPM, 1))
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
    /// Fade durations are in BEATS at `bpm` — the clip's TIMELINE tempo
    /// (`timelineBPM(trackBPM:playbackSpeed:)`), matching ClipTransition.
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
                    // A short echo THROW (≤ 2 beats) keeps full level up to
                    // the downbeat — the echo tail carries the join; longer
                    // echo-outs also ease the dry level down.
                    if transitionOut.duration > 2.0 + 1e-9 {
                        gain *= 1.0 - 0.30 * k
                    }
                }
            case .none:
                let dur = min(microfadeSeconds, clipLen * 0.5)
                if dur > 0.0005, clipEnd - t < dur {
                    gain *= min(1.0, max(0.0, (clipEnd - t) / dur))
                }
            }
        }

        // ── DJ filter automation ──
        // Filters are musical automation, not declick fades, so they apply
        // on source-continuous edges too (a high-pass build that releases
        // exactly on the drop downbeat is a continuous split).
        var highPass = openHighPassHz
        var lowPass = openLowPassHz
        if let filter = transitionIn.filter {
            let window = min(max(transitionIn.duration * beat, 0.05), clipLen)
            let x = (t - clipStart) / window
            switch filter {
            case .bassSwap:
                let k = swapProgress(t: t, mid: clipStart + window / 2, beat: beat)
                highPass = max(highPass, logInterpolate(bassSwapCutoffHz, openHighPassHz, k))
            case .highPassSweep:
                highPass = max(highPass, logInterpolate(buildHighPassPeakHz, openHighPassHz, smooth(x)))
            case .lowPassSweep:
                lowPass = min(lowPass, logInterpolate(closedLowPassHz, openLowPassHz, smooth(x)))
            }
        }
        if let filter = transitionOut.filter {
            let window = min(max(transitionOut.duration * beat, 0.05), clipLen)
            let start = clipEnd - window
            let x = (t - start) / window
            switch filter {
            case .bassSwap:
                let k = swapProgress(t: t, mid: start + window / 2, beat: beat)
                highPass = max(highPass, logInterpolate(openHighPassHz, bassSwapCutoffHz, k))
            case .highPassSweep:
                // Accelerating drain — most of the movement in the last bars.
                let c = min(1, max(0, x))
                highPass = max(highPass, logInterpolate(openHighPassHz, buildHighPassPeakHz, c * c))
            case .lowPassSweep:
                lowPass = min(lowPass, logInterpolate(openLowPassHz, closedLowPassHz, smooth(x)))
            }
        }

        return Value(gain: gain, echoBoost: echoBoost, highPassHz: highPass, lowPassHz: lowPass)
    }

    /// 0 before `mid − ½ beat`, 1 after `mid + ½ beat`, smooth between —
    /// the one-beat bass-swap ramp centered on the fade midpoint.
    static func swapProgress(t: Double, mid: Double, beat: Double) -> Double {
        smooth((t - (mid - beat / 2)) / max(beat, 0.01))
    }

    /// Clamped smoothstep.
    static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    /// Log-frequency interpolation a → b at k ∈ 0…1.
    static func logInterpolate(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let c = min(1, max(0, k))
        return exp(log(a) + (log(b) - log(a)) * c)
    }

    // MARK: Clip-level helpers (timeline units → seconds via MixrTimeline)

    /// Source seconds where a clip's audio ends.
    static func sourceEndSeconds(of clip: MixrClip) -> Double {
        clip.sourceOffsetSeconds
            + MixrTimeline.seconds(fromUnits: clip.length) * clip.playbackSpeed
    }

    /// Continuity of `clip` against its neighbors on the same track:
    /// an edge is continuous when the adjacent clip abuts it on the
    /// timeline AND continues the same source material at the same rate —
    /// a segment split for effects, not a musical boundary.
    static func continuity(for clip: MixrClip, in clips: [MixrClip]) -> Continuity {
        let epsilon = 0.02
        let clipStart = MixrTimeline.seconds(fromUnits: clip.start)
        let clipEnd = MixrTimeline.seconds(fromUnits: clip.start + clip.length)

        var previous = false
        var next = false
        for other in clips where other.id != clip.id && !other.isSoundEffect {
            let otherStart = MixrTimeline.seconds(fromUnits: other.start)
            let otherEnd = MixrTimeline.seconds(fromUnits: other.start + other.length)
            if abs(otherEnd - clipStart) <= epsilon,
               abs(sourceEndSeconds(of: other) - clip.sourceOffsetSeconds) <= 0.05,
               abs(other.playbackSpeed - clip.playbackSpeed) <= 0.001 {
                previous = true
            }
            if abs(otherStart - clipEnd) <= epsilon,
               abs(sourceEndSeconds(of: clip) - other.sourceOffsetSeconds) <= 0.05,
               abs(other.playbackSpeed - clip.playbackSpeed) <= 0.001 {
                next = true
            }
        }
        return Continuity(previous: previous, next: next)
    }

    /// Splits a track's song clips onto two player lanes so overlapping
    /// clips (true crossfades) can sound simultaneously with independent
    /// gains. Non-overlapping clips stay on lane 0.
    static func playerLanes(for clips: [MixrClip]) -> [UUID: Int] {
        let songClips = clips
            .filter { !$0.isSoundEffect }
            .sorted { $0.start < $1.start }
        var lanes: [UUID: Int] = [:]
        var previous: MixrClip?
        var previousLane = 1   // first clip lands on lane 0
        for clip in songClips {
            var lane = 0
            if let prev = previous, clip.start < prev.start + prev.length - 0.001 {
                lane = previousLane == 0 ? 1 : 0
            }
            lanes[clip.id] = lane
            // Track the clip that ends LAST as the overlap reference.
            if let prev = previous, prev.start + prev.length > clip.start + clip.length {
                // previous still the longest-running; keep its lane
            } else {
                previous = clip
                previousLane = lane
            }
        }
        return lanes
    }
}
