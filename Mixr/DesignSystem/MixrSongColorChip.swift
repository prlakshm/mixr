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

    var body: some View {
        Group {
            if let artworkData, let image = UIImage(data: artworkData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if color == .silver {
                silverChipContent
            } else {
                songChipContent
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(shape)
        .overlay {
            if color == .silver {
                shape.strokeBorder(
                    MixrColors.sfxChipOutline.opacity(0.72),
                    lineWidth: 0.65
                )
            } else {
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 1.5)
        .shadow(
            color: color == .silver
                ? MixrColors.sfxChipOutline.opacity(0.12)
                : color.color.opacity(0.28),
            radius: color == .silver ? 3 : 5,
            x: 0,
            y: 0
        )
    }

    // MARK: - Song colors (unchanged)

    private var songChipContent: some View {
        let bright = color.peakColor
        let base = color.color

        return ZStack {
            shape
                .fill(bright.opacity(0.80))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                bright.opacity(0.96),
                                bright.opacity(0.88),
                                base.opacity(0.76),
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
                                bright.opacity(0.68),
                                base.opacity(0.32),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.42, y: 0.38),
                            startRadius: 0,
                            endRadius: 22
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.06),
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
                                Color.white.opacity(0.18),
                                bright.opacity(0.10),
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
                                Color.black.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay(alignment: .topLeading) {
                    shape
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
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
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.45)
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.65),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            bright.opacity(0.50),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .blur(radius: 1.5)

            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(color: bright.opacity(0.60), radius: 3)
                .shadow(color: .black.opacity(0.18), radius: 0.5, x: 0, y: 0.5)
        }
    }

    // MARK: - SFX silver — dimensional metallic, darker center for white icon

    private var silverChipContent: some View {
        ZStack {
            // Vertical 3-stop metallic body — light / graphite / light
            shape.fill(
                LinearGradient(
                    colors: [
                        MixrColors.sfxChipTop.opacity(0.92),
                        MixrColors.sfxChipCenter.opacity(0.88),
                        MixrColors.sfxChipBottom.opacity(0.90),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Soft top specular — edges stay brighter than center
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.06),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.42)
                )
            )

            // Inner shadow for machined depth
            shape
                .strokeBorder(Color.black.opacity(0.28), lineWidth: 1.1)
                .blur(radius: 1.2)
                .offset(y: 0.8)
                .mask(shape)

            // Top-edge rim catch
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            MixrColors.sfxChipOutline.opacity(0.55),
                            MixrColors.sfxChipOutline.opacity(0.08),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.55
                )
                .mask {
                    LinearGradient(
                        colors: [Color.white, Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }

            // Soft darker localized backdrop behind the icon (no hard shape)
            RadialGradient(
                colors: [
                    MixrColors.sfxChipIconBackdrop.opacity(0.55),
                    MixrColors.sfxChipIconBackdrop.opacity(0.18),
                    Color.clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 13
            )
            .frame(width: 26, height: 26)
            .blur(radius: 2.2)
            .allowsHitTesting(false)

            if usesSFXMark {
                MixrSFXMarkGlyph(size: 13, color: .white)
                    .shadow(color: .black.opacity(0.35), radius: 1.2, y: 0.6)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.2, y: 0.6)
            }
        }
    }
}
