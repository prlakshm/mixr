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

    private var ringReveal: Double {
        let phase = renderState.animationPhase(for: .play, offset: .none)
        if phase.isTransient {
            return phase.traceProgress >= 0.995 ? 1 : 0
        }
        return renderState.settledBorderOpacity
    }

    func body(content: Content) -> some View {
        let ringOpacity = renderState.chromeOpacity * ringReveal

        content
            .overlay {
                if ringOpacity > 0.001 {
                    ZStack {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        PartyModeTokens.glintWhite,
                                        PartyModeTokens.lavender,
                                        PartyModeTokens.violet,
                                        PartyModeTokens.magenta.opacity(0.84),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.12
                            )
                            .padding(PartyModeTokens.playOuterRimInset)
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        PartyModeTokens.glintWhite.opacity(0.88),
                                        PartyModeTokens.lavender.opacity(0.74),
                                        PartyModeTokens.violet.opacity(0.88),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.72
                            )
                            .padding(PartyModeTokens.playInnerRingInset)
                        Circle()
                            .strokeBorder(
                                PartyModeTokens.lavender.opacity(0.46),
                                lineWidth: 0.52
                            )
                            .padding(5.2)
                    }
                    .opacity(ringOpacity)
                    .allowsHitTesting(false)
                }
            }
            .shadow(
                color: PartyModeTokens.violet.opacity(0.46 * ringOpacity),
                radius: PartyModeTokens.playNearAuraRadius
            )
            .shadow(
                color: PartyModeTokens.lavender.opacity(0.16 * ringOpacity),
                radius: PartyModeTokens.playAmbientAuraRadius
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
