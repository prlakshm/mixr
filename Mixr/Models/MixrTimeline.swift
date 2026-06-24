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

    nonisolated static func formattedTime(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
