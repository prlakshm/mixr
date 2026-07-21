import SwiftUI

/// Party-only perimeter lighting for Tracks, Timeline, and Controls. The real
/// panels keep their original rectangular layout; only the traced light path
/// receives the reference's rounded glass curvature.
struct PartyModeMainPanelRow: View {
    var body: some View {
        GeometryReader { proxy in
            let timelineWidth = max(
                0,
                proxy.size.width - TLK.sidebarWidth - TLK.smColumnWidth
            )

            HStack(spacing: 0) {
                Color.clear
                    .frame(width: TLK.sidebarWidth)
                    .partyModeBorder(
                        shape: Rectangle(),
                        role: .majorPanel,
                        lighting: .coolLeading,
                        glintOffset: .near
                    )

                Color.clear
                    .frame(width: timelineWidth)
                    .partyModeBorder(
                        shape: Rectangle(),
                        role: .majorPanel,
                        lighting: .shared,
                        glintOffset: .near
                    )

                Color.clear
                    .frame(width: TLK.smColumnWidth)
                    .partyModeBorder(
                        shape: Rectangle(),
                        role: .majorPanel,
                        lighting: .violetTrailing,
                        glintOffset: .near
                    )
            }
        }
    }
}
