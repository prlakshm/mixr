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
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrSecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.button)
            .foregroundStyle(MixrColors.textPrimary)
            .padding(.horizontal, MixrLayout.buttonPaddingH)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .background {
                GlassBackground(level: .default, cornerRadius: MixrRadius.button)
            }
            .clipShape(RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous))
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

extension ButtonStyle where Self == MixrToggleButtonStyle {
    static var mixrToggle: MixrToggleButtonStyle { MixrToggleButtonStyle() }
}
