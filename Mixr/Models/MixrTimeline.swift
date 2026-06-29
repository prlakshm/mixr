import CoreGraphics
import Foundation

enum MixrTimeline {
    nonisolated static let totalUnits: CGFloat = 130
    nonisolated static let timelineDurationSeconds: Double = 240
    nonisolated static let clipEdgeEpsilon: CGFloat = 0.001

    private enum ClipInsertionPlacement {
        case before(MixrClip)
        case after(MixrClip)
    }

    nonisolated static func seconds(fromUnits units: CGFloat) -> Double {
        Double(units / totalUnits) * timelineDurationSeconds
    }

    nonisolated static func units(fromSeconds seconds: Double) -> CGFloat {
        guard timelineDurationSeconds > 0 else { return 0 }
        return CGFloat(seconds / timelineDurationSeconds) * totalUnits
    }

    nonisolated static func remixDurationSeconds(tracks: [MixrTrack]) -> Double {
        tracks
            .flatMap(\.clips)
            .map { seconds(fromUnits: $0.start + $0.length) }
            .max() ?? 0
    }

    /// Timeline width in layout units — at least the default span, extended to the
    /// end of the longest clip arrangement across all tracks.
    nonisolated static func contentUnits(for tracks: [MixrTrack]) -> CGFloat {
        let maxClipEnd = tracks
            .flatMap(\.clips)
            .map { $0.start + $0.length }
            .max() ?? 0
        return max(totalUnits, maxClipEnd)
    }

    nonisolated static func gridLineSeconds(upToContentUnits units: CGFloat) -> [CGFloat] {
        let maxSeconds = Int(seconds(fromUnits: units).rounded(.up))
        guard maxSeconds > 0 else { return [0] }
        return stride(from: 0, through: maxSeconds, by: 10).map { CGFloat($0) }
    }

    nonisolated static func rulerLabelSeconds(upToContentUnits units: CGFloat) -> [CGFloat] {
        let maxSeconds = Int(seconds(fromUnits: units).rounded(.up))
        guard maxSeconds > 0 else { return [0] }
        return stride(from: 0, through: maxSeconds, by: 30).map { CGFloat($0) }
    }

    /// Repositions a dragged clip and pushes only clips that overlap its new range.
    /// Gaps are preserved; the dragged clip's requested start remains the anchor.
    nonisolated static func reflowedClips(
        moving clipID: UUID,
        to proposedStart: CGFloat,
        in clips: [MixrClip],
        epsilon: CGFloat = clipEdgeEpsilon
    ) -> [MixrClip] {
        guard var movingClip = clips.first(where: { $0.id == clipID }) else {
            return clips.sorted { $0.start < $1.start }
        }

        let anchoredStart = max(0, proposedStart)
        let emptyTransition = ClipTransition()
        movingClip.start = anchoredStart
        movingClip.transitionIn = emptyTransition
        movingClip.transitionOut = emptyTransition

        let movingEnd = anchoredStart + movingClip.length
        let otherClips = clips
            .filter { $0.id != clipID }
            .sorted { lhs, rhs in
                if abs(lhs.start - rhs.start) > epsilon { return lhs.start < rhs.start }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var arranged: [MixrClip] = []
        var suffix: [MixrClip] = []
        var prefixEnd: CGFloat = 0

        for clip in otherClips {
            let clipEnd = clip.start + clip.length
            if clipEnd <= anchoredStart + epsilon {
                var prefixClip = clip
                if prefixClip.start < prefixEnd - epsilon {
                    prefixClip.start = prefixEnd
                    prefixClip.transitionIn = emptyTransition
                    prefixClip.transitionOut = emptyTransition
                }
                prefixEnd = max(prefixEnd, prefixClip.start + prefixClip.length)
                arranged.append(prefixClip)
            } else {
                suffix.append(clip)
            }
        }

        arranged.append(movingClip)

        var cursorEnd = movingEnd
        for var clip in suffix {
            if clip.start < cursorEnd - epsilon {
                clip.start = cursorEnd
                clip.transitionIn = emptyTransition
                clip.transitionOut = emptyTransition
            }
            cursorEnd = max(cursorEnd, clip.start + clip.length)
            arranged.append(clip)
        }

        return arranged.sorted { lhs, rhs in
            if abs(lhs.start - rhs.start) > epsilon { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Resolves a forgiving drag position into an exact clip start. Edge zones
    /// snap before/after nearby clips; otherwise the raw free-placement start is used.
    nonisolated static func resolvedClipInsertionStart(
        moving clipID: UUID,
        rawStart: CGFloat,
        pointerUnit: CGFloat?,
        in clips: [MixrClip],
        snapZoneUnits: CGFloat,
        centerBeforeRatio: CGFloat = 0.40,
        epsilon: CGFloat = clipEdgeEpsilon
    ) -> CGFloat {
        guard let movingClip = clips.first(where: { $0.id == clipID }),
              let pointerUnit
        else {
            return max(0, rawStart)
        }

        guard let placement = clipInsertionPlacement(
            moving: clipID,
            pointerUnit: pointerUnit,
            in: clips,
            snapZoneUnits: snapZoneUnits,
            centerBeforeRatio: centerBeforeRatio,
            epsilon: epsilon
        ) else {
            return max(0, rawStart)
        }

        switch placement {
        case .before(let targetClip):
            let prefixEnd = clips
                .filter { $0.id != clipID && $0.id != targetClip.id && $0.start < targetClip.start - epsilon }
                .map { $0.start + $0.length }
                .max() ?? 0
            return max(0, max(prefixEnd, targetClip.start - movingClip.length))

        case .after(let targetClip):
            return max(0, targetClip.start + targetClip.length)
        }
    }

    private nonisolated static func clipInsertionPlacement(
        moving clipID: UUID,
        pointerUnit: CGFloat,
        in clips: [MixrClip],
        snapZoneUnits: CGFloat,
        centerBeforeRatio: CGFloat,
        epsilon: CGFloat
    ) -> ClipInsertionPlacement? {
        struct Candidate {
            let placement: ClipInsertionPlacement
            let priority: Int
            let distance: CGFloat
            let targetStart: CGFloat
        }

        let otherClips = clips.filter { $0.id != clipID }
        let snapZone = max(0, snapZoneUnits)
        var candidates: [Candidate] = []

        for clip in otherClips {
            let start = clip.start
            let end = clip.start + clip.length
            guard clip.length > epsilon else { continue }

            let leadingDistance = abs(pointerUnit - start)
            if leadingDistance <= snapZone + epsilon {
                candidates.append(Candidate(
                    placement: .before(clip),
                    priority: 0,
                    distance: leadingDistance,
                    targetStart: start
                ))
            }

            let trailingDistance = abs(pointerUnit - end)
            if trailingDistance <= snapZone + epsilon {
                candidates.append(Candidate(
                    placement: .after(clip),
                    priority: 0,
                    distance: trailingDistance,
                    targetStart: start
                ))
            }

            if pointerUnit > start + epsilon && pointerUnit < end - epsilon {
                let localRatio = (pointerUnit - start) / clip.length
                candidates.append(Candidate(
                    placement: localRatio <= centerBeforeRatio ? .before(clip) : .after(clip),
                    priority: 1,
                    distance: min(abs(pointerUnit - start), abs(pointerUnit - end)),
                    targetStart: start
                ))
            }
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if abs(lhs.distance - rhs.distance) > epsilon { return lhs.distance < rhs.distance }
                return lhs.targetStart < rhs.targetStart
            }
            .first?
            .placement
    }

    nonisolated static func formattedTime(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
