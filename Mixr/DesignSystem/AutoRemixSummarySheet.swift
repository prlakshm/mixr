import SwiftUI

// MARK: - Auto Error Sheet

/// Same Apple-style alert chrome as Auto scope / Delete confirm, with a single OK.
struct AutoRemixErrorSheet: View {
    /// 1.0 on a phone; roomier screens pass the layout's alert scale.
    var scale: CGFloat = 1
    let message: String
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("Auto couldn’t finish")
                    .font(.system(size: MixrAlertChrome.titleFontSize * scale, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)

                Text(message)
                    .font(.system(size: MixrAlertChrome.messageFontSize * scale, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MixrAlertChrome.horizontalPadding * scale)
            .padding(.top, MixrAlertChrome.messageVerticalPadding * scale)
            .padding(.bottom, MixrAlertChrome.messageVerticalPadding * scale + MixrAlertChrome.titleBottomExtraPadding * scale)
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)

            Button("OK", action: onDismiss)
                .buttonStyle(MixrAlertActionPressStyle(kind: .primary, weight: .regular, scale: scale))
                .frame(height: MixrAlertChrome.actionHeight * scale)
        }
        .frame(width: MixrAlertChrome.alertWidth * scale)
        .fixedSize(horizontal: true, vertical: true)
        .background { MixrAlertChrome.background() }
        .clipShape(RoundedRectangle(cornerRadius: MixrAlertChrome.cornerRadius * scale, style: .continuous))
        .partyModeBorder(
            shape: RoundedRectangle(
                cornerRadius: MixrAlertChrome.cornerRadius * scale,
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
