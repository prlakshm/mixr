import SwiftUI

// MARK: - Auto Scope Dialog

/// Compact Apple-style alert shown before Auto touches the timeline.
/// Says what Auto does, offers the two scopes, and always has Cancel; the
/// presenter also dismisses on outside taps. Three actions stack, as in a
/// system alert.
struct AutoScopeDialog: View {
    /// 1.0 on a phone; roomier screens pass the layout's alert scale.
    var scale: CGFloat = 1
    /// When a clip is selected the focused action targets it; otherwise it
    /// targets the clips under the playhead.
    var hasSelectedClip: Bool
    var onChooseFocused: () -> Void = {}
    var onChooseEntireProject: () -> Void = {}
    var onCancel: () -> Void = {}

    static let title = "Auto Remix"
    static let message = "Rebuild your songs as a club mix with builds, drops and transitions. You can undo it."

    private var focusedTitle: String {
        hasSelectedClip ? "Selected Clip" : "Clips at Playhead"
    }

    var body: some View {
        VStack(spacing: 0) {
            MixrAlertHeader(title: Self.title, message: Self.message, scale: scale)

            MixrAlertDivider()
            Button("Entire Project", action: onChooseEntireProject)
                .buttonStyle(MixrAlertActionPressStyle(kind: .primary, scale: scale))
                .frame(height: MixrAlertChrome.actionHeight * scale)

            MixrAlertDivider()
            Button(focusedTitle, action: onChooseFocused)
                .buttonStyle(MixrAlertActionPressStyle(kind: .primary, weight: .regular, scale: scale))
                .frame(height: MixrAlertChrome.actionHeight * scale)

            MixrAlertDivider()
            Button("Cancel", action: onCancel)
                .buttonStyle(MixrAlertActionPressStyle(kind: .cancel, scale: scale))
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
            lighting: .clockwise,
            glintOffset: .near
        )
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Action Style

private struct AutoScopeAlertActionStyle: ButtonStyle {
    var weight: Font.Weight = .regular
    var isPreferred: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let resting = isPreferred
            ? MixrAlertPressColors.whiteResting
            : MixrAlertPressColors.cancelResting
        let pressed = isPreferred
            ? MixrAlertPressColors.whitePressed
            : MixrAlertPressColors.cancelPressed

        configuration.label
            .font(.system(size: MixrAlertChrome.actionFontSize, weight: weight))
            .foregroundStyle(configuration.isPressed ? pressed : resting)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 1.17 : 0)
            .animation(
                .spring(response: 0.17, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

// MARK: - Auto Loading Overlay

/// Simple circular spinner on a black screen (Auto, Export, etc.).
struct MixrAutoLoadingOverlay: View {
    var accessibilityLabelText: String = "Loading"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
        .accessibilityLabel(accessibilityLabelText)
    }
}

#Preview("Auto Scope Dialog") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        AutoScopeDialog(hasSelectedClip: true)
    }
    .frame(width: 932, height: 430)
    .preferredColorScheme(.dark)
}

#Preview("Auto Loading") {
    MixrAutoLoadingOverlay()
        .frame(width: 932, height: 430)
        .preferredColorScheme(.dark)
}
