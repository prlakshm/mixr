import SwiftUI

struct PartyModePlayButtonSurface: View {
    @Environment(\.partyModeRenderState) private var renderState

    var body: some View {
        Circle()
            .fill(MixrColors.primaryPurple)
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "A389FF").opacity(0.66),
                                Color(hex: "6940EB").opacity(0.98),
                                Color(hex: "351181").opacity(0.99),
                            ],
                            center: UnitPoint(x: 0.42, y: 0.34),
                            startRadius: 0,
                            endRadius: 24
                        )
                    )
                    .opacity(renderState.chromeOpacity)
            }
    }
}

private struct PartyModePlayButtonModifier: ViewModifier {
    @Environment(\.partyModeRenderState) private var renderState

    func body(content: Content) -> some View {
        content
            .overlay {
                if renderState.chromeOpacity > 0.001 {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        PartyModeTokens.glintWhite.opacity(0.90),
                                        PartyModeTokens.lavender,
                                        PartyModeTokens.violet,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.35
                            )
                            .padding(0.45)
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        PartyModeTokens.lavender.opacity(0.58),
                                        PartyModeTokens.violet.opacity(0.78),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.58
                            )
                            .padding(3.6)
                    }
                    .opacity(renderState.chromeOpacity)
                    .allowsHitTesting(false)
                }
            }
            .shadow(
                color: PartyModeTokens.violet.opacity(0.42 * renderState.chromeOpacity),
                radius: 6
            )
            .shadow(
                color: PartyModeTokens.lavender.opacity(0.12 * renderState.chromeOpacity),
                radius: 10
            )
            .partyModeBorder(
                shape: Circle(),
                role: .play,
                lighting: .clockwise,
                semanticColor: PartyModeTokens.violet,
                glintOffset: .none
            )
    }
}

private struct PartyModeIconGlowModifier: ViewModifier {
    let color: Color

    @Environment(\.partyModeRenderState) private var renderState

    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(0.42 * renderState.chromeOpacity),
                radius: 4
            )
            .shadow(
                color: PartyModeTokens.lavender.opacity(0.14 * renderState.chromeOpacity),
                radius: 7
            )
    }
}

extension View {
    func partyModePlayButton() -> some View {
        modifier(PartyModePlayButtonModifier())
    }

    func partyModeIconGlow(color: Color = PartyModeTokens.violet) -> some View {
        modifier(PartyModeIconGlowModifier(color: color))
    }
}
