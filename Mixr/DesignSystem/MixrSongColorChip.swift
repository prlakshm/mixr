import SwiftUI
import UIKit

/// Sidebar song color chip — matches waveform / track color family.
struct MixrSongColorChip: View {
    let color: MixrWaveformColor
    var artworkData: Data? = nil
    /// Center SF Symbol — ignored when `usesSFXMark` is true.
    var icon: String = "music.note"
    /// When true, shows the AE-stencil sfx monogram instead of `icon`.
    var usesSFXMark: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    /// Option D — reduced outer glow, crisp edges (SFX chip only).
    private var isReducedGlowChip: Bool { color == .silver }

    var body: some View {
        Group {
            if let artworkData, let image = UIImage(data: artworkData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                defaultChipContent
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(shape)
        .overlay {
            if isReducedGlowChip {
                shape.strokeBorder(
                    MixrColors.sfxOutline.opacity(0.58),
                    lineWidth: 0.65
                )
            } else {
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            }
        }
        .shadow(
            color: .black.opacity(isReducedGlowChip ? 0.30 : 0.24),
            radius: isReducedGlowChip ? 2 : 3,
            x: 0,
            y: isReducedGlowChip ? 1 : 1.5
        )
        .shadow(
            color: isReducedGlowChip
                ? MixrColors.sfxGlow.opacity(0.10)
                : color.color.opacity(0.28),
            radius: isReducedGlowChip ? 2 : 5,
            x: 0,
            y: 0
        )
    }

    private var defaultChipContent: some View {
        let bright = color.peakColor
        let base = color.color
        // Dim highlights ~10% and deepen shadows ~20% so the white icon reads clearer.
        // SFX: light +10% twice; dark +10% twice for dimension.
        let light: CGFloat = isReducedGlowChip ? 0.90 * 1.10 * 1.10 : 0.90
        let dark: CGFloat = isReducedGlowChip ? 1.20 * 1.10 * 1.10 : 1.20
        // SFX option D — pull back body bloom so edges read crisp, not hazy.
        let bloomScale: CGFloat = isReducedGlowChip ? 0.72 : 1.0

        return ZStack {
            shape
                .fill(bright.opacity(0.80 * light))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                bright.opacity(0.96 * light),
                                bright.opacity(0.88 * light),
                                base.opacity(0.76 * light),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [
                                bright.opacity(0.68 * light * bloomScale),
                                base.opacity(0.32 * light * bloomScale),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.42, y: 0.38),
                            startRadius: 0,
                            endRadius: isReducedGlowChip ? 16 : 22
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15 * light),
                                Color.white.opacity(0.06 * light),
                                Color.clear,
                                Color.clear,
                            ],
                            startPoint: UnitPoint(x: 0.02, y: 0.0),
                            endPoint: UnitPoint(x: 0.58, y: 0.48)
                        )
                    )
                    .mask {
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.55),
                                Color.clear,
                            ],
                            startPoint: UnitPoint(x: 0.08, y: 0.0),
                            endPoint: UnitPoint(x: 0.62, y: 0.52)
                        )
                    }
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.18 * light),
                                bright.opacity(0.10 * light),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.18, y: 0.14),
                            startRadius: 0,
                            endRadius: 10
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(min(1, 0.12 * dark)),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay(alignment: .topLeading) {
                    shape
                        .strokeBorder(Color.white.opacity(0.14 * light), lineWidth: 0.5)
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.18),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: UnitPoint(x: 0.55, y: 0.55)
                            )
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    shape
                        .strokeBorder(Color.black.opacity(min(1, 0.18 * dark)), lineWidth: 0.45)
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(min(1, 0.65 * dark)),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                }

            if !isReducedGlowChip {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                bright.opacity(0.50 * light),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .frame(width: 14, height: 14)
                    .blur(radius: 1.5)
            }

            if usesSFXMark {
                MixrSFXMarkGlyph(size: 13 * 0.95 * 0.95, color: .white)
                    .shadow(
                        color: isReducedGlowChip
                            ? .clear
                            : bright.opacity(0.60 * light),
                        radius: isReducedGlowChip ? 0 : 3
                    )
                    .shadow(color: .black.opacity(min(1, 0.18 * dark)), radius: 0.5, x: 0, y: 0.5)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .shadow(color: bright.opacity(0.60 * light), radius: 3)
                    .shadow(color: .black.opacity(min(1, 0.18 * dark)), radius: 0.5, x: 0, y: 0.5)
            }
        }
    }
}
