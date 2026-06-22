import SwiftUI

// MARK: - Screen Layout Constants

private enum TLK {
    static let sidebarWidth: CGFloat    = 208
    static let transportHeight: CGFloat = 50
    static let rulerHeight: CGFloat     = 20
    static let trackRowHeight: CGFloat  = 46
    static let waveformHeight: CGFloat  = 34
    static let smColumnWidth: CGFloat   = 130
    static let trackToggleSize: CGFloat = 28
    static let effectsHeight: CGFloat   = 118
    static let playheadUnit: CGFloat    = 55
    static let timelineUnitWidth: CGFloat = 10
    static let totalUnits: CGFloat      = 130
    static let compactEffectScale: CGFloat = 1.0
    static let compactEffectCardWidth: CGFloat = 152
    static let compactEffectCardHeight: CGFloat = 66
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
            HStack(spacing: 0) {
                TLSongRowGripper()
                TLSongColorChip(color: track.color)
                    .padding(.leading, 4)
            }

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

private struct TLSongRowGripper: View {
    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(MixrColors.textSecondary.opacity(0.62))
                    .frame(width: 2.4, height: 2.4)
            }
        }
        .frame(width: 8, height: 34)
    }
}

private struct TLSongColorChip: View {
    let color: MixrWaveformColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let bright = color.peakColor

        ZStack {
            shape
                .fill(bright.opacity(0.80))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                bright.opacity(0.96),
                                bright.opacity(0.88),
                                color.color.opacity(0.76),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [
                                bright.opacity(0.68),
                                color.color.opacity(0.32),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.42, y: 0.38),
                            startRadius: 0,
                            endRadius: 22
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.06),
                                Color.clear,
                                Color.clear,
                            ],
                            startPoint: UnitPoint(x: 0.02, y: 0.0),
                            endPoint: UnitPoint(x: 0.58, y: 0.48)
                        )
                    )
                    .mask {
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.55),
                                Color.clear,
                            ],
                            startPoint: UnitPoint(x: 0.08, y: 0.0),
                            endPoint: UnitPoint(x: 0.62, y: 0.52)
                        )
                    }
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                bright.opacity(0.10),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.18, y: 0.14),
                            startRadius: 0,
                            endRadius: 10
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay(alignment: .topLeading) {
                    shape
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.18),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: UnitPoint(x: 0.55, y: 0.55)
                            )
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    shape
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.45)
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.65),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            bright.opacity(0.50),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .blur(radius: 1.5)

            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(color: bright.opacity(0.60), radius: 3)
                .shadow(color: .black.opacity(0.18), radius: 0.5, x: 0, y: 0.5)
        }
        .frame(width: 34, height: 34)
        .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 1.5)
        .shadow(color: color.color.opacity(0.28), radius: 5, x: 0, y: 0)
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

                        // Vertical beat grid — behind tracks and waveforms
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

                TLTrackControlsColumn()
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

                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 4))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(
                        tick,
                        with: .color(MixrColors.divider.opacity(0.25)),
                        lineWidth: 0.5
                    )
                }

                for unit in TLK.markerUnits {
                    let x = (unit / TLK.totalUnits) * width

                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 7))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(
                        tick,
                        with: .color(MixrColors.divider.opacity(0.45)),
                        lineWidth: 0.5
                    )

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
            // Minor 5-second lines
            for unit in TLK.minorGridUnits where !TLK.majorGridUnits.contains(unit) {
                let x = (unit / TLK.totalUnits) * width

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                ctx.stroke(
                    path,
                    with: .color(MixrColors.divider.opacity(0.55)),
                    lineWidth: 0.65
                )
            }

            // Major labeled lines
            for unit in TLK.markerUnits {
                let x = (unit / TLK.totalUnits) * width

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                ctx.stroke(
                    path,
                    with: .color(MixrColors.divider.opacity(0.8)),
                    lineWidth: 0.9
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

// MARK: - Track Controls Column

private struct TLTrackToggleButtonStyle: ButtonStyle {
    private let size = TLK.trackToggleSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.caption)
            .foregroundStyle(MixrColors.textPrimary.opacity(0.92))
            .frame(width: size, height: size)
            .background {
                GlassBackground(level: .default, cornerRadius: size / 2)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 1.5)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct TLTrackControlsColumn: View {
    @State private var volumes: [UUID: Double] = [
        mockTracks[0].id: 0.82,
        mockTracks[1].id: 0.74,
        mockTracks[2].id: 0.68,
        mockTracks[3].id: 0.91,
        mockTracks[4].id: 0.77,
    ]

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: TLK.rulerHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }

            ForEach(mockTracks) { track in
                TLTrackControlRow(
                    track: track,
                    volume: Binding(
                        get: { volumes[track.id] ?? 0.75 },
                        set: { volumes[track.id] = $0 }
                    )
                )
                .frame(height: TLK.trackRowHeight)
                .overlay(alignment: .bottom) {
                    MixrColors.divider.frame(height: 0.5)
                }
            }

            Spacer()
        }
        .padding(.leading, 7.5)
        .padding(.trailing, 8)
        .background(MixrColors.backgroundSecondary)
        .overlay(alignment: .leading) {
            MixrColors.divider.frame(width: 0.5)
        }
    }
}

private struct TLTrackControlRow: View {
    let track: MockTrack
    @Binding var volume: Double

    var body: some View {
        HStack(spacing: 5) {
            Button("S") { }
                .buttonStyle(TLTrackToggleButtonStyle())

            Button("M") { }
                .buttonStyle(TLTrackToggleButtonStyle())

            HStack(spacing: 4) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary.opacity(0.85))
                    .frame(width: 11)

                TLVolumeSlider(
                    value: $volume,
                    accentColor: track.color.peakColor,
                    trackColor: track.color.color
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var volumeIcon: String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
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
