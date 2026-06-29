import CoreGraphics
import Foundation

enum MixrTimeline {
    nonisolated static let totalUnits: CGFloat = 130
    nonisolated static let timelineDurationSeconds: Double = 240
    nonisolated static let clipEdgeEpsilon: CGFloat = 0.001

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
        movingClip.start = anchoredStart
        movingClip.transitionIn = .none
        movingClip.transitionOut = .none

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
                    prefixClip.transitionIn = .none
                    prefixClip.transitionOut = .none
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
                clip.transitionIn = .none
                clip.transitionOut = .none
            }
            cursorEnd = max(cursorEnd, clip.start + clip.length)
            arranged.append(clip)
        }

        return arranged.sorted { lhs, rhs in
            if abs(lhs.start - rhs.start) > epsilon { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    nonisolated static func formattedTime(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
