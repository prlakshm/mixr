import SwiftUI

// MARK: - Spacing

enum MixrSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Corner Radius

enum MixrRadius {
    static let glass: CGFloat = 16
    static let button: CGFloat = 12
    static let icon: CGFloat = 20
    static let toggle: CGFloat = 16
    static let waveform: CGFloat = 10
}

// MARK: - Layout

enum MixrLayout {
    static let buttonPaddingH: CGFloat = 16
    static let buttonPaddingV: CGFloat = 10
    static let iconButtonSize: CGFloat = 40
    static let toggleButtonWidth: CGFloat = 32
    static let toggleButtonHeight: CGFloat = 40
    static let trackToggleSize: CGFloat = 28
    static let glassBlurRadius: CGFloat = 24
    static let borderWidth: CGFloat = 1
    static let glassBorderWidth: CGFloat = 0.5
}

// MARK: - Shared Icons

struct MixrChevron: View {
    let direction: Direction
    var size: CGFloat = 10
    var color: Color = MixrColors.textSecondary

    enum Direction {
        case back
        case forward

        var systemName: String {
            switch self {
            case .back:
                "chevron.left"
            case .forward:
                "chevron.right"
            }
        }
    }

    var body: some View {
        Image(systemName: direction.systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }
}

// MARK: - History Arrows (undo / redo)

/// Custom rounded undo/redo mark — the ↶↷ metaphor redrawn to match the
/// transport controls: thicker stroke, smoother curve, round caps, an open
/// rounded arrowhead, and a stub tail that ends right after the U-turn
/// (the SF Symbol's long descender is the reason this exists).
/// Drawn in a 24×24 design grid and scaled to fit; redo mirrors undo.
struct MixrHistoryArrowShape: Shape {
    enum Direction {
        case undo
        case redo
    }

    var direction: Direction

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // Trunk: stub tail → 180° arc over the top → longer arrow leg.
        // Bend radius 5.0 (up from 4.5) — more fluid, matches Mixr's
        // continuous rounded rectangles.
        p.move(to: CGPoint(x: 17.0, y: 13.2))
        p.addLine(to: CGPoint(x: 17.0, y: 10.8))
        p.addArc(
            center: CGPoint(x: 12, y: 10.8),
            radius: 5.0,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: 7.0, y: 15.0))

        // Open arrowhead — ~8% smaller than the bend so it tucks in and
        // the curve stays the visually heaviest element. Round caps.
        p.move(to: CGPoint(x: 4.6, y: 12.95))
        p.addLine(to: CGPoint(x: 7.0, y: 15.5))
        p.addLine(to: CGPoint(x: 9.4, y: 12.95))

        if direction == .redo {
            p = p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: 24, y: 0))
        }

        // Fit the 24×24 design grid into rect (supports wider-than-tall frames).
        let scaleX = rect.width / 24
        let scaleY = rect.height / 24
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scaleX, y: scaleY)
        return p.applying(transform)
    }
}

struct MixrHistoryArrow: View {
    let direction: MixrHistoryArrowShape.Direction
    var width: CGFloat
    var height: CGFloat
    var color: Color = MixrColors.textSecondary

    init(
        direction: MixrHistoryArrowShape.Direction,
        size: CGFloat,
        color: Color = MixrColors.textSecondary
    ) {
        self.direction = direction
        self.width = size
        self.height = size
        self.color = color
    }

    init(
        direction: MixrHistoryArrowShape.Direction,
        width: CGFloat,
        height: CGFloat,
        color: Color = MixrColors.textSecondary
    ) {
        self.direction = direction
        self.width = width
        self.height = height
        self.color = color
    }

    private var strokeWidth: CGFloat {
        // Matched to prior SF Symbol weight at 15.5pt in a 26×15 frame.
        height * (2.39 / 24) * (15.5 / 14)
    }

    var body: some View {
        MixrHistoryArrowShape(direction: direction)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: strokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: width, height: height)
    }
}

// MARK: - Waveform Metrics

enum WaveformMetrics {
    static let height: CGFloat = 48
    static let cornerRadius: CGFloat = MixrRadius.waveform
    static let innerPadding: CGFloat = MixrSpacing.sm
    static let clipOpacity: CGFloat = 0.55
    static let waveformOpacity: CGFloat = 1.0
    static let fadeFraction: CGFloat = 0.15
    static let tailWidth: CGFloat = 28
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 1
    static let barMinHeight: CGFloat = 2
    static let barCornerRadius: CGFloat = 1
}

// MARK: - Shadows

struct MixrShadow {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let color: Color

    static let subtle = MixrShadow(x: 0, y: 1, radius: 2, color: .black.opacity(0.25))
    static let medium = MixrShadow(x: 0, y: 4, radius: 12, color: .black.opacity(0.35))
    static let large = MixrShadow(x: 0, y: 8, radius: 24, color: .black.opacity(0.45))

    // Glass elevation — soft lift, not flat rectangles
    static let glassElevated = MixrShadow(x: 0, y: 6, radius: 20, color: .black.opacity(0.20))
    static let glassStrong = MixrShadow(x: 0, y: 10, radius: 28, color: .black.opacity(0.26))
}

// MARK: - Glows

struct MixrGlow {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let color: Color

    static let purplePrimary = MixrGlow(
        x: 0, y: 0, radius: 30,
        color: MixrColors.primaryPurple.opacity(0.20)
    )
    static let purpleStrong = MixrGlow(
        x: 0, y: 0, radius: 60,
        color: MixrColors.primaryPurple.opacity(0.35)
    )
    static let pinkWaveform = MixrGlow(
        x: 0, y: 0, radius: 30,
        color: MixrColors.waveformPink.opacity(0.20)
    )

    // Restrained glass ambient — lit-from-above, not neon
    static let glassAmbient = MixrGlow(
        x: 0, y: -2, radius: 24,
        color: MixrColors.primaryPurple.opacity(0.07)
    )
    static let glassAmbientStrong = MixrGlow(
        x: 0, y: -2, radius: 32,
        color: MixrColors.primaryPurple.opacity(0.09)
    )

    static func forWaveform(_ waveformColor: MixrWaveformColor) -> MixrGlow {
        MixrGlow(x: 0, y: 0, radius: 8, color: waveformColor.glowColor)
    }
}

// MARK: - View Extensions

extension View {
    func mixrShadow(_ shadow: MixrShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    func mixrGlow(_ glow: MixrGlow) -> some View {
        self.shadow(color: glow.color, radius: glow.radius, x: glow.x, y: glow.y)
    }
}
