import Foundation
import SwiftData

// MARK: - Project Snapshot

/// Full serializable project state — used both for SwiftData persistence and
/// as the unit of the undo/redo history.
struct ProjectSnapshot: Codable {
    var name: String
    var tracks: [MixrTrack]
    var selectedTrackID: UUID?
    var projectBPM: Int?
}

// MARK: - SwiftData Record

/// One persisted project. The timeline graph is stored as an encoded
/// ProjectSnapshot blob — simple, stable, and schema-migration-free for V1.
@Model
final class MixrProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var snapshotData: Data

    init(id: UUID = UUID(), name: String, snapshotData: Data = Data()) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.snapshotData = snapshotData
    }
}

// MARK: - Summary (for the project dropdown)

struct ProjectSummary: Identifiable, Equatable {
    let id: UUID
    var name: String
    var modifiedAt: Date
}

// MARK: - Snapshot Coding

enum ProjectSnapshotCoder {
    static func encode(_ snapshot: ProjectSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Data) -> ProjectSnapshot? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(ProjectSnapshot.self, from: data)
    }
}
