import SwiftUI

struct WaveformClip: View {
    let waveformColor: MixrWaveformColor
    var amplitudes: [CGFloat]?
    var height: CGFloat = WaveformMetrics.height
    /// Selection only affects SFX specular intensity; song tracks ignore this.
    var isSelected: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let size    = geometry.size
            let samples = resolvedAmplitudes(for: size.width)
            let shape   = WaveformClipShape(tailWidth: WaveformMetrics.tailWidth)
            let wedge   = WaveformWedgeShape(tailWidth: WaveformMetrics.tailWidth)
            let isSFX   = waveformColor == .silver

            ZStack {
                WaveformClipBackground(
                    waveformColor: waveformColor,
                    isSelected: isSelected
                )
                WaveformSilhouetteCanvas(waveformColor: waveformColor, amplitudes: samples)
            }
            .clipShape(shape)
            .mask { Rectangle().fill(WaveformFade.mask(width: size.width)) }
            // Subtle tail guide lines inside the rounded clip.
            .overlay {
                wedge
                    .stroke(
                        isSFX
                            ? MixrColors.sfxSecondary.opacity(0.42)
                            : waveformColor.color.opacity(0.34),
                        lineWidth: 0.75
                    )
            }
            // Outer rim — metallic gradient for SFX; flat color for songs.
            .overlay {
                if isSFX {
                    shape.stroke(
                        isSelected
                            ? MixrWaveformColor.sfxMetallicOutlineSelected
                            : MixrWaveformColor.sfxMetallicOutline,
                        lineWidth: isSelected ? 1.05 : 0.9
                    )
                } else {
                    shape.stroke(
                        waveformColor.outlineColor,
                        lineWidth: MixrLayout.glassBorderWidth
                    )
                }
            }
        }
        .frame(height: height)
        // Tight, restrained glow — same affordance for every track color.
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
            Text("SFX selected")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary)
            WaveformClip(waveformColor: .silver, isSelected: true)
                .frame(maxWidth: .infinity)
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
