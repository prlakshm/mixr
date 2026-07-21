import SwiftUI

enum GlassLevel {
    case `default`
    case selected
    case elevated
    case strong

    var tintColor: Color {
        switch self {
        case .default: MixrColors.glassNavyDefault
        case .selected: MixrColors.glassNavyDefault
        case .elevated: MixrColors.glassNavyElevated
        case .strong: MixrColors.glassNavyStrong
        }
    }

    /// Dark transparent glass; levels differ by rim/depth more than milky fill.
    var tintOpacity: Double {
        switch self {
        case .default: 0.28
        case .selected: 0.30
        case .elevated: 0.34
        case .strong: 0.42
        }
    }

    var materialOpacity: Double {
        switch self {
        case .default: 0.08
        case .selected: 0.07
        case .elevated: 0.10
        case .strong: 0.12
        }
    }

    var highlightOpacity: Double {
        switch self {
        case .default: 0.05
        case .selected: 0.06
        case .elevated: 0.075
        case .strong: 0.09
        }
    }

    var borderColor: Color {
        switch self {
        case .default: MixrColors.glassBorderDefault
        case .selected: MixrColors.primaryPurple.opacity(0.42)
        case .elevated: MixrColors.glassBorderElevated
        case .strong: MixrColors.glassBorderStrong
        }
    }

    var accentColor: Color {
        switch self {
        case .default: Color.white.opacity(0.08)
        case .selected: MixrColors.primaryPurple
        case .elevated: Color.white.opacity(0.12)
        case .strong: Color(hex: "8B9DC2").opacity(0.18)
        }
    }

    var edgeHighlightOpacity: Double {
        switch self {
        case .default: 0.16
        case .selected: 0.24
        case .elevated: 0.20
        case .strong: 0.22
        }
    }

    var lowerReflectionOpacity: Double {
        switch self {
        case .default: 0.08
        case .selected: 0.36
        case .elevated: 0.13
        case .strong: 0.18
        }
    }

    var partyModeDepthOpacity: Double {
        switch self {
        case .default: 0.035
        case .selected: 0.025
        case .elevated: 0.07
        case .strong: 0.13
        }
    }
}

struct GlassBackground: View {
    let level: GlassLevel
    let cornerRadius: CGFloat

    @Environment(\.partyModeRenderState) private var renderState

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
                    .opacity(level.materialOpacity)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(MixrGradients.glassSurfaceDepth(highlightOpacity: level.highlightOpacity))
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(level.highlightOpacity * 0.95),
                            Color.clear,
                            Color.black.opacity(0.16),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [
                            level.accentColor.opacity(level == .selected ? 0.16 : 0.055),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.10, y: 0.05),
                        startRadius: 0,
                        endRadius: 260
                    )
                )
            }
            .overlay {
                shape.fill(
                    Color.black.opacity(
                        level.partyModeDepthOpacity * renderState.chromeOpacity
                    )
                )
            }
            .overlay {
                shape.strokeBorder(level.borderColor, lineWidth: MixrLayout.glassBorderWidth)
            }
            .overlay {
                GlassAsymmetricEdgeReflection(
                    shape: shape,
                    accentColor: level.accentColor,
                    topOpacity: level.edgeHighlightOpacity,
                    lowerOpacity: level.lowerReflectionOpacity,
                    isSelected: level == .selected
                )
            }
    }
}

private struct GlassAsymmetricEdgeReflection<S: InsettableShape>: View {
    let shape: S
    let accentColor: Color
    let topOpacity: Double
    let lowerOpacity: Double
    var isSelected: Bool

    var body: some View {
        ZStack {
            // Thin complete rim: keeps every card feeling like a physical glass object.
            shape.strokeBorder(Color.white.opacity(isSelected ? 0.12 : 0.07), lineWidth: isSelected ? 0.75 : 0.55)

            // Top-left catchlight, stronger near the leading corner and fading across the pane.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(topOpacity),
                        Color.white.opacity(topOpacity * 0.42),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.82, y: 0.55)
                ),
                lineWidth: isSelected ? 0.95 : 0.72
            )

            // Lower asymmetric reflection: this gives non-selected cards body without making them neon.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        accentColor.opacity(lowerOpacity),
                        accentColor.opacity(lowerOpacity * 0.44),
                        Color.white.opacity(lowerOpacity * 0.22),
                        Color.clear,
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ),
                lineWidth: isSelected ? 1.15 : 0.7
            )

            // Very soft edge bloom, mostly visible along the lower-left edge.
            shape.strokeBorder(accentColor.opacity(isSelected ? 0.34 : lowerOpacity * 0.62), lineWidth: isSelected ? 1.25 : 0.9)
                .blur(radius: isSelected ? 1.2 : 0.75)
                .mask {
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.45),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.02, y: 0.98),
                        startRadius: 0,
                        endRadius: 260
                    )
                }

            // Tiny right-edge glint so large cards do not feel lit only from one side.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(isSelected ? 0.055 : 0.032),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 0.5
            )
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
                .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                .partyModeBorder(
                    shape: shape,
                    role: .button,
                    lighting: .shared,
                    glintOffset: .near
                )
        case .selected:
            base
                .shadow(color: MixrColors.primaryPurple.opacity(0.28), radius: 12, x: 0, y: 0)
                .shadow(color: .black.opacity(0.34), radius: 8, x: 0, y: 3)
                .partyModeBorder(
                    shape: shape,
                    role: .semantic,
                    lighting: .violetTrailing,
                    semanticColor: MixrColors.primaryPurple,
                    glintOffset: .near
                )
        case .elevated:
            base
                .mixrShadow(.glassElevated)
                .mixrGlow(.glassAmbient)
                .partyModeBorder(
                    shape: shape,
                    role: .dialog,
                    lighting: .clockwise,
                    glintOffset: .near
                )
        case .strong:
            base
                .mixrShadow(.glassStrong)
                .mixrGlow(.glassAmbientStrong)
                .partyModeBorder(
                    shape: shape,
                    role: .majorPanel,
                    lighting: .counterClockwise,
                    glintOffset: .far
                )
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
