import SwiftUI

/// Glass volume slider for timeline track rows.
struct TLVolumeSlider: View {
    @Binding var value: Double
    let accentColor: Color
    let trackColor: Color

    private let trackHeight: CGFloat = 4
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

                fillBar(width: max(thumbX + thumbWidth * 0.5, thumbWidth * 0.4))

                sliderThumb
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
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
            .fill(MixrColors.glassNavyDefault.opacity(0.50))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.06)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.clear,
                            Color.black.opacity(0.22),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            }
            .overlay {
                shape.strokeBorder(trackColor.opacity(0.12), lineWidth: 0.7)
                    .blur(radius: 0.5)
            }
            .frame(width: width, height: trackHeight)
            .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
    }

    private func fillBar(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.50),
                        accentColor.opacity(0.78),
                        accentColor.opacity(0.62),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: width, height: trackHeight)
            .shadow(color: accentColor.opacity(0.14), radius: 2.5, x: 0, y: 0)
    }

    private var sliderThumb: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(MixrColors.glassNavyElevated.opacity(0.58))
            .background {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.10)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.82),
                                Color.white.opacity(0.38),
                                accentColor.opacity(0.16),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.55)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.18), lineWidth: 0.6)
            }
            .shadow(color: accentColor.opacity(0.12), radius: 3, x: 0, y: 0)
            .shadow(color: .black.opacity(0.36), radius: 2, x: 0, y: 1)
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
                    accentColor: MixrColors.waveformPink,
                    trackColor: MixrColors.waveformPink
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
