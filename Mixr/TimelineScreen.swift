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
    static let effectsHeight: CGFloat     = 118
    static let playheadUnit: CGFloat      = 55
    static let timelineUnitWidth: CGFloat = 10
    static let totalUnits: CGFloat        = 130
    static let compactEffectScale: CGFloat         = 1.0
    static let compactEffectCardWidth: CGFloat     = 152
    static let compactEffectCardHeight: CGFloat    = 66
    static let markerUnits: [CGFloat]     = [0, 17, 33, 49, 65, 81, 97, 113, 129]
    static let minorGridStep: CGFloat     = 5
    static let importButtonHeight: CGFloat = 44

    static var minorGridUnits: [CGFloat] {
        stride(from: 0, through: Int(totalUnits), by: Int(minorGridStep)).map { CGFloat($0) }
    }

    static let majorGridUnits: Set<CGFloat> = Set(markerUnits)
}

// MARK: - Root

struct TimelineScreen: View {
    @StateObject private var library = TrackLibrary()
    @State private var showFilePicker = false

    var body: some View {
        GeometryReader { geo in
            let isPortrait    = geo.size.height > geo.size.width
            let effectsH      = min(TLK.effectsHeight, geo.size.height * 0.24)
            let timelineH     = max(0, geo.size.height - TLK.transportHeight - effectsH)

            ZStack {
                MixrColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    TLTransportBar()

                    TLTrackArea(
                        tracks: $library.tracks,
                        showFilePicker: $showFilePicker,
                        onReorder: { source, destination in
                            library.reorder(from: source, to: destination)
                        }
                    )
                    .frame(height: timelineH)

                    TLEffectsPanel()
                        .frame(height: effectsH)
                }
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
                    Button { } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MixrColors.textSecondary)
                    }
                    .frame(width: 28, height: 40)

                    Button { } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(MixrColors.primaryPurple))
                    .shadow(color: MixrColors.primaryPurple.opacity(0.50), radius: 10)

                    Button { } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MixrColors.textSecondary)
                    }
                    .frame(width: 28, height: 40)
                }

                HStack(spacing: 3) {
                    Text("1:24")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(MixrColors.textSecondary)
                    Text("3:45")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(MixrColors.textSecondary)
                }
                .frame(height: 40, alignment: .center)

                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 0) {
                        Text("124")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MixrColors.textPrimary)
                        Text("BPM")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MixrColors.textSecondary)
                            .kerning(0.5)
                    }
                    .frame(width: 30, height: 40)

                    VStack(spacing: 0) {
                        Text("Gm")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MixrColors.textPrimary)
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
    @Binding var showFilePicker: Bool
    let onReorder: (IndexSet, Int) -> Void

    @State private var draggingID: UUID?       = nil
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let laneViewportW = max(0, geo.size.width - TLK.sidebarWidth - TLK.smColumnWidth)
            let contentW      = max(laneViewportW, TLK.totalUnits * TLK.timelineUnitWidth)
            let rowsH         = CGFloat(tracks.count) * TLK.trackRowHeight
            let contentH      = max(geo.size.height - TLK.rulerHeight, rowsH)

            ZStack(alignment: .topLeading) {
                // Column background fills
                HStack(spacing: 0) {
                    MixrColors.backgroundSecondary.frame(width: TLK.sidebarWidth)
                    MixrColors.backgroundSecondary
                    MixrColors.backgroundSecondary.frame(width: TLK.smColumnWidth)
                }
                .frame(width: geo.size.width)

                // Single shared vertical scroll for all three columns
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        // LEFT: sidebar song rows
                        sidebarRows(contentH: contentH)

                        // CENTER: horizontal-scrolling timeline canvas
                        timelineCanvas(
                            contentW: contentW,
                            contentH: TLK.rulerHeight + contentH,
                            viewportW: laneViewportW
                        )

                        // RIGHT: S/M + volume controls
                        controlsRows(contentH: contentH)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Import Songs — always visible, pinned to sidebar bottom
                VStack(spacing: 0) {
                    Spacer()
                    importButton
                        .frame(width: TLK.sidebarWidth)
                        .background(
                            MixrColors.backgroundSecondary
                                .overlay(alignment: .top) {
                                    MixrColors.divider.frame(height: 0.5)
                                }
                        )
                }
                .frame(width: TLK.sidebarWidth, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // MARK: Sidebar rows

    @ViewBuilder
    private func sidebarRows(contentH: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Ruler height spacer — aligns song rows with timeline track lanes
            Color.clear
                .frame(height: TLK.rulerHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }

            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                TLSongRow(
                    track: track,
                    onDragChanged: { delta in
                        if draggingID == nil { draggingID = track.id }
                        dragTranslation = delta
                    },
                    onDragEnded: { delta in
                        commitReorder(fromID: track.id, translation: delta)
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

            // Padding so rows don't hide under the import button
            Color.clear.frame(height: TLK.importButtonHeight + 8)
        }
        .frame(width: TLK.sidebarWidth)
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .trailing) {
            MixrColors.divider.frame(width: 0.5)
        }
    }

    // MARK: Timeline canvas (horizontal scroll)

    @ViewBuilder
    private func timelineCanvas(contentW: CGFloat, contentH: CGFloat, viewportW: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                MixrColors.backgroundSecondary

                TLGridCanvas(width: contentW, height: contentH)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    TLRuler(width: contentW)
                        .frame(height: TLK.rulerHeight)

                    ForEach(tracks) { track in
                        TLTrackLane(track: track, timelineWidth: contentW)
                            .frame(height: TLK.trackRowHeight)
                            .offset(y: rowOffset(trackID: track.id))
                            .zIndex(draggingID == track.id ? 1 : 0)
                    }
                }

                TLPlayhead(timelineWidth: contentW, totalHeight: contentH)
                    .allowsHitTesting(false)
            }
            .frame(width: contentW, height: contentH)
        }
        .frame(maxWidth: .infinity)
        .frame(width: viewportW)
        .clipped()
    }

    // MARK: Controls rows

    @ViewBuilder
    private func controlsRows(contentH: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: TLK.rulerHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }

            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                TLTrackControlRow(
                    track: track,
                    volume: $tracks[idx].volume
                )
                .frame(height: TLK.trackRowHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
                .offset(y: rowOffset(trackID: track.id))
                .zIndex(draggingID == track.id ? 1 : 0)
            }

            Spacer()
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

    private var importButton: some View {
        Button {
            showFilePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Import Songs")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(MixrColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat) -> Void)?   = nil

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                TLSongRowGripper(
                    onDragChanged: onDragChanged,
                    onDragEnded:   onDragEnded
                )
                MixrSongColorChip(color: track.color)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 2) {
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
                HStack(spacing: 0) {
                    Text(track.artist)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(track.bpm) BPM")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: TLK.trackRowHeight)
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

                for unit in TLK.markerUnits {
                    let x = (unit / TLK.totalUnits) * width
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 7))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(tick, with: .color(MixrColors.divider.opacity(0.45)), lineWidth: 0.5)

                    let label = unit == 0 ? "0:00" : "\(Int(unit))"
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
            for unit in TLK.minorGridUnits where !TLK.majorGridUnits.contains(unit) {
                let x = (unit / TLK.totalUnits) * width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                ctx.stroke(path, with: .color(MixrColors.divider.opacity(0.55)), lineWidth: 0.65)
            }
            for unit in TLK.markerUnits {
                let x = (unit / TLK.totalUnits) * width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                ctx.stroke(path, with: .color(MixrColors.divider.opacity(0.8)), lineWidth: 0.9)
            }
        }
        .frame(width: width, height: height)
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

// MARK: - Playhead

private struct TLPlayhead: View {
    let timelineWidth: CGFloat
    let totalHeight: CGFloat

    private var xPos: CGFloat {
        (TLK.playheadUnit / TLK.totalUnits) * timelineWidth
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 1, height: totalHeight)
                .offset(x: xPos - 0.5)

            TLPlayheadHandle()
                .fill(Color.white)
                .frame(width: 14, height: 11)
                .offset(x: xPos - 7, y: TLK.rulerHeight - 11)
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

    var body: some View {
        HStack(spacing: 5) {
            Button("S") { }.buttonStyle(.mixrCompactTrackToggle)
            Button("M") { }.buttonStyle(.mixrCompactTrackToggle)

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
    @State private var selectedEffect: MixrEffect?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                MixrColors.divider.frame(height: 0.5)

                Capsule()
                    .fill(MixrColors.textSecondary.opacity(0.30))
                    .frame(width: 36, height: 4)
                    .padding(.top, 5)

                HStack {
                    Text("Effects")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 3)
                .padding(.bottom, 0)

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
            }
            .frame(maxWidth: .infinity)
            .background {
                GlassBackground(level: .strong, cornerRadius: 0)
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
