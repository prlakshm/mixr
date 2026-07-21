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
        case .majorPanel, .dialog: PartyModeTokens.coreStrokeWidth
        case .export, .play: 1.14
        case .button, .menu, .effectCard, .semantic, .trackChip, .sfxSurface: 0.96
        case .timelineClip: 0.72
        case .sfxClip: 0.86
        case .compactControl: PartyModeTokens.compactStrokeWidth
        }
    }

    var primaryOpacity: Double {
        switch self {
        case .majorPanel: 0.88
        case .dialog: 0.89
        case .export: 0.94
        case .play: 0.92
        case .button: 0.88
        case .menu: 0.88
        case .effectCard: 0.62
        case .semantic: 0.44
        case .trackChip: 0.72
        case .timelineClip: 0.25
        case .sfxSurface: 0.94
        case .sfxClip: 0.96
        case .compactControl: 0.72
        }
    }

    var nearGlowOpacity: Double {
        switch self {
        case .majorPanel: 0.42
        case .dialog: 0.38
        case .export: 0.42
        case .play: 0.42
        case .button: 0.29
        case .menu: 0.30
        case .effectCard: 0.24
        case .semantic: 0.18
        case .trackChip: 0.26
        case .timelineClip: 0.08
        case .sfxSurface: 0.34
        case .sfxClip: 0.34
        case .compactControl: 0.18
        }
    }

    var mediumGlowOpacity: Double {
        switch self {
        case .majorPanel: 0.24
        case .dialog: 0.21
        case .export: 0.24
        case .play: 0.25
        case .button: 0.15
        case .menu: 0.16
        case .effectCard: 0.13
        case .semantic: 0.09
        case .trackChip: 0.12
        case .timelineClip: 0.04
        case .sfxSurface: 0.18
        case .sfxClip: 0.18
        case .compactControl: 0.09
        }
    }

    var ambientGlowOpacity: Double {
        switch self {
        case .majorPanel: 0.13
        case .dialog: 0.10
        case .export: 0.13
        case .play: 0.13
        case .button: 0.075
        case .menu: 0.08
        case .effectCard: 0.065
        case .semantic: 0.045
        case .trackChip: 0.055
        case .timelineClip: 0.018
        case .sfxSurface: 0.085
        case .sfxClip: 0.09
        case .compactControl: 0.045
        }
    }

    var innerHighlightOpacity: Double {
        switch self {
        case .majorPanel, .dialog: 0.24
        case .export, .play: 0.22
        case .button, .menu: 0.16
        case .effectCard, .sfxSurface: 0.14
        case .semantic, .trackChip, .sfxClip: 0.12
        case .compactControl: 0.10
        case .timelineClip: 0.06
        }
    }

    var glowScale: CGFloat {
        switch self {
        case .majorPanel, .dialog, .export: 1
        case .play: 1.14
        case .button, .menu: 0.78
        case .effectCard, .semantic: 0.72
        case .trackChip: 0.58
        case .timelineClip: 0.44
        case .sfxSurface: 0.76
        case .sfxClip: 0.64
        case .compactControl: 0.54
        }
    }

    var tracesDuringActivation: Bool {
        switch self {
        case .timelineClip, .sfxClip, .trackChip: false
        default: true
        }
    }

    var traceDuration: TimeInterval {
        switch self {
        case .majorPanel: PartyModeTokens.traceDurationPanel
        case .dialog: PartyModeTokens.durationAtPartyVelocity(0.88)
        case .export, .play: PartyModeTokens.durationAtPartyVelocity(0.68)
        case .button, .menu, .effectCard, .semantic, .sfxSurface:
            PartyModeTokens.traceDurationButton
        case .compactControl: PartyModeTokens.durationAtPartyVelocity(0.54)
        case .timelineClip, .sfxClip, .trackChip: 0.01
        }
    }

    func activationDelay(for offset: PartyModeGlintOffset) -> TimeInterval {
        let environmentalDelay = PartyModeTokens.delay(for: offset)
        switch self {
        case .majorPanel:
            return environmentalDelay
        case .dialog, .menu:
            return max(0.08, environmentalDelay)
        case .button, .export, .play, .effectCard, .semantic, .sfxSurface:
            return max(0.09, environmentalDelay)
        case .compactControl:
            return max(0.10, environmentalDelay)
        case .timelineClip, .sfxClip, .trackChip:
            return environmentalDelay
        }
    }

    var afterglintDuration: TimeInterval {
        switch self {
        case .majorPanel, .dialog: PartyModeTokens.afterglintDuration
        case .export, .play: PartyModeTokens.durationAtPartyVelocity(0.48)
        case .button, .menu, .effectCard, .semantic, .sfxSurface:
            PartyModeTokens.durationAtPartyVelocity(0.46)
        case .compactControl: PartyModeTokens.durationAtPartyVelocity(0.42)
        case .timelineClip, .sfxClip, .trackChip: 0.01
        }
    }

    var traceIntensity: Double {
        switch self {
        case .majorPanel, .dialog, .export, .play: 1
        case .button, .menu, .sfxSurface: 0.82
        case .effectCard, .semantic: 0.72
        case .compactControl: 0.62
        case .trackChip, .timelineClip, .sfxClip: 0
        }
    }

    var rectangleOverlayCornerRadius: CGFloat {
        switch self {
        case .majorPanel: 12
        case .dialog: 14
        case .export: 12
        case .button: 8
        case .menu: 10
        case .effectCard: 12
        case .semantic: 8
        case .trackChip: 7
        case .timelineClip, .sfxClip: 5
        case .sfxSurface: 9
        case .compactControl, .play: 20
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
        case .counterClockwise: UnitPoint(x: 0.18, y: 1)
        case .coolLeading: .leading
        case .violetTrailing: .bottomLeading
        }
    }

    var endPoint: UnitPoint {
        switch self {
        case .shared: .topTrailing
        case .clockwise: UnitPoint(x: 0.88, y: 0.02)
        case .counterClockwise: UnitPoint(x: 1, y: 0.22)
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
                        .init(color: PartyModeTokens.lavender.opacity(0.90), location: 0),
                        .init(color: PartyModeTokens.violet, location: 0.27),
                        .init(color: PartyModeTokens.glintWhite.opacity(0.98), location: 0.58),
                        .init(color: PartyModeTokens.electricBlue.opacity(0.90), location: 1),
                    ]),
                    startPoint: lighting.startPoint,
                    endPoint: lighting.endPoint
                )
            )
        }

        if let semanticColor {
            return AnyShapeStyle(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: semanticColor.opacity(0.76), location: 0),
                        .init(color: semanticColor, location: 0.32),
                        .init(color: PartyModeTokens.lavender.opacity(0.70), location: 0.57),
                        .init(color: semanticColor.opacity(0.92), location: 1),
                    ]),
                    startPoint: lighting.startPoint,
                    endPoint: lighting.endPoint
                )
            )
        }

        let stops: [Gradient.Stop]
        if role == .compactControl {
            stops = [
                .init(color: PartyModeTokens.coolCyan, location: 0),
                .init(color: PartyModeTokens.electricBlue, location: 0.25),
                .init(color: PartyModeTokens.violet, location: 0.66),
                .init(color: PartyModeTokens.lavender, location: 1),
            ]
        } else {
            stops = [
                .init(color: PartyModeTokens.coolCyan.opacity(0.84), location: 0),
                .init(color: PartyModeTokens.electricBlue, location: 0.20),
                .init(color: PartyModeTokens.lavender.opacity(0.96), location: 0.35),
                .init(color: PartyModeTokens.glintWhite.opacity(0.86), location: 0.39),
                .init(color: PartyModeTokens.lavender.opacity(0.96), location: 0.42),
                .init(color: PartyModeTokens.violet, location: 0.66),
                .init(color: PartyModeTokens.magenta.opacity(0.82), location: 1),
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

private struct PartyModeBorderModifier<S: PartyModeTraceableShape>: ViewModifier {
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
                PartyModePerimeterLayers(
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

private struct PartyModeStaticInsetBorderModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let role: PartyModeSurfaceRole
    let lighting: PartyModeLightingVariant
    let semanticColor: Color?

    @Environment(\.partyModeRenderState) private var renderState
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay {
            if renderState.chromeOpacity > 0.001 {
                PartyModeStaticShapeLayers(
                    shape: shape,
                    role: role,
                    lighting: lighting,
                    semanticColor: semanticColor,
                    opacity: renderState.chromeOpacity * (isEnabled ? 1 : 0.42)
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

    @Environment(\.partyModeRenderState) private var renderState
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay {
            if renderState.chromeOpacity > 0.001 {
                PartyModeStaticShapeLayers(
                    shape: shape,
                    role: role,
                    lighting: lighting,
                    semanticColor: semanticColor,
                    opacity: renderState.chromeOpacity * (isEnabled ? 1 : 0.42)
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct PartyModePerimeterLayers<S: PartyModeTraceableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let lighting: PartyModeLightingVariant
    let semanticColor: Color?
    let glintOffset: PartyModeGlintOffset
    let renderState: PartyModeRenderState
    let isEnabled: Bool

    private var gradient: AnyShapeStyle {
        PartyModeBorderGradient.style(
            role: role,
            lighting: lighting,
            semanticColor: semanticColor
        )
    }

    var body: some View {
        let phase = renderState.animationPhase(for: role, offset: glintOffset)
        let opacity = renderState.chromeOpacity * (isEnabled ? 1 : 0.42)
        let completion = role.tracesDuringActivation
            ? phase.settledBorderOpacity
            : 1

        ZStack {
            PartyModeSettledGlow(
                shape: shape,
                role: role,
                gradient: gradient,
                completion: completion,
                opacity: opacity
            )

            if phase.isTransient && phase.traceProgress > 0 && phase.traceProgress < 1 {
                PartyModeTraceHead(
                    shape: shape,
                    role: role,
                    progress: phase.traceProgress,
                    opacity: opacity
                )
            }

            if phase.isTransient && phase.reconnectFlareProgress > 0 {
                PartyModeReconnectFlare(
                    shape: shape,
                    role: role,
                    progress: phase.reconnectFlareProgress,
                    opacity: opacity
                )
            }

            if phase.isTransient && phase.afterglintProgress > 0 && phase.afterglintProgress < 1 {
                PartyModeAfterglint(
                    shape: shape,
                    role: role,
                    progress: phase.afterglintProgress,
                    opacity: opacity
                )
            }
        }
    }
}

private struct PartyModeSettledGlow<S: InsettableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let gradient: AnyShapeStyle
    let completion: Double
    let opacity: Double

    var body: some View {
        if completion > 0.001 {
            let end = min(1, max(0, CGFloat(completion)))
            let nearRadius = PartyModeTokens.nearGlowRadius * role.glowScale
            let mediumRadius = PartyModeTokens.mediumGlowRadius * role.glowScale
            let ambientRadius = PartyModeTokens.ambientGlowRadius * role.glowScale
            let perimeter = shape.inset(by: role.strokeWidth * 0.5).trim(from: 0, to: end)

            ZStack {
                perimeter
                    .stroke(
                        gradient,
                        lineWidth: role.strokeWidth * PartyModeTokens.ambientGlowStrokeScale
                    )
                    .blur(radius: ambientRadius)
                    .opacity(role.ambientGlowOpacity * opacity)
                    .blendMode(.screen)

                perimeter
                    .stroke(
                        gradient,
                        lineWidth: role.strokeWidth * PartyModeTokens.mediumGlowStrokeScale
                    )
                    .blur(radius: mediumRadius)
                    .opacity(role.mediumGlowOpacity * opacity)
                    .blendMode(.screen)

                perimeter
                    .stroke(
                        gradient,
                        lineWidth: role.strokeWidth * PartyModeTokens.nearGlowStrokeScale
                    )
                    .blur(radius: nearRadius)
                    .opacity(role.nearGlowOpacity * opacity)
                    .blendMode(.screen)

                perimeter
                    .stroke(gradient, lineWidth: role.strokeWidth)
                    .opacity(role.primaryOpacity * opacity)

                perimeter
                    .stroke(
                        PartyModeTokens.glintWhite,
                        lineWidth: PartyModeTokens.innerHighlightWidth
                    )
                    .mask {
                        LinearGradient(
                            colors: [.white, .white.opacity(0.34), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .opacity(role.innerHighlightOpacity * opacity)

                PartyModeCornerCatch(
                    shape: shape,
                    role: role,
                    completion: end,
                    opacity: opacity
                )
            }
        }
    }
}

private struct PartyModeCornerCatch<S: InsettableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let completion: CGFloat
    let opacity: Double

    var body: some View {
        shape
            .inset(by: role.strokeWidth * 0.45)
            .trim(from: 0, to: completion)
            .stroke(PartyModeTokens.glintWhite, lineWidth: 0.78)
            .mask {
                GeometryReader { proxy in
                    let radius = max(18, min(proxy.size.width, proxy.size.height) * 0.72)
                    ZStack {
                        RadialGradient(
                            colors: [.white, .white.opacity(0.42), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: radius
                        )
                        RadialGradient(
                            colors: [.white.opacity(0.78), .white.opacity(0.24), .clear],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: radius * 0.82
                        )
                    }
                }
            }
            .opacity(role.innerHighlightOpacity * 0.92 * opacity)
    }
}

private struct PartyModeTraceHead<S: InsettableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        let insetShape = shape.inset(by: role.strokeWidth * 0.45)
        let trailStart = max(0, progress - PartyModeTokens.traceTrailLength)
        let headStart = max(0, progress - 0.012)
        let intensity = opacity * role.traceIntensity

        ZStack {
            insetShape
                .trim(from: trailStart, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [
                            PartyModeTokens.violet.opacity(0),
                            PartyModeTokens.electricBlue.opacity(0.72),
                            PartyModeTokens.lavender,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.75, lineCap: .round)
                )
                .blur(radius: PartyModeTokens.traceHeadGlowRadius * 0.52)
                .opacity(0.82 * intensity)
                .blendMode(.screen)

            insetShape
                .trim(from: headStart, to: progress)
                .stroke(
                    PartyModeTokens.glintWhite,
                    style: StrokeStyle(
                        lineWidth: PartyModeTokens.traceHeadCoreWidth,
                        lineCap: .round
                    )
                )
                .shadow(
                    color: PartyModeTokens.lavender.opacity(0.92),
                    radius: PartyModeTokens.traceHeadGlowRadius
                )
                .opacity(intensity)
        }
    }
}

private struct PartyModeReconnectFlare<S: PartyModeTraceableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .local).insetBy(
                dx: role.strokeWidth * 0.45,
                dy: role.strokeWidth * 0.45
            )
            let point = shape.startPoint(in: bounds)
            let intensity = Double(progress) * opacity * role.traceIntensity

            ZStack {
                Circle()
                    .fill(PartyModeTokens.violet)
                    .frame(width: 7, height: 7)
                    .blur(radius: 7)
                    .opacity(0.72 * intensity)
                Circle()
                    .fill(PartyModeTokens.lavender)
                    .frame(width: 4.5, height: 4.5)
                    .blur(radius: 2.4)
                    .opacity(0.88 * intensity)
                Circle()
                    .fill(PartyModeTokens.glintWhite)
                    .frame(width: 2.2, height: 2.2)
                    .opacity(intensity)
            }
            .blendMode(.screen)
            .position(point)
        }
    }
}

private struct PartyModeAfterglint<S: InsettableShape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let progress: CGFloat
    let opacity: Double

    private var decay: Double {
        let value = Double(progress)
        if value <= 0.20 {
            return 1 - (value / 0.20) * 0.08
        }
        let tail = min(1, max(0, (value - 0.20) / 0.80))
        return 0.92 * pow(1 - tail, 2.2)
    }

    var body: some View {
        let travel = PartyModeTokens.afterglintTravelPosition(for: progress)
        let trail = PartyModeTokens.afterglintInitialTrail
            + (PartyModeTokens.afterglintFinalTrail - PartyModeTokens.afterglintInitialTrail)
                * pow(progress, 1.18)
        let segments = PartyModeTrimSegments.wrapped(from: travel - trail, to: travel)
        let afterglintHeadSegments = PartyModeTrimSegments.wrapped(
            from: travel - 0.012,
            to: travel
        )
        let glowRadius = 10 + (3 - 10) * progress
        let intensity = opacity * role.traceIntensity * decay
        let insetShape = shape.inset(by: role.strokeWidth * 0.45)

        ZStack {
            ForEach(segments) { segment in
                insetShape
                    .trim(from: segment.from, to: segment.to)
                    .stroke(
                        LinearGradient(
                            colors: [
                                PartyModeTokens.violet.opacity(0),
                                PartyModeTokens.lavender.opacity(0.74),
                                PartyModeTokens.glintWhite,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.65, lineCap: .round)
                    )
                    .shadow(
                        color: PartyModeTokens.lavender.opacity(0.86),
                        radius: glowRadius
                    )
                    .opacity(intensity)
                    .blendMode(.screen)
            }

            ForEach(afterglintHeadSegments) { segment in
                insetShape
                    .trim(from: segment.from, to: segment.to)
                    .stroke(
                        PartyModeTokens.glintWhite,
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round)
                    )
                    .shadow(
                        color: PartyModeTokens.lavender.opacity(0.94),
                        radius: glowRadius * 0.72
                    )
                    .opacity(intensity)
                    .blendMode(.screen)
            }
        }
    }
}

private struct PartyModeStaticShapeLayers<S: Shape>: View {
    let shape: S
    let role: PartyModeSurfaceRole
    let lighting: PartyModeLightingVariant
    let semanticColor: Color?
    let opacity: Double

    private var gradient: AnyShapeStyle {
        PartyModeBorderGradient.style(
            role: role,
            lighting: lighting,
            semanticColor: semanticColor
        )
    }

    var body: some View {
        let nearRadius = PartyModeTokens.nearGlowRadius * role.glowScale
        let mediumRadius = PartyModeTokens.mediumGlowRadius * role.glowScale
        let ambientRadius = PartyModeTokens.ambientGlowRadius * role.glowScale

        ZStack {
            shape
                .stroke(
                    gradient,
                    lineWidth: role.strokeWidth * PartyModeTokens.ambientGlowStrokeScale
                )
                .blur(radius: ambientRadius)
                .opacity(role.ambientGlowOpacity * opacity)
                .blendMode(.screen)
            shape
                .stroke(
                    gradient,
                    lineWidth: role.strokeWidth * PartyModeTokens.mediumGlowStrokeScale
                )
                .blur(radius: mediumRadius)
                .opacity(role.mediumGlowOpacity * opacity)
                .blendMode(.screen)
            shape
                .stroke(
                    gradient,
                    lineWidth: role.strokeWidth * PartyModeTokens.nearGlowStrokeScale
                )
                .blur(radius: nearRadius)
                .opacity(role.nearGlowOpacity * opacity)
                .blendMode(.screen)
            shape
                .stroke(gradient, lineWidth: role.strokeWidth)
                .opacity(role.primaryOpacity * opacity)
            shape
                .stroke(
                    PartyModeTokens.glintWhite,
                    lineWidth: PartyModeTokens.innerHighlightWidth
                )
                .mask {
                    LinearGradient(
                        colors: [.white, .white.opacity(0.30), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .opacity(role.innerHighlightOpacity * opacity)
        }
    }
}

extension View {
    func partyModeBorder(
        shape: Rectangle,
        role: PartyModeSurfaceRole = .button,
        lighting: PartyModeLightingVariant = .shared,
        semanticColor: Color? = nil,
        glintOffset: PartyModeGlintOffset = .none
    ) -> some View {
        modifier(
            PartyModeBorderModifier(
                shape: PartyModeClockwiseRoundedRectangle(
                    cornerRadius: role.rectangleOverlayCornerRadius
                ),
                role: role,
                lighting: lighting,
                semanticColor: semanticColor,
                glintOffset: glintOffset
            )
        )
    }

    func partyModeBorder(
        shape: RoundedRectangle,
        role: PartyModeSurfaceRole = .button,
        lighting: PartyModeLightingVariant = .shared,
        semanticColor: Color? = nil,
        glintOffset: PartyModeGlintOffset = .none
    ) -> some View {
        modifier(
            PartyModeBorderModifier(
                shape: PartyModeClockwiseRoundedRectangle(
                    cornerRadius: shape.cornerSize.width
                ),
                role: role,
                lighting: lighting,
                semanticColor: semanticColor,
                glintOffset: glintOffset
            )
        )
    }

    func partyModeBorder(
        shape: Circle,
        role: PartyModeSurfaceRole = .button,
        lighting: PartyModeLightingVariant = .shared,
        semanticColor: Color? = nil,
        glintOffset: PartyModeGlintOffset = .none
    ) -> some View {
        modifier(
            PartyModeBorderModifier(
                shape: PartyModeClockwiseCircle(),
                role: role,
                lighting: lighting,
                semanticColor: semanticColor,
                glintOffset: glintOffset
            )
        )
    }

    func partyModeBorder<S: InsettableShape>(
        shape: S,
        role: PartyModeSurfaceRole = .button,
        lighting: PartyModeLightingVariant = .shared,
        semanticColor: Color? = nil,
        glintOffset: PartyModeGlintOffset = .none
    ) -> some View {
        modifier(
            PartyModeStaticInsetBorderModifier(
                shape: shape,
                role: role,
                lighting: lighting,
                semanticColor: semanticColor
            )
        )
    }

    /// Party chrome for semantic custom shapes such as timeline clips. These
    /// retain their real outline but intentionally skip the racecar sequence.
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
                semanticColor: semanticColor
            )
        )
    }
}
