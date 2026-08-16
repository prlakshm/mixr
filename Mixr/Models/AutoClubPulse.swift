import Foundation

// MARK: - Club Pulse Layer
//
// ONE kick and ONE bass at a time. Thin songs get a written pulse; songs
// that already slam keep their kit and only receive risers / snare rolls /
// impacts / hats. Two kicks flam — that is a hard fail.

nonisolated enum AutoClubPulse {

    /// Whether Auto should synthesize a kick / sub under the song.
    struct Policy: Sendable, Equatable {
        /// Source already has a club kick / slamming kit.
        var sourceHasClubKick: Bool
        /// Write a synthesized kick on the grid.
        var writesKick: Bool
        /// Write a synthesized bass/sub weight on the grid.
        var writesBass: Bool
        /// High-pass / blur the original low end while the pulse plays.
        var duckSourceLowEnd: Bool
        var detail: String
    }

    /// One scheduled pulse hit (kick / bass / hat) on the SFX bus.
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
                detail: "source already slams — pulse adds risers/hats only (no second kick)"
            )
        }
        if thin {
            return Policy(
                sourceHasClubKick: false,
                writesKick: true,
                writesBass: true,
                duckSourceLowEnd: true,
                detail: "thin source — writing kick+bass and ducking original low end"
            )
        }
        // Mid: add kick weight carefully, skip bass to avoid mud.
        return Policy(
            sourceHasClubKick: false,
            writesKick: true,
            writesBass: false,
            duckSourceLowEnd: true,
            detail: "moderate kit — writing kick only, ducking source low end"
        )
    }

    /// Schedules pulse hits for the given regions. Kick and bass are muted
    /// in `buildOut`, `breakdown`, and `void`. Intro teases kick every
    /// other bar; drops get every-beat kick + downbeat bass.
    static func scheduleHits(
        regions: [Region],
        policy: Policy,
        beatSeconds: Double,
        barSeconds: Double
    ) -> [Hit] {
        var hits: [Hit] = []
        guard policy.writesKick || policy.writesBass else {
            // Still allow light hats on groove/drop for slamming sources.
            for region in regions where region.role == .groove || region.role == .drop {
                var t = region.timelineStart + beatSeconds * 2
                while t < region.timelineEnd - 0.01 {
                    hits.append(Hit(assetID: "clubHat", timelineStart: t, purpose: "hat layer"))
                    t += barSeconds
                }
            }
            return hits
        }

        for region in regions {
            switch region.role {
            case .void, .breakdown, .buildOut:
                continue
            case .introTease:
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
