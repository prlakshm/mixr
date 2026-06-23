import SwiftUI
import Combine
import AVFoundation
import CoreMedia

// MARK: - Track Library

@MainActor
final class TrackLibrary: ObservableObject {
    @Published var tracks: [MixrTrack] = []

    private let colorCycle: [MixrWaveformColor] = [.pink, .purple, .red, .yellow, .blue]

    // MARK: - Import

    /// Appends placeholder tracks immediately (preserving selection order and color assignment),
    /// then asynchronously patches duration and clip length per track by UUID.
    func addTracks(from urls: [URL]) {
        for url in urls {
            let color   = colorCycle[tracks.count % colorCycle.count]
            let trackID = UUID()
            let title   = url.deletingPathExtension().lastPathComponent

            let placeholder = MixrTrack(
                id: trackID,
                title: title,
                artist: "Unknown Artist",
                duration: "--:--",
                durationSeconds: nil,
                bpm: 120,
                color: color,
                volume: 0.75,
                url: url,
                clips: [MixrClip(id: UUID(), start: 0, length: 48)]
            )
            tracks.append(placeholder)

            Task {
                let asset = AVURLAsset(url: url)
                guard let cm = try? await asset.load(.duration) else { return }
                let seconds = CMTimeGetSeconds(cm)
                guard seconds.isFinite, seconds > 0 else { return }
                guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[idx].duration        = Self.formattedDuration(seconds)
                tracks[idx].durationSeconds = seconds
                tracks[idx].clips[0].length = Self.clipUnits(for: seconds)
            }
        }
    }

    // MARK: - Reorder

    func reorder(from source: IndexSet, to destination: Int) {
        withAnimation(.easeOut(duration: 0.22)) {
            tracks.move(fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: - Helpers

    private static func formattedDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Maps audio duration to timeline clip length in units.
    /// Assumes the full 130-unit timeline spans ~240 seconds.
    private static func clipUnits(for seconds: Double) -> CGFloat {
        let units = CGFloat(seconds / 240.0) * 130
        return min(max(units, 10), 120)
    }
}
