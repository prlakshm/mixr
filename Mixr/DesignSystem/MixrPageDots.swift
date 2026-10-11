import SwiftUI

/// Page / progress indicator shared by the tour card and the SFX library:
/// all dots, the current one only a touch wider and in the accent, so the
/// row reads as dots rather than a progress bar.
struct MixrPageDots: View {
    let count: Int
    let current: Int
    var accent: Color = MixrColors.secondaryPurple
    var dot: CGFloat = 6
    /// The current dot's width: barely wider than the rest.
    var currentWidth: CGFloat = 9
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? accent : Color.white.opacity(0.25))
                    .frame(width: i == current ? currentWidth : dot, height: dot)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
    }
}
