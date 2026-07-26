import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - Screen Layout Constants

enum TLK {
    static let sidebarWidth: CGFloat      = 208
    static let transportHeight: CGFloat   = 50
    static let rulerHeight: CGFloat       = 20
    static let trackRowHeight: CGFloat    = 46
    static let waveformHeight: CGFloat    = 34
    static let smColumnWidth: CGFloat     = 130
    static let trackToggleSize: CGFloat   = 28
    static let effectsExpandedHeight: CGFloat   = 118
    static let effectsCollapsedHeight: CGFloat  = 42
    static let effectsHeight: CGFloat           = effectsExpandedHeight
    static let playheadUnit: CGFloat      = 0
    static let playheadHandleWidth: CGFloat  = 17
    static let playheadHandleHeight: CGFloat = 14
    static let timelineUnitWidth: CGFloat = 10
    static let totalUnits: CGFloat        = 130
    static let compactEffectScale: CGFloat         = 1.0
    static let compactEffectCardWidth: CGFloat     = 152
    static let compactEffectCardHeight: CGFloat    = 66
    static let markerUnits: [CGFloat]     = [0, 17, 33, 49, 65, 81, 97, 113, 129]
    static let importFooterHeight: CGFloat = 46
    static let importFooterHorizontalPadding: CGFloat = 12
    static let importFooterButtonSpacing: CGFloat = 7
    /// Exact width of the tracks-footer Import Songs control (sidebar minus
    /// padding, gap, and SFX chrome) — reused by the empty-timeline CTA.
    static var sidebarImportSongsWidth: CGFloat {
        sidebarWidth
            - importFooterHorizontalPadding * 2
            - importFooterButtonSpacing
            - MixrSFXOutlineButtonLabel.chromeWidth
    }
    static let timelineDurationSeconds: CGFloat = 240
    static let gridLineStepSeconds: CGFloat = 10
    static let rulerLabelStepSeconds: CGFloat = 30

    /// Timeline layering — playhead line above tracks; handle above line; clip-editing overlays highest.
    static let timelinePlayheadLineZIndex:   CGFloat = 20
    static let timelinePlayheadHandleZIndex: CGFloat = 25
    static let timelineGripZIndex:           CGFloat = 10

    /// Duplicate auto-scroll — only when start is off-screen or in the last ~25% of viewport.
    static let duplicateScrollViewportAnchor:  CGFloat = 0.275   // 27.5% from leading edge
    static let duplicateScrollComfortThreshold:  CGFloat = 0.75    // scroll if past 75% of viewport
    static let duplicateScrollAnimationDuration: Double  = 0.55

    /// Ease-out curve — starts confidently, decelerates into place (no spring).
    static var duplicateScrollAnimation: Animation {
        .timingCurve(0.22, 1.0, 0.36, 1.0, duration: duplicateScrollAnimationDuration)
    }

    static var gridLineSeconds: [CGFloat] {
        stride(
            from: 0,
            through: Int(timelineDurationSeconds),
            by: Int(gridLineStepSeconds)
        ).map { CGFloat($0) }
    }

    static var rulerLabelSeconds: [CGFloat] {
        stride(
            from: 0,
            through: Int(timelineDurationSeconds),
            by: Int(rulerLabelStepSeconds)
        ).map { CGFloat($0) }
    }

    static func timelineUnit(for seconds: CGFloat) -> CGFloat {
        (seconds / timelineDurationSeconds) * totalUnits
    }

    static func timeLabel(for seconds: CGFloat) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    static let majorGridUnits: Set<CGFloat> = Set(markerUnits)

    // Clip drag-move
    static let clipDragGhostOpacity:  Double  = 0.28
    static let clipDragLongPressDuration: Double = 0.50
    static let clipDragLongPressMaxDistance: CGFloat = 8
    static let clipDragLiftScale:     CGFloat = 1.05
    static let clipDragLiftY:         CGFloat = 6
    static let clipDragNeighborShift: CGFloat = 20       // pt shift each neighbor
    static let clipDragScrollZone:    CGFloat = 120      // px from viewport edge
    static let clipDragScrollSpeed:   CGFloat = 10       // max px per 60 fps frame
    static let clipDragShadowRadius:  CGFloat = 18
    static let clipDragShadowY:       CGFloat = 10
    static let clipDragScrimOpacity:  Double  = 0.52
    static let clipDragScrimAnim:     Double  = 0.13
    static let clipDragDropResponse:  Double  = 0.38
    static let clipDragDropDamping:   Double  = 0.80
    static let clipDragArmedSettleDuration: Double = 0.09
    static let clipInsertPreviewResponse: Double = 0.22
    static let clipInsertionSnapZone: CGFloat = 10
    static let clipInsertionSnapHysteresis: CGFloat = 8
    /// Indicator eases to its resolved target over this duration (magnetic snap glide).
    static let clipIndicatorEaseDuration: Double = 0.10
}

// MARK: - Clip Drag State

/// All positions are in the "tlareaRoot" named coordinate space (the outer ZStack of TLTrackArea),
/// which is OUTSIDE all scroll views and therefore stable as the timeline scrolls.
private struct ClipDragState {
    let clipID:       UUID
    let trackID:      UUID
    let trackIdx:     Int
    let originalClip: MixrClip

    /// Horizontal pixel offset from the clip's leading edge to the cursor at grab time.
    /// Expressed in content/screen pixels (equivalent in our 1:1 layout).
    let grabScreenPx: CGFloat

    /// Vertical pixel offset from the clip's top edge to the cursor at grab time,
    /// in TLTrackArea screen pixels.
    let grabScreenPy: CGFloat

    /// Cursor X in "tlareaRoot" coordinate space — stable across horizontal scroll changes.
    var cursorAreaX: CGFloat

    /// Cursor Y in "tlareaRoot" coordinate space — stable across vertical scroll changes.
    var cursorAreaY: CGFloat

    /// Intended horizontal scroll offset, maintained by the 60 fps scroll loop.
    /// Updated independently of the system's hScrollOffset so auto-scroll is accurate.
    var scrollX: CGFloat

    /// Content-pixel position of the clip's proposed leading edge.
    /// Kept in sync by updateClipDrag and the scroll loop.
    var proposedLeadingEdgePx: CGFloat

    /// Last resolved drop result — used for snap hysteresis.
    var lastDropResult: ClipDropResult?
    var lastPointerUnit: CGFloat?

    /// 0…1 animated gap opening when inserting into a clip body.
    var insertPreviewProgress: CGFloat = 0

    /// The resolved insertion start (timeline units) that the indicator eases toward.
    /// Updated every drag event; the indicator animates to its corresponding screen X.
    var resolvedInsertStart: CGFloat = 0
    var isIndicatorSnapped: Bool = false
    var activeSnapStart: CGFloat? = nil

    // MARK: - Helpers

    /// Raw proposed start in timeline units (before snap resolution).
    func proposedStart(contentUnits: CGFloat, contentW: CGFloat) -> CGFloat {
        guard contentW > 0 else { return 0 }
        return max(0, (proposedLeadingEdgePx / contentW) * contentUnits)
    }

    /// Pointer position in timeline units (pointer = leading edge + grab offset).
    func pointerUnit(contentUnits: CGFloat, contentW: CGFloat) -> CGFloat {
        guard contentW > 0 else { return 0 }
        let grabOffsetUnits = (grabScreenPx / contentW) * contentUnits
        return max(0, proposedStart(contentUnits: contentUnits, contentW: contentW) + grabOffsetUnits)
    }

    func snapZoneUnits(contentW: CGFloat, contentUnits: CGFloat) -> CGFloat {
        guard contentW > 0 else { return 0 }
        return (TLK.clipInsertionSnapZone / contentW) * contentUnits
    }

    func hysteresisUnits(contentW: CGFloat, contentUnits: CGFloat) -> CGFloat {
        guard contentW > 0 else { return 0 }
        return (TLK.clipInsertionSnapHysteresis / contentW) * contentUnits
    }

    mutating func resolveDropResult(contentUnits: CGFloat, contentW: CGFloat, clips: [MixrClip]) -> ClipDropResult {
        let raw = proposedStart(contentUnits: contentUnits, contentW: contentW)
        let pointer = pointerUnit(contentUnits: contentUnits, contentW: contentW)
        let result = MixrTimeline.resolveClipDrop(
            moving: clipID,
            rawStart: raw,
            pointerUnit: pointer,
            in: clips,
            snapZoneUnits: snapZoneUnits(contentW: contentW, contentUnits: contentUnits),
            hysteresisUnits: hysteresisUnits(contentW: contentW, contentUnits: contentUnits),
            previousResult: lastDropResult,
            previousPointerUnit: lastPointerUnit,
            originalStart: originalClip.start
        )
        lastDropResult = result
        lastPointerUnit = pointer
        return result
    }

    /// Re-resolves without any hysteresis — for use at drop commit only.
    func freshDropResult(contentUnits: CGFloat, contentW: CGFloat, clips: [MixrClip]) -> ClipDropResult {
        let raw = proposedStart(contentUnits: contentUnits, contentW: contentW)
        let pointer = pointerUnit(contentUnits: contentUnits, contentW: contentW)
        return MixrTimeline.resolveClipDrop(
            moving: clipID,
            rawStart: raw,
            pointerUnit: pointer,
            in: clips,
            snapZoneUnits: snapZoneUnits(contentW: contentW, contentUnits: contentUnits),
            hysteresisUnits: hysteresisUnits(contentW: contentW, contentUnits: contentUnits),
            previousResult: nil,
            previousPointerUnit: nil,
            originalStart: originalClip.start
        )
    }

    func currentDropResult(contentUnits: CGFloat, contentW: CGFloat, clips: [MixrClip]) -> ClipDropResult {
        if let lastDropResult { return lastDropResult }
        var copy = self
        return copy.resolveDropResult(contentUnits: contentUnits, contentW: contentW, clips: clips)
    }

    func insertionStart(for result: ClipDropResult) -> CGFloat {
        MixrTimeline.insertionStart(for: result, movingClipLength: originalClip.length)
    }

    private func nearestSnapStart(
        rawStart: CGFloat,
        contentUnits: CGFloat,
        contentW: CGFloat,
        clips: [MixrClip]
    ) -> CGFloat? {
        let snapZone = snapZoneUnits(contentW: contentW, contentUnits: contentUnits)
        let others = clips.filter { $0.id != clipID }
        var best: (start: CGFloat, distance: CGFloat)?

        for clip in others {
            let edges = [clip.start, clip.start + clip.length]
            for edge in edges {
                let distance = abs(rawStart - edge)
                guard distance <= snapZone + MixrTimeline.clipEdgeEpsilon else { continue }
                if best == nil || distance < best!.distance - MixrTimeline.clipEdgeEpsilon {
                    best = (max(0, edge), distance)
                }
            }
        }

        return best?.start
    }

    mutating func updateIndicatorTarget(
        contentUnits: CGFloat,
        contentW: CGFloat,
        clips: [MixrClip]
    ) -> (start: CGFloat, isSnapped: Bool) {
        let raw = proposedStart(contentUnits: contentUnits, contentW: contentW)
        let snapZone = snapZoneUnits(contentW: contentW, contentUnits: contentUnits)

        if let activeSnapStart {
            if abs(raw - activeSnapStart) <= snapZone + MixrTimeline.clipEdgeEpsilon {
                resolvedInsertStart = activeSnapStart
                isIndicatorSnapped = true
                return (activeSnapStart, true)
            }
            self.activeSnapStart = nil
        }

        if let snapStart = nearestSnapStart(
            rawStart: raw,
            contentUnits: contentUnits,
            contentW: contentW,
            clips: clips
        ) {
            activeSnapStart = snapStart
            resolvedInsertStart = snapStart
            isIndicatorSnapped = true
            return (snapStart, true)
        }

        resolvedInsertStart = raw
        isIndicatorSnapped = false
        return (raw, false)
    }

    func indicatorTarget(contentUnits: CGFloat, contentW: CGFloat, clips: [MixrClip]) -> (start: CGFloat, isSnapped: Bool) {
        if let activeSnapStart, isIndicatorSnapped {
            let raw = proposedStart(contentUnits: contentUnits, contentW: contentW)
            let snapZone = snapZoneUnits(contentW: contentW, contentUnits: contentUnits)
            if abs(raw - activeSnapStart) <= snapZone + MixrTimeline.clipEdgeEpsilon {
                return (activeSnapStart, true)
            }
        }

        let raw = proposedStart(contentUnits: contentUnits, contentW: contentW)
        if let snapStart = nearestSnapStart(
            rawStart: raw,
            contentUnits: contentUnits,
            contentW: contentW,
            clips: clips
        ) {
            return (snapStart, true)
        }
        return (raw, false)
    }

    func indicatorDropResult(contentUnits: CGFloat, contentW: CGFloat, clips: [MixrClip]) -> ClipDropResult {
        let insertStart = max(0, resolvedInsertStart)
        guard !isIndicatorSnapped else {
            return .place(start: insertStart)
        }

        return MixrTimeline.resolveClipDrop(
            moving: clipID,
            rawStart: insertStart,
            pointerUnit: insertStart,
            in: clips,
            snapZoneUnits: snapZoneUnits(contentW: contentW, contentUnits: contentUnits),
            hysteresisUnits: 0,
            previousResult: nil,
            previousPointerUnit: nil,
            originalStart: nil
        )
    }

    /// Converts a timeline-unit insertion start to screen X in tlareaRoot space.
    func indicatorScreenX(insertStart: CGFloat, contentUnits: CGFloat, contentW: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        guard contentUnits > 0 else { return sidebarWidth }
        return sidebarWidth + (insertStart / contentUnits) * contentW - scrollX
    }
}

// MARK: - Root

struct TimelineScreen: View {
    @StateObject private var library = TrackLibrary()
    @StateObject private var playback = MixrPlaybackEngine()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var envUndoManager
    @State private var showFilePicker = false
    @SceneStorage("editor.effects.isCollapsed")
    private var isEffectsCollapsed = false

    // Selected clip — shared by the timeline, effects panel, and Auto.
    @State private var selectedClipID: UUID?

    // Floating panel / dialog state
    @State private var showSFXPanel = false
    @State private var showAutoDialog = false
    @State private var isAutoRunning = false
    @State private var isExporting = false
    @State private var autoErrorMessage: String?
    @State private var showProjectMenu = false
    @State private var projectTitleFrame: CGRect = .zero
    @State private var showDeleteProjectConfirm = false

    // Playhead drag state
    @State private var isPlayheadDragging = false
    @State private var dragPlayheadUnit: CGFloat = 0
    @State private var wasPlayingBeforeDrag = false

    /// Displayed playhead position — drag overrides live position during scrub.
    private var effectivePlayheadUnit: CGFloat {
        isPlayheadDragging
            ? dragPlayheadUnit
            : MixrTimeline.units(fromSeconds: playback.currentTimeSeconds)
    }

    /// Displayed timestamp — shows dragged position while scrubbing.
    private var displayTimeSeconds: Double {
        isPlayheadDragging
            ? MixrTimeline.seconds(fromUnits: dragPlayheadUnit)
            : playback.currentTimeSeconds
    }

    /// Maximum unit the playhead can reach (= end of the longest clip).
    private var maxPlayheadUnit: CGFloat {
        MixrTimeline.units(fromSeconds: max(1, playback.totalDurationSeconds))
    }

    var body: some View {
        GeometryReader { geo in
            let layout = EditorLayoutMetrics(
                containerSize: geo.size,
                effectsState: EditorEffectsState(isCollapsed: isEffectsCollapsed)
            )

            ZStack {
                MixrColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    TLTransportBar(
                        playback: playback,
                        library: library,
                        layoutMode: layout.mode,
                        displayTimeSeconds: displayTimeSeconds,
                        isProjectMenuOpen: showProjectMenu,
                        isExporting: $isExporting,
                        onProjectTapped: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showProjectMenu.toggle()
                            }
                        },
                        onProjectRenameBegan: {
                            dismissProjectMenu()
                        }
                    )
                    .frame(height: layout.transportHeight)
                    .zIndex(1)

                    TLTrackArea(
                        tracks: $library.tracks,
                        selectedClipID: $selectedClipID,
                        selectedTrackID: library.selectedTrackID,
                        effectivePlayheadUnit: effectivePlayheadUnit,
                        maxPlayheadUnit: maxPlayheadUnit,
                        isPlayheadDragging: isPlayheadDragging,
                        bottomOverlayAllowance: layout.effectsHeight,
                        sidebarWidth: layout.tracksWidth,
                        controlsWidth: layout.controlsWidth,
                        importFooterHeight: layout.importFooterHeight,
                        showFilePicker: $showFilePicker,
                        showSFXPanel: $showSFXPanel,
                        sfxPresentationStyle: EditorPresentationRules.style(
                            availableWidth: geo.size.width
                        ),
                        onSelectSoundEffect: { effect in
                            library.addSoundEffect(
                                effect,
                                atPlayheadUnit: effectivePlayheadUnit
                            )
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        },
                        onImportURLs: { urls in
                            library.addTracks(from: urls)
                        },
                        onDeleteTrack: { id in
                            library.deleteTrack(id: id)
                        },
                        onReorder: { source, destination in
                            library.reorder(from: source, to: destination)
                        },
                        onSelectTrack: { id in
                            library.selectTrack(id: id)
                        },
                        onToggleSolo: { id in
                            library.toggleSolo(trackID: id)
                        },
                        onToggleMute: { id in
                            library.toggleMute(trackID: id)
                        },
                        onEditBegin: { name, scope in
                            library.beginGestureEdit(name, scope: scope)
                        },
                        onEditCommit: {
                            library.commitGestureEdit()
                        },
                        onEditCancel: {
                            library.cancelGestureEdit()
                        },
                        onMixSettingsChanged: {
                            playback.applyMixSettings(from: library.tracks, projectBPM: library.projectBPM)
                            library.scheduleAutosave()
                        },
                        onPlayheadDragStart: {
                            wasPlayingBeforeDrag = playback.isPlaying
                            if playback.isPlaying { playback.pause() }
                        },
                        onPlayheadDragChanged: { unit in
                            isPlayheadDragging = true
                            dragPlayheadUnit = unit
                        },
                        onPlayheadDragEnded: { unit in
                            isPlayheadDragging = false
                            let secs = MixrTimeline.seconds(fromUnits: unit)
                            playback.seek(to: secs)
                            if wasPlayingBeforeDrag { playback.play() }
                        },
                        onTimelineTapped: { unit in
                            isPlayheadDragging = false
                            playback.seek(to: MixrTimeline.seconds(fromUnits: unit))
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.timelineHeight)
                    .layoutPriority(1)
                    .zIndex(20)

                    TLEffectsPanel(
                        isCollapsed: $isEffectsCollapsed,
                        tracks: $library.tracks,
                        selectedClipID: selectedClipID,
                        playheadUnit: effectivePlayheadUnit,
                        onEditBegin: { name, scope in
                            library.beginGestureEdit(name, scope: scope)
                        },
                        onEditCommit: { library.commitGestureEdit() },
                        onAutoTapped: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                showAutoDialog = true
                            }
                        }
                    )
                    .frame(height: layout.effectsHeight)
                    .clipped()
                    .zIndex(0)
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isEffectsCollapsed)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                PartyModeMainChromeOverlay(
                    screenSize: geo.size,
                    effectsHeight: layout.effectsHeight
                )

                if showProjectMenu {
                    let menuX = max(
                        8,
                        (projectTitleFrame.minX > 0 ? projectTitleFrame.minX : 96)
                            - ProjectDropdownMenu.horizontalPadding
                    )

                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .onTapGesture { dismissProjectMenu() }

                        ProjectDropdownMenu(
                            projects: library.projects,
                            currentProjectID: library.currentProjectSummaryID,
                            currentName: library.projectName,
                            onSelectProject: { id in
                                selectedClipID = nil
                                library.switchProject(to: id)
                            },
                            onCreateProject: {
                                selectedClipID = nil
                                library.createProject()
                            },
                            onDeleteProject: {
                                dismissProjectMenu()
                                showDeleteProjectConfirm = true
                            },
                            onDismiss: { dismissProjectMenu() }
                        )
                        .offset(x: menuX, y: layout.transportHeight - 4)
                    }
                    .zIndex(95)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }

                floatingOverlays
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "timelineScreen")
            .onPreferenceChange(ProjectTitleFrameKey.self) {
                projectTitleFrame = $0
            }
            .confirmationDialog(
                "What should Auto remix?",
                isPresented: $showAutoDialog,
                titleVisibility: .visible
            ) {
                Button(selectedClipID == nil ? "Playhead Clips" : "Selected Clip") {
                    if let selectedClipID {
                        runAuto(scope: .selectedClip(selectedClipID))
                    } else {
                        runAuto(scope: .playheadClips)
                    }
                }
                Button("Entire Project") {
                    runAuto(scope: .entireProject)
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Delete “\(library.projectName)”?",
                isPresented: $showDeleteProjectConfirm
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    selectedClipID = nil
                    library.deleteCurrentProject()
                }
            }
            .alert(
                "Auto couldn’t finish",
                isPresented: Binding(
                    get: { autoErrorMessage != nil },
                    set: { if !$0 { autoErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(autoErrorMessage ?? "")
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .task {
            library.attachPersistence(context: modelContext)
            library.attachUndoManager(envUndoManager)
        }
        // The window's UndoManager can arrive/change after first render.
        .onChange(of: envUndoManager.map(ObjectIdentifier.init)) { _, _ in
            library.attachUndoManager(envUndoManager)
        }
        // Track list or clip geometry changed → full sync (may add/remove players)
        .onChange(of: library.tracks.map { track in
            track.clips.map { "\($0.start):\($0.length)" }.joined(separator: ",")
        }.joined(separator: "|")) { _, _ in
            playback.syncTracks(library.tracks, projectBPM: library.projectBPM)
            library.scheduleAutosave()
        }
        // Only volume/mute/solo changed → lightweight update, does NOT restart engine
        .onChange(of: library.tracks.map { "\($0.id):\($0.volume):\($0.isMuted):\($0.isSoloed)" }.joined()) { _, _ in
            playback.applyMixSettings(from: library.tracks, projectBPM: library.projectBPM)
            library.scheduleAutosave()
        }
        // Per-clip settings changed (effect levels/presets, clip volume,
        // transitions). Every effect is live-ramped on the running graph
        // (the flanger kernel smooths its own parameters), so a lightweight
        // snapshot update is enough — no reschedule, no playback restart.
        .onChange(of: library.tracks.map { track in
            track.clips.map { clip in
                let fx = clip.effects
                let levels = fx.levels
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ";")
                return "\(clip.id):\(clip.volume):\(levels):\(fx.reverbPreset.rawValue):\(fx.echoPreset.rawValue):\(fx.pitchDirection.rawValue):"
                    + "\(clip.transitionIn.type.rawValue)@\(clip.transitionIn.duration):"
                    + "\(clip.transitionOut.type.rawValue)@\(clip.transitionOut.duration)"
            }.joined(separator: ",")
        }.joined(separator: "|")) { _, _ in
            playback.applyMixSettings(from: library.tracks, projectBPM: library.projectBPM)
            library.scheduleAutosave()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.mp3, .wav, .mpeg4Audio, .aiff, .audio],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            library.addTracks(from: urls)
        }
    }

    // MARK: - Floating overlays

    @ViewBuilder
    private var floatingOverlays: some View {
        // Auto / Export loading — same full-screen spinner.
        if isAutoRunning || isExporting {
            MixrAutoLoadingOverlay(
                accessibilityLabelText: isExporting ? "Exporting" : "Auto is running"
            )
            .zIndex(80)
            .transition(.opacity)
        }
    }

    private func dismissProjectMenu() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            showProjectMenu = false
        }
    }

    // MARK: - Auto

    /// Runs Auto for the chosen scope.
    /// Entire Project → plan pipeline (validate → apply).
    /// Selected Clip / Playhead → AutoArrangementEngine.
    /// Success lands directly on the timeline (same one-step feel as focused scopes).
    private func runAuto(scope: AutoScope) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            showAutoDialog = false
            isAutoRunning = true
            autoErrorMessage = nil
        }
        let playheadUnit = effectivePlayheadUnit

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))

            switch AutoRemixRunner.engine(for: scope) {
            case .planPipeline:
                await runEntireProjectAuto()
            case .arrangementEngine:
                library.beginGestureEdit("Auto Remix", scope: .tracks)
                let arranged = AutoArrangementEngine.arrange(
                    tracks: library.tracks,
                    scope: scope,
                    playheadUnit: playheadUnit
                )
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    library.tracks = arranged
                    isAutoRunning = false
                }
                library.commitGestureEdit()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    /// Entire Project: draft → validate → apply.
    /// Commits undo only after a successful apply; failures leave the timeline
    /// untouched and show an error sheet.
    private func runEntireProjectAuto() async {
        let originalTracks = library.tracks
        let seed = UInt64(Date().timeIntervalSince1970)

        // Measure the source audio first — Auto's editing decisions come
        // from real signal features (silence, beat phase, energy), never
        // guesses. A file that cannot be decoded simply contributes no
        // features and keeps Auto maximally conservative for that song.
        var signals: [UUID: SongSignalFeatures] = [:]
        for track in originalTracks where !track.isSFXTrack && !track.clips.isEmpty {
            guard let url = track.url else { continue }
            if let features = await MixrAudioAnalyzer.extractSignalFeatures(
                url: url,
                bpmHint: track.bpm.map(Double.init)
            ) {
                signals[track.id] = features
            }
        }

        let outcome = AutoRemixRunner.runEntireProject(
            tracks: originalTracks,
            seed: seed,
            signals: signals
        )

        switch outcome {
        case .success(let tracks, _, _):
            library.beginGestureEdit("Auto Remix", scope: .tracks)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                library.tracks = tracks
                isAutoRunning = false
            }
            library.commitGestureEdit()
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .failure(let message):
            library.tracks = originalTracks
            library.cancelGestureEdit()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isAutoRunning = false
                autoErrorMessage = message
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Rotate Overlay

private struct TLRotateOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "iphone.gen2.landscape")
                    .font(.system(size: 42, weight: .regular))
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 26, weight: .semibold))
                Text("Rotate iPhone")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white)
            .opacity(0.92)
        }
    }
}

private struct ProjectTitleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private enum TLProjectTitleMetrics {
    /// Cap for the title column — idle truncates here, rename scrolls here, and
    /// the chevron never travels past it. Short names hug their text instead.
    /// Sized so "My Remix 12" (79.2pt at 13pt semibold) still fits whole.
    static let maxTitleWidth: CGFloat = 80
    /// Floor so a near-empty name still has a caret and a tap target.
    static let minTitleWidth: CGFloat = 22
    static let fieldHeight: CGFloat = 18
    static let chevronSlotWidth: CGFloat = 12
    /// Tight so the chevron tucks right up against short names.
    static let titleToChevronSpacing: CGFloat = 4.25
    /// Breathing room for the end-of-text caret while renaming.
    static let caretSlack: CGFloat = 2
    static var font: UIFont {
        UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold),
            maximumPointSize: 15.5
        )
    }
    /// Full title control width so undo/redo stay parked after this slot,
    /// whatever the name measures — unchanged from the fixed-column layout.
    static var controlWidth: CGFloat {
        maxTitleWidth + titleToChevronSpacing + chevronSlotWidth
    }

    /// The slot the control occupied when the title column was a fixed 76pt.
    private static let legacySlotWidth: CGFloat = 92
    /// Wider names claim room from the gap after the control, so undo/redo stay
    /// parked and the chevron-to-undo air matches the fixed-column layout.
    static var trailingSpacingReduction: CGFloat {
        max(0, controlWidth - legacySlotWidth)
    }

    /// Rendered width of `name`, clamped into the column's min/max.
    static func titleWidth(for name: String, extraSlack: CGFloat = 0) -> CGFloat {
        let measured = (name as NSString)
            .size(withAttributes: [.font: font])
            .width
            .rounded(.up)
        return min(max(measured + extraSlack, minTitleWidth), maxTitleWidth)
    }
}

// MARK: - Transport Bar

private struct TLTransportBar: View {
    @Environment(AppAppearanceState.self) private var appearanceState
    @ObservedObject var playback: MixrPlaybackEngine
    @ObservedObject var library: TrackLibrary
    let layoutMode: EditorLayoutMode
    var displayTimeSeconds: Double = 0
    var isProjectMenuOpen: Bool = false
    @Binding var isExporting: Bool
    var onProjectTapped: () -> Void = {}
    var onProjectRenameBegan: () -> Void = {}
    @State private var exportedFile: TLExportedFile?
    @State private var exportErrorMessage: String?

    @State private var isRenamingProject = false
    @State private var renameText = ""
    @State private var renameFieldFocused = false
    @State private var renameCaretX: CGFloat?

    var body: some View {
        Group {
            switch layoutMode {
            case .regular:
                ZStack {
                    homeGroup
                    exportButton
                    transportControls
                        .offset(x: 63)
                }
            case .compact:
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        homeGroup
                        exportButton
                    }
                    .frame(height: EditorLayoutMetrics.regularTransportHeight)

                    transportControls
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
        }
        .sheet(item: $exportedFile) { file in
            TLShareSheet(items: [file.url])
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private var homeGroup: some View {
        HStack(spacing: layoutMode == .regular ? 24 : 10) {
            Button {
                appearanceState.togglePartyMode()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MixrColors.primaryPurple)
                        .partyModeIconGlow()
                    Text("Mixr")
                        .mixrScaledFont(
                            size: 20,
                            weight: .bold,
                            relativeTo: .title2
                        )
                        .foregroundStyle(MixrColors.textPrimary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Party Mode")
            .accessibilityValue(appearanceState.isPartyModeEnabled ? "On" : "Off")

            HStack(
                spacing: (layoutMode == .regular ? 18 : 8)
                    - TLProjectTitleMetrics.trailingSpacingReduction
            ) {
                projectTitleControl

                HStack(spacing: TLToolbarHistoryMetrics.buttonSpacing) {
                    TLToolbarHistoryCustomButton(isEnabled: library.canUndo) {
                        library.undo()
                    } icon: {
                        MixrHistoryArrow(
                            direction: .undo,
                            width: TLToolbarHistoryMetrics.glyphWidth,
                            height: TLToolbarHistoryMetrics.glyphHeight
                        )
                    }
                    .accessibilityLabel("Undo")

                    TLToolbarHistoryCustomButton(isEnabled: library.canRedo) {
                        library.redo()
                    } icon: {
                        MixrHistoryArrow(
                            direction: .redo,
                            width: TLToolbarHistoryMetrics.glyphWidth,
                            height: TLToolbarHistoryMetrics.glyphHeight
                        )
                    }
                    .accessibilityLabel("Redo")
                }
                .frame(height: TLToolbarHistoryMetrics.hitHeight)
                .offset(y: -0.8)
            }
        }
        .padding(.leading, layoutMode == .regular ? 14 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportButton: some View {
        Button("Export", systemImage: "square.and.arrow.up", action: startExport)
            .frame(minWidth: layoutMode == .regular ? 74 : 66)
            .buttonStyle(MixrSecondaryGlassButtonStyle(partyRole: .export))
            .fixedSize(horizontal: true, vertical: false)
            .disabled(isExporting)
            .padding(.trailing, layoutMode == .regular ? 14 : 8)
            .frame(maxWidth: layoutMode == .regular ? .infinity : nil, alignment: .trailing)
    }

    private var transportControls: some View {
        HStack(alignment: .center, spacing: layoutMode == .regular ? 12 : 9) {
            HStack(alignment: .center, spacing: layoutMode == .regular ? 12 : 9) {
                Button("Skip to Start", systemImage: "backward.end.fill") {
                    playback.skipToStart()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary)
                .frame(minWidth: 44, minHeight: 44)

                Button(
                    playback.isPlaying ? "Pause" : "Play",
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                ) {
                    playback.togglePlayPause()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background { PartyModePlayButtonSurface() }
                .shadow(color: MixrColors.primaryPurple.opacity(0.50), radius: 10)
                .partyModePlayButton()

                Button("Skip to End", systemImage: "forward.end.fill") {
                    playback.skipToEnd()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
            }

            HStack(spacing: 3) {
                Text(MixrTimeline.formattedTime(displayTimeSeconds))
                    .mixrScaledFont(
                        size: 13,
                        weight: .semibold,
                        design: .monospaced
                    )
                    .foregroundStyle(MixrColors.textPrimary)
                Text("/")
                    .mixrScaledFont(size: 11)
                    .foregroundStyle(MixrColors.textSecondary)
                Text(MixrTimeline.formattedTime(playback.totalDurationSeconds))
                    .mixrScaledFont(size: 13, design: .monospaced)
                    .foregroundStyle(MixrColors.textSecondary)
            }
            .frame(height: 40, alignment: .center)

            HStack(alignment: .center, spacing: layoutMode == .regular ? 10 : 7) {
                VStack(spacing: 0) {
                    Text(library.projectBPMDisplay)
                        .mixrScaledFont(
                            size: 14,
                            weight: .bold,
                            relativeTo: .headline
                        )
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("BPM")
                        .mixrScaledFont(
                            size: 8,
                            weight: .semibold,
                            relativeTo: .caption2
                        )
                        .foregroundStyle(MixrColors.textSecondary)
                        .kerning(0.5)
                }
                .frame(width: 30, height: 40)

                VStack(spacing: 0) {
                    Text(library.displayKey)
                        .mixrScaledFont(
                            size: 14,
                            weight: .bold,
                            relativeTo: .headline
                        )
                        .foregroundStyle(MixrColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("KEY")
                        .mixrScaledFont(
                            size: 8,
                            weight: .semibold,
                            relativeTo: .caption2
                        )
                        .foregroundStyle(MixrColors.textSecondary)
                        .kerning(0.5)
                }
                .frame(width: 56, height: 40)
            }
        }
    }

    // MARK: - Project title

    @ViewBuilder
    private var projectTitleControl: some View {
        HStack(spacing: TLProjectTitleMetrics.titleToChevronSpacing) {
            Group {
                if isRenamingProject {
                    TLProjectNameField(
                        text: $renameText,
                        isFocused: $renameFieldFocused,
                        initialCaretX: renameCaretX,
                        onSubmit: commitProjectRename
                    )
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitProjectRename() }
                    }
                } else {
                    Text(library.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(
                width: titleColumnWidth,
                height: TLProjectTitleMetrics.fieldHeight,
                alignment: .leading
            )
            .clipped()
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ProjectTitleFrameKey.self,
                        value: geo.frame(in: .named("timelineScreen"))
                    )
                }
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary)
                .rotationEffect(.degrees(isProjectMenuOpen ? 180 : 0))
                .frame(
                    width: TLProjectTitleMetrics.chevronSlotWidth,
                    height: TLProjectTitleMetrics.fieldHeight
                )
                .allowsHitTesting(!isRenamingProject)
        }
        .frame(height: TLProjectTitleMetrics.fieldHeight)
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(Rectangle())
        .modifier(
            TLProjectTitleInteractionModifier(
                isRenaming: isRenamingProject,
                onTap: onProjectTapped,
                onLongPress: beginProjectRename(at:)
            )
        )
        .animation(
            .spring(response: 0.25, dampingFraction: 0.85),
            value: isProjectMenuOpen
        )
        .animation(nil, value: isRenamingProject)
        .animation(
            isRenamingProject
                ? nil
                : .spring(response: 0.25, dampingFraction: 0.85),
            value: titleColumnWidth
        )
        // Fixed footprint so undo/redo stay parked while the title hugs its text.
        .frame(
            width: TLProjectTitleMetrics.controlWidth,
            height: TLProjectTitleMetrics.fieldHeight,
            alignment: .leading
        )
    }

    /// Hugs the current name, capped at the column max.
    private var titleColumnWidth: CGFloat {
        TLProjectTitleMetrics.titleWidth(
            for: isRenamingProject ? renameText : library.projectName,
            extraSlack: isRenamingProject ? TLProjectTitleMetrics.caretSlack : 0
        )
    }

    private func beginProjectRename(at point: CGPoint) {
        onProjectRenameBegan()
        renameText = library.projectName
        // Caret X is in the HStack; title column is leading at fixed width.
        renameCaretX = min(max(point.x, 0), titleColumnWidth)
        isRenamingProject = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.async {
            renameFieldFocused = true
        }
    }

    private func commitProjectRename() {
        guard isRenamingProject else { return }
        library.renameCurrentProject(to: renameText)
        isRenamingProject = false
        renameFieldFocused = false
        renameCaretX = nil
    }

    /// Bounces the project offline with the exact per-clip effect settings
    /// used in live playback (see MixrExportRenderer), then shares the file.
    private func startExport() {
        guard !isExporting else { return }
        isExporting = true
        let tracks = library.tracks
        let name = library.projectName
        let projectBPM = library.projectBPM

        Task.detached(priority: .userInitiated) {
            let result = Result {
                try MixrExportRenderer.export(
                    tracks: tracks,
                    projectName: name,
                    projectBPM: projectBPM
                )
            }
            await MainActor.run {
                isExporting = false
                switch result {
                case .success(let url):
                    exportedFile = TLExportedFile(url: url)
                case .failure(let error):
                    exportErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct TLProjectTitleInteractionModifier: ViewModifier {
    var isRenaming: Bool
    var onTap: () -> Void
    var onLongPress: (CGPoint) -> Void
    @State private var suppressNextTap = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRenaming {
            content
        } else {
            content
                .onTapGesture {
                    if suppressNextTap {
                        suppressNextTap = false
                        return
                    }
                    onTap()
                }
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .sequenced(
                            before: DragGesture(
                                minimumDistance: 0,
                                coordinateSpace: .local
                            )
                        )
                        .onEnded { value in
                            guard case .second(true, let drag) = value else {
                                return
                            }
                            suppressNextTap = true
                            onLongPress(drag?.location ?? .zero)
                        }
                )
        }
    }
}

/// Zero-inset field so title metrics match the SwiftUI label (chevron stays put).
private final class TLProjectNameTextField: UITextField {
    /// Report no intrinsic width so UIKit never stretches the SwiftUI title.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 18)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds }

    override func canPerformAction(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool {
        // Keep Paste available even when simulator pasteboard syncing lags
        // (same idea as the speed toolbar field). Copy/Cut follow selection.
        if action == #selector(paste(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

/// Inline project-title editor — same look as the label, gray caret like the
/// speed toolbar field (no bordered/filled text-field chrome).
private struct TLProjectNameField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    /// Local X in the title slot where the long-press began; nil → caret at end.
    var initialCaretX: CGFloat? = nil
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TLProjectNameTextField {
        let field = TLProjectNameTextField()
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.clipsToBounds = true
        field.returnKeyType = .done
        field.textAlignment = .left
        field.contentVerticalAlignment = .center
        field.autocorrectionType = .no
        field.autocapitalizationType = .words
        field.spellCheckingType = .no
        field.textContentType = nil
        field.clearButtonMode = .never
        field.font = TLProjectTitleMetrics.font
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .white
        // Match TLSpeedValueField caret tint.
        field.tintColor = UIColor(white: 0.62, alpha: 1)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.attributedPlaceholder = NSAttributedString(
            string: "Project name",
            attributes: [
                .foregroundColor: UIColor(MixrColors.textPlaceholder),
                .font: TLProjectTitleMetrics.font,
            ]
        )
        if #available(iOS 17.0, *) {
            field.inlinePredictionType = .no
        }
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: TLProjectNameTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.font = TLProjectTitleMetrics.font
        field.textColor = .white
        field.tintColor = UIColor(white: 0.62, alpha: 1)

        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
                context.coordinator.placeInitialCaret(in: field)
            }
        } else if !isFocused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TLProjectNameField
        private var didPlaceInitialCaret = false

        init(_ parent: TLProjectNameField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func placeInitialCaret(in field: UITextField) {
            guard !didPlaceInitialCaret else { return }
            didPlaceInitialCaret = true

            if let x = parent.initialCaretX {
                let point = CGPoint(x: x, y: field.bounds.midY)
                if let position = field.closestPosition(to: point) {
                    field.selectedTextRange = field.textRange(from: position, to: position)
                    return
                }
            }

            let end = field.endOfDocument
            field.selectedTextRange = field.textRange(from: end, to: end)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            placeInitialCaret(in: textField)
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            didPlaceInitialCaret = false
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            textField.resignFirstResponder()
            return true
        }
    }
}

/// Identifiable wrapper so the share sheet can present via .sheet(item:).
private struct TLExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// UIKit share sheet — used to hand the exported mix off to Files,
/// Messages, AirDrop, etc.
private struct TLShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct TLSFXLibraryPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let style: EditorPresentationStyle
    let onSelect: (SoundEffectDefinition) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .popover:
            content.popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                let width: CGFloat = 560
                panel
                    .frame(
                        width: width,
                        height: SFXMetrics.panelHeight(forWidth: width)
                    )
                    .padding(12)
                    .presentationCompactAdaptation(.sheet)
            }
        case .sheet:
            content.sheet(isPresented: $isPresented) {
                GeometryReader { proxy in
                    let width = max(320, min(680, proxy.size.width - 32))
                    let height = min(
                        proxy.size.height - 32,
                        SFXMetrics.panelHeight(forWidth: width)
                    )

                    panel
                        .frame(width: width, height: max(260, height))
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height / 2
                        )
                }
                .presentationBackground(.clear)
            }
        }
    }

    private var panel: some View {
        SFXLibraryPanel(
            onSelect: { effect in
                onSelect(effect)
                isPresented = false
            },
            onClose: {
                isPresented = false
            }
        )
    }
}

// MARK: - Toolbar History Button (undo / redo)

private enum TLToolbarHistoryMetrics {
    static let iconSize:   CGFloat = 15.5
    static let glyphWidth:  CGFloat = 20
    static let glyphHeight: CGFloat = 17
    static let hitWidth:   CGFloat = 34
    static let hitHeight:  CGFloat = 40
    static let buttonSpacing: CGFloat = 4
    static let strokeWidth: CGFloat = 0
}

struct TLHistoryActionIcon: View {
    enum Kind { case undo, redo }

    let kind: Kind
    var color: Color = MixrColors.textSecondary

    var body: some View {
        TLHistoryUndoShape()
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: TLToolbarHistoryMetrics.strokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .scaleEffect(x: kind == .redo ? -1 : 1, y: 1)
            .frame(
                width: TLToolbarHistoryMetrics.glyphWidth,
                height: TLToolbarHistoryMetrics.glyphHeight
            )
    }
}

/// Undo arrow — long top stroke + chevron, short bottom tail on the right.
private struct TLHistoryUndoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Short bottom tail (lower-right stub)
        let tailTip  = CGPoint(x: w * 0.97, y: h * 0.88)
        let tailRoot = CGPoint(x: w * 0.80, y: h * 0.76)
        let topRight = CGPoint(x: w * 0.86, y: h * 0.18)
        let topLeft  = CGPoint(x: w * 0.30, y: h * 0.14)
        let arrowTip = CGPoint(x: w * 0.04, y: h * 0.44)
        let arrowTop = CGPoint(x: w * 0.27, y: h * 0.04)
        let arrowBottom = CGPoint(x: w * 0.27, y: h * 0.52)

        path.move(to: tailTip)
        path.addQuadCurve(
            to: tailRoot,
            control: CGPoint(x: w * 0.99, y: h * 0.70)
        )
        path.addCurve(
            to: topRight,
            control1: CGPoint(x: w * 0.74, y: h * 0.84),
            control2: CGPoint(x: w * 0.94, y: h * 0.30)
        )
        path.addLine(to: topLeft)
        path.addLine(to: arrowTip)
        path.move(to: arrowTip)
        path.addLine(to: arrowTop)
        path.move(to: arrowTip)
        path.addLine(to: arrowBottom)

        return path
    }
}

struct TLToolbarHistoryButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: TLToolbarHistoryMetrics.iconSize, weight: .semibold))
                .foregroundStyle(MixrColors.textSecondary)
                .scaleEffect(x: 1.28, y: 1.0)
                .frame(
                    width: TLToolbarHistoryMetrics.glyphWidth,
                    height: TLToolbarHistoryMetrics.glyphHeight
                )
                .frame(
                    width: TLToolbarHistoryMetrics.hitWidth,
                    height: TLToolbarHistoryMetrics.hitHeight,
                    alignment: .center
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(TLToolbarHistoryPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .animation(.easeOut(duration: 0.16), value: isEnabled)
    }
}


/// Same chrome as `TLToolbarHistoryButton`, for custom mock / preview icons.
struct TLToolbarHistoryCustomButton<Icon: View>: View {
    let isEnabled: Bool
    let action: () -> Void
    private let icon: () -> Icon

    init(
        isEnabled: Bool,
        action: @escaping () -> Void = {},
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.isEnabled = isEnabled
        self.action = action
        self.icon = icon
    }

    var body: some View {
        Button(action: action) {
            icon()
                .frame(
                    width: TLToolbarHistoryMetrics.hitWidth,
                    height: TLToolbarHistoryMetrics.hitHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(TLToolbarHistoryPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .animation(.easeOut(duration: 0.16), value: isEnabled)
    }
}

// MARK: - Wide history icons (legacy mock — option G)

struct TLWideHistoryUndoIcon: View {
    var color: Color = MixrColors.textSecondary

    var body: some View {
        TLHistoryActionIcon(kind: .undo, color: color)
    }
}

struct TLWideHistoryRedoIcon: View {
    var color: Color = MixrColors.textSecondary

    var body: some View {
        TLHistoryActionIcon(kind: .redo, color: color)
    }
}

/// Click state: the glyph brightens toward white, shrinks slightly, and a
/// soft glass highlight blooms behind it — lit, not faded.
private struct TLToolbarHistoryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.38 : 0)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
                    .padding(.vertical, 8)
            }
            .animation(.spring(response: 0.17, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - Track Area (unified three-column scrollable layout)

private struct TLTrackArea: View {
    @Binding var tracks: [MixrTrack]
    @Binding var selectedClipID: UUID?
    let selectedTrackID: UUID?
    let effectivePlayheadUnit: CGFloat
    let maxPlayheadUnit: CGFloat
    let isPlayheadDragging: Bool
    let bottomOverlayAllowance: CGFloat
    let sidebarWidth: CGFloat
    let controlsWidth: CGFloat
    let importFooterHeight: CGFloat
    @Binding var showFilePicker: Bool
    @Binding var showSFXPanel: Bool
    let sfxPresentationStyle: EditorPresentationStyle
    let onSelectSoundEffect: (SoundEffectDefinition) -> Void
    let onImportURLs: ([URL]) -> Void
    let onDeleteTrack: (UUID) -> Void
    let onReorder: (IndexSet, Int) -> Void
    let onSelectTrack: (UUID) -> Void
    let onToggleSolo: (UUID) -> Void
    let onToggleMute: (UUID) -> Void
    /// Undo bracketing — capture before mutating, register on commit.
    /// Views never talk to UndoManager directly; TrackLibrary is the
    /// single editing layer.
    let onEditBegin: (String, TimelineEditScope) -> Void
    let onEditCommit: () -> Void
    let onEditCancel: () -> Void
    let onMixSettingsChanged: () -> Void
    let onPlayheadDragStart: () -> Void
    let onPlayheadDragChanged: (CGFloat) -> Void
    let onPlayheadDragEnded: (CGFloat) -> Void
    let onTimelineTapped: (CGFloat) -> Void

    @State private var draggingID: UUID?        = nil
    @State private var dragTranslation: CGFloat = 0
    @State private var isTimelineDropTarget     = false

    // Clip editing state
    @State private var clipTapAnchorX:   CGFloat?    = nil
    @State private var activeGrip:       ActiveGrip? = nil
    @State private var isSpeedEditing:   Bool        = false
    @State private var currentContentW:     CGFloat = 0
    @State private var currentContentUnits: CGFloat = TLK.totalUnits
    @State private var currentLaneVW:       CGFloat = 0

    // Scroll tracking for floating overlay positioning
    @State private var hScrollOffset: CGFloat = 0
    @State private var vScrollOffset: CGFloat = 0
    @State private var hScrollPosition = ScrollPosition()

    // Duplicate auto-scroll — scrollAnchorUnit is recomputed into an exact offset at scroll time.
    @State private var scrollAnchorUnit: CGFloat = 0
    @State private var scrollTrigger: UUID?

    // Clip drag-move state
    @State private var clipDragState:  ClipDragState? = nil
    @State private var clipDragArmed:  UUID? = nil
    @State private var clipDragArmedAt: Date? = nil
    @State private var clipDragArmedAreaX: CGFloat = 0
    @State private var clipDragArmedAreaY: CGFloat = 0
    @State private var isDraggingClip: Bool = false
    /// 60 fps loop that drives edge auto-scroll while a drag is active.
    @State private var clipDragScrollTask: Task<Void, Never>? = nil

    // MARK: - Clip lookup

    private struct FoundClip {
        let trackIdx: Int
        let clipIdx:  Int
        let track:    MixrTrack
        let clip:     MixrClip
    }

    private func findClip(_ id: UUID) -> FoundClip? {
        for (ti, track) in tracks.enumerated() {
            if let ci = track.clips.firstIndex(where: { $0.id == id }) {
                return FoundClip(trackIdx: ti, clipIdx: ci, track: track, clip: track.clips[ci])
            }
        }
        return nil
    }

    /// Scroll after duplicate only when the new clip start is off-screen or in the
    /// trailing ~25% of the visible timeline (not comfortably visible).
    private func shouldAutoScrollToDuplicateStart(
        _ startUnit: CGFloat,
        contentUnits: CGFloat,
        contentW: CGFloat,
        viewportW: CGFloat
    ) -> Bool {
        guard viewportW > 0, contentUnits > 0, contentW > 0 else { return false }
        let startX = (startUnit / contentUnits) * contentW
        let visibleMin = hScrollOffset
        let visibleMax = hScrollOffset + viewportW

        if startX < visibleMin || startX > visibleMax {
            return true
        }
        if startX >= visibleMin + viewportW * TLK.duplicateScrollComfortThreshold {
            return true
        }
        return false
    }

    /// Content-space x offset that places `startUnit` at ~27.5% from the viewport's leading edge.
    private func duplicateScrollOffset(
        startUnit: CGFloat,
        contentUnits: CGFloat,
        contentW: CGFloat,
        viewportW: CGFloat
    ) -> CGFloat {
        let startX = (startUnit / contentUnits) * contentW
        let target = startX - viewportW * TLK.duplicateScrollViewportAnchor
        let maxOffset = max(0, contentW - viewportW)
        return max(0, min(target, maxOffset))
    }

    /// Reset horizontal scroll and playhead to 0:00 when the timeline is cleared.
    private func scrollToTimelineStart() {
        scrollTrigger = nil
        onTimelineTapped(0)
        withAnimation(TLK.duplicateScrollAnimation) {
            hScrollPosition.scrollTo(x: 0)
        }
    }

    private func splitClip(id: UUID) {
        guard let f = findClip(id) else { return }
        let phUnit  = effectivePlayheadUnit
        let inClip  = phUnit > f.clip.start && phUnit < f.clip.start + f.clip.length
        let splitAt = inClip ? phUnit : f.clip.start + f.clip.length / 2
        guard splitAt - f.clip.start >= 2,
              f.clip.start + f.clip.length - splitAt >= 2 else { return }
        onEditBegin("Split Clip", .trackClips(f.track.id))
        defer { onEditCommit() }
        let leftLen  = splitAt - f.clip.start
        let rightLen = f.clip.length - leftLen
        let newID    = UUID()
        let inheritedSpeed = f.clip.playbackSpeed
        tracks[f.trackIdx].clips[f.clipIdx].length = leftLen
        tracks[f.trackIdx].clips[f.clipIdx].transitionOut = .none
        let rightClip = MixrClip(
            id: newID,
            start: splitAt,
            length: rightLen,
            playbackSpeed: inheritedSpeed,
            volume: f.clip.volume,
            effects: f.clip.effects,
            sourceOffsetSeconds: f.clip.sourceOffsetSeconds
                + MixrTimeline.seconds(fromUnits: leftLen) * inheritedSpeed
        )
        tracks[f.trackIdx].clips.insert(rightClip, at: f.clipIdx + 1)
        let contentUnits = MixrTimeline.contentUnits(for: tracks)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedClipID  = newID
            activeGrip      = nil
            isSpeedEditing  = false
            clipTapAnchorX  = splitAt / contentUnits * currentContentW
        }
    }

    private func duplicateClip(id: UUID) {
        guard let f = findClip(id) else { return }
        onEditBegin("Duplicate Clip", .trackClips(f.track.id))
        defer { onEditCommit() }
        let newStart = f.clip.start + f.clip.length
        // Bug 1 fix: always copy the full source length, never truncate.
        let newLen = f.clip.length
        let newID  = UUID()
        // Bug 2 fix: push every clip that follows the source rightward by newLen
        // so the duplicate slots in without overlapping any neighbour.
        for i in (f.clipIdx + 1)..<tracks[f.trackIdx].clips.count {
            tracks[f.trackIdx].clips[i].start += newLen
        }
        // Source clip's outgoing transition is stale after insertion; clear it so
        // the source exits cleanly into the new independent duplicate.
        tracks[f.trackIdx].clips[f.clipIdx].transitionOut = .none
        tracks[f.trackIdx].clips.insert(
            MixrClip(
                id: newID,
                start: newStart,
                length: newLen,
                playbackSpeed: f.clip.playbackSpeed,
                volume: f.clip.volume,
                effects: f.clip.effects,
                sourceOffsetSeconds: f.clip.sourceOffsetSeconds
            ),
            at: f.clipIdx + 1
        )
        let contentUnits = MixrTimeline.contentUnits(for: tracks)
        onTimelineTapped(newStart)
        let contentW = max(currentLaneVW, contentUnits * TLK.timelineUnitWidth)
        if shouldAutoScrollToDuplicateStart(
            newStart,
            contentUnits: contentUnits,
            contentW: contentW,
            viewportW: currentLaneVW
        ) {
            scrollAnchorUnit = newStart
            scrollTrigger = UUID()
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedClipID = newID
            activeGrip     = nil
            isSpeedEditing = false
            clipTapAnchorX = newStart / contentUnits * currentContentW
        }
    }

    private func deleteClip(id: UUID) {
        guard let f = findClip(id) else { return }
        if f.track.clips.count <= 1 {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedClipID = nil
                activeGrip     = nil
                isSpeedEditing = false
                clipTapAnchorX = nil
            }
            // Track deletion registers its own undo step in TrackLibrary.
            onDeleteTrack(f.track.id)
            return
        }

        onEditBegin("Delete Clip", .trackClips(f.track.id))
        defer { onEditCommit() }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            tracks[f.trackIdx].clips.remove(at: f.clipIdx)
            selectedClipID = nil
            activeGrip     = nil
            isSpeedEditing = false
            clipTapAnchorX = nil
        }
    }

    /// Applies a playback-speed multiplier, rescales clip length from the implied
    /// source duration, and ripples following clips: right on grow, left on shrink.
    private func applyClipSpeed(id: UUID, speed: Double) {
        guard let f = findClip(id) else { return }
        let clamped = min(
            TLClipEditingMetrics.maxPlaybackSpeed,
            max(TLClipEditingMetrics.minPlaybackSpeed, speed)
        )
        onEditBegin("Change Speed", .trackClips(f.track.id))
        defer { onEditCommit() }
        let currentSpeed = max(f.clip.playbackSpeed, 0.0001)
        let sourceLength = Double(f.clip.length) * currentSpeed
        let rawNewLength = sourceLength / clamped
        let newLength = max(
            MixrTimeline.minClipLengthUnits,
            CGFloat(rawNewLength)
        )
        let oldEnd = f.clip.start + f.clip.length
        let newEnd = f.clip.start + newLength
        let delta = newEnd - oldEnd

        tracks[f.trackIdx].clips[f.clipIdx].length = newLength
        tracks[f.trackIdx].clips[f.clipIdx].playbackSpeed = clamped

        if delta > 0.001 {
            // Grow: push following clips that would overlap the new end.
            var cursor = newEnd
            for i in (f.clipIdx + 1)..<tracks[f.trackIdx].clips.count {
                if tracks[f.trackIdx].clips[i].start < cursor - 0.001 {
                    tracks[f.trackIdx].clips[i].start = cursor
                    tracks[f.trackIdx].clips[i].transitionIn = .none
                    tracks[f.trackIdx].clips[i].transitionOut = .none
                }
                cursor = max(
                    cursor,
                    tracks[f.trackIdx].clips[i].start
                        + tracks[f.trackIdx].clips[i].length
                )
            }
            tracks[f.trackIdx].clips[f.clipIdx].transitionOut = .none
        } else if delta < -0.001 {
            // Shrink: scoot every following clip left by the same amount so no
            // gap opens after this clip (mirrors grow pushing right).
            for i in (f.clipIdx + 1)..<tracks[f.trackIdx].clips.count {
                tracks[f.trackIdx].clips[i].start = max(
                    0,
                    tracks[f.trackIdx].clips[i].start + delta
                )
            }
            tracks[f.trackIdx].clips[f.clipIdx].transitionOut = .none
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            isSpeedEditing = false
            selectedClipID = id
            activeGrip = nil
        }
    }

    private func setTransition(type: ClipTransitionType, grip: ActiveGrip) {
        guard let f = findClip(grip.clipID) else { return }
        onEditBegin("Change Transition", .clip(grip.clipID))
        defer { onEditCommit() }
        var tx = ClipTransition()
        tx.type = type
        if grip.side == .leading {
            tracks[f.trackIdx].clips[f.clipIdx].transitionIn  = tx
        } else {
            tracks[f.trackIdx].clips[f.clipIdx].transitionOut = tx
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            activeGrip = nil
            isSpeedEditing = false
        }
    }

    private func updateTransition(_ transition: ClipTransition, grip: ActiveGrip) {
        guard let f = findClip(grip.clipID) else { return }
        onEditBegin("Change Transition", .clip(grip.clipID))
        defer { onEditCommit() }
        if grip.side == .leading {
            tracks[f.trackIdx].clips[f.clipIdx].transitionIn = transition
        } else {
            tracks[f.trackIdx].clips[f.clipIdx].transitionOut = transition
        }
    }

    // MARK: - Clip drag-move

    private var clipDragSettleComplete: Bool {
        guard let armedAt = clipDragArmedAt else { return clipDragState != nil }
        return Date().timeIntervalSince(armedAt) >= TLK.clipDragArmedSettleDuration
    }

    /// Long-press began — lift clip in place, show scrim, wait for settle before tracking movement.
    private func armClipDrag(clipID: UUID, areaX: CGFloat, areaY: CGFloat) {
        guard clipDragState == nil, clipDragArmed == nil, let found = findClip(clipID) else { return }
        // Capture the before-state now; exactly one undo step registers at
        // drop commit (never per drag frame), and a cancel discards it.
        onEditBegin("Move Clip", .trackClips(found.track.id))
        clipDragArmed = clipID
        clipDragArmedAt = Date()
        clipDragArmedAreaX = areaX
        clipDragArmedAreaY = areaY
        withAnimation(.easeOut(duration: TLK.clipDragScrimAnim)) {
            isDraggingClip = true
            activeGrip = nil
            isSpeedEditing = false
            selectedClipID = clipID
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Called on drag events after the long press has armed clip movement.
    private func startClipDrag(
        clipID: UUID,
        cursorAreaX: CGFloat, cursorAreaY: CGFloat,
        startAreaX:  CGFloat, startAreaY:  CGFloat
    ) {
        guard clipDragState == nil, let f = findClip(clipID) else { return }

        let xOffset = (f.clip.start / currentContentUnits) * currentContentW
        let grabScreenPx = startAreaX - sidebarWidth - xOffset + hScrollOffset
        let clipTopAreaY = TLK.rulerHeight
            + CGFloat(f.trackIdx) * TLK.trackRowHeight
            + (TLK.trackRowHeight - TLK.waveformHeight) / 2
            - vScrollOffset
        let grabScreenPy = startAreaY - clipTopAreaY
        let initialLeadingEdgePx = cursorAreaX - sidebarWidth + hScrollOffset - grabScreenPx

        clipDragArmed = nil
        clipDragArmedAt = nil

        clipDragState = ClipDragState(
            clipID: clipID,
            trackID: f.track.id,
            trackIdx: f.trackIdx,
            originalClip: f.clip,
            grabScreenPx: grabScreenPx,
            grabScreenPy: grabScreenPy,
            cursorAreaX: cursorAreaX,
            cursorAreaY: cursorAreaY,
            scrollX: hScrollOffset,
            proposedLeadingEdgePx: initialLeadingEdgePx,
            // Seed at the clip's current start so indicator appears in-place on first frame.
            resolvedInsertStart: f.clip.start
        )
        beginDragScrollLoop()
    }

    /// Updates cursor position and recomputes proposed drop location, insert preview progress,
    /// and the resolved insertion start that the indicator eases toward.
    private func updateClipDrag(cursorAreaX: CGFloat, cursorAreaY: CGFloat) {
        guard var drag = clipDragState else { return }
        drag.cursorAreaX = cursorAreaX
        drag.cursorAreaY = cursorAreaY
        drag.proposedLeadingEdgePx =
            cursorAreaX - sidebarWidth + drag.scrollX - drag.grabScreenPx

        guard let ti = tracks.firstIndex(where: { $0.id == drag.trackID }) else { return }
        let wasSnapped = drag.isIndicatorSnapped
        let previousInsertStart = drag.resolvedInsertStart
        let target = drag.updateIndicatorTarget(
            contentUnits: currentContentUnits,
            contentW: currentContentW,
            clips: tracks[ti].clips
        )
        let shouldAnimateIndicator = wasSnapped || target.isSnapped
        let newInsertStart = target.start
        let indicatorMoved = abs(newInsertStart - previousInsertStart) > 0.001
        let targetProgress: CGFloat = 0
        let progressChanged = drag.insertPreviewProgress != targetProgress

        if progressChanged || indicatorMoved {
            let update = {
                drag.insertPreviewProgress = targetProgress
                clipDragState = drag
            }
            if shouldAnimateIndicator {
                withAnimation(.easeOut(duration: TLK.clipIndicatorEaseDuration)) {
                    update()
                }
            } else {
                update()
            }
        } else {
            clipDragState = drag
        }
    }

    private func handleClipMoveChanged(
        clipID: UUID,
        cursorAreaX: CGFloat, cursorAreaY: CGFloat,
        startAreaX: CGFloat, startAreaY: CGFloat
    ) {
        if clipDragArmed == clipID, clipDragState == nil {
            guard clipDragSettleComplete else { return }
            startClipDrag(
                clipID: clipID,
                cursorAreaX: cursorAreaX, cursorAreaY: cursorAreaY,
                startAreaX: startAreaX, startAreaY: startAreaY
            )
            updateClipDrag(cursorAreaX: cursorAreaX, cursorAreaY: cursorAreaY)
        } else if clipDragState?.clipID == clipID {
            updateClipDrag(cursorAreaX: cursorAreaX, cursorAreaY: cursorAreaY)
        }
    }

    private func handleClipMoveEnded() {
        if clipDragArmed != nil, clipDragState == nil {
            cancelClipDrag()
            return
        }
        commitClipDrop()
    }

    /// 60 fps loop: drives proportional edge auto-scroll while a clip drag is active.
    /// Maintains `drag.scrollX` independently of SwiftUI's hScrollOffset state so that
    /// proposedLeadingEdgePx stays accurate even when onScrollGeometryChange lags.
    private func beginDragScrollLoop() {
        clipDragScrollTask?.cancel()
        clipDragScrollTask = Task { @MainActor in
            while isDraggingClip, !Task.isCancelled {
                guard let drag = clipDragState else { break }
                let viewportLeft = sidebarWidth
                let viewportRight = sidebarWidth + currentLaneVW
                let movingClipW = currentContentUnits > 0
                    ? (drag.originalClip.length / currentContentUnits) * currentContentW
                    : 0
                let clipLeft = drag.cursorAreaX - drag.grabScreenPx
                let clipRight = clipLeft + movingClipW
                var delta: CGFloat = 0

                if clipRight > viewportRight {
                    // Quadratic acceleration: only scroll once the lifted clip presses into the visible edge.
                    let t = min((clipRight - viewportRight) / TLK.clipDragScrollZone, 1.0)
                    delta =  TLK.clipDragScrollSpeed * t * t
                } else if clipLeft < viewportLeft {
                    let t = min((viewportLeft - clipLeft) / TLK.clipDragScrollZone, 1.0)
                    delta = -TLK.clipDragScrollSpeed * t * t
                }
                if delta != 0 {
                    let desiredContentW = max(
                        currentContentW,
                        drag.proposedLeadingEdgePx + movingClipW + currentLaneVW * 0.35
                    )
                    let maxOff = max(0, desiredContentW - currentLaneVW)
                    let newScrollX = max(0, min(drag.scrollX + delta, maxOff))
                    var updatedDrag = drag
                    updatedDrag.scrollX = newScrollX
                    updatedDrag.proposedLeadingEdgePx =
                        drag.cursorAreaX - sidebarWidth + newScrollX - drag.grabScreenPx
                    if let ti = tracks.firstIndex(where: { $0.id == updatedDrag.trackID }) {
                        _ = updatedDrag.updateIndicatorTarget(
                            contentUnits: currentContentUnits,
                            contentW: currentContentW,
                            clips: tracks[ti].clips
                        )
                        updatedDrag.insertPreviewProgress = 0
                    }
                    withAnimation(.easeOut(duration: TLK.clipIndicatorEaseDuration)) {
                        clipDragState = updatedDrag
                    }
                    hScrollPosition.scrollTo(x: newScrollX)
                }
                try? await Task.sleep(for: .milliseconds(16))   // ≈ 60 fps
            }
        }
    }

    private func currentDropResult(for drag: ClipDragState, clips: [MixrClip]) -> ClipDropResult {
        drag.currentDropResult(
            contentUnits: currentContentUnits,
            contentW: currentContentW,
            clips: clips
        )
    }

    private func commitClipDrop() {
        clipDragScrollTask?.cancel()
        clipDragScrollTask = nil
        guard let drag = clipDragState else { return }
        guard let ti = tracks.firstIndex(where: { $0.id == drag.trackID }),
              tracks[ti].clips.contains(where: { $0.id == drag.clipID })
        else { cancelClipDrag(); return }

        // Commit to the same placement target shown by the insertion indicator.
        let result = drag.indicatorDropResult(
            contentUnits: currentContentUnits,
            contentW: currentContentW,
            clips: tracks[ti].clips
        )
        let reflowedClips = MixrTimeline.applyClipDrop(
            result: result,
            moving: drag.clipID,
            in: tracks[ti].clips
        )
        let committedStart = reflowedClips.first(where: { $0.id == drag.clipID })?.start
            ?? MixrTimeline.insertionStart(for: result, movingClipLength: drag.originalClip.length)
        let committedEnd = reflowedClips
            .map { $0.start + $0.length }
            .max() ?? committedStart

        onTimelineTapped(max(0, min(committedStart, max(maxPlayheadUnit, committedEnd))))
        withAnimation(.spring(response: TLK.clipDragDropResponse, dampingFraction: TLK.clipDragDropDamping)) {
            tracks[ti].clips = reflowedClips
            clipDragState  = nil
            clipDragArmed  = nil
            clipDragArmedAt = nil
            isDraggingClip = false
            selectedClipID = drag.clipID
        }
        // One undo step per completed drag; ghost-restore drops register
        // nothing because the captured state is unchanged.
        onEditCommit()
    }

    private func cancelClipDrag() {
        onEditCancel()
        clipDragScrollTask?.cancel()
        clipDragScrollTask = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            clipDragState  = nil
            clipDragArmed  = nil
            clipDragArmedAt = nil
            isDraggingClip = false
        }
    }

    // MARK: - Floating drag overlays (screen-space, outside all scroll views)
    // All positions computed in "tlareaRoot" coordinate space (outer ZStack),
    // which is stable regardless of horizontal or vertical scroll state.

    @ViewBuilder
    private func floatingDraggedClip(contentW: CGFloat, contentUnits: CGFloat) -> some View {
        if let drag = clipDragState,
           let track = tracks.first(where: { $0.id == drag.trackID }) {
            let clipW = max(1, (drag.originalClip.length / contentUnits) * contentW)
            WaveformClip(waveformColor: track.color)
                .frame(height: TLK.waveformHeight)
                .frame(width: clipW)
                .shadow(color: .black.opacity(0.55), radius: TLK.clipDragShadowRadius, x: 0, y: TLK.clipDragShadowY)
                .shadow(color: track.color.color.opacity(0.44), radius: 14)
                .scaleEffect(TLK.clipDragLiftScale)
                .offset(
                    x: drag.cursorAreaX - drag.grabScreenPx,
                    y: drag.cursorAreaY - drag.grabScreenPy - TLK.clipDragLiftY
                )
                .allowsHitTesting(false)
        } else if let armedID = clipDragArmed,
                  let f = findClip(armedID) {
            let clipW = max(1, (f.clip.length / contentUnits) * contentW)
            let contentX = (f.clip.start / contentUnits) * contentW
            let screenX = sidebarWidth + contentX - hScrollOffset
            let clipTopY = TLK.rulerHeight
                + CGFloat(f.trackIdx) * TLK.trackRowHeight
                + (TLK.trackRowHeight - TLK.waveformHeight) / 2
                - vScrollOffset
            WaveformClip(waveformColor: f.track.color)
                .frame(height: TLK.waveformHeight)
                .frame(width: clipW)
                .shadow(color: .black.opacity(0.55), radius: TLK.clipDragShadowRadius, x: 0, y: TLK.clipDragShadowY)
                .shadow(color: f.track.color.color.opacity(0.44), radius: 14)
                .scaleEffect(TLK.clipDragLiftScale)
                .offset(x: screenX, y: clipTopY - TLK.clipDragLiftY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func clipDragInsertionIndicator() -> some View {
        if let drag = clipDragState,
           let track = tracks.first(where: { $0.id == drag.trackID }) {
            // Use the pre-resolved, animated insertStart stored in drag state.
            // updateClipDrag keeps this current with an easeOut animation so the
            // indicator magnetically glides to snap targets rather than jumping.
            let screenX = drag.indicatorScreenX(
                insertStart: drag.resolvedInsertStart,
                contentUnits: currentContentUnits,
                contentW: currentContentW,
                sidebarWidth: sidebarWidth
            )
            let trackTopY = TLK.rulerHeight
                + CGFloat(drag.trackIdx) * TLK.trackRowHeight
                - vScrollOffset

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(track.color.color.opacity(0.85))
                .frame(width: 2, height: TLK.trackRowHeight)
                .shadow(color: track.color.color.opacity(0.60), radius: 6)
                .offset(x: screenX - 1, y: trackTopY)
                .allowsHitTesting(false)
        } else if let armedID = clipDragArmed,
                  let f = findClip(armedID) {
            let screenX = sidebarWidth
                + (f.clip.start / currentContentUnits) * currentContentW
                - hScrollOffset
            let trackTopY = TLK.rulerHeight
                + CGFloat(f.trackIdx) * TLK.trackRowHeight
                - vScrollOffset

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(f.track.color.color.opacity(0.85))
                .frame(width: 2, height: TLK.trackRowHeight)
                .shadow(color: f.track.color.color.opacity(0.60), radius: 6)
                .offset(x: screenX - 1, y: trackTopY)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let laneVW = max(1, geo.size.width - sidebarWidth - controlsWidth)
            let baseContentUnits = MixrTimeline.contentUnits(for: tracks)
            let baseContentW = max(laneVW, baseContentUnits * TLK.timelineUnitWidth)
            let dragContentUnits = clipDragState.map { drag in
                let trackClips = tracks.first(where: { $0.id == drag.trackID })?.clips ?? []
                let insertStart = drag.indicatorTarget(
                    contentUnits: baseContentUnits,
                    contentW: baseContentW,
                    clips: trackClips
                ).start
                return insertStart + drag.originalClip.length + MixrTimeline.units(fromSeconds: 20)
            } ?? baseContentUnits
            let contentUnits = max(baseContentUnits, dragContentUnits)
            let contentW = max(laneVW, contentUnits * TLK.timelineUnitWidth)
            let rowsH    = CGFloat(tracks.count) * TLK.trackRowHeight
            let lanesH   = tracks.isEmpty
                ? max(geo.size.height - TLK.rulerHeight, TLK.trackRowHeight)
                : max(rowsH, geo.size.height - TLK.rulerHeight)
            let totalH   = TLK.rulerHeight + lanesH

            ZStack(alignment: .topLeading) {
                // Full-area background
                HStack(spacing: 0) {
                    MixrColors.backgroundSecondary.frame(width: sidebarWidth)
                    MixrColors.backgroundSecondary
                    MixrColors.backgroundSecondary.frame(width: controlsWidth)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Main layout — vertical scroll wraps the three columns
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {

                        // ── Left: sidebar (no horizontal scroll) ──
                        sidebarColumn()
                            .zIndex(2)

                        // ── Centre: single horizontal scroll for ruler + lanes ──
                        ScrollView(.horizontal, showsIndicators: false) {
                            ZStack(alignment: .topLeading) {
                                TLRuler(width: contentW, contentUnits: contentUnits)
                                    .frame(width: contentW, height: TLK.rulerHeight)

                                TLPlayheadLine(
                                    timelineWidth: contentW,
                                    totalHeight: totalH,
                                    playheadUnit: effectivePlayheadUnit,
                                    contentUnits: contentUnits,
                                    isDragging: isPlayheadDragging
                                )
                                .zIndex(TLK.timelinePlayheadLineZIndex)

                                lanesContent(
                                    contentW: contentW,
                                    contentUnits: contentUnits,
                                    lanesH: lanesH,
                                    viewportW: laneVW
                                )
                                .offset(y: TLK.rulerHeight)
                                .zIndex(10)
                            }
                            .frame(width: contentW, height: totalH)
                        }
                        .scrollPosition($hScrollPosition)
                        .scrollDisabled(isDraggingClip || clipDragArmed != nil)
                        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, new in
                            // Only let the system scroll update hScrollOffset when no drag is active.
                            // During drag, drag.scrollX is the single source of truth; hScrollPosition
                            // is driven exclusively by beginDragScrollLoop via scrollTo(x:).
                            if !isDraggingClip, clipDragArmed == nil {
                                hScrollOffset = new
                            }
                        }
                        .onChange(of: scrollTrigger) { _, trigger in
                            guard trigger != nil else { return }
                            let startUnit = scrollAnchorUnit
                            Task { @MainActor in
                                // Wait for extended contentW to commit after duplicate.
                                try? await Task.sleep(for: .milliseconds(40))
                                let units = MixrTimeline.contentUnits(for: tracks)
                                let w = max(currentLaneVW, units * TLK.timelineUnitWidth)
                                let target = duplicateScrollOffset(
                                    startUnit: startUnit,
                                    contentUnits: units,
                                    contentW: w,
                                    viewportW: currentLaneVW
                                )
                                withAnimation(TLK.duplicateScrollAnimation) {
                                    hScrollPosition.scrollTo(x: target)
                                }
                                scrollTrigger = nil
                            }
                        }
                        .frame(width: laneVW, height: totalH)
                        .zIndex(1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .strokeBorder(
                                    isTimelineDropTarget
                                        ? MixrColors.primaryPurple.opacity(0.52)
                                        : MixrColors.divider.opacity(0.95),
                                    lineWidth: isTimelineDropTarget ? 1.2 : 0.55
                                )
                                .animation(.easeInOut(duration: 0.18), value: isTimelineDropTarget)
                        }
                        .overlay {
                            if isTimelineDropTarget {
                                RoundedRectangle(cornerRadius: 0, style: .continuous)
                                    .strokeBorder(MixrColors.textPrimary.opacity(0.18), lineWidth: 0.5)
                                    .padding(2)
                                    .transition(.opacity)
                            }
                        }
                        .onDrop(
                            of: TLAudioDrop.supportedTypes,
                            isTargeted: $isTimelineDropTarget,
                            perform: handleAudioDrop
                        )

                        // ── Right: controls (no horizontal scroll) ──
                        controlsColumn()
                            .zIndex(2)
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in
                    vScrollOffset = new
                }
                .scrollDisabled(isDraggingClip || clipDragArmed != nil)
                .frame(width: geo.size.width, height: geo.size.height)

                // Floating clip-editing overlays — outside all scroll views, above sidebar/controls
                clipEditingFloatingOverlay(
                    sidebarW: sidebarWidth,
                    contentW: currentContentW,
                    contentUnits: currentContentUnits,
                    laneVW:   laneVW,
                    viewportH: geo.size.height + bottomOverlayAllowance,
                    hScrollOffset: hScrollOffset,
                    vScrollOffset: vScrollOffset
                )
                .zIndex(300)

                floatingPlayheadHandle(
                    sidebarW: sidebarWidth,
                    contentW: currentContentW,
                    contentUnits: currentContentUnits,
                    laneVW: laneVW,
                    hScrollOffset: hScrollOffset
                )
                .zIndex(250)

                // Clip drag: insertion indicator — positioned in tlareaRoot space
                clipDragInsertionIndicator()
                    .zIndex(490)

                // Clip drag: floating lifted copy — follows cursor in tlareaRoot space
                floatingDraggedClip(contentW: currentContentW, contentUnits: currentContentUnits)
                    .zIndex(500)

                // Import footer (fixed to sidebar bottom)
                VStack(spacing: 0) {
                    Spacer()
                    importFooter.frame(width: sidebarWidth)
                }
                .frame(width: sidebarWidth, height: geo.size.height)
                .zIndex(1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                currentContentW = contentW
                currentContentUnits = contentUnits
                currentLaneVW = laneVW
            }
            .onChange(of: contentW) { _, new in currentContentW = new }
            .onChange(of: contentUnits) { _, new in currentContentUnits = new }
            .onChange(of: laneVW) { _, new in currentLaneVW = new }
            .onChange(of: tracks.isEmpty) { _, isEmpty in
                if isEmpty {
                    scrollToTimelineStart()
                }
            }
            // Name this coordinate space so clip drag gestures (deep inside both
            // scroll views) can report stable screen positions regardless of scroll.
            .coordinateSpace(name: "tlareaRoot")
        }
    }

    // MARK: Column helpers

    private func columnHeader(_ title: String, leadingInset: CGFloat) -> some View {
        HStack {
            Text(title)
                .mixrScaledFont(
                    size: 11.5,
                    weight: .semibold,
                    relativeTo: .subheadline
                )
                .foregroundStyle(MixrColors.textSecondary.opacity(0.73))
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingInset)
    }

    private func sidebarColumn() -> some View {
        VStack(spacing: 0) {
            // Label — matches ruler height
            MixrColors.backgroundSecondary
                .frame(width: sidebarWidth, height: TLK.rulerHeight)
                .overlay { columnHeader("Tracks", leadingInset: 10.5) }
                .overlay(alignment: .bottom) { MixrColors.divider.frame(height: 0.5) }
                .overlay(alignment: .trailing) { MixrColors.divider.frame(width: 0.5) }

            sidebarTrackRows
        }
        .frame(width: sidebarWidth)
    }

    private func controlsColumn() -> some View {
        VStack(spacing: 0) {
            // Label — matches ruler height
            MixrColors.backgroundSecondary
                .frame(width: controlsWidth, height: TLK.rulerHeight)
                .overlay { columnHeader("Controls", leadingInset: 10.5) }
                .overlay(alignment: .bottom) { MixrColors.divider.frame(height: 0.5) }
                .overlay(alignment: .leading) { MixrColors.divider.frame(width: 0.5) }

            controlsTrackRows
        }
        .frame(width: controlsWidth)
    }

    // MARK: Sidebar track rows

    private var sidebarTrackRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { _, track in
                TLSongRow(
                    track: track,
                    rowWidth: sidebarWidth,
                    isSelected: track.id == selectedTrackID,
                    onDragChanged: { delta in
                        if draggingID == nil { draggingID = track.id }
                        dragTranslation = delta
                    },
                    onDragEnded: { delta in
                        commitReorder(fromID: track.id, translation: delta)
                    },
                    onDelete: {
                        onDeleteTrack(track.id)
                    },
                    onSelect: {
                        onSelectTrack(track.id)
                    }
                )
                .frame(height: TLK.trackRowHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
                // Clip drag scrim for non-active tracks
                .overlay {
                    if isDraggingClip, clipDragState?.trackID != track.id {
                        Color.black.opacity(TLK.clipDragScrimOpacity)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: TLK.clipDragScrimAnim), value: isDraggingClip)
                .offset(y: rowOffset(trackID: track.id))
                .zIndex(draggingID == track.id ? 1 : 0)
                .scaleEffect(
                    y: draggingID == track.id ? 1.02 : 1,
                    anchor: .center
                )
                .shadow(
                    color: draggingID == track.id ? .black.opacity(0.28) : .clear,
                    radius: 6, x: 0, y: 3
                )
            }

            Color.clear.frame(height: importFooterHeight)
        }
        .frame(width: sidebarWidth)
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .trailing) {
            MixrColors.divider.frame(width: 0.5)
        }
    }

    // MARK: Timeline lanes content (no scroll wrapper — parent provides horizontal scroll)

    @ViewBuilder
    private func lanesContent(contentW: CGFloat, contentUnits: CGFloat, lanesH: CGFloat, viewportW: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TLTimelineSurface(isDropTarget: isTimelineDropTarget)
                .frame(width: contentW, height: lanesH)
                .onTapGesture { location in
                    let unit = (location.x / contentW) * contentUnits
                    onTimelineTapped(max(0, min(unit, maxPlayheadUnit)))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedClipID = nil
                        activeGrip     = nil
                        isSpeedEditing = false
                        clipTapAnchorX = nil
                    }
                }

            TLGridCanvas(width: contentW, height: lanesH, contentUnits: contentUnits)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    let laneHasSelectedClip = track.clips.contains { $0.id == selectedClipID }
                    let isThisDragTrack = clipDragState?.trackID == track.id
                        || (clipDragArmed != nil && track.clips.contains { $0.id == clipDragArmed })

                    TLTrackLane(
                        track:          track,
                        timelineWidth:  contentW,
                        contentUnits:   contentUnits,
                        selectedClipID: selectedClipID,
                        activeGrip:     activeGrip,
                        armedClipID:    isThisDragTrack ? clipDragArmed : nil,
                        clipDragState:  isThisDragTrack ? clipDragState : nil,
                        isScrimmed:     isDraggingClip && !isThisDragTrack,
                        isActiveForDrag: isDraggingClip && isThisDragTrack,
                        isInaudible:    !TrackLibrary.isAudible(track, in: tracks),
                        onClipTapped:   { clipID, tapX in
                            guard !isDraggingClip else { return }
                            let unit = (tapX / contentW) * contentUnits
                            onTimelineTapped(max(0, min(unit, maxPlayheadUnit)))
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedClipID = clipID
                                activeGrip     = nil
                                isSpeedEditing = false
                                clipTapAnchorX = tapX
                            }
                        },
                        onGripTapped:   { grip in
                            guard !isDraggingClip else { return }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                activeGrip = grip
                                isSpeedEditing = false
                            }
                        },
                        onClipDragArmed: { clipID, areaX, areaY in
                            armClipDrag(clipID: clipID, areaX: areaX, areaY: areaY)
                        },
                        onClipDragChanged: { clipID, cursorAreaX, cursorAreaY, startAreaX, startAreaY in
                            handleClipMoveChanged(
                                clipID: clipID,
                                cursorAreaX: cursorAreaX, cursorAreaY: cursorAreaY,
                                startAreaX: startAreaX, startAreaY: startAreaY
                            )
                        },
                        onClipDragEnded: {
                            handleClipMoveEnded()
                        },
                        onClipDragCancelled: {
                            cancelClipDrag()
                        }
                    )
                    .frame(height: TLK.trackRowHeight)
                    .offset(y: rowOffset(trackID: track.id))
                    .animation(.easeOut(duration: TLK.clipDragScrimAnim), value: isDraggingClip)
                    .zIndex(laneHasSelectedClip ? 5 : (draggingID == track.id ? 1 : (isDraggingClip && isThisDragTrack ? 3 : 0)))
                }
            }

            if tracks.isEmpty {
                TLEmptyTimelineState(
                    isDropTarget: isTimelineDropTarget,
                    maximumButtonWidth: min(
                        TLK.sidebarImportSongsWidth,
                        max(96, viewportW - 24)
                    ),
                    onImport: { showFilePicker = true }
                )
                    .frame(width: min(contentW, viewportW), height: lanesH)
                    .position(x: min(contentW, viewportW) / 2, y: lanesH / 2)
            }
        }
        .frame(width: contentW, height: lanesH)
    }

    // MARK: Clip editing floating overlays
    // Rendered in the TLTrackArea outer ZStack so they are never clipped by the
    // horizontal or vertical scroll views. X is converted from content-space to
    // screen-space by adding sidebarW and subtracting the current scroll offset.

    @ViewBuilder
    private func clipEditingFloatingOverlay(
        sidebarW: CGFloat,
        contentW: CGFloat,
        contentUnits: CGFloat,
        laneVW: CGFloat,
        viewportH: CGFloat,
        hScrollOffset: CGFloat,
        vScrollOffset: CGFloat
    ) -> some View {
        let screenXFor: (CGFloat) -> CGFloat = { contentX in
            sidebarW + contentX - hScrollOffset
        }

        if let cid = selectedClipID, activeGrip == nil, !isDraggingClip, let f = findClip(cid) {
            let mode: TLClipContextToolbar.Mode = isSpeedEditing ? .speed : .actions
            let tbW = mode == .speed
                ? TLClipEditingMetrics.toolbarSpeedWidth
                : TLClipEditingMetrics.toolbarWidth
            let tbH = (mode == .speed
                ? TLClipEditingMetrics.toolbarSpeedBodyHeight
                : TLClipEditingMetrics.toolbarBodyHeight)
                + TLClipEditingMetrics.toolbarPointerH
            let playheadContentX = (effectivePlayheadUnit / contentUnits) * contentW
            let tbSX   = screenXFor(playheadContentX)
            let trackTopY = TLK.rulerHeight + CGFloat(f.trackIdx) * TLK.trackRowHeight - vScrollOffset
            let tbTopY    = trackTopY + TLK.trackRowHeight * 0.03 - tbH * 0.5 - 6
            TLClipContextToolbar(
                trackColor: f.track.color.color,
                mode: mode,
                speedValue: f.clip.playbackSpeed,
                onSplit: { splitClip(id: cid) },
                onSpeed: {
                    withAnimation(
                        .easeInOut(duration: TLClipEditingMetrics.toolbarMorphDuration)
                    ) {
                        isSpeedEditing = true
                    }
                },
                onDuplicate: { duplicateClip(id: cid) },
                onDelete: { deleteClip(id: cid) },
                onSpeedBack: {
                    withAnimation(
                        .easeInOut(duration: TLClipEditingMetrics.toolbarMorphDuration)
                    ) {
                        isSpeedEditing = false
                    }
                },
                onSpeedCommit: { applyClipSpeed(id: cid, speed: $0) }
            )
            .frame(width: tbW)
            .offset(x: tbSX - tbW / 2, y: tbTopY)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.90, anchor: .bottom)),
                removal:   .opacity.combined(with: .scale(scale: 0.90, anchor: .bottom))
            ))
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedClipID)
            .animation(
                .easeInOut(duration: TLClipEditingMetrics.toolbarMorphDuration),
                value: isSpeedEditing
            )
        }

        if let grip = activeGrip, let f = findClip(grip.clipID) {
            let mW     = TLClipEditingMetrics.menuWidth
            let edgeX  = (grip.side == .leading
                ? f.clip.start
                : f.clip.start + f.clip.length) / contentUnits * contentW
            let rawX   = grip.side == .leading ? edgeX + 8 : edgeX - mW - 8
            // Clamp in content space, then convert to screen space
            let clampedContentX = max(0, min(contentW - mW - 4, rawX))
            let menuSX = max(sidebarW + 4, min(sidebarW + laneVW - mW - 4, screenXFor(clampedContentX)))
            let maxMenuY = viewportH - TLClipEditingMetrics.menuEstimatedHeight - 12

            let firstTrackMenuY: CGFloat = TLK.rulerHeight - 24 - vScrollOffset
            let perTrackDrop: CGFloat = 44

            let unclampedMenuY = firstTrackMenuY + CGFloat(f.trackIdx) * perTrackDrop

            let menuY = max(4, min(unclampedMenuY, maxMenuY))
            let curTx  = grip.side == .leading
                ? f.clip.transitionIn
                : f.clip.transitionOut
            TLTransitionMenu(
                selected:   curTx,
                trackColor: f.track.color.color,
                onSelect:   { setTransition(type: $0, grip: grip) },
                onUpdate:   { updateTransition($0, grip: grip) }
            )
            .frame(width: mW, alignment: .leading)
            .offset(x: menuSX, y: menuY)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.93, anchor: .topLeading)),
                removal:   .opacity.combined(with: .scale(scale: 0.93, anchor: .topLeading))
            ))
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: activeGrip)
        }
    }

    // MARK: Floating playhead handle
    // The vertical play line stays inside the timeline viewport. The triangle
    // handle is fixed to the ruler strip so it always appears above the grid.

    private func floatingPlayheadHandle(
        sidebarW: CGFloat,
        contentW: CGFloat,
        contentUnits: CGFloat,
        laneVW: CGFloat,
        hScrollOffset: CGFloat
    ) -> some View {
        let contentX = (effectivePlayheadUnit / contentUnits) * contentW
        let screenX = sidebarW + contentX - hScrollOffset
        let handleVisible = screenX >= sidebarW - TLK.playheadHandleWidth
            && screenX <= sidebarW + laneVW + TLK.playheadHandleWidth
        let hitWidth: CGFloat = 44
        let hitHeight = TLK.rulerHeight + TLK.playheadHandleHeight
        let hitOriginX = screenX - hitWidth / 2

        return ZStack(alignment: .top) {
            if handleVisible {
                TLPlayheadHandle()
                    .fill(isPlayheadDragging ? Color.white : Color.white.opacity(0.95))
                    .frame(width: TLK.playheadHandleWidth, height: TLK.playheadHandleHeight)
                    .shadow(
                        color: isPlayheadDragging ? .white.opacity(0.50) : .clear,
                        radius: isPlayheadDragging ? 6 : 0
                    )
                    .offset(y: TLK.rulerHeight - TLK.playheadHandleHeight)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.08), value: isPlayheadDragging)

                Color.clear
                    .frame(width: hitWidth, height: hitHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isPlayheadDragging {
                                    onPlayheadDragStart()
                                }
                                let contentLocationX = hitOriginX + value.location.x - sidebarW + hScrollOffset
                                let unit = (contentLocationX / contentW) * contentUnits
                                onPlayheadDragChanged(max(0, min(unit, maxPlayheadUnit)))
                            }
                            .onEnded { value in
                                let contentLocationX = hitOriginX + value.location.x - sidebarW + hScrollOffset
                                let unit = (contentLocationX / contentW) * contentUnits
                                onPlayheadDragEnded(max(0, min(unit, maxPlayheadUnit)))
                            }
                    )
            }
        }
        .frame(width: hitWidth, height: hitHeight)
        .offset(x: hitOriginX, y: 0)
    }

    // MARK: Controls track rows

    private var controlsTrackRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                TLTrackControlRow(
                    track: track,
                    availableWidth: controlsWidth,
                    volume: $tracks[idx].volume,
                    onToggleSolo: { onToggleSolo(track.id) },
                    onToggleMute: { onToggleMute(track.id) },
                    onVolumeEditingChanged: { editing in
                        if editing {
                            onEditBegin("Change Volume", .trackMix(track.id))
                        } else {
                            onEditCommit()
                        }
                    },
                    onMixSettingsChanged: onMixSettingsChanged
                )
                .frame(height: TLK.trackRowHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
                // Clip drag scrim for non-active tracks
                .overlay {
                    if isDraggingClip, clipDragState?.trackID != track.id {
                        Color.black.opacity(TLK.clipDragScrimOpacity)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: TLK.clipDragScrimAnim), value: isDraggingClip)
                .offset(y: rowOffset(trackID: track.id))
                .zIndex(draggingID == track.id ? 1 : 0)
            }
        }
        .padding(.leading, 7.5)
        .padding(.trailing, 8)
        .frame(width: controlsWidth)
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .leading) {
            MixrColors.divider.frame(width: 0.5)
        }
    }

    // MARK: Import button

    private var importFooter: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            importButton
                .offset(y: 1.5)
            Spacer(minLength: 0)
        }
        .frame(height: importFooterHeight)
        .frame(maxWidth: .infinity)
        .background(
            MixrColors.backgroundSecondary
                .overlay(alignment: .top) {
                    MixrColors.divider.frame(height: 0.5)
                }
        )
    }

    private var importButton: some View {
        Group {
            if importFooterHeight > EditorLayoutMetrics.regularImportFooterHeight {
                VStack(spacing: 6) {
                    importSongsButton
                    sfxButton
                }
            } else {
                HStack(spacing: TLK.importFooterButtonSpacing) {
                    importSongsButton
                    sfxButton
                }
            }
        }
        .padding(.horizontal, TLK.importFooterHorizontalPadding)
    }

    private var importSongsButton: some View {
        Button {
            showFilePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Import Songs")
                    .mixrFont(.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(MixrColors.textMuted.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MixrSpacing.sm)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
            .partyModeBorder(
                shape: RoundedRectangle(cornerRadius: 8),
                role: .button,
                lighting: .coolLeading,
                glintOffset: .near
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
    }

    private var sfxButton: some View {
        Button {
            showSFXPanel = true
        } label: {
            MixrSFXOutlineButtonLabel(style: .d)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Sound Effects")
        .modifier(
            TLSFXLibraryPresentation(
                isPresented: $showSFXPanel,
                style: sfxPresentationStyle,
                onSelect: onSelectSoundEffect
            )
        )
    }

    // MARK: Audio drop importing

    private func handleAudioDrop(_ providers: [NSItemProvider]) -> Bool {
        var didRequestImport = false

        for provider in providers {
            guard let type = TLAudioDrop.supportedTypes.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else {
                continue
            }

            didRequestImport = true
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard
                    let url,
                    let importedURL = TLAudioDrop.temporaryCopy(of: url)
                else { return }

                DispatchQueue.main.async {
                    onImportURLs([importedURL])
                }
            }
        }

        return didRequestImport
    }

    // MARK: Drag helpers

    /// Visual Y offset for a row during a drag.
    /// The grabbed row follows `dragTranslation`; surrounding rows shift to show the insertion gap.
    private func rowOffset(trackID: UUID) -> CGFloat {
        guard let dragID = draggingID,
              let fromIdx = tracks.firstIndex(where: { $0.id == dragID })
        else { return 0 }

        let steps    = Int((dragTranslation / TLK.trackRowHeight).rounded())
        let insertAt = max(0, min(tracks.count - 1, fromIdx + steps))

        if trackID == dragID { return dragTranslation }

        guard let thisIdx = tracks.firstIndex(where: { $0.id == trackID }) else { return 0 }

        // Rows between the original position and insertion point shift to open the gap
        if fromIdx < insertAt, thisIdx > fromIdx, thisIdx <= insertAt { return -TLK.trackRowHeight }
        if fromIdx > insertAt, thisIdx >= insertAt, thisIdx < fromIdx { return  TLK.trackRowHeight }
        return 0
    }

    private func commitReorder(fromID: UUID, translation: CGFloat) {
        defer {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                draggingID      = nil
                dragTranslation = 0
            }
        }
        guard let fromIdx = tracks.firstIndex(where: { $0.id == fromID }) else { return }
        let steps    = Int((translation / TLK.trackRowHeight).rounded())
        let insertAt = max(0, min(tracks.count - 1, fromIdx + steps))
        guard insertAt != fromIdx else { return }
        onReorder(IndexSet([fromIdx]), insertAt > fromIdx ? insertAt + 1 : insertAt)
    }
}

// MARK: - Song Row

private struct TLSongRow: View {
    let track: MixrTrack
    let rowWidth: CGFloat
    var isSelected: Bool = false
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat) -> Void)?   = nil
    var onDelete: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil

    @State private var swipeOffset: CGFloat = 0
    @State private var isDeleting = false

    private let deleteActionWidth: CGFloat = 72
    private let revealThreshold: CGFloat = 36

    private var isDeleteRevealed: Bool {
        swipeOffset <= -revealThreshold
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .zIndex(isDeleteRevealed ? 2 : 0)

            rowContent
                .background(MixrTrackRowBackground(isSFXTrack: track.isSFXTrack))
                .offset(x: isDeleting ? -rowWidth : swipeOffset)
                .opacity(isDeleting ? 0.72 : 1)
                .contentShape(Rectangle())
                .overlay {
                    TLRowHorizontalSwipeHandler(
                        swipeOffset: $swipeOffset,
                        deleteActionWidth: deleteActionWidth,
                        revealThreshold: revealThreshold,
                        onHorizontalSwipeBegan: closeDeleteAction
                    )
                }
                .zIndex(1)
        }
        .frame(height: TLK.trackRowHeight)
        .clipped()
        .onChange(of: track.id) { _, _ in
            swipeOffset = 0
            isDeleting = false
        }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            TLSongRowGripper(
                onDragChanged: {
                    closeDeleteAction()
                    onDragChanged?($0)
                },
                onDragEnded: onDragEnded
            )

            MixrSongColorChip(
                color: track.color,
                artworkData: track.artworkData,
                icon: "music.note",
                usesSFXMark: track.isSFXTrack
            )

            VStack(alignment: .leading, spacing: 2) {
                titleRow
                metadataRow
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: TLK.trackRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
    }

    private var titleRow: some View {
        HStack(spacing: 0) {
            Text(track.title)
                .mixrScaledFont(
                    size: 12,
                    weight: .semibold,
                    relativeTo: .subheadline
                )
                .foregroundStyle(MixrColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(track.duration)
                .mixrScaledFont(size: 10, relativeTo: .caption)
                .foregroundStyle(MixrColors.textSecondary)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 0) {
            Text(track.artist)
                .mixrScaledFont(size: 11, relativeTo: .caption)
                .foregroundStyle(MixrColors.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(track.isSFXTrack
                ? "\(track.clips.count) clip\(track.clips.count == 1 ? "" : "s")"
                : "\(track.bpmDisplay) BPM")
                .mixrScaledFont(size: 10, relativeTo: .caption)
                .foregroundStyle(MixrColors.textSecondary)
        }
    }

    private var deleteAction: some View {
        Button {
            performDelete()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Delete")
                    .mixrScaledFont(
                        size: 10,
                        weight: .semibold,
                        relativeTo: .caption
                    )
            }
            .foregroundStyle(.white)
            .frame(width: deleteActionWidth, height: TLK.trackRowHeight)
            .background(Color(.systemRed))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func performDelete() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            isDeleting = true
            swipeOffset = -rowWidth
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDelete?()
        }
    }

    private func closeDeleteAction() {
        guard swipeOffset != 0 else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            swipeOffset = 0
        }
    }
}

// UIView that passes touches through in the gripper region so the SwiftUI
// DragGesture on TLSongRowGripper still receives them.
private final class TLGripperPassthroughView: UIView {
    // Gripper is 8pt wide at leading padding 10pt → passthrough through first ~26pt
    var gripperPassthroughWidth: CGFloat = 26

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.x < gripperPassthroughWidth { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct TLRowHorizontalSwipeHandler: UIViewRepresentable {
    @Binding var swipeOffset: CGFloat
    let deleteActionWidth: CGFloat
    let revealThreshold: CGFloat
    var onHorizontalSwipeBegan: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            swipeOffset: $swipeOffset,
            deleteActionWidth: deleteActionWidth,
            revealThreshold: revealThreshold,
            onHorizontalSwipeBegan: onHorizontalSwipeBegan
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = TLGripperPassthroughView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var swipeOffset: CGFloat
        let deleteActionWidth: CGFloat
        let revealThreshold: CGFloat
        var onHorizontalSwipeBegan: () -> Void
        private var dragStartOffset: CGFloat = 0
        private var isActive = false

        private let horizontalDominance: CGFloat = 1.25
        private let minimumDirectionMovement: CGFloat = 8

        init(
            swipeOffset: Binding<CGFloat>,
            deleteActionWidth: CGFloat,
            revealThreshold: CGFloat,
            onHorizontalSwipeBegan: @escaping () -> Void
        ) {
            _swipeOffset = swipeOffset
            self.deleteActionWidth = deleteActionWidth
            self.revealThreshold = revealThreshold
            self.onHorizontalSwipeBegan = onHorizontalSwipeBegan
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }

            let t = pan.translation(in: view)
            let v = pan.velocity(in: view)
            let movement = max(abs(t.x), abs(t.y))
            let speed = hypot(v.x, v.y)

            // Fast horizontal flick — begin immediately.
            if speed > 80, abs(v.x) > abs(v.y) * horizontalDominance {
                return true
            }

            // Not enough movement yet — don't claim; ScrollView keeps the gesture.
            guard movement >= minimumDirectionMovement else { return false }

            return abs(t.x) > abs(t.y) * horizontalDominance
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Scroll view owns vertical drags; when we begin (horizontal only), stay exclusive.
            if other is UIPanGestureRecognizer, other.view is UIScrollView { return false }
            return true
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let tx = pan.translation(in: view).x

            switch pan.state {
            case .began:
                isActive = true
                dragStartOffset = swipeOffset
                onHorizontalSwipeBegan()
            case .changed:
                guard isActive else { return }
                let next = min(0, max(-deleteActionWidth, dragStartOffset + tx))
                DispatchQueue.main.async {
                    withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
                        self.swipeOffset = next
                    }
                }
            case .ended, .cancelled:
                defer {
                    isActive = false
                    pan.setTranslation(.zero, in: view)
                }
                guard isActive else { return }
                let projected = dragStartOffset + tx + pan.velocity(in: view).x * 0.12
                let shouldReveal = swipeOffset < -revealThreshold || projected < -deleteActionWidth
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        self.swipeOffset = shouldReveal ? -self.deleteActionWidth : 0
                    }
                }
            default:
                break
            }
        }
    }
}

private struct TLSongRowGripper: View {
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat) -> Void)?   = nil

    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(MixrColors.textSecondary.opacity(0.62))
                    .frame(width: 2.4, height: 2.4)
            }
        }
        .frame(width: 8, height: 34)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    onDragChanged?(value.translation.height)
                }
                .onEnded { value in
                    onDragEnded?(value.translation.height)
                }
        )
    }
}

// MARK: - Time Ruler

private struct TLRuler: View {
    let width: CGFloat
    let contentUnits: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            MixrColors.background.opacity(0.80)

            Canvas { ctx, size in
                for seconds in MixrTimeline.gridLineSeconds(upToContentUnits: contentUnits) {
                    let unit = MixrTimeline.units(fromSeconds: Double(seconds))
                    let x = (unit / contentUnits) * width
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 4))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(tick, with: .color(MixrColors.divider.opacity(0.25)), lineWidth: 0.5)
                }

                for seconds in MixrTimeline.rulerLabelSeconds(upToContentUnits: contentUnits) {
                    let unit = MixrTimeline.units(fromSeconds: Double(seconds))
                    let x = (unit / contentUnits) * width
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 7))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(tick, with: .color(MixrColors.divider.opacity(0.45)), lineWidth: 0.5)

                    let label = TLK.timeLabel(for: seconds)
                    let resolved = ctx.resolve(
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(MixrColors.textSecondary)
                    )
                    if seconds == 0 {
                        ctx.draw(resolved, at: CGPoint(x: 2, y: 5), anchor: .topLeading)
                    } else {
                        ctx.draw(resolved, at: CGPoint(x: x, y: 5), anchor: .top)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
        }
    }
}

// MARK: - Grid Canvas

private struct TLGridCanvas: View {
    let width: CGFloat
    let height: CGFloat
    let contentUnits: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            for seconds in MixrTimeline.gridLineSeconds(upToContentUnits: contentUnits) {
                let unit = MixrTimeline.units(fromSeconds: Double(seconds))
                let x = (unit / contentUnits) * width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                ctx.stroke(path, with: .color(MixrColors.divider.opacity(0.55)), lineWidth: 0.65)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Timeline Surface

private struct TLTimelineSurface: View {
    let isDropTarget: Bool

    var body: some View {
        Rectangle()
            .fill(MixrColors.backgroundSecondary)
            .overlay {
                Rectangle()
                    .fill(MixrColors.surface.opacity(isDropTarget ? 0.28 : 0.18))
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDropTarget ? 0.055 : 0.035),
                        Color.clear,
                        Color.black.opacity(0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .top) {
                Color.white.opacity(isDropTarget ? 0.12 : 0.06)
                    .frame(height: 0.5)
            }
            .overlay(alignment: .leading) {
                Color.black.opacity(0.18)
                    .frame(width: 1)
            }
            .animation(.easeInOut(duration: 0.18), value: isDropTarget)
    }
}

private struct TLEmptyTimelineState: View {
    let isDropTarget: Bool
    let maximumButtonWidth: CGFloat
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(isDropTarget ? "Drop audio files to import" : "Import songs to start a remix")
                    .mixrScaledFont(
                        size: 13,
                        weight: .medium
                    )
                    .foregroundStyle(MixrColors.textSecondary.opacity(isDropTarget ? 0.86 : 0.73))

                if !isDropTarget {
                    Text("Drag audio files here or use Import Songs")
                        .mixrScaledFont(size: 10, relativeTo: .caption)
                        .foregroundStyle(MixrColors.textSecondary.opacity(0.73))
                }
            }

            if !isDropTarget {
                Button(action: onImport) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Import Songs")
                            .mixrFont(.button)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(MixrColors.textMuted.opacity(0.84))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MixrSpacing.sm)
                    .padding(.vertical, MixrLayout.buttonPaddingV)
                    .background { TLEmptyImportSongsGlass() }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                MixrColors.importCTABorder.opacity(0.38),
                                lineWidth: 0.6
                            )
                    }
                    .partyModeBorder(
                        shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                        role: .button,
                        lighting: .coolLeading,
                        glintOffset: .near
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: maximumButtonWidth)
                .padding(.top, MixrSpacing.md)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// Secondary frosted Import Songs chrome — dark navy-purple fill with
/// dimensional top glow and depth, plus party-mode rim from the caller.
private struct TLEmptyImportSongsGlass: View {
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        shape
            .fill(MixrColors.importCTAFill.opacity(0.78))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.14)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            MixrColors.importCTAGlow.opacity(0.14),
                            MixrColors.importCTAGlow.opacity(0.05),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.72)
                    )
                )
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.025),
                            Color.clear,
                            Color.black.opacity(0.14),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
    }
}

// MARK: - Clip Move Gesture Bridge

private struct TLClipMoveGestureBridge: UIViewRepresentable {
    let clipID: UUID
    let areaFrame: CGRect
    let contentXOffset: CGFloat
    let isEnabled: Bool
    var onTap: (UUID, CGFloat) -> Void
    var onMoveArmed: (UUID, CGFloat, CGFloat) -> Void
    var onMoveChanged: (UUID, CGFloat, CGFloat, CGFloat, CGFloat) -> Void
    var onMoveEnded: () -> Void
    var onMoveCancelled: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = TLK.clipDragLongPressDuration
        longPress.allowableMovement = TLK.clipDragLongPressMaxDistance
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        context.coordinator.longPressRecognizer = longPress
        context.coordinator.tapRecognizer = tap
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.clipID = clipID
        context.coordinator.areaFrame = areaFrame
        context.coordinator.contentXOffset = contentXOffset
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTap = onTap
        context.coordinator.onMoveArmed = onMoveArmed
        context.coordinator.onMoveChanged = onMoveChanged
        context.coordinator.onMoveEnded = onMoveEnded
        context.coordinator.onMoveCancelled = onMoveCancelled
        context.coordinator.longPressRecognizer?.isEnabled = isEnabled
        context.coordinator.tapRecognizer?.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            clipID: clipID,
            areaFrame: areaFrame,
            contentXOffset: contentXOffset,
            isEnabled: isEnabled,
            onTap: onTap,
            onMoveArmed: onMoveArmed,
            onMoveChanged: onMoveChanged,
            onMoveEnded: onMoveEnded,
            onMoveCancelled: onMoveCancelled
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var clipID: UUID
        var areaFrame: CGRect
        var contentXOffset: CGFloat
        var isEnabled: Bool
        var onTap: (UUID, CGFloat) -> Void
        var onMoveArmed: (UUID, CGFloat, CGFloat) -> Void
        var onMoveChanged: (UUID, CGFloat, CGFloat, CGFloat, CGFloat) -> Void
        var onMoveEnded: () -> Void
        var onMoveCancelled: () -> Void
        weak var longPressRecognizer: UILongPressGestureRecognizer?
        weak var tapRecognizer: UITapGestureRecognizer?

        private var startLocation: CGPoint?
        private var didBeginMove = false

        init(
            clipID: UUID,
            areaFrame: CGRect,
            contentXOffset: CGFloat,
            isEnabled: Bool,
            onTap: @escaping (UUID, CGFloat) -> Void,
            onMoveArmed: @escaping (UUID, CGFloat, CGFloat) -> Void,
            onMoveChanged: @escaping (UUID, CGFloat, CGFloat, CGFloat, CGFloat) -> Void,
            onMoveEnded: @escaping () -> Void,
            onMoveCancelled: @escaping () -> Void
        ) {
            self.clipID = clipID
            self.areaFrame = areaFrame
            self.contentXOffset = contentXOffset
            self.isEnabled = isEnabled
            self.onTap = onTap
            self.onMoveArmed = onMoveArmed
            self.onMoveChanged = onMoveChanged
            self.onMoveEnded = onMoveEnded
            self.onMoveCancelled = onMoveCancelled
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard isEnabled, recognizer.state == .ended else { return }
            let local = recognizer.location(in: recognizer.view)
            onTap(clipID, contentXOffset + local.x)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard isEnabled, let view = recognizer.view else { return }
            let local = recognizer.location(in: view)
            let areaPoint = CGPoint(
                x: areaFrame.minX + local.x,
                y: areaFrame.minY + local.y
            )

            switch recognizer.state {
            case .began:
                startLocation = local
                didBeginMove = true
                onMoveArmed(clipID, areaPoint.x, areaPoint.y)
            case .changed:
                guard let startLocation else { return }
                let startAreaPoint = CGPoint(
                    x: areaFrame.minX + startLocation.x,
                    y: areaFrame.minY + startLocation.y
                )
                onMoveChanged(
                    clipID,
                    areaPoint.x,
                    areaPoint.y,
                    startAreaPoint.x,
                    startAreaPoint.y
                )
            case .ended:
                if didBeginMove { onMoveEnded() }
                reset()
            case .cancelled, .failed:
                if didBeginMove { onMoveCancelled() }
                reset()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func reset() {
            startLocation = nil
            didBeginMove = false
        }
    }
}

// MARK: - Track Lane

private struct TLTrackLane: View {
    let track:          MixrTrack
    let timelineWidth:  CGFloat
    let contentUnits:   CGFloat
    var selectedClipID: UUID?          = nil
    var activeGrip:     ActiveGrip?    = nil
    var armedClipID:    UUID?          = nil
    /// Non-nil when a clip on THIS track is actively being dragged.
    var clipDragState:  ClipDragState? = nil
    var isScrimmed:     Bool           = false
    var isActiveForDrag: Bool          = false
    /// Muted, or excluded by another track's solo — clips render dimmed.
    var isInaudible:    Bool           = false
    var onClipTapped:   ((UUID, CGFloat) -> Void)?          = nil
    var onGripTapped:   ((ActiveGrip) -> Void)?             = nil
    var onClipDragArmed:   ((UUID, CGFloat, CGFloat) -> Void)?                     = nil
    var onClipDragChanged: ((UUID, CGFloat, CGFloat, CGFloat, CGFloat) -> Void)? = nil
    var onClipDragEnded:   (() -> Void)?                                         = nil
    var onClipDragCancelled: (() -> Void)?                                       = nil

    private let gripHit = TLClipEditingMetrics.gripHit

    private func resolvedPreviewFrames() -> [ClipRenderFrame] {
        guard let drag = clipDragState else {
            return track.clips.map {
                ClipRenderFrame(clipID: $0.id, start: $0.start, length: $0.length)
            }
        }

        let snapStart = drag.isIndicatorSnapped ? drag.resolvedInsertStart : nil
        let snapPreviewIDs = snapPreviewNeighborIDs(around: snapStart)

        return track.clips.compactMap { clip in
            if clip.id == drag.clipID {
                return ClipRenderFrame(
                    clipID: clip.id,
                    start: clip.start,
                    length: clip.length,
                    opacity: TLK.clipDragGhostOpacity,
                    isSourceGhost: true
                )
            }

            let neighborShiftPx: CGFloat
            if clip.id == snapPreviewIDs.left {
                neighborShiftPx = -TLK.clipDragNeighborShift
            } else if clip.id == snapPreviewIDs.right {
                neighborShiftPx = TLK.clipDragNeighborShift
            } else {
                neighborShiftPx = 0
            }

            return ClipRenderFrame(
                clipID: clip.id,
                start: clip.start,
                length: clip.length,
                neighborShiftPx: neighborShiftPx
            )
        }
    }

    private func snapPreviewNeighborIDs(around snapStart: CGFloat?) -> (left: UUID?, right: UUID?) {
        guard let snapStart else { return (nil, nil) }
        let epsilon = MixrTimeline.clipEdgeEpsilon
        let others = track.clips.filter { $0.id != clipDragState?.clipID }
        let left = others
            .filter { abs(($0.start + $0.length) - snapStart) <= epsilon }
            .max { lhs, rhs in lhs.start < rhs.start }
        let right = others
            .filter { abs($0.start - snapStart) <= epsilon }
            .min { lhs, rhs in lhs.start < rhs.start }

        return (left?.id, right?.id)
    }

    private func modelClip(for id: UUID) -> MixrClip? {
        track.clips.first(where: { $0.id == id })
    }

    private func segments(for clipID: UUID, in frames: [ClipRenderFrame]) -> [ClipRenderFrame] {
        frames.filter { $0.clipID == clipID && !$0.isSourceGhost }
    }

    // MARK: Body

    var body: some View {
        let frames = resolvedPreviewFrames()

        ZStack(alignment: .leading) {
            // Faint wash of the track's own color; the SFX lane sits 5%
            // lower than the standard 0.025 so its silver tint reads a
            // touch quieter than the song lanes.
            track.color.color.opacity(track.isSFXTrack ? 0.018 : 0.025)
            MixrColors.divider
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            ForEach(track.clips) { clip in
                let clipSegments = segments(for: clip.id, in: frames)
                let isDraggingThis = clipDragState?.clipID == clip.id
                let isArmedThis = armedClipID == clip.id && clipDragState == nil
                let isSel = clip.id == selectedClipID
                // Original model position — stable, never changes during drag.
                let origXOffset = (clip.start / contentUnits) * timelineWidth
                let origClipW   = max(1, (clip.length / contentUnits) * timelineWidth)

                // Visual rendering — driven by render frames (may animate/split/shift)
                ForEach(clipSegments) { segment in
                    let xOffset = (segment.start / contentUnits) * timelineWidth + segment.neighborShiftPx
                    let clipW   = max(1, (segment.length / contentUnits) * timelineWidth)
                    clipBody(
                        clip: clip,
                        segment: segment,
                        xOffset: xOffset,
                        clipW: clipW,
                        isSel: isSel,
                        isDraggingThis: isDraggingThis,
                        isArmedThis: isArmedThis
                    )
                }

                // Permanent gesture hit area — always present regardless of drag state so that
                // the UILongPressGestureRecognizer UIView is NEVER removed mid-gesture.
                // isEnabled stays true for the actively-dragged clip so that .changed / .ended
                // events continue to fire even after clipDragState is set.
                Color.clear
                    .frame(width: origClipW, height: TLK.trackRowHeight)
                    .contentShape(Rectangle())
                    .overlay {
                        GeometryReader { proxy in
                            TLClipMoveGestureBridge(
                                clipID: clip.id,
                                areaFrame: proxy.frame(in: .named("tlareaRoot")),
                                contentXOffset: origXOffset,
                                isEnabled: clipDragState == nil || isDraggingThis,
                                onTap: { clipID, tapX in
                                    guard clipDragState == nil else { return }
                                    onClipTapped?(clipID, tapX)
                                },
                                onMoveArmed:     { id, x, y           in onClipDragArmed?(id, x, y) },
                                onMoveChanged:   { id, cx, cy, sx, sy in onClipDragChanged?(id, cx, cy, sx, sy) },
                                onMoveEnded:     {                        onClipDragEnded?() },
                                onMoveCancelled: {                        onClipDragCancelled?() }
                            )
                        }
                    }
                    .position(x: origXOffset + origClipW / 2, y: TLK.trackRowHeight / 2)
                    .zIndex(isDraggingThis ? 3 : 0)

                // SFX clips have no transitions — no grips.
                if !isDraggingThis && !isArmedThis && !clip.isSoundEffect {
                    clipGrips(for: clip, segments: clipSegments)
                }
            }

            // Ghost of dragged clip at original position — visual only, no gesture.
            // The permanent hit area above handles all gesture events for the dragged clip.
            if let drag = clipDragState,
               let ghost = frames.first(where: { $0.isSourceGhost }),
               drag.trackID == track.id {
                let xOffset = (ghost.start / contentUnits) * timelineWidth
                let clipW   = max(1, (ghost.length / contentUnits) * timelineWidth)
                WaveformClip(waveformColor: track.color)
                    .frame(height: TLK.waveformHeight)
                    .frame(width: clipW)
                    .opacity(TLK.clipDragGhostOpacity)
                    .allowsHitTesting(false)
                    .position(x: xOffset + clipW / 2, y: TLK.trackRowHeight / 2)
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isInaudible ? 0.42 : 1)
        .animation(.easeOut(duration: 0.18), value: isInaudible)
        .overlay {
            if isScrimmed {
                Color.black.opacity(TLK.clipDragScrimOpacity)
                    .allowsHitTesting(true)
                    .transition(.opacity)
            }
        }
        .overlay {
            if isActiveForDrag {
                Rectangle()
                    .strokeBorder(track.color.color.opacity(0.38), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func clipBody(
        clip: MixrClip,
        segment: ClipRenderFrame,
        xOffset: CGFloat,
        clipW: CGFloat,
        isSel: Bool,
        isDraggingThis: Bool,
        isArmedThis: Bool
    ) -> some View {
        let selectedBorderHeight = TLK.trackRowHeight - 2

        WaveformClip(waveformColor: track.color)
            .frame(height: TLK.waveformHeight)
            .frame(width: clipW)
            .overlay {
                if isSel && !isDraggingThis {
                    let accent = track.color.color
                    let selectedOutline = track.color.selectedOutlineColor
                    let selectedGlow = track.color.glowColor
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                track.color == .silver
                                    ? selectedGlow
                                    : accent.opacity(0.88),
                                lineWidth: 8.2
                            )
                            .blur(radius: 5.6)
                            .opacity(track.color == .silver ? 1.0 : 0.7)
                            .padding(-3.0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                track.color == .silver
                                    ? selectedOutline.opacity(0.55)
                                    : accent.opacity(0.38),
                                lineWidth: 8.5
                            )
                            .blur(radius: 3.2)
                            .opacity(0.82)
                            .padding(1.0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selectedOutline, lineWidth: 2.4)
                            .shadow(
                                color: track.color == .silver ? selectedGlow : accent.opacity(0.88),
                                radius: 7
                            )
                            .shadow(
                                color: track.color == .silver
                                    ? MixrColors.sfxGlow.opacity(0.10)
                                    : accent.opacity(0.5),
                                radius: 15
                            )
                            .padding(-0.35)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                            .padding(1.2)
                    }
                    .frame(width: clipW, height: selectedBorderHeight)
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: isSel && !isDraggingThis && !isArmedThis ? Color.black.opacity(0.34) : .clear,
                    radius: 7, x: 0, y: 4)
            .opacity(isArmedThis ? 0 : segment.opacity)
            .allowsHitTesting(false)
            .position(x: xOffset + clipW / 2, y: TLK.trackRowHeight / 2)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: segment.start)
            .animation(.spring(response: TLK.clipInsertPreviewResponse, dampingFraction: 0.82), value: segment.length)
            .zIndex(isSel ? 2 : 0)
    }

    @ViewBuilder
    private func clipGrips(for clip: MixrClip, segments: [ClipRenderFrame]) -> some View {
        if let first = segments.first {
            let xOffset = (first.start / contentUnits) * timelineWidth + first.neighborShiftPx
            TLTransitionGrip(
                trackColor: track.color.color,
                isActive: activeGrip?.clipID == clip.id && activeGrip?.side == .leading,
                transitionType: clip.transitionIn.type,
                onTap: {
                    onGripTapped?(ActiveGrip(clipID: clip.id, trackID: track.id, side: .leading))
                }
            )
            .frame(width: gripHit, height: gripHit)
            .position(x: xOffset, y: (TLK.trackRowHeight + TLK.waveformHeight - gripHit) / 2)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: first.start)
            .zIndex(TLK.timelineGripZIndex)
        }

        if let last = segments.last {
            let xOffset = (last.start / contentUnits) * timelineWidth + last.neighborShiftPx
            let clipW = max(1, (last.length / contentUnits) * timelineWidth)
            TLTransitionGrip(
                trackColor: track.color.color,
                isActive: activeGrip?.clipID == clip.id && activeGrip?.side == .trailing,
                transitionType: clip.transitionOut.type,
                onTap: {
                    onGripTapped?(ActiveGrip(clipID: clip.id, trackID: track.id, side: .trailing))
                }
            )
            .frame(width: gripHit, height: gripHit)
            .position(x: xOffset + clipW, y: (TLK.trackRowHeight + TLK.waveformHeight - gripHit) / 2)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: last.start)
            .zIndex(TLK.timelineGripZIndex)
        }
    }
}

private struct TLClipBoundaryCanvas: View {
    let tracks: [MixrTrack]
    let timelineWidth: CGFloat
    let totalHeight: CGFloat
    var topInset: CGFloat = TLK.rulerHeight

    var body: some View {
        Canvas { ctx, _ in
            for track in tracks {
                for clip in track.clips {
                    let startX = (clip.start / TLK.totalUnits) * timelineWidth
                    let endX = ((clip.start + clip.length) / TLK.totalUnits) * timelineWidth

                    strokeBoundary(at: startX, in: &ctx)
                    strokeBoundary(at: endX, in: &ctx)
                }
            }
        }
        .frame(width: timelineWidth, height: totalHeight)
    }

    private func strokeBoundary(at x: CGFloat, in ctx: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: topInset))
        path.addLine(to: CGPoint(x: x, y: totalHeight))
        ctx.stroke(path, with: .color(MixrColors.divider.opacity(0.8)), lineWidth: 0.9)
    }
}

// MARK: - Audio Drop Support

private enum TLAudioDrop {
    static let supportedTypes: [String] = [
        UTType.mp3.identifier,
        UTType.mpeg4Audio.identifier,
        UTType.wav.identifier,
        UTType.aiff.identifier,
    ]

    static func temporaryCopy(of sourceURL: URL) -> URL? {
        let fileManager = FileManager.default
        let dropDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MixrDroppedAudio", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: dropDirectory,
                withIntermediateDirectories: true
            )

            let destination = dropDirectory.appendingPathComponent(sourceURL.lastPathComponent)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

// MARK: - Playhead (line + handle split for correct z-order)

private struct TLPlayheadLine: View {
    let timelineWidth: CGFloat
    let totalHeight: CGFloat
    let playheadUnit: CGFloat
    let contentUnits: CGFloat
    var isDragging: Bool = false

    private var xPos: CGFloat {
        (playheadUnit / contentUnits) * timelineWidth
    }

    private var lineStartY: CGFloat { TLK.rulerHeight }
    private var lineHeight: CGFloat { totalHeight - TLK.rulerHeight }

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.white : Color.white.opacity(0.90))
            .frame(width: isDragging ? 1.5 : 1, height: lineHeight)
            .offset(x: xPos - 0.5, y: lineStartY)
            .frame(width: timelineWidth, height: totalHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: isDragging)
    }
}

/// Triangle scrub handle + drag hit strip — sits above the line and lane chrome.
private struct TLPlayheadHandleControl: View {
    let timelineWidth: CGFloat
    let totalHeight: CGFloat
    let playheadUnit: CGFloat
    let maxUnit: CGFloat
    var isDragging: Bool = false
    var onDragStart:   () -> Void          = {}
    var onDragChanged: (CGFloat) -> Void   = { _ in }
    var onDragEnded:   (CGFloat) -> Void   = { _ in }

    @State private var gestureActive = false

    private let hitWidth: CGFloat = 44
    private var hitHeight: CGFloat { TLK.rulerHeight + TLK.playheadHandleHeight }

    private var xPos: CGFloat {
        (playheadUnit / TLK.totalUnits) * timelineWidth
    }

    private var lineStartY: CGFloat { TLK.rulerHeight }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TLPlayheadHandle()
                .fill(isDragging ? Color.white : Color.white.opacity(0.95))
                .frame(width: TLK.playheadHandleWidth, height: TLK.playheadHandleHeight)
                .shadow(
                    color: isDragging ? .white.opacity(0.50) : .clear,
                    radius: isDragging ? 6 : 0
                )
                .offset(
                    x: xPos - TLK.playheadHandleWidth / 2,
                    y: lineStartY - TLK.playheadHandleHeight
                )
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.08), value: isDragging)

            HStack(spacing: 0) {
                Color.clear.frame(width: max(0, xPos - hitWidth / 2))
                Color.clear
                    .frame(width: hitWidth, height: hitHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("phContent"))
                            .onChanged { value in
                                if !gestureActive {
                                    gestureActive = true
                                    onDragStart()
                                }
                                let unit = (value.location.x / timelineWidth) * TLK.totalUnits
                                onDragChanged(max(0, min(unit, maxUnit)))
                            }
                            .onEnded { value in
                                gestureActive = false
                                let unit = (value.location.x / timelineWidth) * TLK.totalUnits
                                onDragEnded(max(0, min(unit, maxUnit)))
                            }
                    )
                Spacer(minLength: 0)
            }
            .frame(width: timelineWidth, height: hitHeight)
        }
        .frame(width: timelineWidth, height: totalHeight)
        .coordinateSpace(name: "phContent")
    }
}

private struct TLPlayheadHandle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Track Control Row

private struct TLTrackControlRow: View {
    let track: MixrTrack
    let availableWidth: CGFloat
    @Binding var volume: Double
    var onToggleSolo: () -> Void = {}
    var onToggleMute: () -> Void = {}
    var onVolumeEditingChanged: (Bool) -> Void = { _ in }
    var onMixSettingsChanged: () -> Void = {}

    var body: some View {
        Group {
            if availableWidth >= 116 {
                horizontalControls
            } else {
                compactControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var horizontalControls: some View {
        HStack(spacing: 5) {
            trackToggles
            volumeControl
                .padding(.leading, 4)
        }
    }

    private var compactControls: some View {
        VStack(spacing: 0) {
            trackToggles
            volumeControl
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 1)
    }

    private var trackToggles: some View {
        HStack(spacing: 5) {
            TLTrackToggle(
                label: "S",
                isActive: track.isSoloed,
                accent: MixrColors.secondaryPurple,
                action: toggleSolo
            )

            TLTrackToggle(
                label: "M",
                isActive: track.isMuted,
                accent: MixrColors.primaryPurple,
                action: toggleMute
            )
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 4) {
            Image(systemName: volumeIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary.opacity(0.85))
                .frame(width: 11)

            TLVolumeSlider(
                value: $volume,
                accentColor: track.color.volumeAccentColor,
                trackColor: track.color.volumeTrackColor,
                onEditingChanged: onVolumeEditingChanged
            )
            .frame(maxWidth: .infinity)
            .onChange(of: volume) { _, _ in
                onMixSettingsChanged()
            }
        }
    }

    private func toggleSolo() {
        onToggleSolo()
        onMixSettingsChanged()
    }

    private func toggleMute() {
        onToggleMute()
        onMixSettingsChanged()
    }

    private var volumeIcon: String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.34  { return "speaker.wave.1.fill" }
        if volume < 0.67  { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Solo / Mute glass toggle — active state shows the Mixr accent ring
/// and a lit label, matching the existing compact track toggle.
struct TLTrackToggle: View {
    let label: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.mixrCompactTrackToggle)
            .opacity(isActive ? 1 : 0.92)
            .overlay {
                if isActive {
                    Circle()
                        .strokeBorder(accent.opacity(0.62), lineWidth: 0.9)
                        .frame(width: TLK.trackToggleSize, height: TLK.trackToggleSize)
                        .shadow(color: accent.opacity(0.45), radius: 4)
                }
            }
            .animation(.easeOut(duration: 0.14), value: isActive)
    }
}

// MARK: - Effects Panel

private struct TLEffectsPanel: View {
    @Binding var isCollapsed: Bool
    @Binding var tracks: [MixrTrack]
    let selectedClipID: UUID?
    let playheadUnit: CGFloat
    var onEditBegin: (String, TimelineEditScope) -> Void = { _, _ in }
    var onEditCommit: () -> Void = {}
    var onAutoTapped: () -> Void = {}

    @State private var selectedEffect: MixrEffect?
    /// Current horizontal content offset of the cards row — the open/close
    /// slide compensates for it so the focused card always lands flush with
    /// the "Effects" header, no matter where the row is scrolled.
    @State private var rowScrollOffset: CGFloat = 0

    // MARK: Targeting — selected clip first, else the clip under the playhead.

    private var targetClipPath: (trackIdx: Int, clipIdx: Int)? {
        if let id = selectedClipID {
            for (ti, track) in tracks.enumerated() {
                if let ci = track.clips.firstIndex(where: { $0.id == id }) {
                    return (ti, ci)
                }
            }
        }
        for (ti, track) in tracks.enumerated() {
            if let ci = track.clips.firstIndex(where: {
                playheadUnit >= $0.start && playheadUnit <= $0.start + $0.length
            }) {
                return (ti, ci)
            }
        }
        return nil
    }

    private var targetClip: MixrClip? {
        targetClipPath.map { tracks[$0.trackIdx].clips[$0.clipIdx] }
    }

    private var hasTarget: Bool { targetClipPath != nil }

    private var expandAnimation: Animation {
        .easeInOut(duration: EffectTrayMetrics.expandAnimationDuration)
    }

    /// Siblings dissolve WHILE the focused card slides — a concurrent
    /// crossfade, so no card text ever overlaps mid-push.
    private var siblingFadeOutAnimation: Animation {
        let total = EffectTrayMetrics.expandAnimationDuration
        return .easeInOut(duration: total * 0.45)
    }

    /// On close, siblings reappear only as the reverse push settles, so the
    /// focused card never slides across visible neighbors.
    private var siblingFadeInAnimation: Animation {
        let total = EffectTrayMetrics.expandAnimationDuration
        return .easeInOut(duration: total * 0.40).delay(total * 0.45)
    }

    var body: some View {
        VStack(spacing: 0) {
            MixrColors.divider.frame(height: 0.5)

            effectsHeader

            if !isCollapsed {
                effectsContent
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                MixrColors.backgroundSecondary
                // Extend past the bottom so glass strokeBorder / edge rims
                // clip away — no hairline at the screen edge on any size.
                GlassBackground(level: .strong, cornerRadius: 0)
                    .padding(.bottom, -3)
            }
            .clipped()
        }
        .overlay(alignment: .top) {
            MixrColors.backgroundSecondary.frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(effectsDragGesture)
        .onChange(of: hasTarget) { _, hasClip in
            if !hasClip {
                withAnimation(expandAnimation) {
                    selectedEffect = nil
                }
            }
        }
    }

    @ViewBuilder
    private var effectsContent: some View {
        GeometryReader { geo in
            // Match effectsHeader title inset so the focused card lines up with "Effects".
            let leadingPad: CGFloat = 16
            let trailingPad: CGFloat = 16
            let gap: CGFloat = 8
            let contentWidth = max(0, geo.size.width - leadingPad - trailingPad)
            let cardWidth = TLK.compactEffectCardWidth
            let trayWidth = max(0, contentWidth - cardWidth - gap)
            let isExpanded = selectedEffect?.isAdjustable == true && targetClipPath != nil
            let focusIndex = selectedEffect.flatMap { MixrEffect.allCases.firstIndex(of: $0) } ?? 0
            // Push: slide focused card under "Effects"; left cards exit left.
            // Adding the live scroll offset keeps the landing spot pinned to
            // the header inset even when the row is scrolled (Flanger/Blur).
            let rowOffset: CGFloat = isExpanded
                ? rowScrollOffset - CGFloat(focusIndex) * (cardWidth + gap)
                : 0

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: gap) {
                    ForEach(MixrEffect.allCases) { effect in
                        let isFocus = selectedEffect == effect
                        let isAway = isExpanded && !isFocus
                        let restingOpacity: Double =
                            effect.isAdjustable && !hasTarget ? 0.45 : 1

                        // Keep every card in-layout so open/close is a push, not a fade.
                        HStack(spacing: gap) {
                            Button {
                                handleCardTap(effect)
                            } label: {
                                TLCompactEffectCard(
                                    effect: effect,
                                    isSelected: isFocus
                                )
                                .frame(width: cardWidth, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .opacity(isAway ? 0 : restingOpacity)
                            .animation(
                                isAway ? siblingFadeOutAnimation : siblingFadeInAnimation,
                                value: isAway
                            )
                            .accessibilityValue(isFocus ? "Selected" : "Not selected")

                            // Only on the focused card — grows right and pushes trailing cards out.
                            if isFocus, effect.isAdjustable {
                                traySlot(
                                    effect: effect,
                                    width: isExpanded ? trayWidth : 0,
                                    visible: isExpanded
                                )
                            }
                        }
                        // Focused card + tray render above dissolving siblings.
                        .zIndex(isFocus ? 1 : 0)
                        .allowsHitTesting(!isExpanded || isFocus)
                    }
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, isExpanded ? trailingPad : 32)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .offset(x: rowOffset)
                .animation(expandAnimation, value: selectedEffect)
            }
            .onScrollGeometryChange(for: CGFloat.self, of: {
                $0.contentOffset.x + $0.contentInsets.leading
            }) { _, new in
                rowScrollOffset = new
            }
            .scrollDisabled(isExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .trailing) {
                if !isExpanded {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            MixrColors.backgroundSecondary.opacity(0.46),
                            MixrColors.backgroundSecondary.opacity(0.74),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 34)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: TLK.compactEffectCardHeight + 22)
    }

    @ViewBuilder
    private func traySlot(
        effect: MixrEffect,
        width: CGFloat,
        visible: Bool
    ) -> some View {
        let total = EffectTrayMetrics.expandAnimationDuration

        Group {
            if visible, let path = targetClipPath {
                effectTray(effect: effect, path: path)
            } else {
                Color.clear
            }
        }
        .frame(width: width, alignment: .center)
        .clipped()
        .opacity(visible ? 1 : 0)
        // Fade the tray in as siblings dissolve (never a flash over them);
        // on close it clears quickly before cards slide back.
        .transition(
            .asymmetric(
                insertion: .opacity.animation(
                    .easeInOut(duration: total * 0.5).delay(total * 0.22)
                ),
                removal: .opacity.animation(.easeOut(duration: total * 0.3))
            )
        )
        .allowsHitTesting(visible)
    }

    private func handleCardTap(_ effect: MixrEffect) {
        if effect == .auto {
            onAutoTapped()
            return
        }
        guard hasTarget else { return }
        withAnimation(expandAnimation) {
            selectedEffect = selectedEffect == effect ? nil : effect
        }
    }

    @ViewBuilder
    private func effectTray(effect: MixrEffect, path: (trackIdx: Int, clipIdx: Int)) -> some View {
        let clip = tracks[path.trackIdx].clips[path.clipIdx]
        EffectControlTray(
            effect: effect,
            level: clip.effects.level(for: effect.rawValue),
            reverbPreset: clip.effects.reverbPreset,
            echoPreset: clip.effects.echoPreset,
            pitchDirection: clip.effects.pitchDirection,
            onLevelChanged: { value in
                tracks[path.trackIdx].clips[path.clipIdx].effects
                    .setLevel(value, for: effect.rawValue)
            },
            onEditingChanged: { editing in
                // Capture at drag start; exactly one undo step at drag end.
                if editing {
                    onEditBegin("Change Effect", .clip(clip.id))
                } else {
                    onEditCommit()
                }
            },
            onReverbPreset: { preset in
                guard clip.effects.reverbPreset != preset else { return }
                onEditBegin("Change Effect", .clip(clip.id))
                tracks[path.trackIdx].clips[path.clipIdx].effects.reverbPreset = preset
                onEditCommit()
            },
            onEchoPreset: { preset in
                guard clip.effects.echoPreset != preset else { return }
                onEditBegin("Change Effect", .clip(clip.id))
                tracks[path.trackIdx].clips[path.clipIdx].effects.echoPreset = preset
                onEditCommit()
            },
            onPitchDirection: { direction in
                guard clip.effects.pitchDirection != direction else { return }
                onEditBegin("Change Effect", .clip(clip.id))
                tracks[path.trackIdx].clips[path.clipIdx].effects.pitchDirection = direction
                onEditCommit()
            }
        )
        .id("\(effect.rawValue)-\(clip.id.uuidString)")
    }

    private var effectsHeader: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isCollapsed = EditorEffectsInteraction.toggled(isCollapsed)
            }
        } label: {
            VStack(spacing: 0) {
                Capsule()
                    .fill(MixrColors.interactiveHandle)
                    .frame(width: 36, height: 4)
                    .padding(.top, 5)
                    .offset(y: 5)

                HStack {
                    Text("Effects")
                        .mixrScaledFont(
                            size: 13,
                            weight: .semibold,
                            relativeTo: .headline
                        )
                        .foregroundStyle(MixrColors.textPrimary)

                    Spacer()

                    if !isCollapsed && !hasTarget {
                        Text("Select a clip to shape its effects")
                            .mixrScaledFont(
                                size: EffectCardMetrics.titleFontSize,
                                weight: .semibold,
                                relativeTo: .subheadline
                            )
                            .foregroundStyle(MixrColors.textSecondary.opacity(0.87))
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 3)
                .padding(.bottom, isCollapsed ? 6 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand Effects" : "Collapse Effects")
    }

    private var effectsDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let resolved = EditorEffectsInteraction.collapsedState(
                    afterDrag: value.translation,
                    current: isCollapsed
                )
                guard resolved != isCollapsed else { return }

                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isCollapsed = resolved
                }
            }
    }
}

private struct TLCompactEffectCard: View {
    let effect: MixrEffect
    var isSelected: Bool

    var body: some View {
        EffectCard(effect: effect, isSelected: isSelected)
            .scaleEffect(TLK.compactEffectScale, anchor: .topLeading)
            .frame(
                width: TLK.compactEffectCardWidth,
                height: TLK.compactEffectCardHeight,
                alignment: .topLeading
            )
    }
}

// MARK: - Preview

#Preview("Timeline Screen — Landscape") {
    TimelineScreen()
        .frame(width: 932, height: 430)
        .modelContainer(for: MixrProjectRecord.self, inMemory: true)
}
