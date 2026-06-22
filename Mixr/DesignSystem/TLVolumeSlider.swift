import SwiftUI

/// Glass volume slider for timeline track rows.
struct TLVolumeSlider: View {
    @Binding var value: Double
    let accentColor: Color
    let trackColor: Color

    private let trackHeight: CGFloat = 2.5
    private let fillHeight: CGFloat = 5
    private let thumbWidth: CGFloat = 5
    private let thumbHeight: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let travel = max(width - thumbWidth, 1)
            let clamped = min(max(value, 0), 1)
            let thumbX = clamped * travel

            ZStack(alignment: .leading) {
                sliderTrack(width: width)
                    .frame(height: trackHeight, alignment: .center)

                fillBar(width: max(thumbX + thumbWidth * 0.5, thumbWidth * 0.4))
                    .frame(height: fillHeight, alignment: .center)

                sliderThumb
                    .offset(x: thumbX)
            }
            .frame(width: width, height: thumbHeight + 2, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x - thumbWidth * 0.5, 0), travel)
                        value = x / travel
                    }
            )
        }
        .frame(height: thumbHeight + 2)
    }

    private func sliderTrack(width: CGFloat) -> some View {
        let shape = Capsule(style: .continuous)

        return shape
            .fill(
                LinearGradient(
	                    colors: [
	                        Color.white.opacity(0.30),
	                        MixrColors.divider.opacity(0.68),
	                        Color.white.opacity(0.18),
	                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.11)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
	                        colors: [
	                            Color.white.opacity(0.14),
	                            Color.white.opacity(0.10),
	                            Color.black.opacity(0.16),
	                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
	                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.45)
            }
            .frame(width: width, height: trackHeight)
            .clipShape(shape)
    }

    private func fillBar(width: CGFloat) -> some View {
        let shape = Capsule(style: .continuous)
        let bright = accentColor

        return ZStack {
            // Song chip base — dense colored glass, not light.
            shape
                .fill(bright.opacity(0.76))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                bright.opacity(0.92),
                                bright.opacity(0.84),
                                trackColor.opacity(0.72),
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
                                bright.opacity(0.52),
                                trackColor.opacity(0.28),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.38, y: 0.38),
                            startRadius: 0,
	                            endRadius: max(fillHeight * 2.4, width * 0.38)
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.13),
                                Color.white.opacity(0.05),
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
                                Color.white.opacity(0.50),
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
                                Color.white.opacity(0.14),
                                bright.opacity(0.08),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.18, y: 0.14),
                            startRadius: 0,
	                            endRadius: fillHeight * 1.2
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }

            // Chip-style partial edge lighting.
            shape
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.4)
                .mask {
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.16),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.55, y: 0.55)
                    )
                }

            shape
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.35)
                .mask {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.62),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .compositingGroup()
        .opacity(0.9)
        .frame(width: width, height: fillHeight)
        .clipShape(shape)
    }

    private var sliderThumb: some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        let bright = accentColor

        return ZStack {
            // Song chip color grading — peak-forward, luminous body.
            shape
                .fill(bright.opacity(0.80))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                bright.opacity(0.96),
                                bright.opacity(0.88),
                                trackColor.opacity(0.76),
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
                                trackColor.opacity(0.32),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.42, y: 0.32),
                            startRadius: 0,
                            endRadius: thumbHeight * 0.52
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
                            endRadius: thumbHeight * 0.42
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

            // Premium glass edge lighting — subtle, not plastic.
            shape
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.45)
                .mask {
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.20),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.55, y: 0.65)
                    )
                }

            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            bright.opacity(0.38),
                            trackColor.opacity(0.24),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .shadow(color: bright.opacity(0.22), radius: 3.5, x: 0, y: 0)
        .shadow(color: trackColor.opacity(0.10), radius: 6, x: 0, y: 0)
        .shadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
    }
}

#Preview("TLVolumeSlider") {
    struct PreviewHost: View {
        @State private var value = 0.72

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary)

                TLVolumeSlider(
                    value: $value,
                    accentColor: MixrWaveformColor.pink.peakColor,
                    trackColor: MixrWaveformColor.pink.color
                )
                .frame(width: 72)
            }
            .padding(20)
            .background(MixrColors.backgroundSecondary)
        }
    }

    return PreviewHost()
        .preferredColorScheme(.dark)
}
