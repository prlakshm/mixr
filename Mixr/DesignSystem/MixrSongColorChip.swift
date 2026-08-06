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
    /// Edge length — grows with the track row on roomier screens.
    var size: CGFloat = 34

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    /// Option D — reduced outer glow, crisp edges (SFX chip only).
    private var isReducedGlowChip: Bool { color == .silver }

    @ViewBuilder
    var body: some View {
        if usesSFXMark && artworkData == nil {
            sfxChipContent
        } else {
            standardChip
        }
    }

    private var standardChip: some View {
        Group {
            if let artworkData, let image = UIImage(data: artworkData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                defaultChipContent
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            if isReducedGlowChip {
                // Liquid-glass edge highlights — bright top-left lip, soft secondary rim
                ZStack {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                MixrColors.sfxOutline.opacity(0.88),
                                MixrColors.sfxOutline.opacity(0.38),
                                MixrColors.sfxSecondary.opacity(0.48),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                    // Primary catch — sharp top-left inner rim
                    shape
                        .strokeBorder(Color.white.opacity(0.58), lineWidth: 0.65)
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.55),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: UnitPoint(x: 0.58, y: 0.52)
                            )
                        }
                    // Soft secondary lip — bottom-right (convex glass feel)
                    shape
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        .mask {
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.85)],
                                startPoint: UnitPoint(x: 0.38, y: 0.38),
                                endPoint: .bottomTrailing
                            )
                        }
                    // Darker bottom-right rim catch
                    shape
                        .strokeBorder(Color.black.opacity(0.34), lineWidth: 0.55)
                        .mask {
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.92)],
                                startPoint: UnitPoint(x: 0.4, y: 0.4),
                                endPoint: .bottomTrailing
                            )
                        }
                }
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
        .partyModeBorder(
            shape: shape,
            role: .trackChip,
            lighting: .coolLeading,
            semanticColor: color.color,
            glintOffset: .far
        )
    }

    /// The SFX chip is the same object as an effects-card icon tile, in the SFX
    /// colourway — see `GlassIconTile` in EffectCard.swift, which this mirrors
    /// layer for layer.
    ///
    /// How those tiles actually work: the base is near-opaque black glass
    /// (#111521 → #05070D at 0.96/0.99), and all the colour arrives as *light
    /// trapped inside it* — two radial blooms whose centres sit outside the
    /// tile, one entering the top edge and a brighter one rising from the
    /// bottom, leaving the middle darkest. Over that go a white specular sheen
    /// masked to the top-leading diagonal, a short straight gleam line near the
    /// top, and a rim that runs white → colour → dimmer colour along the same
    /// diagonal. Nothing tints the fill; that is why they read as solid lit
    /// blocks rather than coloured panels, and it is what the chip was missing.
    private var sfxChipContent: some View {
        // The tile is authored at 46pt; every dimension scales from that so the
        // chip is a true miniature rather than an approximation.
        let s = size / EffectCardMetrics.iconTileSize
        let tint = MixrColors.sfxMenuLavender
        let tileShape = sfxTileShape

        return ZStack {
            // The one place this deliberately departs from `GlassIconTile`.
            //
            // That tile carries its base at 0.96/0.99 — effectively opaque —
            // which is fine on an effects card, where the backdrop is flat
            // glass. Here the backdrop is `MixrTrackRowBackground`'s horizontal
            // gradient (#241A39 → #090B13 → #162239), and an opaque black base
            // punches a hole straight through it. Carried at a low opacity
            // instead, the glass darkens and cools whatever the row happens to
            // be doing underneath, so the chip follows the gradient at its own
            // position rather than replacing it.
            tileShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "111521").opacity(0.34),
                            Color(hex: "05070D").opacity(0.52),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Colour entering the top edge.
            tileShape.fill(
                RadialGradient(
                    colors: [
                        tint.opacity(0.60),
                        tint.opacity(0.24),
                        tint.opacity(0.055),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.24, y: -0.08),
                    startRadius: 0,
                    endRadius: size * 0.54
                )
            )

            // The one rising from the bottom. Held back from the tile's own
            // 0.98/0.42/0.11 because the SFX lavender is far lighter than the
            // effect colours (L* 78 vs Echo's 57) — at the authored opacities
            // it blows out to white instead of reading as tint.
            //
            // Seated as the top bloom's reflection: x 0.24 mirrors to 0.76,
            // nudged to 0.78 so the pair is near-symmetric rather than exactly
            // so. This sits just outside the effect tiles' 0.38–0.66 range —
            // deliberate, since those blooms sit under a centred SF Symbol
            // while this one clears a wider, left-weighted stencil.
            tileShape.fill(
                RadialGradient(
                    colors: [
                        tint.opacity(0.60),
                        tint.opacity(0.26),
                        tint.opacity(0.07),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.78, y: 1.02),
                    startRadius: 0,
                    endRadius: size * 0.42
                )
            )

            // Specular sheen along the top-leading diagonal.
            tileShape
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.55 * s)
                .mask {
                    LinearGradient(
                        colors: [.white, .white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            // The straight gleam across the top face.
            Path { path in
                path.move(to: CGPoint(x: size * 0.18, y: size * 0.08))
                path.addLine(to: CGPoint(x: size * 0.78, y: size * 0.08))
            }
            .stroke(
                Color.white.opacity(0.13),
                style: StrokeStyle(lineWidth: 0.8 * s, lineCap: .round)
            )

            // Crisp coloured rim — white at the lit corner, colour through the
            // diagonal, dimmer colour where it turns away.
            tileShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        tint.opacity(0.58),
                        tint.opacity(0.30),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9 * s
            )

            sfxGlyph(tint: tint, scale: s)
        }
        .frame(width: size, height: size)
        .partyModeBorder(
            shape: tileShape,
            role: .trackChip,
            lighting: .counterClockwise,
            semanticColor: MixrColors.sfxGlow,
            glintOffset: .far
        )
    }

    /// Corner radius carried over from the effects tile (12 on 46), so the chip
    /// keeps the family silhouette rather than the sidebar's tighter 7.
    private var sfxTileShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: size * (EffectCardMetrics.iconTileRadius / EffectCardMetrics.iconTileSize),
            style: .continuous
        )
    }


    /// The sfx monogram — deliberately *not* on the effects-tile icon scale.
    ///
    /// This mark is sized against the footer SFX button's stencil
    /// (`MixrSFXOutlineButtonLabel`, ~19.7 × 13.5), so the two SFX entry points
    /// in the timeline read as the same glyph. Driving it from
    /// `EffectCardMetrics.iconSize` instead made it ~19% larger and broke that
    /// pairing. The tile recipe governs the box; the button governs the mark.
    private func sfxGlyph(tint: Color, scale s: CGFloat) -> some View {
        SFXCard.pearlIconFill
            .frame(width: size, height: size)
            .mask {
                MixrSFXMarkGlyph(size: 13 * 0.95 * 0.95 * (size / 34), color: .white)
                    .frame(width: size, height: size)
            }
            // Tight white core plus a soft lavender bloom — the original
            // treatment, kept at its authored radii.
            .shadow(color: Color.white.opacity(0.42), radius: 1.6)
            .shadow(color: Color(hex: "A281BC").opacity(0.35), radius: 2.5)
    }

    private var defaultChipContent: some View {
        let bright = color.peakColor
        let base = color.color
        // Dim highlights ~10% and deepen shadows ~20% so the white icon reads clearer.
        // SFX: prior stack + light +15% for liquid edge; dark +10% for deeper BR rim.
        let light: CGFloat = isReducedGlowChip ? 0.90 * 1.10 * 1.10 * 1.40 * 1.20 * 1.15 : 0.90
        let dark: CGFloat = isReducedGlowChip ? 1.20 * 1.10 * 1.10 * 1.40 * 1.10 * 1.10 : 1.20
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
                                Color.white.opacity((isReducedGlowChip ? 0.20 : 0.15) * light),
                                Color.white.opacity((isReducedGlowChip ? 0.09 : 0.06) * light),
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
                                Color.white.opacity((isReducedGlowChip ? 0.28 : 0.18) * light),
                                bright.opacity((isReducedGlowChip ? 0.14 : 0.10) * light),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.18, y: 0.14),
                            startRadius: 0,
                            endRadius: isReducedGlowChip ? 9 : 10
                        )
                    )
                }
                .overlay {
                    if isReducedGlowChip {
                        // Narrow liquid edge sheen — restrained, not frosted
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.30),
                                    .init(color: Color.white.opacity(0.05), location: 0.38),
                                    .init(color: Color.white.opacity(0.18), location: 0.44),
                                    .init(color: Color.white.opacity(0.05), location: 0.50),
                                    .init(color: .clear, location: 0.60),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                    }
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
                        .strokeBorder(
                            Color.white.opacity((isReducedGlowChip ? 0.28 : 0.14) * light),
                            lineWidth: isReducedGlowChip ? 0.65 : 0.5
                        )
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(isReducedGlowChip ? 0.35 : 0.18),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: UnitPoint(x: 0.55, y: 0.55)
                            )
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    shape
                        .strokeBorder(
                            Color.black.opacity(min(1, (isReducedGlowChip ? 0.22 : 0.18) * dark)),
                            lineWidth: isReducedGlowChip ? 0.55 : 0.45
                        )
                        .mask {
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(min(1, (isReducedGlowChip ? 0.78 : 0.65) * dark)),
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
