import SwiftUI

struct WaveformClip: View {
    let waveformColor: MixrWaveformColor
    var amplitudes: [CGFloat]?
    var height: CGFloat = WaveformMetrics.height

    var body: some View {
        GeometryReader { geometry in
            let size    = geometry.size
            let samples = resolvedAmplitudes(for: size.width)
            let shape   = WaveformClipShape(tailWidth: WaveformMetrics.tailWidth)
            let wedge   = WaveformWedgeShape(tailWidth: WaveformMetrics.tailWidth)

            ZStack {
                WaveformClipBackground(waveformColor: waveformColor)
                WaveformSilhouetteCanvas(waveformColor: waveformColor, amplitudes: samples)
            }
            .clipShape(shape)
            .mask { Rectangle().fill(WaveformFade.mask(width: size.width)) }
            // Subtle tail guide lines inside the rounded clip.
            .overlay {
                wedge
                    .stroke(waveformColor.color.opacity(0.34), lineWidth: 0.75)
            }
            // Main clip border
            .overlay {
                shape.stroke(
                    waveformColor.color.opacity(0.38),
                    lineWidth: MixrLayout.glassBorderWidth
                )
            }
        }
        .frame(height: height)
        // Tight, restrained glow — close to clip surface only
        .shadow(
            color: WaveformSilhouetteStyle.glowColor(for: waveformColor),
            radius: 4,
            x: 0,
            y: 0
        )
    }

    private func resolvedAmplitudes(for width: CGFloat) -> [CGFloat] {
        let count = WaveformMockData.sampleCount(for: width)
        if let amplitudes, amplitudes.count >= count {
            return Array(amplitudes.prefix(count))
        }
        return WaveformMockData.amplitudes(count: count, seed: waveformColor.seed)
    }
}

// MARK: - Seed

private extension MixrWaveformColor {
    var seed: Int {
        switch self {
        case .pink:   1
        case .purple: 2
        case .red:    3
        case .yellow: 4
        case .blue:   5
        case .silver: 6
        }
    }
}

#Preview("Waveform Clips") {
    ScrollView {
        VStack(alignment: .leading, spacing: MixrSpacing.lg) {
            ForEach(MixrWaveformColor.allCases) { color in
                WaveformClip(waveformColor: color)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(MixrSpacing.lg)
    }
    .background {
        ZStack {
            MixrGradients.backgroundLinear
            MixrGradients.backgroundRadial
        }
    }
}
