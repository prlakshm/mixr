import SwiftUI
import UIKit

/// Sidebar song color chip — matches waveform / track color family.
struct MixrSongColorChip: View {
    let color: MixrWaveformColor
    var artworkData: Data? = nil
    /// Center glyph — the SFX track passes "sparkles".
    var icon: String = "music.note"

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
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 1.5)
        .shadow(color: color.color.opacity(0.28), radius: 5, x: 0, y: 0)
    }

    private var defaultChipContent: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let bright = color.peakColor

        return ZStack {
            shape
                .fill(bright.opacity(0.80))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                bright.opacity(0.96),
                                bright.opacity(0.88),
                                color.color.opacity(0.76),
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
                                color.color.opacity(0.32),
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
}
