import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import SwiftData

// MARK: - Edit Scope

/// What an undoable edit touches — captures stay scoped and lightweight
/// (value-typed, copy-on-write) instead of snapshotting the whole app.
enum TimelineEditScope {
    /// One clip's properties (transitions, effects, volume, speed field).
    case clip(UUID)
    /// One track's entire clip array (structural edits + their ripple).
    case trackClips(UUID)
    /// One track's mix state (volume / mute / solo).
    case trackMix(UUID)
    /// Multi-track structure: import, track delete/reorder, Auto, SFX-track creation.
    case tracks
    /// The project's display name.
    case projectName
}

/// Value-typed before/after capture for one scope — small, CoW-backed.
enum TimelineEditState: Equatable {
    case clip(MixrClip)
    case trackClips(trackID: UUID, clips: [MixrClip])
    case trackMix(trackID: UUID, volume: Double, isMuted: Bool, isSoloed: Bool)
    case tracks([MixrTrack], selectedTrackID: UUID?, projectBPM: Int?)
    case projectName(String)

    var scope: TimelineEditScope {
        switch self {
        case .clip(let clip): .clip(clip.id)
        case .trackClips(let trackID, _): .trackClips(trackID)
        case .trackMix(let trackID, _, _, _): .trackMix(trackID)
        case .tracks: .tracks
        case .projectName: .projectName
        }
    }
}

// MARK: - Track Library

@MainActor
final class TrackLibrary: ObservableObject {
    @Published var tracks: [MixrTrack] = []
    @Published var selectedTrackID: UUID?
    @Published private(set) var projectBPM: Int?

    // Project state
    @Published var projectName: String = "My Remix"
    @Published private(set) var projects: [ProjectSummary] = []

    // Undo / redo — Foundation UndoManager (window-provided, session-only).
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private weak var undoManager: UndoManager?
    private var undoObservers: [NSObjectProtocol] = []
    /// In-flight gesture capture (clip drag, slider drag) — registered on commit.
    private var pendingEdit: (name: String, before: TimelineEditState)?

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
        // Register only the synchronous placeholder insertion; the async
        // metadata patches that follow are not user edits.
        beginGestureEdit("Import Songs", scope: .tracks)
        defer { commitGestureEdit() }

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
        performEdit("Reorder Tracks", scope: .tracks) {
            withAnimation(.easeOut(duration: 0.22)) {
                tracks.move(fromOffsets: source, toOffset: destination)
            }
        }
    }

    // MARK: - Delete

    func deleteTrack(id: UUID) {
        performEdit("Delete Track", scope: .tracks) {
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
    }

    // MARK: - Mix Controls (solo / mute / volume)

    func toggleSolo(trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        performEdit("Solo Track", scope: .trackMix(trackID)) {
            tracks[idx].isSoloed.toggle()
        }
    }

    func toggleMute(trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        performEdit("Mute Track", scope: .trackMix(trackID)) {
            tracks[idx].isMuted.toggle()
        }
    }

    /// Whether a track is currently audible given mute and solo state.
    static func isAudible(_ track: MixrTrack, in tracks: [MixrTrack]) -> Bool {
        guard !track.isMuted else { return false }
        let soloActive = tracks.contains { $0.isSoloed }
        return !soloActive || track.isSoloed
    }

    // MARK: - Sound Effects

    /// Adds an SFX clip at the playhead on the first SFX row that fits at
    /// that exact time; otherwise creates an adjacent SFX row (same as
    /// dragging a one-shot up/down). Per row, clips never overlap.
    @discardableResult
    func addSoundEffect(_ definition: SoundEffectDefinition, atPlayheadUnit unit: CGFloat) -> UUID {
        let existingSFXTrackID = tracks.first(where: { $0.isSFXTrack })?.id
        let willNeedNewLane: Bool = {
            let want = max(0, unit)
            let sfx = tracks.filter(\.isSFXTrack)
            guard !sfx.isEmpty else { return true }
            return !sfx.contains {
                SoundEffectLibrary.fitsExactly(
                    proposedStart: want,
                    lengthUnits: definition.lengthUnits,
                    in: $0.clips
                )
            }
        }()
        // New spill lane is structural; exact fit on an existing row is clips-only.
        let scope: TimelineEditScope = (!willNeedNewLane && existingSFXTrackID != nil)
            ? .trackClips(existingSFXTrackID!)
            : .tracks

        var newClipID = UUID()
        performEdit("Add Sound Effect", scope: scope) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                SoundEffectLibrary.placeExact(
                    definition: definition,
                    atUnit: max(0, unit),
                    into: &tracks,
                    clipID: newClipID
                )
            }
        }
        return newClipID
    }

    // MARK: - Undo / Redo (Foundation UndoManager)

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

    /// Connects the window's UndoManager (from @Environment(\.undoManager)).
    /// History is session-only; SwiftData persists only the latest state.
    /// SwiftData's ModelContext undo is deliberately NOT connected — the
    /// debounced snapshot autosave would otherwise pollute the stack.
    func attachUndoManager(_ manager: UndoManager?) {
        guard manager !== undoManager else { return }
        for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
        undoObservers.removeAll()
        undoManager = manager
        pendingEdit = nil

        if let manager {
            manager.levelsOfUndo = 60
            let events: [Notification.Name] = [
                .NSUndoManagerDidCloseUndoGroup,
                .NSUndoManagerDidUndoChange,
                .NSUndoManagerDidRedoChange,
                .NSUndoManagerCheckpoint,
            ]
            for name in events {
                undoObservers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: manager, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.updateHistoryFlags()
                        }
                    }
                )
            }
        }
        updateHistoryFlags()
    }

    func undo() {
        guard undoManager?.canUndo == true else { return }
        undoManager?.undo()
        updateHistoryFlags()
    }

    func redo() {
        guard undoManager?.canRedo == true else { return }
        undoManager?.redo()
        updateHistoryFlags()
    }

    private func updateHistoryFlags() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    // MARK: Scoped capture / restore

    /// Current state for a scope, or nil when the scope's target is gone.
    private func captureState(for scope: TimelineEditScope) -> TimelineEditState? {
        switch scope {
        case .clip(let clipID):
            for track in tracks {
                if let clip = track.clips.first(where: { $0.id == clipID }) {
                    return .clip(clip)
                }
            }
            return nil
        case .trackClips(let trackID):
            guard let track = tracks.first(where: { $0.id == trackID }) else { return nil }
            return .trackClips(trackID: trackID, clips: track.clips)
        case .trackMix(let trackID):
            guard let track = tracks.first(where: { $0.id == trackID }) else { return nil }
            return .trackMix(
                trackID: trackID,
                volume: track.volume,
                isMuted: track.isMuted,
                isSoloed: track.isSoloed
            )
        case .tracks:
            return .tracks(tracks, selectedTrackID: selectedTrackID, projectBPM: projectBPM)
        case .projectName:
            return .projectName(projectName)
        }
    }

    /// Restores a captured state in place. Clip/track identity is matched by
    /// UUID — restored clips keep their original ids, effects, transitions,
    /// speeds, and source offsets (they're value copies, never re-created).
    private func restore(_ state: TimelineEditState) {
        switch state {
        case .clip(let clip):
            for ti in tracks.indices {
                if let ci = tracks[ti].clips.firstIndex(where: { $0.id == clip.id }) {
                    tracks[ti].clips[ci] = clip
                    return
                }
            }
        case .trackClips(let trackID, let clips):
            if let ti = tracks.firstIndex(where: { $0.id == trackID }) {
                tracks[ti].clips = clips
            }
        case .trackMix(let trackID, let volume, let isMuted, let isSoloed):
            if let ti = tracks.firstIndex(where: { $0.id == trackID }) {
                tracks[ti].volume = volume
                tracks[ti].isMuted = isMuted
                tracks[ti].isSoloed = isSoloed
            }
        case .tracks(let all, let selected, let bpm):
            tracks = all
            selectedTrackID = selected
            projectBPM = bpm
        case .projectName(let name):
            projectName = name
        }
    }

    /// Registers one atomic undo step. The undo handler captures the
    /// then-current state and re-registers it, which UndoManager routes to
    /// the redo stack — redo reproduces the exact resulting arrangement,
    /// and a fresh edit clears redo via standard UndoManager behavior.
    private func registerEdit(named name: String, before: TimelineEditState) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { library in
            MainActor.assumeIsolated {
                let current = library.captureState(for: before.scope)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    library.restore(before)
                }
                if let current {
                    library.registerEdit(named: name, before: current)
                }
                library.scheduleAutosave()
            }
        }
        undoManager.setActionName(name)
        updateHistoryFlags()
        scheduleAutosave()
    }

    // MARK: Edit API — views call these; no undo registration in views.

    /// One-shot edit: capture → mutate → register (skipped when nothing changed).
    func performEdit(_ name: String, scope: TimelineEditScope, _ mutate: () -> Void) {
        let before = captureState(for: scope)
        mutate()
        guard let before,
              let after = captureState(for: before.scope),
              after != before
        else { return }
        registerEdit(named: name, before: before)
    }

    /// Gesture edits (clip drag, sliders): capture when the gesture begins…
    func beginGestureEdit(_ name: String, scope: TimelineEditScope) {
        guard pendingEdit == nil, let before = captureState(for: scope) else { return }
        pendingEdit = (name, before)
    }

    /// …register exactly one undo step when it commits (nothing per-frame)…
    func commitGestureEdit() {
        guard let pending = pendingEdit else { return }
        pendingEdit = nil
        guard let after = captureState(for: pending.before.scope),
              after != pending.before
        else { return }
        registerEdit(named: pending.name, before: pending.before)
    }

    /// …or drop the capture when the gesture cancels.
    func cancelGestureEdit() {
        pendingEdit = nil
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
        // History is per-project and session-only: switching starts fresh.
        undoManager?.removeAllActions()
        pendingEdit = nil
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
        undoManager?.removeAllActions()
        pendingEdit = nil
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
        performEdit("Rename Project", scope: .projectName) {
            projectName = trimmed
        }
        saveCurrentProject()
    }

    /// Deletes the current project. Switches to the next most-recent project,
    /// or creates a fresh empty "My Remix" when it was the last one.
    func deleteCurrentProject() {
        guard let modelContext, let id = currentProjectID,
              let record = record(for: id)
        else { return }

        modelContext.delete(record)
        try? modelContext.save()

        undoManager?.removeAllActions()
        pendingEdit = nil
        updateHistoryFlags()

        let remaining = fetchRecords()
        if let next = remaining.first {
            currentProjectID = next.id
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                if let snapshot = ProjectSnapshotCoder.decode(next.snapshotData) {
                    apply(snapshot)
                } else {
                    projectName = next.name
                    tracks = []
                    selectedTrackID = nil
                    projectBPM = nil
                }
            }
            refreshProjectSummaries()
        } else {
            let name = uniqueProjectName(base: "My Remix")
            let fresh = MixrProjectRecord(name: name)
            modelContext.insert(fresh)
            try? modelContext.save()
            currentProjectID = fresh.id
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                projectName = name
                tracks = []
                selectedTrackID = nil
                projectBPM = nil
            }
            refreshProjectSummaries()
        }
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
