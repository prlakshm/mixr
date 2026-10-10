import Foundation

/// Audio the app keeps its own copy of (songs dropped onto the timeline).
/// Lives in Application Support, which iOS never purges (unlike tmp), and
/// is found again by its path inside the store if an app update moves the
/// app's container.
nonisolated enum ImportedAudioStore {
    static let folderName = "ImportedAudio"

    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Copies `source` into the store (its own subfolder, keeping the file
    /// name, which carries "Artist - Title").
    static func copy(_ source: URL) -> URL? {
        guard let base = directory else { return nil }
        let folder = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// The same file in today's container when a saved path points into an
    /// older one (or nil if the path isn't in the store).
    static func relocated(_ path: String) -> URL? {
        guard let base = directory,
              let range = path.range(of: "/\(folderName)/") else { return nil }
        let candidate = base.appendingPathComponent(String(path[range.upperBound...]))
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
