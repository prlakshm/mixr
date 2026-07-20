import SwiftUI

/// Track-row surface with an inset purple-to-navy SFX card variant.
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
                                color: Color(hex: "241A39").opacity(0.96),
                                location: 0
                            ),
                            .init(
                                color: Color(hex: "090B13").opacity(0.98),
                                location: 0.5325
                            ),
                            .init(
                                color: Color(hex: "162239").opacity(0.96),
                                location: 1
                            ),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    cardShape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(hex: "A281BC").opacity(0.34),
                                Color.white.opacity(0.08),
                                Color(hex: "765A92").opacity(0.28),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
                }
                .shadow(color: Color.black.opacity(0.32), radius: 3, x: 0, y: 1.5)
                .opacity(isSFXTrack ? 1 : 0)
                .padding(.leading, 20)
                .padding(.trailing, 5)
                .padding(.vertical, 2)
                .offset(x: -0.5)
            }
    }
}
