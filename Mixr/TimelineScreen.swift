import SwiftUI
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
    static let clipDragNeighborShift: CGFloat = 10       // pt shift each neighbor
    static let clipDragScrollZone:    CGFloat = 100      // px from viewport edge
    static let clipDragScrollSpeed:   CGFloat = 20       // max px per 60 fps frame
    static let clipDragShadowRadius:  CGFloat = 18
    static let clipDragShadowY:       CGFloat = 10
    static let clipDragScrimOpacity:  Double  = 0.52
    static let clipDragScrimAnim:     Double  = 0.13
    static let clipDragDropResponse:  Double  = 0.38
    static let clipDragDropDamping:   Double  = 0.80
    static let clipDragArmedSettleDuration: Double = 0.09
    static let clipInsertPreviewResponse: Double = 0.22
    static let clipInsertionSnapZone: CGFloat = 20
    static let clipInsertionSnapHysteresis: CGFloat = 8
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

    /// Raw proposed start in timeline units (before snap resolution).
    func proposedStart(contentUnits: CGFloat, contentW: CGFloat) -> CGFloat {
        guard contentW > 0 else { return 0 }
        return max(0, (proposedLeadingEdgePx / contentW) * contentUnits)
    }

    /// Pointer position in timeline units (insertion indicator follows resolved start).
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
            previousPointerUnit: lastPointerUnit
        )
        lastDropResult = result
        lastPointerUnit = pointer
        return result
    }

    func currentDropResult(contentUnits: CGFloat, contentW: CGFloat, clips: [MixrClip]) -> ClipDropResult {
        if let lastDropResult { return lastDropResult }
        var copy = self
        return copy.resolveDropResult(contentUnits: contentUnits, contentW: contentW, clips: clips)
    }

    func insertionStart(for result: ClipDropResult) -> CGFloat {
        MixrTimeline.insertionStart(for: result, movingClipLength: originalClip.length)
    }
}

// MARK: - Root

struct TimelineScreen: View {
    @StateObject private var library = TrackLibrary()
    @StateObject private var playback = MixrPlaybackEngine()
    @State private var showFilePicker = false
    @State private var isEffectsCollapsed = false

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
            let isPortrait    = geo.size.height > geo.size.width
            let effectsH = isEffectsCollapsed
                ? TLK.effectsCollapsedHeight
                : TLK.effectsExpandedHeight

            ZStack {
                MixrColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    TLTransportBar(
                        playback: playback,
                        library: library,
                        displayTimeSeconds: displayTimeSeconds
                    )
                    .frame(height: TLK.transportHeight)
                    .zIndex(1)

                    TLTrackArea(
                        tracks: $library.tracks,
                        selectedTrackID: library.selectedTrackID,
                        effectivePlayheadUnit: effectivePlayheadUnit,
                        maxPlayheadUnit: maxPlayheadUnit,
                        isPlayheadDragging: isPlayheadDragging,
                        bottomOverlayAllowance: effectsH,
                        showFilePicker: $showFilePicker,
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
                        onMixSettingsChanged: {
                            playback.applyMixSettings(from: library.tracks)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .zIndex(20)

                    TLEffectsPanel(isCollapsed: $isEffectsCollapsed)
                        .frame(height: effectsH)
                        .clipped()
                        .zIndex(0)
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isEffectsCollapsed)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                if isPortrait {
                    TLRotateOverlay()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            playback.syncTracks(library.tracks)
        }
        // Track list or clip geometry changed → full sync (may add/remove players)
        .onChange(of: library.tracks.map { track in
            track.clips.map { "\($0.start):\($0.length)" }.joined(separator: ",")
        }.joined(separator: "|")) { _, _ in
            playback.syncTracks(library.tracks)
        }
        // Only volume/mute changed → lightweight update, does NOT restart engine
        .onChange(of: library.tracks.map { "\($0.id):\($0.volume):\($0.isMuted)" }.joined()) { _, _ in
            playback.applyMixSettings(from: library.tracks)
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

// MARK: - Transport Bar

private struct TLTransportBar: View {
    @ObservedObject var playback: MixrPlaybackEngine
    @ObservedObject var library: TrackLibrary
    var displayTimeSeconds: Double = 0

    var body: some View {
        ZStack {
            HStack(spacing: 24) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MixrColors.primaryPurple)
                    Text("Mixr")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MixrColors.textPrimary)
                }
                HStack(spacing: 4) {
                    Text("My Remix")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary)
                }
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button { } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 74)
                }
                .buttonStyle(MixrSecondaryGlassButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 14)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        playback.skipToStart()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MixrColors.textSecondary)
                    }
                    .frame(width: 28, height: 40)

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: playback.isPlaying ? 0 : 1)
                    }
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(MixrColors.primaryPurple))
                    .shadow(color: MixrColors.primaryPurple.opacity(0.50), radius: 10)

                    Button {
                        playback.skipToEnd()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MixrColors.textSecondary)
                    }
                    .frame(width: 28, height: 40)
                }

                HStack(spacing: 3) {
                    Text(MixrTimeline.formattedTime(displayTimeSeconds))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(MixrColors.textSecondary)
                    Text(MixrTimeline.formattedTime(playback.totalDurationSeconds))
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(MixrColors.textSecondary)
                }
                .frame(height: 40, alignment: .center)

                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 0) {
                        Text(library.projectBPMDisplay)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MixrColors.textPrimary)
                        Text("BPM")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MixrColors.textSecondary)
                            .kerning(0.5)
                    }
                    .frame(width: 30, height: 40)

                    VStack(spacing: 0) {
                        Text(library.displayKey)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MixrColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("KEY")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MixrColors.textSecondary)
                            .kerning(0.5)
                    }
                    .frame(width: 56, height: 40)
                }
            }
            .offset(x: 60)
        }
        .frame(height: TLK.transportHeight)
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
        }
    }
}

// MARK: - Track Area (unified three-column scrollable layout)

private struct TLTrackArea: View {
    @Binding var tracks: [MixrTrack]
    let selectedTrackID: UUID?
    let effectivePlayheadUnit: CGFloat
    let maxPlayheadUnit: CGFloat
    let isPlayheadDragging: Bool
    let bottomOverlayAllowance: CGFloat
    @Binding var showFilePicker: Bool
    let onImportURLs: ([URL]) -> Void
    let onDeleteTrack: (UUID) -> Void
    let onReorder: (IndexSet, Int) -> Void
    let onSelectTrack: (UUID) -> Void
    let onMixSettingsChanged: () -> Void
    let onPlayheadDragStart: () -> Void
    let onPlayheadDragChanged: (CGFloat) -> Void
    let onPlayheadDragEnded: (CGFloat) -> Void
    let onTimelineTapped: (CGFloat) -> Void

    @State private var draggingID: UUID?        = nil
    @State private var dragTranslation: CGFloat = 0
    @State private var isTimelineDropTarget     = false

    // Clip editing state
    @State private var selectedClipID:   UUID?       = nil
    @State private var clipTapAnchorX:   CGFloat?    = nil
    @State private var activeGrip:       ActiveGrip? = nil
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
        let leftLen  = splitAt - f.clip.start
        let rightLen = f.clip.length - leftLen
        let newID    = UUID()
        tracks[f.trackIdx].clips[f.clipIdx].length = leftLen
        tracks[f.trackIdx].clips[f.clipIdx].transitionOut = .none
        tracks[f.trackIdx].clips.insert(
            MixrClip(id: newID, start: splitAt, length: rightLen),
            at: f.clipIdx + 1
        )
        let contentUnits = MixrTimeline.contentUnits(for: tracks)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedClipID  = newID
            activeGrip      = nil
            clipTapAnchorX  = splitAt / contentUnits * currentContentW
        }
    }

    private func duplicateClip(id: UUID) {
        guard let f = findClip(id) else { return }
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
            MixrClip(id: newID, start: newStart, length: newLen),
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
            clipTapAnchorX = newStart / contentUnits * currentContentW
        }
    }

    private func deleteClip(id: UUID) {
        guard let f = findClip(id) else { return }
        if f.track.clips.count <= 1 {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedClipID = nil
                activeGrip     = nil
                clipTapAnchorX = nil
            }
            onDeleteTrack(f.track.id)
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            tracks[f.trackIdx].clips.remove(at: f.clipIdx)
            selectedClipID = nil
            activeGrip     = nil
            clipTapAnchorX = nil
        }
    }

    private func setTransition(type: ClipTransitionType, grip: ActiveGrip) {
        guard let f = findClip(grip.clipID) else { return }
        var tx = ClipTransition()
        tx.type = type
        if grip.side == .leading {
            tracks[f.trackIdx].clips[f.clipIdx].transitionIn  = tx
        } else {
            tracks[f.trackIdx].clips[f.clipIdx].transitionOut = tx
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            activeGrip = nil
        }
    }

    // MARK: - Clip drag-move

    private var clipDragSettleComplete: Bool {
        guard let armedAt = clipDragArmedAt else { return clipDragState != nil }
        return Date().timeIntervalSince(armedAt) >= TLK.clipDragArmedSettleDuration
    }

    /// Long-press began — lift clip in place, show scrim, wait for settle before tracking movement.
    private func armClipDrag(clipID: UUID, areaX: CGFloat, areaY: CGFloat) {
        guard clipDragState == nil, clipDragArmed == nil, findClip(clipID) != nil else { return }
        clipDragArmed = clipID
        clipDragArmedAt = Date()
        clipDragArmedAreaX = areaX
        clipDragArmedAreaY = areaY
        withAnimation(.easeOut(duration: TLK.clipDragScrimAnim)) {
            isDraggingClip = true
            activeGrip = nil
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
        let grabScreenPx = startAreaX - TLK.sidebarWidth - xOffset + hScrollOffset
        let clipTopAreaY = TLK.rulerHeight
            + CGFloat(f.trackIdx) * TLK.trackRowHeight
            + (TLK.trackRowHeight - TLK.waveformHeight) / 2
            - vScrollOffset
        let grabScreenPy = startAreaY - clipTopAreaY
        let initialLeadingEdgePx = cursorAreaX - TLK.sidebarWidth + hScrollOffset - grabScreenPx

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
            proposedLeadingEdgePx: initialLeadingEdgePx
        )
        beginDragScrollLoop()
    }

    /// Updates cursor position and recomputes proposed drop location + insert preview progress.
    private func updateClipDrag(cursorAreaX: CGFloat, cursorAreaY: CGFloat) {
        guard var drag = clipDragState else { return }
        drag.cursorAreaX = cursorAreaX
        drag.cursorAreaY = cursorAreaY
        drag.proposedLeadingEdgePx =
            cursorAreaX - TLK.sidebarWidth + drag.scrollX - drag.grabScreenPx

        guard let ti = tracks.firstIndex(where: { $0.id == drag.trackID }) else { return }
        let result = drag.resolveDropResult(
            contentUnits: currentContentUnits,
            contentW: currentContentW,
            clips: tracks[ti].clips
        )

        let targetProgress: CGFloat
        if case .insertIntoClip = result {
            targetProgress = 1
        } else {
            targetProgress = 0
        }

        if drag.insertPreviewProgress != targetProgress {
            withAnimation(.spring(response: TLK.clipInsertPreviewResponse, dampingFraction: 0.82)) {
                drag.insertPreviewProgress = targetProgress
                clipDragState = drag
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
                let rightEdge = TLK.sidebarWidth + currentLaneVW - TLK.clipDragScrollZone
                let leftEdge  = TLK.sidebarWidth + TLK.clipDragScrollZone
                var delta: CGFloat = 0
                if drag.cursorAreaX > rightEdge {
                    // Quadratic acceleration: gentle near the edge, fast deep inside
                    let t = min((drag.cursorAreaX - rightEdge) / TLK.clipDragScrollZone, 1.0)
                    delta =  TLK.clipDragScrollSpeed * t * t
                } else if drag.cursorAreaX < leftEdge {
                    let t = min((leftEdge - drag.cursorAreaX) / TLK.clipDragScrollZone, 1.0)
                    delta = -TLK.clipDragScrollSpeed * t * t
                }
                if delta != 0 {
                    let movingClipW = currentContentUnits > 0
                        ? (drag.originalClip.length / currentContentUnits) * currentContentW
                        : 0
                    let desiredContentW = max(
                        currentContentW,
                        drag.proposedLeadingEdgePx + movingClipW + currentLaneVW * 0.35
                    )
                    let maxOff = max(0, desiredContentW - currentLaneVW)
                    let newScrollX = max(0, min(drag.scrollX + delta, maxOff))
                    clipDragState?.scrollX = newScrollX
                    clipDragState?.proposedLeadingEdgePx =
                        drag.cursorAreaX - TLK.sidebarWidth + newScrollX - drag.grabScreenPx
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

        let result = currentDropResult(for: drag, clips: tracks[ti].clips)
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
    }

    private func cancelClipDrag() {
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
                    x: drag.cursorAreaX - clipW / 2,
                    y: drag.cursorAreaY - TLK.waveformHeight / 2
                )
                .allowsHitTesting(false)
        } else if let armedID = clipDragArmed,
                  let f = findClip(armedID) {
            let clipW = max(1, (f.clip.length / contentUnits) * contentW)
            WaveformClip(waveformColor: f.track.color)
                .frame(height: TLK.waveformHeight)
                .frame(width: clipW)
                .shadow(color: .black.opacity(0.55), radius: TLK.clipDragShadowRadius, x: 0, y: TLK.clipDragShadowY)
                .shadow(color: f.track.color.color.opacity(0.44), radius: 14)
                .scaleEffect(TLK.clipDragLiftScale)
                .offset(
                    x: clipDragArmedAreaX - clipW / 2,
                    y: clipDragArmedAreaY - TLK.waveformHeight / 2
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func clipDragInsertionIndicator() -> some View {
        if let drag = clipDragState,
           let track = tracks.first(where: { $0.id == drag.trackID }) {
            let result = currentDropResult(for: drag, clips: track.clips)
            let insertStart = drag.insertionStart(for: result)
            let screenX = TLK.sidebarWidth
                + (insertStart / currentContentUnits) * currentContentW
                - drag.scrollX
            let trackTopY = TLK.rulerHeight
                + CGFloat(drag.trackIdx) * TLK.trackRowHeight
                - vScrollOffset

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(track.color.color.opacity(0.85))
                .frame(width: 2, height: TLK.trackRowHeight)
                .shadow(color: track.color.color.opacity(0.60), radius: 6)
                .offset(x: screenX - 1, y: trackTopY)
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: screenX)
                .allowsHitTesting(false)
        } else if let armedID = clipDragArmed,
                  let f = findClip(armedID) {
            let screenX = TLK.sidebarWidth
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
            let laneVW   = max(0, geo.size.width - TLK.sidebarWidth - TLK.smColumnWidth)
            let baseContentUnits = MixrTimeline.contentUnits(for: tracks)
            let baseContentW = max(laneVW, baseContentUnits * TLK.timelineUnitWidth)
            let dragContentUnits = clipDragState.map { drag in
                let trackClips = tracks.first(where: { $0.id == drag.trackID })?.clips ?? []
                let result = currentDropResult(for: drag, clips: trackClips)
                let insertStart = drag.insertionStart(for: result)
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
                    MixrColors.backgroundSecondary.frame(width: TLK.sidebarWidth)
                    MixrColors.backgroundSecondary
                    MixrColors.backgroundSecondary.frame(width: TLK.smColumnWidth)
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
                        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, new in
                            hScrollOffset = new
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
                .frame(width: geo.size.width, height: geo.size.height)

                // Floating clip-editing overlays — outside all scroll views, above sidebar/controls
                clipEditingFloatingOverlay(
                    sidebarW: TLK.sidebarWidth,
                    contentW: currentContentW,
                    contentUnits: currentContentUnits,
                    laneVW:   laneVW,
                    viewportH: geo.size.height + bottomOverlayAllowance,
                    hScrollOffset: hScrollOffset,
                    vScrollOffset: vScrollOffset
                )
                .zIndex(300)

                floatingPlayheadHandle(
                    sidebarW: TLK.sidebarWidth,
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
                    importFooter.frame(width: TLK.sidebarWidth)
                }
                .frame(width: TLK.sidebarWidth, height: geo.size.height)
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
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(MixrColors.textSecondary.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingInset)
    }

    private func sidebarColumn() -> some View {
        VStack(spacing: 0) {
            // Label — matches ruler height
            MixrColors.backgroundSecondary
                .frame(width: TLK.sidebarWidth, height: TLK.rulerHeight)
                .overlay { columnHeader("Tracks", leadingInset: 10.5) }
                .overlay(alignment: .bottom) { MixrColors.divider.frame(height: 0.5) }
                .overlay(alignment: .trailing) { MixrColors.divider.frame(width: 0.5) }

            sidebarTrackRows
        }
        .frame(width: TLK.sidebarWidth)
    }

    private func controlsColumn() -> some View {
        VStack(spacing: 0) {
            // Label — matches ruler height
            MixrColors.backgroundSecondary
                .frame(width: TLK.smColumnWidth, height: TLK.rulerHeight)
                .overlay { columnHeader("Controls", leadingInset: 10.5) }
                .overlay(alignment: .bottom) { MixrColors.divider.frame(height: 0.5) }
                .overlay(alignment: .leading) { MixrColors.divider.frame(width: 0.5) }

            controlsTrackRows
        }
        .frame(width: TLK.smColumnWidth)
    }

    // MARK: Sidebar track rows

    private var sidebarTrackRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { _, track in
                TLSongRow(
                    track: track,
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

            Color.clear.frame(height: TLK.importFooterHeight)
        }
        .frame(width: TLK.sidebarWidth)
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
                        onClipTapped:   { clipID, tapX in
                            guard !isDraggingClip else { return }
                            let unit = (tapX / contentW) * contentUnits
                            onTimelineTapped(max(0, min(unit, maxPlayheadUnit)))
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedClipID = clipID
                                activeGrip     = nil
                                clipTapAnchorX = tapX
                            }
                        },
                        onGripTapped:   { grip in
                            guard !isDraggingClip else { return }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                activeGrip = grip
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
                TLEmptyTimelineState(isDropTarget: isTimelineDropTarget)
                    .frame(width: min(contentW, viewportW), height: lanesH)
                    .position(x: min(contentW, viewportW) / 2, y: lanesH / 2)
                    .allowsHitTesting(false)
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
            let tbW    = TLClipEditingMetrics.toolbarWidth
            let tbH    = TLClipEditingMetrics.toolbarBodyHeight + TLClipEditingMetrics.toolbarPointerH
            let playheadContentX = (effectivePlayheadUnit / contentUnits) * contentW
            let tbSX   = screenXFor(playheadContentX)
            let trackTopY = TLK.rulerHeight + CGFloat(f.trackIdx) * TLK.trackRowHeight - vScrollOffset
            let tbTopY    = trackTopY + TLK.trackRowHeight * 0.03 - tbH * 0.5 - 6
            TLClipContextToolbar(
                trackColor: f.track.color.color,
                onSplit:     { splitClip(id: cid) },
                onDuplicate: { duplicateClip(id: cid) },
                onDelete:    { deleteClip(id: cid) }
            )
            .frame(width: tbW)
            .offset(x: tbSX - tbW / 2, y: tbTopY)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.90, anchor: .bottom)),
                removal:   .opacity.combined(with: .scale(scale: 0.90, anchor: .bottom))
            ))
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedClipID)
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
                ? f.clip.transitionIn.type
                : f.clip.transitionOut.type
            TLTransitionMenu(
                selected:   curTx,
                trackColor: f.track.color.color,
                onSelect:   { setTransition(type: $0, grip: grip) }
            )
            .frame(width: mW)
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
                    volume: $tracks[idx].volume,
                    isMuted: $tracks[idx].isMuted,
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
        .frame(width: TLK.smColumnWidth)
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
        .frame(height: TLK.importFooterHeight)
        .frame(maxWidth: .infinity)
        .background(
            MixrColors.backgroundSecondary
                .overlay(alignment: .top) {
                    MixrColors.divider.frame(height: 0.5)
                }
        )
    }

    private var importButton: some View {
        Button {
            showFilePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Import Songs")
                    .mixrFont(.button)
            }
            .foregroundStyle(MixrColors.textMuted.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MixrLayout.buttonPaddingH)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
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
                .background(MixrColors.backgroundSecondary)
                .offset(x: isDeleting ? -TLK.sidebarWidth : swipeOffset)
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

            MixrSongColorChip(color: track.color, artworkData: track.artworkData)

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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(track.duration)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(MixrColors.textSecondary)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 0) {
            Text(track.artist)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(MixrColors.textSecondary)
                .lineLimit(1)
            Spacer()
            Text("\(track.bpmDisplay) BPM")
                .font(.system(size: 10, weight: .regular))
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
                    .font(.system(size: 10, weight: .semibold))
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
            swipeOffset = -TLK.sidebarWidth
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

    var body: some View {
        VStack(spacing: 6) {
            Text(isDropTarget ? "Drop audio files to import" : "Import songs to start a remix")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary.opacity(isDropTarget ? 0.86 : 0.68))

            if !isDropTarget {
                Text("Drag audio files here or use Import Songs")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(MixrColors.textSecondary.opacity(0.46))
            }
        }
        .multilineTextAlignment(.center)
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
        var copy = drag
        let result = copy.currentDropResult(
            contentUnits: contentUnits,
            contentW: timelineWidth,
            clips: track.clips
        )
        return MixrTimeline.resolveClipRenderFrames(
            moving: drag.clipID,
            dropResult: result,
            insertPreviewProgress: drag.insertPreviewProgress,
            in: track.clips,
            neighborShiftPx: TLK.clipDragNeighborShift
        )
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
            track.color.color.opacity(0.025)
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

                if !isDraggingThis && !isArmedThis {
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(track.color.color.opacity(0.88), lineWidth: 8.2)
                            .blur(radius: 5.6)
                            .opacity(0.7)
                            .padding(-3.0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(track.color.color.opacity(0.38), lineWidth: 8.5)
                            .blur(radius: 3.2)
                            .opacity(0.82)
                            .padding(1.0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(track.color.color.opacity(1.0), lineWidth: 2.4)
                            .shadow(color: track.color.color.opacity(0.88), radius: 7)
                            .shadow(color: track.color.color.opacity(0.5), radius: 15)
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
    @Binding var volume: Double
    @Binding var isMuted: Bool
    var onMixSettingsChanged: () -> Void = {}

    var body: some View {
        HStack(spacing: 5) {
            Button("S") { }.buttonStyle(.mixrCompactTrackToggle)
            Button("M") {
                isMuted.toggle()
                onMixSettingsChanged()
            }
            .buttonStyle(.mixrCompactTrackToggle)
                .opacity(isMuted ? 1 : 0.92)
                .overlay {
                    if isMuted {
                        Circle()
                            .strokeBorder(MixrColors.primaryPurple.opacity(0.55), lineWidth: 0.75)
                            .frame(width: TLK.trackToggleSize, height: TLK.trackToggleSize)
                    }
                }

            HStack(spacing: 4) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary.opacity(0.85))
                    .frame(width: 11)

                TLVolumeSlider(
                    value: $volume,
                    accentColor: track.color.peakColor,
                    trackColor:  track.color.color
                )
                .frame(maxWidth: .infinity)
                .onChange(of: volume) { _, _ in
                    onMixSettingsChanged()
                }
            }
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var volumeIcon: String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.34  { return "speaker.wave.1.fill" }
        if volume < 0.67  { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Effects Panel

private struct TLEffectsPanel: View {
    @Binding var isCollapsed: Bool
    @State private var selectedEffect: MixrEffect?

    var body: some View {
        VStack(spacing: 0) {
            MixrColors.divider.frame(height: 0.5)

            effectsHeader

            if !isCollapsed {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MixrEffect.allCases) { effect in
                                TLCompactEffectCard(
                                    effect: effect,
                                    isSelected: selectedEffect == effect
                                )
                                .onTapGesture {
                                    selectedEffect = selectedEffect == effect ? nil : effect
                                }
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 32)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: TLK.compactEffectCardHeight + 22)
                    .overlay(alignment: .trailing) {
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
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                MixrColors.backgroundSecondary
                GlassBackground(level: .strong, cornerRadius: 0)
            }
        }
        .overlay(alignment: .top) {
            MixrColors.backgroundSecondary.frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(effectsDragGesture)
    }

    private var effectsHeader: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(MixrColors.textSecondary.opacity(0.30))
                .frame(width: 36, height: 4)
                .padding(.top, 4)
                .offset(y: 5)

            HStack {
                Text("Effects")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 3)
            .padding(.bottom, isCollapsed ? 6 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isCollapsed.toggle()
            }
        }
    }

    private var effectsDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let vertical = value.translation.height
                guard abs(vertical) > abs(value.translation.width) else { return }

                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    if vertical > 24 {
                        isCollapsed = true
                    } else if vertical < -24 {
                        isCollapsed = false
                    }
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
}
