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
    /// then asynchronously patches embedded metadata, duration, and clip length per track by UUID.
    func addTracks(from urls: [URL]) {
        for url in urls {
            let color   = colorCycle[tracks.count % colorCycle.count]
            let trackID = UUID()
            let parsed  = Self.parsedFilenameMetadata(from: url)
            let title   = parsed.title ?? url.deletingPathExtension().lastPathComponent

            let placeholder = MixrTrack(
                id: trackID,
                title: title,
                artist: parsed.artist ?? "Unknown Artist",
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
                let metadata = await Self.audioMetadata(from: url)
                guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[idx].title  = metadata.title
                tracks[idx].artist = metadata.artist

                if let seconds = metadata.durationSeconds {
                    tracks[idx].duration        = Self.formattedDuration(seconds)
                    tracks[idx].durationSeconds = seconds
                    tracks[idx].clips[0].length = Self.clipUnits(for: seconds)
                }
            }
        }
    }

    // MARK: - Reorder

    func reorder(from source: IndexSet, to destination: Int) {
        withAnimation(.easeOut(duration: 0.22)) {
            tracks.move(fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: - Delete

    func deleteTrack(id: UUID) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            tracks.removeAll { $0.id == id }
        }
    }

    // MARK: - Helpers

    private static func formattedDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func audioMetadata(from url: URL) async -> ImportedAudioMetadata {
        let parsed = parsedFilenameMetadata(from: url)
        let fallbackTitle = parsed.title ?? url.deletingPathExtension().lastPathComponent
        let fallbackArtist = parsed.artist ?? "Unknown Artist"
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let fullMetadata = (try? await asset.load(.metadata)) ?? []
        let metadata = commonMetadata + fullMetadata

        let title = await stringValue(
            in: metadata,
            identifiers: [
                .commonIdentifierTitle,
                .iTunesMetadataSongName,
                .id3MetadataTitleDescription,
            ]
        ) ?? fallbackTitle

        let artist = await stringValue(
            in: metadata,
            identifiers: [
                .commonIdentifierArtist,
                .iTunesMetadataArtist,
                .id3MetadataLeadPerformer,
            ]
        )

        let albumArtist = await stringValue(
            in: metadata,
            identifiers: [
                .iTunesMetadataAlbumArtist,
                .id3MetadataBand,
            ]
        )

        let cmDuration = try? await asset.load(.duration)
        let seconds = cmDuration.map(CMTimeGetSeconds)
        let validSeconds = seconds.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }

        return ImportedAudioMetadata(
            title: title,
            artist: artist ?? albumArtist ?? fallbackArtist,
            durationSeconds: validSeconds
        )
    }

    private static func stringValue(
        in metadata: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier]
    ) async -> String? {
        for identifier in identifiers {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: identifier
            )

            for item in items {
                let value = (try? await item.load(.stringValue))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let value, !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    private static func parsedFilenameMetadata(from url: URL) -> FilenameMetadata {
        let filename = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" - ", " – ", " — "]

        for separator in separators where filename.contains(separator) {
            let parts = filename.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }

            let artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts.dropFirst().joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return FilenameMetadata(
                title: title.isEmpty ? nil : title,
                artist: artist.isEmpty ? nil : artist
            )
        }

        return FilenameMetadata(title: filename.isEmpty ? nil : filename, artist: nil)
    }

    /// Maps audio duration to timeline clip length in units.
    /// Assumes the full 130-unit timeline spans ~240 seconds.
    private static func clipUnits(for seconds: Double) -> CGFloat {
        let units = CGFloat(seconds / 240.0) * 130
        return min(max(units, 10), 120)
    }
}

private struct ImportedAudioMetadata {
    let title: String
    let artist: String
    let durationSeconds: Double?
}

private struct FilenameMetadata {
    let title: String?
    let artist: String?
}
