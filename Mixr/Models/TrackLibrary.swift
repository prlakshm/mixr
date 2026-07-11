import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import SwiftData

// MARK: - Track Library

@MainActor
final class TrackLibrary: ObservableObject {
    @Published var tracks: [MixrTrack] = []
    @Published var selectedTrackID: UUID?
    @Published private(set) var projectBPM: Int?

    // Project state
    @Published var projectName: String = "My Remix"
    @Published private(set) var projects: [ProjectSummary] = []

    // Undo / redo
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var undoStack: [ProjectSnapshot] = []
    private var redoStack: [ProjectSnapshot] = []
    private let undoLimit = 50

    // Persistence
    private var modelContext: ModelContext?
    private var currentProjectID: UUID?
    private var autosaveTask: Task<Void, Never>?

    private let colorCycle: [MixrWaveformColor] = [.pink, .purple, .red, .yellow, .blue]

    var displayKey: String {
        if let selectedTrackID,
           let track = tracks.first(where: { $0.id == selectedTrackID }),
           track.key != nil {
            return track.keyDisplay
        }
        return tracks.first(where: { $0.key != nil })?.keyDisplay ?? "--"
    }

    var projectBPMDisplay: String {
        projectBPM.map(String.init) ?? "--"
    }

    // MARK: - Import

    /// Appends placeholder tracks immediately (preserving selection order and color assignment),
    /// then asynchronously patches embedded metadata, duration, and clip length per track by UUID.
    func addTracks(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        pushUndoSnapshot()

        for url in urls {
            let songCount = tracks.filter { !$0.isSFXTrack }.count
            let color   = colorCycle[songCount % colorCycle.count]
            let trackID = UUID()
            let parsed  = Self.parsedFilenameMetadata(from: url)
            let title   = parsed.title ?? url.deletingPathExtension().lastPathComponent

            let placeholder = MixrTrack(
                id: trackID,
                title: title,
                artist: parsed.artist ?? "Unknown Artist",
                duration: "--:--",
                durationSeconds: nil,
                bpm: nil,
                key: nil,
                color: color,
                volume: 0.75,
                isMuted: false,
                url: url,
                artworkData: nil,
                clips: [MixrClip(id: UUID(), start: 0, length: 48)]
            )
            // Keep the SFX track pinned below all song tracks.
            if let sfxIdx = tracks.firstIndex(where: { $0.isSFXTrack }) {
                tracks.insert(placeholder, at: sfxIdx)
            } else {
                tracks.append(placeholder)
            }

            if selectedTrackID == nil {
                selectedTrackID = trackID
            }

            Task {
                // ── Phase 1: embedded metadata (fast) ──
                let metadata = await Self.audioMetadata(from: url)
                guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }

                tracks[idx].title       = metadata.title
                tracks[idx].artist      = metadata.artist
                tracks[idx].artworkData = metadata.artworkData

                if let bpm = metadata.bpm {
                    tracks[idx].bpm           = bpm
                    tracks[idx].bpmConfidence = nil  // from embedded metadata, fully trusted
                    if projectBPM == nil { projectBPM = bpm }
                }
                if let key = metadata.key {
                    tracks[idx].key           = key
                    tracks[idx].keyConfidence = nil
                }

                if let seconds = metadata.durationSeconds {
                    tracks[idx].duration        = Self.formattedDuration(seconds)
                    tracks[idx].durationSeconds = seconds
                    tracks[idx].clips[0].length = Self.clipUnits(for: seconds)
                }
                scheduleAutosave()

                // ── Phase 2: on-device audio analysis when metadata is absent ──
                let needsBPM = metadata.bpm == nil
                let needsKey = metadata.key == nil
                guard needsBPM || needsKey else { return }

                let analysis = await MixrAudioAnalyzer.analyze(url: url)
                guard let idx2 = tracks.firstIndex(where: { $0.id == trackID }) else { return }

                let bpmThreshold = 0.30
                let keyThreshold = 0.25

                if needsBPM,
                   let bpm  = analysis.bpm,
                   let conf = analysis.bpmConfidence, conf >= bpmThreshold {
                    tracks[idx2].bpm           = bpm
                    tracks[idx2].bpmConfidence = conf
                    if projectBPM == nil { projectBPM = bpm }
                }

                if needsKey,
                   let key  = analysis.key,
                   let conf = analysis.keyConfidence, conf >= keyThreshold {
                    tracks[idx2].key           = key
                    tracks[idx2].keyConfidence = conf
                }
                scheduleAutosave()
            }
        }
    }

    // MARK: - Selection

    func selectTrack(id: UUID) {
        selectedTrackID = id
    }

    // MARK: - Reorder

    func reorder(from source: IndexSet, to destination: Int) {
        withAnimation(.easeOut(duration: 0.22)) {
            tracks.move(fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: - Delete

    func deleteTrack(id: UUID) {
        pushUndoSnapshot()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            tracks.removeAll { $0.id == id }
        }

        if selectedTrackID == id {
            selectedTrackID = tracks.first?.id
        }

        if tracks.isEmpty {
            selectedTrackID = nil
            projectBPM = nil
        }
    }

    // MARK: - Mix Controls (solo / mute / volume)

    func toggleSolo(trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        pushUndoSnapshot()
        tracks[idx].isSoloed.toggle()
    }

    func toggleMute(trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        pushUndoSnapshot()
        tracks[idx].isMuted.toggle()
    }

    /// Whether a track is currently audible given mute and solo state.
    static func isAudible(_ track: MixrTrack, in tracks: [MixrTrack]) -> Bool {
        guard !track.isMuted else { return false }
        let soloActive = tracks.contains { $0.isSoloed }
        return !soloActive || track.isSoloed
    }

    // MARK: - Sound Effects

    /// Index of the silver SFX track, creating it (pinned last) if needed.
    @discardableResult
    private func ensureSFXTrack() -> Int {
        if let idx = tracks.firstIndex(where: { $0.isSFXTrack }) { return idx }
        let sfxTrack = MixrTrack(
            id: UUID(),
            title: "Sound Effects",
            artist: "Built-in SFX",
            duration: "",
            durationSeconds: nil,
            bpm: nil,
            key: nil,
            color: .silver,
            volume: 0.85,
            isMuted: false,
            trackType: .soundEffect,
            url: nil,
            artworkData: nil,
            clips: []
        )
        tracks.append(sfxTrack)
        return tracks.count - 1
    }

    /// Adds an SFX clip at the playhead, sliding right past any overlapping
    /// SFX clips (never overlapping, never negative). Returns the new clip id.
    @discardableResult
    func addSoundEffect(_ definition: SoundEffectDefinition, atPlayheadUnit unit: CGFloat) -> UUID {
        pushUndoSnapshot()
        let idx = withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            ensureSFXTrack()
        }
        let start = SoundEffectLibrary.nonOverlappingStart(
            proposedStart: max(0, unit),
            lengthUnits: definition.lengthUnits,
            in: tracks[idx].clips
        )
        let clip = MixrClip(
            id: UUID(),
            start: start,
            length: definition.lengthUnits,
            soundEffectID: definition.id
        )
        tracks[idx].clips.append(clip)
        tracks[idx].clips.sort { $0.start < $1.start }
        return clip.id
    }

    // MARK: - Undo / Redo

    private var currentSnapshot: ProjectSnapshot {
        ProjectSnapshot(
            name: projectName,
            tracks: tracks,
            selectedTrackID: selectedTrackID,
            projectBPM: projectBPM
        )
    }

    private func apply(_ snapshot: ProjectSnapshot) {
        projectName = snapshot.name
        tracks = snapshot.tracks
        selectedTrackID = snapshot.selectedTrackID
        projectBPM = snapshot.projectBPM
    }

    /// Call BEFORE any meaningful mutation. New edits clear the redo stack.
    func pushUndoSnapshot() {
        undoStack.append(currentSnapshot)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        updateHistoryFlags()
        scheduleAutosave()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            apply(snapshot)
        }
        updateHistoryFlags()
        scheduleAutosave()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            apply(snapshot)
        }
        updateHistoryFlags()
        scheduleAutosave()
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Projects (SwiftData persistence)

    func attachPersistence(context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        // Yield so the first SwiftUI frame can paint before SwiftData I/O and
        // audio graph setup (avoids a long black screen on launch).
        Task { @MainActor in
            await Task.yield()
            loadProjects()
        }
    }

    private func fetchRecords() -> [MixrProjectRecord] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<MixrProjectRecord>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func record(for id: UUID) -> MixrProjectRecord? {
        fetchRecords().first { $0.id == id }
    }

    private func loadProjects() {
        guard let modelContext else { return }
        let records = fetchRecords()

        if let latest = records.first {
            currentProjectID = latest.id
            if let snapshot = ProjectSnapshotCoder.decode(latest.snapshotData) {
                apply(snapshot)
            } else {
                projectName = latest.name
            }
        } else {
            let record = MixrProjectRecord(name: projectName)
            modelContext.insert(record)
            try? modelContext.save()
            currentProjectID = record.id
        }
        refreshProjectSummaries()
    }

    private func refreshProjectSummaries() {
        projects = fetchRecords().map {
            ProjectSummary(id: $0.id, name: $0.name, modifiedAt: $0.modifiedAt)
        }
    }

    var currentProjectSummaryID: UUID? { currentProjectID }

    func saveCurrentProject() {
        guard let modelContext, let id = currentProjectID,
              let record = record(for: id)
        else { return }
        record.name = projectName
        record.modifiedAt = Date()
        if let data = ProjectSnapshotCoder.encode(currentSnapshot) {
            record.snapshotData = data
        }
        try? modelContext.save()
        refreshProjectSummaries()
    }

    /// Debounced autosave — call after any project mutation.
    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.saveCurrentProject()
        }
    }

    func switchProject(to id: UUID) {
        guard id != currentProjectID, let modelContext else { return }
        saveCurrentProject()
        guard let target = record(for: id) else { return }

        currentProjectID = id
        // History is per-project: switching starts a fresh history.
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryFlags()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            if let snapshot = ProjectSnapshotCoder.decode(target.snapshotData) {
                apply(snapshot)
            } else {
                projectName = target.name
                tracks = []
                selectedTrackID = nil
                projectBPM = nil
            }
        }
        try? modelContext.save()
        refreshProjectSummaries()
    }

    func createProject() {
        guard let modelContext else { return }
        saveCurrentProject()

        let name = uniqueProjectName(base: "My Remix")
        let record = MixrProjectRecord(name: name)
        modelContext.insert(record)
        try? modelContext.save()

        currentProjectID = record.id
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryFlags()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            projectName = name
            tracks = []
            selectedTrackID = nil
            projectBPM = nil
        }
        refreshProjectSummaries()
    }

    func renameCurrentProject(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != projectName else { return }
        pushUndoSnapshot()
        projectName = trimmed
        saveCurrentProject()
    }

    private func uniqueProjectName(base: String) -> String {
        let existing = Set(fetchRecords().map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
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

        let bpm = await bpmValue(in: metadata)
        let key = await keyValue(in: metadata)

        let artworkData = await artworkData(in: metadata)

        let cmDuration = try? await asset.load(.duration)
        let seconds = cmDuration.map(CMTimeGetSeconds)
        let validSeconds = seconds.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }

        return ImportedAudioMetadata(
            title: title,
            artist: artist ?? albumArtist ?? fallbackArtist,
            durationSeconds: validSeconds,
            bpm: bpm,
            key: normalizedKey(key),
            artworkData: artworkData
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

    private static func bpmValue(in metadata: [AVMetadataItem]) async -> Int? {
        let identifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataBeatsPerMin,
        ]

        for identifier in identifiers {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: identifier
            )

            for item in items {
                if let number = try? await item.load(.numberValue) {
                    let bpm = number.intValue
                    if bpm > 0 { return bpm }
                }

                if let string = try? await item.load(.stringValue) {
                    if let bpm = parseBPM(string) { return bpm }
                }
            }
        }

        return nil
    }

    private static func parseBPM(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed), value > 0 { return value }

        let digits = trimmed.filter(\.isNumber)
        if let value = Int(digits), value > 0 { return value }
        return nil
    }

    private static func keyValue(in metadata: [AVMetadataItem]) async -> String? {
        for item in metadata {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            guard identifier.contains("key") else { continue }

            if let value = try? await item.load(.stringValue) {
                if let normalized = normalizedKey(value) { return normalized }
            }
        }

        return nil
    }

    private static func normalizedKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func artworkData(in metadata: [AVMetadataItem]) async -> Data? {
        let items = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierArtwork
        )

        for item in items {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
        }

        let iTunesItems = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .iTunesMetadataCoverArt
        )

        for item in iTunesItems {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
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
    static func clipUnits(for seconds: Double) -> CGFloat {
        let units = CGFloat(seconds / 240.0) * 130
        return min(max(units, 10), 120)
    }
}

private struct ImportedAudioMetadata {
    let title: String
    let artist: String
    let durationSeconds: Double?
    let bpm: Int?
    let key: String?
    let artworkData: Data?
}

private struct FilenameMetadata {
    let title: String?
    let artist: String?
}
