import SwiftUI

// MARK: - Shared alert chrome (Auto scope, delete confirm, Auto error)

enum MixrAlertChrome {
    /// Compact alert metrics — slightly tighter than the 15pt scale pass.
    static let cornerRadius: CGFloat = 14
    static let alertWidth: CGFloat = 268
    static let titleHeight: CGFloat = 60
    /// Extra space under the title/message before the action divider.
    static let titleBottomExtraPadding: CGFloat = 1
    static let actionHeight: CGFloat = 44
    static let horizontalPadding: CGFloat = 18
    static let titleFontSize: CGFloat = 15
    static let actionFontSize: CGFloat = 15
    static let messageFontSize: CGFloat = 13
    static let messageVerticalPadding: CGFloat = 16

    /// iOS sizes a system alert the same on every device, but Mixr's own
    /// chrome scales with the screen, so a 268pt dialog reads undersized next
    /// to a tablet-sized toolbar and effects panel. The alert follows the
    /// layout's content scale, capped well short of it — an alert is a focused
    /// interruption, not a panel, and should never become a billboard.
    /// Apple's alerts are a fixed 270pt on every device. 1.25 put ours at
    /// 335pt, which read as a panel rather than an alert next to system UI;
    /// 1.12 lands at ~300pt — still visibly ours, but inside the size family
    /// a system alert occupies.
    static let maximumScale: CGFloat = 1.12

    static func scale(forContentScale contentScale: CGFloat) -> CGFloat {
        min(maximumScale, max(1, contentScale))
    }

    static func background(cornerRadius: CGFloat = cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // As solid as the project menu: an alert interrupts, so the timeline
        // (and the bright playhead line) must not show through its actions.
        return shape
            .fill(Color(hex: "050810").opacity(0.90))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.10)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.045),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                    )
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}

/// Title plus an optional one- or two-line message, as in a system alert.
struct MixrAlertHeader: View {
    let title: String
    var message: String? = nil
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 5 * scale) {
            Text(title)
                .font(.system(size: MixrAlertChrome.titleFontSize * scale, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.system(size: MixrAlertChrome.messageFontSize * scale, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, MixrAlertChrome.horizontalPadding * scale)
        .padding(.top, MixrAlertChrome.messageVerticalPadding * scale)
        .padding(
            .bottom,
            (MixrAlertChrome.messageVerticalPadding + MixrAlertChrome.titleBottomExtraPadding) * scale
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A title, a message and OK: Mixr's chrome for errors (Auto, Export).
struct MixrMessageAlert: View {
    let title: String
    let message: String
    /// 1.0 on a phone; roomier screens pass the layout's alert scale.
    var scale: CGFloat = 1
    var onDismiss: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MixrAlertChrome.cornerRadius * scale, style: .continuous)
        VStack(spacing: 0) {
            MixrAlertHeader(title: title, message: message, scale: scale)
            MixrAlertDivider()
            Button("OK", action: onDismiss)
                .buttonStyle(MixrAlertActionPressStyle(kind: .primary, scale: scale))
                .frame(height: MixrAlertChrome.actionHeight * scale)
        }
        .frame(width: MixrAlertChrome.alertWidth * scale)
        .fixedSize(horizontal: true, vertical: true)
        .background { MixrAlertChrome.background(cornerRadius: MixrAlertChrome.cornerRadius * scale) }
        .clipShape(shape)
        .partyModeBorder(shape: shape, role: .dialog, lighting: .counterClockwise, glintOffset: .near)
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Hairline between an alert's header and its actions, or between actions.
struct MixrAlertDivider: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(
                width: axis == .vertical ? 0.5 : nil,
                height: axis == .horizontal ? 0.5 : nil
            )
    }
}

/// Press colors shared by project menu + alert actions.
/// Every resting color darkens by the same factor on press.
enum MixrAlertPressColors {
    /// Shared darken step for white, gray, and red.
    static let pressFactor: Double = 0.64

    static let whiteResting = Color.white
    static let whitePressed = Color.white.opacity(pressFactor)

    static let redResting = MixrColors.destructive
    static let redPressed = MixrColors.destructive.opacity(pressFactor)

    /// Cancel / Playhead Clips resting gray.
    static let cancelRestingOpacity: Double = 0.74
    static let cancelResting = Color.white.opacity(cancelRestingOpacity)
    static let cancelPressed = Color.white.opacity(cancelRestingOpacity * pressFactor)
}

enum MixrAlertActionKind {
    case primary
    case cancel
    case destructive
}

/// Alert / menu label press: dip + explicit font color change (no fill).
struct MixrAlertActionPressStyle: ButtonStyle {
    var kind: MixrAlertActionKind
    var weight: Font.Weight? = nil
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        let resting: Color
        let pressed: Color
        let resolvedWeight: Font.Weight

        switch kind {
        case .primary:
            resting = MixrAlertPressColors.whiteResting
            pressed = MixrAlertPressColors.whitePressed
            resolvedWeight = weight ?? .semibold
        case .cancel:
            resting = MixrAlertPressColors.cancelResting
            pressed = MixrAlertPressColors.cancelPressed
            resolvedWeight = weight ?? .regular
        case .destructive:
            resting = MixrAlertPressColors.redResting
            pressed = MixrAlertPressColors.redPressed
            resolvedWeight = weight ?? .semibold
        }

        return configuration.label
            .font(.system(size: MixrAlertChrome.actionFontSize * scale, weight: resolvedWeight))
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
