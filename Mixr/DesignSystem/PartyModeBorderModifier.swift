import SwiftUI

enum PartyModeSurfaceRole: Sendable {
    case majorPanel
    case button
    case export
    case play
    case compactControl
    case dialog
    case menu
    case effectCard
    case semantic
    case trackChip
    case timelineClip
    case sfxSurface
    case sfxClip

    var strokeWidth: CGFloat {
        switch self {
        case .majorPanel, .dialog: PartyModeTokens.primaryStrokeWidth
        case .export, .play: 1.14
        case .button, .menu, .effectCard, .semantic, .trackChip, .sfxSurface: 0.92
        case .timelineClip: 0.72
        case .sfxClip: 0.82
        case .compactControl: PartyModeTokens.compactStrokeWidth
        }
    }

    var primaryOpacity: Double {
        switch self {
        case .majorPanel: 0.78
        case .dialog: 0.88
        case .export: 0.98
        case .play: 0
        case .button: 0.78
        case .menu: 0.84
        case .effectCard: 0.52
        case .semantic: 0.38
        case .trackChip: 0.68
        case .timelineClip: 0.25
        case .sfxSurface: 0.90
        case .sfxClip: 0.94
        case .compactControl: 0.66
        }
    }

    var nearGlowOpacity: Double {
        switch self {
        case .majorPanel: 0.34
        case .dialog: 0.27
        case .export: 0.36
        case .play: 0.36
        case .button: 0.19
        case .menu: 0.22
        case .effectCard: 0.13
        case .semantic: 0.10
        case .trackChip: 0.20
        case .timelineClip: 0.06
        case .sfxSurface: 0.27
        case .sfxClip: 0.32
        case .compactControl: 0.14
        }
    }

    var ambientGlowOpacity: Double {
        switch self {
        case .majorPanel: 0.18
        case .dialog: 0.12
        case .export: 0.18
        case .play: 0.17
        case .button: 0.075
        case .menu: 0.09
        case .effectCard: 0.07
        case .semantic: 0.04
        case .trackChip: 0.08
        case .timelineClip: 0.02
        case .sfxSurface: 0.11
        case .sfxClip: 0.12
        case .compactControl: 0.055
        }
    }

    var glowScale: CGFloat {
        switch self {
        case .majorPanel, .dialog, .export: 1
        case .play: 0.82
        case .button, .menu: 0.74
        case .effectCard, .semantic: 0.64
        case .trackChip: 0.56
        case .timelineClip: 0.44
        case .sfxSurface: 0.70
        case .sfxClip: 0.60
        case .compactControl: 0.56
        }
    }

    var glintOpacity: Double {
        switch self {
        case .majorPanel, .dialog, .export, .play: 1
        case .button, .menu: 0.72
        case .compactControl: 0.58
        case .effectCard: 0.44
        case .semantic, .trackChip: 0.34
        case .timelineClip: 0.24
        case .sfxSurface: 0.60
        case .sfxClip: 0.46
        }
    }

    var glintWidth: CGFloat {
        switch self {
        case .majorPanel, .dialog: 0.045
        case .play: 0.075
        case .timelineClip: 0.04
        case .sfxClip: 0.05
        default: 0.06
        }
    }
}

enum PartyModeLightingVariant: Sendable {
    case shared
    case clockwise
    case counterClockwise
    case coolLeading
    case violetTrailing

    var startPoint: UnitPoint {
        switch self {
        case .shared: .bottomLeading
        case .clockwise: UnitPoint(x: 0.02, y: 0.72)
        case .counterClockwise: UnitPoint(x: 0.18, y: 1.0)
        case .coolLeading: .leading
        case .violetTrailing: .bottomLeading
        }
    }

    var endPoint: UnitPoint {
        switch self {
        case .shared: .topTrailing
        case .clockwise: UnitPoint(x: 0.88, y: 0.02)
        case .counterClockwise: UnitPoint(x: 1.0, y: 0.22)
        case .coolLeading: .topTrailing
        case .violetTrailing: .trailing
        }
    }
}

private enum PartyModeBorderGradient {
    static func style(
        role: PartyModeSurfaceRole,
        lighting: PartyModeLightingVariant,
        semanticColor: Color?
    ) -> AnyShapeStyle {
        if role == .sfxSurface || role == .sfxClip {
            return AnyShapeStyle(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: PartyModeTokens.lavender.opacity(0.88), location: 0),
                        .init(color: PartyModeTokens.violet, location: 0.30),
                        .init(color: PartyModeTokens.glintWhite.opacity(0.96), location: 0.63),
                        .init(color: PartyModeTokens.electricBlue.opacity(0.86), location: 1),
                    ]),
                    startPoint: lighting.startPoint,
                    endPoint: lighting.endPoint
                )
            )
        }

        if let semanticColor {
            let sharedReflection = role == .effectCard
                ? PartyModeTokens.lavender.opacity(0.72)
                : semanticColor.opacity(0.78)
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        semanticColor.opacity(0.76), semanticColor,
                        sharedReflection, semanticColor.opacity(0.90),
                    ],
                    startPoint: lighting.startPoint,
                    endPoint: lighting.endPoint
                )
            )
        }

        let stops: [Gradient.Stop]
        if role == .compactControl {
            stops = [
                .init(color: PartyModeTokens.electricBlue, location: 0),
                .init(color: PartyModeTokens.coolCyan, location: 0.16),
                .init(color: PartyModeTokens.electricBlue, location: 0.34),
                .init(color: PartyModeTokens.violet, location: 0.70),
                .init(color: PartyModeTokens.lavender, location: 1),
            ]
        } else {
            stops = [
                .init(color: PartyModeTokens.electricBlue, location: 0),
                .init(color: PartyModeTokens.coolCyan, location: 0.13),
                .init(color: PartyModeTokens.electricBlue, location: 0.29),
                .init(color: PartyModeTokens.violet, location: 0.57),
                .init(color: PartyModeTokens.lavender, location: 0.80),
                .init(color: PartyModeTokens.magenta, location: 1),
            ]
        }
        return AnyShapeStyle(
            LinearGradient(
                gradient: Gradient(stops: stops),
                startPoint: lighting.startPoint,
                endPoint: lighting.endPoint
            )
        )
    }
}

private struct PartyModeBorderModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let role: PartyModeSurfaceRole
    let lighting: PartyModeLightingVariant
    let semanticColor: Color?
    let glintOffset: PartyModeGlintOffset

    @Environment(\.partyModeRenderState) private var renderState
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay {
            if renderState.chromeOpacity > 0.001 {
                PartyModeBorderLayers(
                    shape: shape,
                    role: role,
                    lighting: lighting,
                    semanticColor: semanticColor,
                    glintOffset: glintOffset,
                    renderState: renderState,
                    isEnabled: isEnabled
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct PartyModeShapeBorderModifier<S: Shape>: ViewModifier {
    let shape: S
    let role: PartyModeSurfaceRole
    let lighting: PartyModeLightingVariant
    let semanticColor: Color?
    let glintOffset: PartyModeGlintOffset

    @Environment(\.partyModeRenderState) private var renderState
    @Environment(\.isEnabled) private var isEnabled

    private var gradient: AnyShapeStyle {
        PartyModeBorderGradient.style(
            role: role,
            lighting: lighting,
            semanticColor: semanticColor
        )
    }

    private var glintProgress: CGFloat {
        let delay = PartyModeTokens.delay(for: glintOffset) / PartyModeTokens.glintDuration
        return min(1, max(0, (renderState.glintPhase - delay) / (1 - delay)))
    }

    func body(content: Content) -> some View {
        content.overlay {
            if renderState.chromeOpacity > 0.001 {
                let enabledOpacity = isEnabled ? 1.0 : 0.42
                let opacity = renderState.chromeOpacity * enabledOpacity
                let nearRadius = PartyModeTokens.nearGlowRadius * role.glowScale
                let ambientRadius = PartyModeTokens.ambientGlowRadius * role.glowScale

                ZStack {
                    shape
                        .stroke(gradient, lineWidth: role.strokeWidth * 1.5)
                        .blur(radius: ambientRadius)
                        .opacity(role.ambientGlowOpacity * opacity)
                    shape
                        .stroke(gradient, lineWidth: role.strokeWidth * 1.25)
                        .blur(radius: nearRadius)
                        .opacity(role.nearGlowOpacity * opacity)
                    shape
                        .stroke(gradient, lineWidth: role.strokeWidth)
                        .opacity(role.primaryOpacity * opacity)

                    if renderState.isGlintActive {
                        let width = role.glintWidth
                        shape
                            .trim(from: max(0, glintProgress - width), to: glintProgress)
                            .stroke(
                                PartyModeTokens.glintWhite,
                                style: StrokeStyle(
                                    lineWidth: role.strokeWidth * (role == .play ? 1.5 : 1.3),
                                    lineCap: .round
                                )
                            )
                            .shadow(
                                color: PartyModeTokens.glintWhite.opacity(0.52 * role.glintOpacity),
                                radius: nearRadius
                            )
                            .opacity(opacity * role.glintOpacity)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct PartyModeBorderLayers<S: InsettableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let lighting: PartyModeLightingVariant
    let semanticColor: Color?
    let glintOffset: PartyModeGlintOffset
    let renderState: PartyModeRenderState
    let isEnabled: Bool

    private var enabledOpacity: Double { isEnabled ? 1 : 0.42 }

    private var borderGradient: AnyShapeStyle {
        PartyModeBorderGradient.style(
            role: role,
            lighting: lighting,
            semanticColor: semanticColor
        )
    }

    private var glintProgress: CGFloat {
        let delay = PartyModeTokens.delay(for: glintOffset) / PartyModeTokens.glintDuration
        return min(1, max(0, (renderState.glintPhase - delay) / (1 - delay)))
    }

    var body: some View {
        let opacity = renderState.chromeOpacity * enabledOpacity
        let nearRadius = PartyModeTokens.nearGlowRadius * role.glowScale
        let ambientRadius = PartyModeTokens.ambientGlowRadius * role.glowScale

        ZStack {
            shape
                .strokeBorder(borderGradient, lineWidth: role.strokeWidth * 1.5)
                .blur(radius: ambientRadius)
                .opacity(role.ambientGlowOpacity * opacity)

            shape
                .strokeBorder(borderGradient, lineWidth: role.strokeWidth * 1.25)
                .blur(radius: nearRadius)
                .opacity(role.nearGlowOpacity * opacity)

            shape
                .strokeBorder(borderGradient, lineWidth: role.strokeWidth)
                .opacity(role.primaryOpacity * opacity)

            shape
                .strokeBorder(Color.white.opacity(0.075 * opacity), lineWidth: 0.38)
                .mask {
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.32), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            if renderState.isGlintActive {
                let width = role.glintWidth
                let start = max(0, glintProgress - width)
                shape
                    .inset(by: role.strokeWidth * 0.45)
                    .trim(from: start, to: glintProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                PartyModeTokens.glintWhite.opacity(0),
                                PartyModeTokens.glintWhite,
                                PartyModeTokens.lavender.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(
                            lineWidth: role.strokeWidth * (role == .play ? 1.5 : 1.3),
                            lineCap: .round
                        )
                    )
                    .shadow(
                        color: PartyModeTokens.glintWhite.opacity(0.52 * role.glintOpacity),
                        radius: nearRadius
                    )
                    .opacity(opacity * role.glintOpacity)
            }
        }
    }
}

extension View {
    func partyModeBorder<S: InsettableShape>(
        shape: S,
        role: PartyModeSurfaceRole = .button,
        lighting: PartyModeLightingVariant = .shared,
        semanticColor: Color? = nil,
        glintOffset: PartyModeGlintOffset = .none
    ) -> some View {
        modifier(
            PartyModeBorderModifier(
                shape: shape,
                role: role,
                lighting: lighting,
                semanticColor: semanticColor,
                glintOffset: glintOffset
            )
        )
    }

    /// Party chrome for custom shapes that cannot provide an inset stroke.
    func partyModeShapeBorder<S: Shape>(
        shape: S,
        role: PartyModeSurfaceRole = .button,
        lighting: PartyModeLightingVariant = .shared,
        semanticColor: Color? = nil,
        glintOffset: PartyModeGlintOffset = .none
    ) -> some View {
        modifier(
            PartyModeShapeBorderModifier(
                shape: shape,
                role: role,
                lighting: lighting,
                semanticColor: semanticColor,
                glintOffset: glintOffset
            )
        )
    }
}
