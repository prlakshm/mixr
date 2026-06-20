import SwiftUI

enum GlassLevel {
    case `default`
    case elevated
    case strong

    var overlayColor: Color {
        switch self {
        case .default:
            MixrColors.surface.opacity(0.55)
        case .elevated:
            MixrColors.elevatedSurface.opacity(0.65)
        case .strong:
            MixrColors.elevatedSurface.opacity(0.75)
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
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(level.overlayColor)
            }
            .overlay {
                shape.strokeBorder(level.borderColor, lineWidth: MixrLayout.borderWidth)
            }
    }
}

struct GlassCardModifier: ViewModifier {
    let level: GlassLevel
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                GlassBackground(level: level, cornerRadius: cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
