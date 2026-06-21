import SwiftUI

// MARK: - Screen Layout Constants

private enum TLK {
    static let sidebarWidth: CGFloat    = 185
    static let transportHeight: CGFloat = 50
    static let rulerHeight: CGFloat     = 20
    static let trackRowHeight: CGFloat  = 46
    static let waveformHeight: CGFloat  = 34
    static let smColumnWidth: CGFloat   = 54
    static let effectsHeight: CGFloat   = 98
    static let playheadUnit: CGFloat    = 55
    static let timelineUnitWidth: CGFloat = 10
    static let totalUnits: CGFloat      = 130
    static let compactEffectScale: CGFloat = 0.72
    static let compactEffectCardWidth: CGFloat = 110
    static let compactEffectCardHeight: CGFloat = 48
    static let markerUnits: [CGFloat]   = [0, 17, 33, 49, 65, 81, 97, 113, 129]
    static let minorGridStep: CGFloat   = 5

    static var minorGridUnits: [CGFloat] {
        stride(from: 0, through: Int(totalUnits), by: Int(minorGridStep)).map { CGFloat($0) }
    }

    static let majorGridUnits: Set<CGFloat> = Set(markerUnits)
}

// MARK: - Mock Data

private struct MockTrack: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let duration: String
    let bpm: Int
    let color: MixrWaveformColor
    let clips: [MockClip]
}

private struct MockClip: Identifiable {
    let id = UUID()
    let start: CGFloat   // timeline units  0 – totalUnits
    let length: CGFloat  // timeline units
}

private let mockTracks: [MockTrack] = [
    MockTrack(
        title: "Blinding Lights", artist: "The Weeknd",
        duration: "3:20", bpm: 124, color: .pink,
        clips: [
            MockClip(start: 0,   length: 57),
            MockClip(start: 113, length: 17),
        ]
    ),
    MockTrack(
        title: "Levitating", artist: "Dua Lipa",
        duration: "3:23", bpm: 124, color: .purple,
        clips: [MockClip(start: 17, length: 48)]
    ),
    MockTrack(
        title: "Good 4 U", artist: "Olivia Rodrigo",
        duration: "2:58", bpm: 124, color: .red,
        clips: [MockClip(start: 33, length: 48)]
    ),
    MockTrack(
        title: "Stay", artist: "The Kid LAROI",
        duration: "2:21", bpm: 124, color: .yellow,
        clips: [MockClip(start: 49, length: 48)]
    ),
    MockTrack(
        title: "Heat Waves", artist: "Glass Animals",
        duration: "3:28", bpm: 124, color: .blue,
        clips: [MockClip(start: 65, length: 65)]
    ),
]

// MARK: - Root

struct TimelineScreen: View {
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let effectsHeight = min(TLK.effectsHeight, geo.size.height * 0.24)
            let timelineHeight = max(0, geo.size.height - TLK.transportHeight - effectsHeight)

            ZStack {
                MixrColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    TLTransportBar()

                    HStack(spacing: 0) {
                        TLSongSidebar()
                            .frame(width: TLK.sidebarWidth, height: timelineHeight)

                        TLTimelineArea()
                            .frame(height: timelineHeight)
                    }
                    .frame(height: timelineHeight)

                    TLEffectsPanel()
                        .frame(height: effectsHeight)
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
    }
}

private struct TLRotateOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

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
        HStack(spacing: 0) {
            // Logo + project dropdown — tight left cluster
            HStack(spacing: 10) {
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

            Spacer(minLength: 12)

            // Playback + time + BPM/Key — shifted left to leave room for action buttons
            HStack(spacing: 18) {
                HStack(spacing: 22) {
                    Button { } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MixrColors.textSecondary)
                    }

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

                HStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Text("124")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MixrColors.textPrimary)
                        Text("BPM")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MixrColors.textSecondary)
                            .kerning(0.5)
                    }
                    VStack(spacing: 0) {
                        Text("Gm")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MixrColors.textPrimary)
                        Text("KEY")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MixrColors.textSecondary)
                            .kerning(0.5)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // Action buttons — wide enough for full labels
            HStack(spacing: 8) {
                Button { } label: {
                    Label("Mixer", systemImage: "slider.horizontal.3")
                        .frame(minWidth: 92)
                }
                .buttonStyle(MixrSecondaryGlassButtonStyle())

                Button { } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 96)
                }
                .buttonStyle(MixrSecondaryGlassButtonStyle())
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 14)
        }
        .frame(height: TLK.transportHeight)
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
        }
    }
}

// MARK: - Song Sidebar

private struct TLSongSidebar: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(mockTracks) { track in
                        TLSongRow(track: track)
                    }
                }
            }

            // Import Songs
            Button { } label: {
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
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .trailing) {
            MixrColors.divider.frame(width: 0.5)
        }
    }
}

private struct TLSongRow: View {
    let track: MockTrack

    var body: some View {
        HStack(spacing: 9) {
            // Colored album icon
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(track.color.color.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(track.color.color.opacity(0.36), lineWidth: 0.5)
                    }
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(track.color.color)
            }
            .frame(width: 34, height: 34)

            // Song info
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
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
        }
    }
}

// MARK: - Timeline Area

private struct TLTimelineArea: View {
    var body: some View {
        GeometryReader { geo in
            let timelineViewportW = max(0, geo.size.width - TLK.smColumnWidth)
            let timelineContentW = max(timelineViewportW, TLK.totalUnits * TLK.timelineUnitWidth)
            let timelineContentH = max(
                geo.size.height,
                TLK.rulerHeight + CGFloat(mockTracks.count) * TLK.trackRowHeight
            )

            HStack(spacing: 0) {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        MixrColors.backgroundSecondary

                        // Vertical beat grid (drawn behind clips)
                        TLGridCanvas(width: timelineContentW, height: timelineContentH)
                            .allowsHitTesting(false)

                        // Ruler + track rows stacked vertically
                        VStack(spacing: 0) {
                            TLRuler(width: timelineContentW)
                                .frame(height: TLK.rulerHeight)

                            ForEach(mockTracks) { track in
                                TLTrackLane(track: track, timelineWidth: timelineContentW)
                                    .frame(height: TLK.trackRowHeight)
                            }
                        }

                        // Playhead on top of everything
                        TLPlayhead(timelineWidth: timelineContentW, totalHeight: timelineContentH)
                            .allowsHitTesting(false)
                    }
                    .frame(width: timelineContentW, height: timelineContentH)
                }
                .frame(width: timelineViewportW, height: geo.size.height)
                .clipped()

                TLSMColumn()
                    .frame(width: TLK.smColumnWidth, height: geo.size.height)
            }
        }
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
                    let isMajor = TLK.majorGridUnits.contains(unit)

                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - (isMajor ? 7 : 4)))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(
                        tick,
                        with: .color(
                            MixrColors.divider.opacity(isMajor ? 0.40 : 0.22)
                        ),
                        lineWidth: 0.5
                    )
                }

                for unit in TLK.markerUnits {
                    let x = (unit / TLK.totalUnits) * width
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
            for unit in TLK.minorGridUnits {
                let x = (unit / TLK.totalUnits) * width
                let isMajor = TLK.majorGridUnits.contains(unit)

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                ctx.stroke(
                    path,
                    with: .color(
                        MixrColors.divider.opacity(isMajor ? 0.40 : 0.22)
                    ),
                    lineWidth: 0.5
                )
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Track Lane

private struct TLTrackLane: View {
    let track: MockTrack
    let timelineWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Very subtle track color tint
            track.color.color.opacity(0.025)

            // Clips
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
            // Vertical line
            Rectangle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 1, height: totalHeight)
                .offset(x: xPos - 0.5)

            // Downward-pointing handle in ruler
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

// MARK: - S / M Button Column

private struct TLSMColumn: View {
    var body: some View {
        VStack(spacing: 0) {
            // Blank space that lines up with the ruler
            Color.clear
                .frame(height: TLK.rulerHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }

            ForEach(mockTracks) { _ in
                HStack(spacing: 5) {
                    Button("S") { }.buttonStyle(MixrToggleButtonStyle())
                    Button("M") { }.buttonStyle(MixrToggleButtonStyle())
                }
                .frame(height: TLK.trackRowHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
            }

            Spacer()
        }
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .leading) {
            MixrColors.divider.frame(width: 0.5)
        }
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
                    .padding(.top, 4)

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
                        .padding(.trailing, 8)
                        .padding(.top, 7)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: TLK.compactEffectCardHeight + 20)
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
