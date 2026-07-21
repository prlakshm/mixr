import SwiftUI

struct MixrPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.button)
            .foregroundStyle(MixrColors.textPrimary)
            .padding(.horizontal, MixrLayout.buttonPaddingH)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .background(MixrGradients.accentLinear)
            .clipShape(RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
            .shadow(color: MixrColors.primaryPurple.opacity(0.35), radius: 12, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrSecondaryGlassButtonStyle: ButtonStyle {
    var partyRole: PartyModeSurfaceRole = .button

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
        configuration.label
            .mixrFont(.button)
            .foregroundStyle(MixrColors.textPrimary)
            .padding(.horizontal, MixrLayout.buttonPaddingH)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .background {
                GlassBackground(level: .default, cornerRadius: MixrRadius.button)
            }
            .clipShape(RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous))
            .overlay {
                shape
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            }
            .partyModeBorder(
                shape: shape,
                role: partyRole,
                lighting: partyRole == .export ? .violetTrailing : .coolLeading,
                glintOffset: .near
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MixrColors.textPrimary)
            .frame(
                width: MixrLayout.iconButtonSize,
                height: MixrLayout.iconButtonSize
            )
            .background(MixrColors.primaryPurple)
            .clipShape(Circle())
            .shadow(color: MixrColors.primaryPurple.opacity(0.32), radius: 10, x: 0, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrIconGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MixrColors.textPrimary)
            .frame(
                width: MixrLayout.iconButtonSize,
                height: MixrLayout.iconButtonSize
            )
            .background {
                GlassBackground(level: .default, cornerRadius: MixrRadius.icon)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.55)
            }
            .partyModeBorder(
                shape: Circle(),
                role: .compactControl,
                lighting: .clockwise,
                glintOffset: .far
            )
            .shadow(color: .black.opacity(0.32), radius: 5, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.caption)
            .foregroundStyle(MixrColors.textPrimary)
            .frame(
                width: MixrLayout.toggleButtonWidth,
                height: MixrLayout.toggleButtonWidth
            )
            .background {
                GlassBackground(level: .default, cornerRadius: MixrLayout.toggleButtonWidth / 2)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .partyModeBorder(
                shape: Circle(),
                role: .compactControl,
                lighting: .coolLeading,
                glintOffset: .far
            )
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 1.5)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == MixrPrimaryButtonStyle {
    static var mixrPrimary: MixrPrimaryButtonStyle { MixrPrimaryButtonStyle() }
}

extension ButtonStyle where Self == MixrSecondaryGlassButtonStyle {
    static var mixrSecondaryGlass: MixrSecondaryGlassButtonStyle { MixrSecondaryGlassButtonStyle() }
}

extension ButtonStyle where Self == MixrIconButtonStyle {
    static var mixrIcon: MixrIconButtonStyle { MixrIconButtonStyle() }
}

extension ButtonStyle where Self == MixrIconGlassButtonStyle {
    static var mixrIconGlass: MixrIconGlassButtonStyle { MixrIconGlassButtonStyle() }
}

struct MixrCompactTrackToggleButtonStyle: ButtonStyle {
    private let size = MixrLayout.trackToggleSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.caption)
            .foregroundStyle(MixrColors.textPrimary.opacity(0.92))
            .frame(width: size, height: size)
            .background {
                GlassBackground(level: .default, cornerRadius: size / 2)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .partyModeBorder(
                shape: Circle(),
                role: .compactControl,
                lighting: .violetTrailing,
                glintOffset: .far
            )
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 1.5)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == MixrCompactTrackToggleButtonStyle {
    static var mixrCompactTrackToggle: MixrCompactTrackToggleButtonStyle { MixrCompactTrackToggleButtonStyle() }
}

extension ButtonStyle where Self == MixrToggleButtonStyle {
    static var mixrToggle: MixrToggleButtonStyle { MixrToggleButtonStyle() }
}
