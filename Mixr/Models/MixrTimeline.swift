import CoreGraphics
import Foundation

enum MixrTimeline {
    nonisolated static let totalUnits: CGFloat = 130
    nonisolated static let timelineDurationSeconds: Double = 240

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

    nonisolated static func formattedTime(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
