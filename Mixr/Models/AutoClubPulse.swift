import Foundation

// MARK: - Club Pulse Layer
//
// Product lock: the ONLY new Auto sound is a kick/bass pulse for THIN
// songs (piano ballad, weak drums). Four-on-the-floor kick + bass weight.
// ONE kick at a time. Duck / high-pass the original low end while the
// pulse plays. If the source already slams, do NOT write this pulse.
// Existing SFX-row one-shots (riser, snare build, impact, …) still cover
// hype on slamming kits — never a second competing kick.

nonisolated enum AutoClubPulse {

    /// Whether Auto should synthesize a kick / sub under the song.
    struct Policy: Sendable, Equatable {
        /// Source already has a club kick / slamming kit.
        var sourceHasClubKick: Bool
        /// Write a synthesized four-on-the-floor kick (thin songs only).
        var writesKick: Bool
        /// Write synthesized bass/sub weight (thin songs only).
        var writesBass: Bool
        /// High-pass / blur the original low end while the pulse plays.
        var duckSourceLowEnd: Bool
        var detail: String
    }

    /// One scheduled pulse hit on the SFX bus (Club Kick / Club Bass menu assets).
    struct Hit: Sendable, Equatable {
        var assetID: String
        var timelineStart: Double
        var purpose: String
    }

    /// Arrangement regions that mute or enable the pulse.
    enum RegionRole: String, Sendable {
        case introTease
        case groove
        case build
        case buildOut       // last bars of a build — kick+bass OUT
        case drop
        case breakdown
        case outro
        case void
    }

    struct Region: Sendable, Equatable {
        var role: RegionRole
        var timelineStart: Double
        var timelineEnd: Double
    }

    /// Drum thresholds for the one-kick rule (measured 0…1).
    /// Strong drums alone mean the kit already owns the kick — bass can
    /// read low on sparse pop arrangements (Britney bass ≈ 0.37) without
    /// making the song "thin."
    static let slammingDrumThreshold = 0.70
    static let thinDrumThreshold = 0.45
    /// Festival/rock beds with uncertain analysis must not get a house kick.
    static let uncertainConfidenceCeiling = 0.75

    static func policy(
        drumStrength: Double,
        bassDensity: Double,
        bpm: Double? = nil,
        analysisConfidence: Double = 1.0
    ) -> Policy {
        _ = bassDensity // retained for call-site compatibility / future nuance
        let pocket = bpm.flatMap { AutoClubTempo.classify($0) }
        let strongDrums = drumStrength >= slammingDrumThreshold

        // Strong drums → source already owns the kick (ignore bass).
        if strongDrums {
            return Policy(
                sourceHasClubKick: true,
                writesKick: false,
                writesBass: false,
                duckSourceLowEnd: false,
                detail: "source already slams — no pulse kick (use existing SFX one-shots only)"
            )
        }

        // Festival/rock pocket: never invent a four-on-the-floor house kick
        // when drum analysis is uncertain (Paramore-class mis-reads).
        if pocket == .festival, analysisConfidence < uncertainConfidenceCeiling {
            return Policy(
                sourceHasClubKick: true,
                writesKick: false,
                writesBass: false,
                duckSourceLowEnd: false,
                detail: "festival / rock pocket — no house pulse when drum analysis is uncertain"
            )
        }

        // Thin ONLY when drums are actually weak (piano / sparse kit).
        if drumStrength < thinDrumThreshold {
            return Policy(
                sourceHasClubKick: false,
                writesKick: true,
                writesBass: true,
                duckSourceLowEnd: true,
                detail: "thin source — four-on-the-floor kick+bass; ducking original low end"
            )
        }

        // Mid kits keep their own drums — do not invent a competing pulse.
        return Policy(
            sourceHasClubKick: false,
            writesKick: false,
            writesBass: false,
            duckSourceLowEnd: false,
            detail: "moderate kit — no pulse layer (source drums carry the groove)"
        )
    }

    /// Schedules four-on-the-floor kick + bass-weight hits. Muted in
    /// `buildOut`, `breakdown`, and `void`. Returns [] when the policy
    /// does not write a pulse. `halfTimeDrop` spaces drop kicks on the
    /// half-time grid (dancehall / global-bass feel) without a second kick.
    static func scheduleHits(
        regions: [Region],
        policy: Policy,
        beatSeconds: Double,
        barSeconds: Double,
        halfTimeDrop: Bool = false
    ) -> [Hit] {
        guard policy.writesKick || policy.writesBass else { return [] }

        var hits: [Hit] = []
        for region in regions {
            switch region.role {
            case .void, .breakdown, .buildOut:
                continue
            case .introTease:
                // Kick tease: every other bar (filtered intro identity).
                if policy.writesKick {
                    var t = region.timelineStart
                    var barIndex = 0
                    while t < region.timelineEnd - 0.01 {
                        if barIndex % 2 == 0 {
                            hits.append(Hit(
                                assetID: "clubKick",
                                timelineStart: t,
                                purpose: "kick tease"
                            ))
                        }
                        t += barSeconds
                        barIndex += 1
                    }
                }
            case .groove, .build, .outro:
                // Four-on-the-floor.
                if policy.writesKick {
                    var t = region.timelineStart
                    while t < region.timelineEnd - 0.01 {
                        hits.append(Hit(
                            assetID: "clubKick",
                            timelineStart: t,
                            purpose: "club kick"
                        ))
                        t += beatSeconds
                    }
                }
                if policy.writesBass {
                    var t = region.timelineStart
                    while t < region.timelineEnd - 0.01 {
                        hits.append(Hit(
                            assetID: "clubBass",
                            timelineStart: t,
                            purpose: "bass weight"
                        ))
                        t += barSeconds
                    }
                }
            case .drop:
                let kickStep = halfTimeDrop ? beatSeconds * 2 : beatSeconds
                if policy.writesKick {
                    var t = region.timelineStart
                    while t < region.timelineEnd - 0.01 {
                        hits.append(Hit(
                            assetID: "clubKick",
                            timelineStart: t,
                            purpose: halfTimeDrop ? "half-time drop kick" : "drop kick"
                        ))
                        t += kickStep
                    }
                }
                if policy.writesBass {
                    var t = region.timelineStart
                    while t < region.timelineEnd - 0.01 {
                        hits.append(Hit(
                            assetID: "clubBass",
                            timelineStart: t,
                            purpose: halfTimeDrop ? "half-time drop sub" : "drop sub"
                        ))
                        t += beatSeconds * 2
                    }
                }
            }
        }
        return hits
    }

    /// True when two kick sources would sound at once (hard fail).
    static func violatesOneKickRule(policy: Policy) -> Bool {
        policy.sourceHasClubKick && policy.writesKick
    }
}
