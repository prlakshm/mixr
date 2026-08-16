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

    /// Drum / bass thresholds for the one-kick rule (measured 0…1).
    static let slammingDrumThreshold = 0.70
    static let slammingBassThreshold = 0.55
    static let thinDrumThreshold = 0.45
    static let thinBassThreshold = 0.40

    static func policy(
        drumStrength: Double,
        bassDensity: Double
    ) -> Policy {
        let slamming = drumStrength >= slammingDrumThreshold
            && bassDensity >= slammingBassThreshold
        let thin = drumStrength < thinDrumThreshold || bassDensity < thinBassThreshold

        if slamming {
            return Policy(
                sourceHasClubKick: true,
                writesKick: false,
                writesBass: false,
                duckSourceLowEnd: false,
                detail: "source already slams — no pulse kick (use existing SFX one-shots only)"
            )
        }
        if thin {
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
    /// does not write a pulse.
    static func scheduleHits(
        regions: [Region],
        policy: Policy,
        beatSeconds: Double,
        barSeconds: Double
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
                if policy.writesKick {
                    var t = region.timelineStart
                    while t < region.timelineEnd - 0.01 {
                        hits.append(Hit(
                            assetID: "clubKick",
                            timelineStart: t,
                            purpose: "drop kick"
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
                            purpose: "drop sub"
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
