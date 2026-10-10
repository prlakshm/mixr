import SwiftUI

// MARK: - Auto Error Sheet

/// Auto's failure alert: the shared one-button Mixr alert.
struct AutoRemixErrorSheet: View {
    /// 1.0 on a phone; roomier screens pass the layout's alert scale.
    var scale: CGFloat = 1
    let message: String
    var onDismiss: () -> Void = {}

    static let title = "Auto Couldn’t Finish"

    var body: some View {
        MixrMessageAlert(title: Self.title, message: message, scale: scale, onDismiss: onDismiss)
    }
}

#Preview("Auto Error") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        AutoRemixErrorSheet(
            message: "Add at least one song clip before running Auto on the entire project."
        )
    }
    .frame(width: 500, height: 320)
    .preferredColorScheme(.dark)
}
