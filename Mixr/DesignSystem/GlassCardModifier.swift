import SwiftUI

enum GlassLevel {
    case `default`
    case elevated
    case strong

    var tintColor: Color {
        switch self {
        case .default: MixrColors.glassNavyDefault
        case .elevated: MixrColors.glassNavyElevated
        case .strong: MixrColors.glassNavyStrong
        }
    }

    /// Lower opacity than spec sheet — screenshot shows deep translucency.
    var tintOpacity: Double {
        switch self {
        case .default: 0.34
        case .elevated: 0.44
        case .strong: 0.54
        }
    }

    var highlightOpacity: Double {
        switch self {
        case .default: 0.035
        case .elevated: 0.05
        case .strong: 0.06
        }
    }

    var borderColor: Color {
        switch self {
        case .default: MixrColors.glassBorderDefault
        case .elevated: MixrColors.glassBorderElevated
        case .strong: MixrColors.glassBorderStrong
        }
    }
}

struct GlassBackground: View {
    let level: GlassLevel
    let cornerRadius: CGFloat

    init(level: GlassLevel = .default, cornerRadius: CGFloat = MixrRadius.glass) {
        self.level = level
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(level.tintColor.opacity(level.tintOpacity))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(MixrGradients.glassSurfaceDepth(highlightOpacity: level.highlightOpacity))
            }
            .overlay {
                shape.fill(MixrGradients.glassAmbientWash)
            }
            .overlay {
                shape.strokeBorder(level.borderColor, lineWidth: MixrLayout.glassBorderWidth)
            }
            .overlay {
                shape.strokeBorder(MixrGradients.glassRimStroke, lineWidth: MixrLayout.glassBorderWidth)
            }
    }
}

struct GlassCardModifier: ViewModifier {
    let level: GlassLevel
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let base = content
            .background {
                GlassBackground(level: level, cornerRadius: cornerRadius)
            }
            .clipShape(shape)

        switch level {
        case .default:
            base
        case .elevated:
            base
                .mixrShadow(.glassElevated)
                .mixrGlow(.glassAmbient)
        case .strong:
            base
                .mixrShadow(.glassStrong)
                .mixrGlow(.glassAmbientStrong)
        }
    }
}

extension View {
    func glassCard(
        _ level: GlassLevel = .default,
        cornerRadius: CGFloat = MixrRadius.glass
    ) -> some View {
        modifier(GlassCardModifier(level: level, cornerRadius: cornerRadius))
    }
}
