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

/// Custom rounded undo/redo mark (gallery Option 4): a long horizontal
/// arrow with the head at the leading edge, whose trailing end wraps down
/// through a perfectly circular rounded turn into a tiny tail.
///
/// The turn is a true arc computed in point space — never a unit-space
/// curve squashed by the glyph's aspect ratio — so it stays smooth at any
/// width/height. Redo is an exact mirror of undo.
struct MixrHistoryArrowShape: Shape {
    enum Direction {
        case undo
        case redo
    }

    var direction: Direction

    func path(in rect: CGRect) -> Path {
        // Inset so round stroke caps stay inside the frame.
        let inset = min(rect.width, rect.height) * 0.08
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let drawW = max(1, rect.width - inset * 2)
        let drawH = max(1, rect.height - inset * 2)

        // Layout — long top bar, circular hook on the trailing side.
        let yTop = minY + drawH * 0.18
        let yBottom = minY + drawH * 0.82
        let radius = (yBottom - yTop) / 2          // true circle, any aspect
        let hookCenterX = maxX - radius
        let tipX = minX + drawW * 0.03
        let tailLength = radius * 0.45             // tiny tail
        let headBack = drawH * 0.30
        let headRise = drawH * 0.26

        var p = Path()

        // Continuous stroke: tip → long bar → circular turn → tiny tail.
        // Every join is tangent-horizontal, so there are no kinks.
        p.move(to: CGPoint(x: tipX, y: yTop))
        p.addLine(to: CGPoint(x: hookCenterX, y: yTop))
        p.addArc(
            center: CGPoint(x: hookCenterX, y: (yTop + yBottom) / 2),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: hookCenterX - tailLength, y: yBottom))

        // Open arrowhead at the leading tip.
        p.move(to: CGPoint(x: tipX + headBack, y: yTop - headRise))
        p.addLine(to: CGPoint(x: tipX, y: yTop))
        p.addLine(to: CGPoint(x: tipX + headBack, y: yTop + headRise))

        if direction == .redo {
            // Mirror about the rect's vertical center line.
            p = p.applying(
                CGAffineTransform(translationX: rect.midX * 2, y: 0)
                    .scaledBy(x: -1, y: 1)
            )
        }

        return p
    }
}

enum MixrHistoryArrowMetrics {
    static let transportGlyphWidth: CGFloat = 32
    static let transportGlyphHeight: CGFloat = 14
}

struct MixrHistoryArrow: View {
    let direction: MixrHistoryArrowShape.Direction
    var width: CGFloat
    var height: CGFloat
    var color: Color = MixrColors.textSecondary

    init(
        direction: MixrHistoryArrowShape.Direction,
        size: CGFloat = 14,
        color: Color = MixrColors.textSecondary
    ) {
        self.direction = direction
        self.width = size
        self.height = size
        self.color = color
    }

    init(
        direction: MixrHistoryArrowShape.Direction,
        width: CGFloat = MixrHistoryArrowMetrics.transportGlyphWidth,
        height: CGFloat = MixrHistoryArrowMetrics.transportGlyphHeight,
        color: Color = MixrColors.textSecondary
    ) {
        self.direction = direction
        self.width = width
        self.height = height
        self.color = color
    }

    private var strokeWidth: CGFloat {
        // Scale stroke with the shorter axis so thinning height keeps
        // weight. Option 4: slightly thicker than the earlier draft.
        max(1.5, min(width, height) * 0.155)
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
