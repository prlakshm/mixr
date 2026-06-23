import SwiftUI
import UniformTypeIdentifiers

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
    static let minorGridStep: CGFloat     = 5
    static let importFooterHeight: CGFloat = 46
    static let timelineDurationSeconds: CGFloat = 240
    static let rulerLabelStepSeconds: CGFloat = 30

    static var minorGridUnits: [CGFloat] {
        stride(from: 0, through: Int(totalUnits), by: Int(minorGridStep)).map { CGFloat($0) }
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
}

// MARK: - Root

struct TimelineScreen: View {
    @StateObject private var library = TrackLibrary()
    @StateObject private var playback = MixrPlaybackEngine()
    @State private var showFilePicker = false
    @State private var isEffectsCollapsed = false

    private var playheadUnit: CGFloat {
        MixrTimeline.units(fromSeconds: playback.currentTimeSeconds)
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
                    TLTransportBar(playback: playback, library: library)
                        .frame(height: TLK.transportHeight)

                    TLTrackArea(
                        tracks: $library.tracks,
                        selectedTrackID: library.selectedTrackID,
                        playheadUnit: playheadUnit,
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
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .clipped()

                    TLEffectsPanel(isCollapsed: $isEffectsCollapsed)
                        .frame(height: effectsH)
                        .clipped()
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
        .onChange(of: library.tracks.map { "\($0.id):\($0.clips.first?.length ?? 0)" }.joined()) { _, _ in
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
                    Text(MixrTimeline.formattedTime(playback.currentTimeSeconds))
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
                            .minimumScaleFactor(0.7)
                        Text("KEY")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MixrColors.textSecondary)
                            .kerning(0.5)
                    }
                    .frame(width: 30, height: 40)
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
    let playheadUnit: CGFloat
    @Binding var showFilePicker: Bool
    let onImportURLs: ([URL]) -> Void
    let onDeleteTrack: (UUID) -> Void
    let onReorder: (IndexSet, Int) -> Void
    let onSelectTrack: (UUID) -> Void
    let onMixSettingsChanged: () -> Void

    @State private var draggingID: UUID?       = nil
    @State private var dragTranslation: CGFloat = 0
    @State private var isTimelineDropTarget = false

    var body: some View {
        GeometryReader { geo in
            let laneViewportW = max(0, geo.size.width - TLK.sidebarWidth - TLK.smColumnWidth)
            let contentW      = max(laneViewportW, TLK.totalUnits * TLK.timelineUnitWidth)
            let rowsH         = CGFloat(tracks.count) * TLK.trackRowHeight
            let trackSectionH = tracks.isEmpty
                ? max(geo.size.height - TLK.rulerHeight, TLK.trackRowHeight)
                : rowsH

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    MixrColors.backgroundSecondary.frame(width: TLK.sidebarWidth)
                    MixrColors.backgroundSecondary
                    MixrColors.backgroundSecondary.frame(width: TLK.smColumnWidth)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        rulerRow(contentW: contentW, laneViewportW: laneViewportW)

                        HStack(alignment: .top, spacing: 0) {
                            sidebarTrackRows
                            timelineLanesCanvas(
                                contentW: contentW,
                                trackSectionH: trackSectionH,
                                viewportW: laneViewportW
                            )
                            controlsTrackRows
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)

                VStack(spacing: 0) {
                    Spacer()
                    importFooter
                        .frame(width: TLK.sidebarWidth)
                }
                .frame(width: TLK.sidebarWidth, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // MARK: Ruler row

    private func columnHeader(_ title: String, leadingInset: CGFloat) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingInset)
    }

    @ViewBuilder
    private func rulerRow(contentW: CGFloat, laneViewportW: CGFloat) -> some View {
        HStack(spacing: 0) {
            MixrColors.backgroundSecondary
                .frame(width: TLK.sidebarWidth, height: TLK.rulerHeight)
                .overlay {
                    columnHeader("Tracks", leadingInset: 10.5)
                }
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
                .overlay(alignment: .trailing) {
                    MixrColors.divider.frame(width: 0.5)
                }

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    TLRuler(width: contentW)
                        .frame(width: contentW, height: TLK.rulerHeight)

                    playheadHandle(in: contentW, playheadUnit: playheadUnit)
                }
                .frame(width: contentW, height: TLK.rulerHeight)
            }
            .frame(width: laneViewportW, height: TLK.rulerHeight)
            .background(MixrColors.background.opacity(0.80))

            MixrColors.backgroundSecondary
                .frame(width: TLK.smColumnWidth, height: TLK.rulerHeight)
                .overlay {
                    columnHeader("Controls", leadingInset: 10.5)
                }
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
                .overlay(alignment: .leading) {
                    MixrColors.divider.frame(width: 0.5)
                }
        }
        .frame(height: TLK.rulerHeight)
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

    // MARK: Timeline lanes (horizontal scroll)

    @ViewBuilder
    private func timelineLanesCanvas(contentW: CGFloat, trackSectionH: CGFloat, viewportW: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                TLTimelineSurface(isDropTarget: isTimelineDropTarget)
                    .frame(width: contentW, height: trackSectionH)

                TLGridCanvas(width: contentW, height: trackSectionH)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TLTrackLane(track: track, timelineWidth: contentW)
                            .frame(height: TLK.trackRowHeight)
                            .offset(y: rowOffset(trackID: track.id))
                            .zIndex(draggingID == track.id ? 1 : 0)
                    }
                }

                TLClipBoundaryCanvas(
                    tracks: tracks,
                    timelineWidth: contentW,
                    totalHeight: trackSectionH,
                    topInset: 0
                )
                .allowsHitTesting(false)

                TLPlayhead(
                    timelineWidth: contentW,
                    totalHeight: trackSectionH,
                    playheadUnit: playheadUnit,
                    showsHandle: false
                )
                .allowsHitTesting(false)

                if tracks.isEmpty {
                    TLEmptyTimelineState(isDropTarget: isTimelineDropTarget)
                        .frame(width: min(contentW, viewportW), height: trackSectionH)
                        .position(x: min(contentW, viewportW) / 2, y: trackSectionH / 2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: contentW, height: trackSectionH)
        }
        .frame(width: viewportW, height: trackSectionH)
        .background {
            TLTimelineSurface(isDropTarget: isTimelineDropTarget)
        }
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
        .clipped()
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

    private func playheadHandle(in timelineWidth: CGFloat, playheadUnit: CGFloat) -> some View {
        let xPos = (playheadUnit / TLK.totalUnits) * timelineWidth

        return TLPlayheadHandle()
            .fill(Color.white)
            .frame(width: TLK.playheadHandleWidth, height: TLK.playheadHandleHeight)
            .offset(x: xPos - TLK.playheadHandleWidth / 2, y: TLK.rulerHeight - TLK.playheadHandleHeight)
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
    @State private var swipeDragStartOffset: CGFloat?
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
                .gesture(swipeGesture)
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

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }

                if swipeDragStartOffset == nil {
                    swipeDragStartOffset = swipeOffset
                }

                let baseOffset = swipeDragStartOffset ?? 0
                let nextOffset = min(0, max(-deleteActionWidth, baseOffset + horizontal))

                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
                    swipeOffset = nextOffset
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                defer { swipeDragStartOffset = nil }
                guard abs(horizontal) > abs(vertical) else { return }

                let shouldReveal = swipeOffset < -revealThreshold || value.predictedEndTranslation.width < -deleteActionWidth
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    swipeOffset = shouldReveal ? -deleteActionWidth : 0
                }
            }
    }

    private func closeDeleteAction() {
        guard swipeOffset != 0 else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            swipeOffset = 0
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
                .onChanged { value in onDragChanged?(value.translation.height) }
                .onEnded   { value in onDragEnded?(value.translation.height)   }
        )
    }
}

// MARK: - Time Ruler

private struct TLRuler: View {
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            MixrColors.background.opacity(0.80)

            Canvas { ctx, size in
                for unit in TLK.minorGridUnits {
                    let x = (unit / TLK.totalUnits) * width
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 4))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(tick, with: .color(MixrColors.divider.opacity(0.25)), lineWidth: 0.5)
                }

                for seconds in TLK.rulerLabelSeconds {
                    let unit = TLK.timelineUnit(for: seconds)
                    let x = (unit / TLK.totalUnits) * width
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
                    let labelX = max(2, x + 3)
                    ctx.draw(resolved, at: CGPoint(x: labelX, y: 5), anchor: .topLeading)
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

    var body: some View {
        Canvas { ctx, _ in
            for unit in TLK.minorGridUnits {
                let x = (unit / TLK.totalUnits) * width
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

// MARK: - Track Lane

private struct TLTrackLane: View {
    let track: MixrTrack
    let timelineWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            track.color.color.opacity(0.025)

            ForEach(track.clips) { clip in
                let xOffset = (clip.start  / TLK.totalUnits) * timelineWidth
                let clipW   = max(0, (clip.length / TLK.totalUnits) * timelineWidth)

                WaveformClip(waveformColor: track.color)
                    .frame(height: TLK.waveformHeight)
                    .frame(width: clipW)
                    .offset(x: xOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
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

// MARK: - Playhead

private struct TLPlayhead: View {
    let timelineWidth: CGFloat
    let totalHeight: CGFloat
    var playheadUnit: CGFloat = 0
    var showsHandle: Bool = true

    private var xPos: CGFloat {
        (playheadUnit / TLK.totalUnits) * timelineWidth
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 1, height: totalHeight)
                .offset(x: xPos - 0.5)

            if showsHandle {
                TLPlayheadHandle()
                    .fill(Color.white)
                    .frame(width: TLK.playheadHandleWidth, height: TLK.playheadHandleHeight)
                    .offset(x: xPos - TLK.playheadHandleWidth / 2, y: TLK.rulerHeight - TLK.playheadHandleHeight)
            }
        }
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
                .padding(.top, 5)

            HStack {
                Text("Effects")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                Spacer()
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary)
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
