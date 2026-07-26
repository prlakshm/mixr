import SwiftUI

/// Draws the application-level Party chrome after the real interface has been
/// clipped to its existing geometry. This keeps the ambient bloom outside
/// content masks without changing any normal-mode layout or hit testing.
struct PartyModeMainChromeOverlay: View {
    let screenSize: CGSize
    /// Matches the live toolbar — the one-row and two-row bars differ, and both
    /// grow on roomier screens.
    var transportHeight: CGFloat = TLK.transportHeight
    let effectsHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: transportHeight)
                .partyModeBorder(
                    shape: Rectangle(),
                    role: .majorPanel,
                    lighting: .violetTrailing,
                    glintOffset: .none
                )

            PartyModeMainPanelRow()
                .frame(
                    height: max(
                        0,
                        screenSize.height - transportHeight - effectsHeight
                    )
                )

            Color.clear
                .frame(height: effectsHeight)
                .partyModeBorder(
                    shape: Rectangle(),
                    role: .majorPanel,
                    lighting: .counterClockwise,
                    glintOffset: .far
                )
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
