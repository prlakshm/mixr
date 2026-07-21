import SwiftUI

// MARK: - Auto Error Sheet

/// Same Apple-style alert chrome as Auto scope / Delete confirm, with a single OK.
struct AutoRemixErrorSheet: View {
    let message: String
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("Auto couldn’t finish")
                    .font(.system(size: MixrAlertChrome.titleFontSize, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)

                Text(message)
                    .font(.system(size: MixrAlertChrome.messageFontSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MixrAlertChrome.horizontalPadding)
            .padding(.top, MixrAlertChrome.messageVerticalPadding)
            .padding(.bottom, MixrAlertChrome.messageVerticalPadding + MixrAlertChrome.titleBottomExtraPadding)
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)

            Button("OK", action: onDismiss)
                .buttonStyle(MixrAlertActionPressStyle(kind: .primary, weight: .regular))
                .frame(height: MixrAlertChrome.actionHeight)
        }
        .frame(width: MixrAlertChrome.alertWidth)
        .fixedSize(horizontal: true, vertical: true)
        .background { MixrAlertChrome.background() }
        .clipShape(RoundedRectangle(cornerRadius: MixrAlertChrome.cornerRadius, style: .continuous))
        .partyModeBorder(
            shape: RoundedRectangle(
                cornerRadius: MixrAlertChrome.cornerRadius,
                style: .continuous
            ),
            role: .dialog,
            lighting: .counterClockwise,
            glintOffset: .near
        )
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Auto couldn’t finish")
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
