import SwiftUI

// MARK: - Bar Style

enum WaveformBarStyle {
    static let width = WaveformMetrics.barWidth
    static let spacing = WaveformMetrics.barSpacing
    static let minHeight = WaveformMetrics.barMinHeight
    static let cornerRadius = WaveformMetrics.barCornerRadius

    static func fill(for waveformColor: MixrWaveformColor) -> LinearGradient {
        MixrGradients.waveformBarFill(for: waveformColor.color)
    }
}

// MARK: - Clip Shape

struct WaveformClipShape: Shape {
    var cornerRadius: CGFloat = WaveformMetrics.cornerRadius
    var tailWidth: CGFloat = WaveformMetrics.tailWidth

    func path(in rect: CGRect) -> Path {
        let height = rect.height
        let radius = min(cornerRadius, height / 2, max(0, (rect.width - tailWidth) / 2))
        let bodyRight = rect.maxX - tailWidth
        let midY = rect.midY

        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: bodyRight - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: bodyRight - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bodyRight, y: midY - radius * 0.4))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        path.addLine(to: CGPoint(x: bodyRight, y: midY + radius * 0.4))
        path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: bodyRight - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Clip Background

struct WaveformClipBackground: View {
    let waveformColor: MixrWaveformColor
    var cornerRadius: CGFloat = WaveformMetrics.cornerRadius
    var tailWidth: CGFloat = WaveformMetrics.tailWidth

    var body: some View {
        WaveformClipShape(cornerRadius: cornerRadius, tailWidth: tailWidth)
            .fill(.ultraThinMaterial)
            .overlay {
                WaveformClipShape(cornerRadius: cornerRadius, tailWidth: tailWidth)
                    .fill(waveformColor.tintColor.opacity(WaveformMetrics.clipOpacity))
            }
            .overlay {
                WaveformClipShape(cornerRadius: cornerRadius, tailWidth: tailWidth)
                    .strokeBorder(
                        waveformColor.color.opacity(0.25),
                        lineWidth: MixrLayout.borderWidth
                    )
            }
    }
}

// MARK: - Fade Overlay

enum WaveformFade {
    static let fraction = WaveformMetrics.fadeFraction

    static func gradient(for color: Color) -> LinearGradient {
        MixrGradients.waveformFade(for: color)
    }

    static func trailingMask(width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(gradient(for: color))
            .frame(width: width * fraction)
    }
}
