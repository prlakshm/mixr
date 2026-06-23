import Foundation

enum MixrTimeline {
    static let totalUnits: CGFloat = 130
    static let timelineDurationSeconds: Double = 240

    static func seconds(fromUnits units: CGFloat) -> Double {
        Double(units / totalUnits) * timelineDurationSeconds
    }

    static func units(fromSeconds seconds: Double) -> CGFloat {
        guard timelineDurationSeconds > 0 else { return 0 }
        return CGFloat(seconds / timelineDurationSeconds) * totalUnits
    }

    static func remixDurationSeconds(tracks: [MixrTrack]) -> Double {
        tracks
            .flatMap(\.clips)
            .map { seconds(fromUnits: $0.start + $0.length) }
            .max() ?? 0
    }

    static func formattedTime(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
