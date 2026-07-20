import SwiftUI

// MARK: - Silhouette Style

enum WaveformSilhouetteStyle {
    /// Samples per point — high density for a continuous filled shape.
    static let samplesPerPoint: CGFloat = 4.25
    static let maxFill: CGFloat = 0.86
    static let minAmplitude: CGFloat = 0.05
    static let maxAmplitude: CGFloat = 0.98
    static let smoothingRadius: Int = 1

    static func glowColor(for waveformColor: MixrWaveformColor) -> Color {
        waveformColor.glowColor
    }
}

// MARK: - Mock Amplitude Data

enum WaveformMockData {
    static func amplitudes(count: Int, seed: Int) -> [CGFloat] {
        guard count > 0 else { return [] }

        let raw = (0..<count).map { index -> CGFloat in
            let progress = Double(index) / Double(max(count - 1, 1))
            let phase = progress * .pi * 2 * 30 + Double(seed) * 0.61

            var sample = 0.0
            sample += abs(sin(phase * 1.1 + Double(seed))) * 0.18
            sample += abs(sin(phase * 2.9 + 1.2)) * 0.16
            sample += abs(sin(phase * 6.4 + 2.1)) * 0.14
            sample += abs(sin(phase * 13.2 + 0.9)) * 0.11
            sample += abs(sin(phase * 24.8 + Double(seed) * 0.3)) * 0.08
            sample += pseudoNoise(index: index, seed: seed) * 0.32

            let spikeRoll = pseudoNoise(index: index * 5 + 17, seed: seed + 11)
            if spikeRoll > 0.80 {
                sample += (spikeRoll - 0.80) * 2.4
            }

            let valleyRoll = pseudoNoise(index: index * 7 + 3, seed: seed + 29)
            if valleyRoll < 0.14 {
                sample *= valleyRoll / 0.14
            }

            let attack = min(1.0, progress * 8.0)
            let tailStart = 0.91
            let tailTaper = progress > tailStart
                ? 1.0 - ((progress - tailStart) / (1.0 - tailStart))
                : 1.0
            let envelope = attack * max(0.10, tailTaper)

            let blended = sample * envelope
            let shaped = pow(min(1.0, max(0, blended)), 1.15)
            let scaled = WaveformSilhouetteStyle.minAmplitude
                + shaped * (WaveformSilhouetteStyle.maxAmplitude - WaveformSilhouetteStyle.minAmplitude)

            return CGFloat(scaled)
        }

        return smooth(raw, radius: WaveformSilhouetteStyle.smoothingRadius)
    }

    static func sampleCount(for width: CGFloat) -> Int {
        let drawable = max(0, width - WaveformMetrics.innerPadding * 2)
        return max(2, Int(drawable * WaveformSilhouetteStyle.samplesPerPoint))
    }

    private static func pseudoNoise(index: Int, seed: Int) -> Double {
        let value = sin(Double(index * 12_989 + seed * 78_233)) * 43_758.5453
        return value - floor(value)
    }

    private static func smooth(_ values: [CGFloat], radius: Int) -> [CGFloat] {
        guard radius > 0, values.count > 2 else { return values }

        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            let slice = values[lower...upper]
            return slice.reduce(0, +) / CGFloat(slice.count)
        }
    }
}

// MARK: - Silhouette Path

enum WaveformSilhouettePath {
    static func build(
        amplitudes: [CGFloat],
        size: CGSize,
        padding: CGFloat = WaveformMetrics.innerPadding,
        tailWidth: CGFloat = WaveformMetrics.tailWidth
    ) -> Path {
        let count = amplitudes.count
        guard count >= 2 else { return Path() }

        let centerY = size.height / 2
        let maxHalfHeight = (size.height - padding * 2) / 2 * WaveformSilhouetteStyle.maxFill
        let tailInset = tailWidth * 0.35
        let drawableWidth = max(1, size.width - padding * 2 - tailInset)

        func xPosition(for index: Int) -> CGFloat {
            padding + drawableWidth * CGFloat(index) / CGFloat(count - 1)
        }

        func halfHeight(for index: Int) -> CGFloat {
            maxHalfHeight * amplitudes[index]
        }

        var path = Path()

        path.move(to: CGPoint(x: xPosition(for: 0), y: centerY - halfHeight(for: 0)))

        for index in 1..<count {
            path.addLine(to: CGPoint(
                x: xPosition(for: index),
                y: centerY - halfHeight(for: index)
            ))
        }

        for index in stride(from: count - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(
                x: xPosition(for: index),
                y: centerY + halfHeight(for: index)
            ))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Clip Shape

/// Rounded rectangle clip container.
struct WaveformClipShape: Shape {
    var cornerRadius: CGFloat = WaveformMetrics.cornerRadius
    var tailWidth: CGFloat    = WaveformMetrics.tailWidth

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)
    }
}

// MARK: - Tail Guide Lines

/// Faint triangular guide lines drawn inside the rounded tail region.
struct WaveformWedgeShape: Shape {
    var tailWidth: CGFloat = WaveformMetrics.tailWidth

    func path(in rect: CGRect) -> Path {
        let tailStart = rect.maxX - tailWidth
        let tipX      = rect.maxX - 2
        let mid       = rect.midY

        var path = Path()

        path.move(to: CGPoint(x: tailStart, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: tailStart, y: rect.maxY - 1))

        path.move(to: CGPoint(x: tailStart, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: tipX, y: mid))

        path.move(to: CGPoint(x: tailStart, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: tipX, y: mid))

        return path
    }
}

// MARK: - Clip Background

struct WaveformClipBackground: View {
    let waveformColor: MixrWaveformColor
    var cornerRadius: CGFloat = WaveformMetrics.cornerRadius
    var tailWidth: CGFloat = WaveformMetrics.tailWidth

    var body: some View {
        let shape = WaveformClipShape(cornerRadius: cornerRadius, tailWidth: tailWidth)

        // Layer 1 — dark navy base through material
        shape
            .fill(MixrColors.glassClipNavy)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.22)
                    .environment(\.colorScheme, .dark)
            }
            // Layer 2 — strong color tint (this is the primary background hue)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            waveformColor.tintColor,
                            waveformColor == .silver
                                ? MixrColors.sfxClipInnerTint.opacity(0.076)
                                : waveformColor.color.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            // Layer 3 — slight top-down depth darkening
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color.clear,
                            Color.black.opacity(0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                WaveformClipGridLines()
                    .clipShape(shape)
            }
            // Border — color-matched
            .overlay {
                shape.stroke(
                    waveformColor.outlineColor,
                    lineWidth: MixrLayout.glassBorderWidth
                )
            }
    }
}

// MARK: - Grid Lines

private struct WaveformClipGridLines: View {
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            Canvas { context, size in
                let centerY = size.height / 2
                let lineColor = Color.white.opacity(0.04)

                for offset in [-0.28, 0, 0.28] {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: centerY + height * offset * 0.5))
                    path.addLine(to: CGPoint(x: size.width, y: centerY + height * offset * 0.5))
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                }
            }
        }
    }
}

// MARK: - Silhouette Canvas

struct WaveformSilhouetteCanvas: View {
    let waveformColor: MixrWaveformColor
    let amplitudes: [CGFloat]
    var tailWidth: CGFloat = WaveformMetrics.tailWidth

    var body: some View {
        Canvas { context, size in
            let silhouette = WaveformSilhouettePath.build(
                amplitudes: amplitudes,
                size: size,
                tailWidth: tailWidth
            )
            let peakColor = waveformColor.peakColor
            let baseColor = waveformColor.color

            let waveformGradient = waveformColor == .silver
                ? Gradient(colors: [
                    MixrColors.sfxWaveformTop,
                    MixrColors.sfxWaveformBottom,
                ])
                : Gradient(colors: [
                    peakColor.opacity(0.94),
                    baseColor,
                    peakColor,
                ])

            context.fill(silhouette, with: .linearGradient(
                waveformGradient,
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))

            context.drawLayer { layer in
                let glowColor = waveformColor == .silver
                    ? MixrColors.sfxWaveformGlow.opacity(0.08)
                    : baseColor.opacity(0.38)
                let highlightColor = waveformColor == .silver
                    ? MixrColors.sfxWaveformTop.opacity(0.08)
                    : peakColor.opacity(0.20)

                layer.addFilter(.shadow(color: glowColor, radius: 2.5, x: 0, y: 0))
                layer.fill(silhouette, with: .color(highlightColor))
            }
        }
        .opacity(WaveformMetrics.waveformOpacity * waveformColor.waveformOpacity)
    }
}

// MARK: - Fade Mask

enum WaveformFade {
    static let fraction: CGFloat = 0.06

    static func gradient(for color: Color) -> LinearGradient {
        MixrGradients.waveformFade(for: color)
    }

    static func mask(width: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.95),
                .init(color: .white.opacity(0.78), location: 0.985),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
