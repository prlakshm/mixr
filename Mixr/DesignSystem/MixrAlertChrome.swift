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

    static func background(cornerRadius: CGFloat = cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(Color(hex: "050810").opacity(0.68))
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

/// Press colors shared by project menu + alert actions.
/// Every resting color darkens by the same factor on press.
enum MixrAlertPressColors {
    /// Shared darken step for white, gray, and red.
    static let pressFactor: Double = 0.64

    static let whiteResting = Color.white
    static let whitePressed = Color.white.opacity(pressFactor)

    static let redResting = Color.red
    static let redPressed = Color.red.opacity(pressFactor)

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
            .font(.system(size: MixrAlertChrome.actionFontSize, weight: resolvedWeight))
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
