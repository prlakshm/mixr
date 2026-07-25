import SwiftUI

/// Track-row surface with an inset purple-to-navy SFX liquid-glass card.
/// Same color stops as before; optics match effects-card glass (clear depth,
/// specular rim, edge energy — not frosted fill).
struct MixrTrackRowBackground: View {
    let isSFXTrack: Bool

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(MixrColors.backgroundSecondary)

            cardShape
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(
                                color: Color(hex: "241A39").opacity(0.48),
                                location: 0
                            ),
                            .init(
                                color: Color(hex: "090B13").opacity(0.56),
                                location: 0.5325
                            ),
                            .init(
                                color: Color(hex: "162239").opacity(0.50),
                                location: 1
                            ),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .background {
                    cardShape
                        .fill(.ultraThinMaterial)
                        .opacity(0.035)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    cardShape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.07),
                                Color.white.opacity(0.015),
                                Color.black.opacity(0.16),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    cardShape.fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.045),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.12, y: 0.08),
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
                }
                .overlay {
                    cardShape.fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "A281BC").opacity(0.08),
                                Color.clear,
                                Color(hex: "765A92").opacity(0.07),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay { glassRim }
                .partyModeBorder(
                    shape: cardShape,
                    role: .sfxSurface,
                    lighting: .counterClockwise,
                    glintOffset: .far
                )
                .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 1.5)
                .opacity(isSFXTrack ? 1 : 0)
                .padding(.leading, 19.5)
                .padding(.trailing, 5)
                .padding(.vertical, 2)
        }
    }

    private var glassRim: some View {
        // 50% more subtle than the prior liquid-glass rim (×0.50).
        let rim = 0.50
        return ZStack {
            cardShape.strokeBorder(Color.white.opacity(0.07 * rim), lineWidth: 0.5)

            cardShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color(hex: "A281BC").opacity(0.38 * rim),
                        Color.white.opacity(0.08 * rim),
                        Color(hex: "765A92").opacity(0.30 * rim),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.6
            )

            cardShape
                .strokeBorder(Color.white.opacity(0.36 * rim), lineWidth: 0.6)
                .mask {
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.4),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.7, y: 0.55)
                    )
                }

            cardShape
                .strokeBorder(Color.black.opacity(0.28 * rim), lineWidth: 0.5)
                .mask {
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.9)],
                        startPoint: UnitPoint(x: 0.35, y: 0.3),
                        endPoint: .bottomTrailing
                    )
                }
        }
        .allowsHitTesting(false)
    }
}
