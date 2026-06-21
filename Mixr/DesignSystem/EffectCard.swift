import SwiftUI

// MARK: - Effect Model

enum MixrEffect: String, CaseIterable, Identifiable {
    case auto
    case reverb
    case echo
    case bassBoost
    case pitchUp
    case warmth
    case chorus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .reverb: "Reverb"
        case .echo: "Echo"
        case .bassBoost: "Bass Boost"
        case .pitchUp: "Pitch Up"
        case .warmth: "Warmth"
        case .chorus: "Chorus"
        }
    }

    var subtitle: String? {
        switch self {
        default: nil
        }
    }

    var color: Color {
        switch self {
        case .auto: MixrColors.primaryPurple
        case .reverb: Color(hex: "0EA5E9")
        case .echo: MixrColors.waveformPurple
        case .bassBoost: MixrColors.waveformYellow
        case .pitchUp: MixrColors.waveformPink
        case .warmth: MixrColors.waveformRed
        case .chorus: Color(hex: "F97316")
        }
    }

    var icon: String {
        switch self {
        case .auto: "sparkles"
        case .reverb: "water.waves"
        case .echo: "wind"
        case .bassBoost: "bolt.fill"
        case .pitchUp: "star.fill"
        case .warmth: "flame.fill"
        case .chorus: "drop.fill"
        }
    }

    var iconScale: CGFloat {
        switch self {
        case .warmth: 0.95
        default: 1.0
        }
    }

    var iconGlow: EffectIconGlowLayout {
        switch self {
        case .auto:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.18, y: -0.08),
                bottomCenter: UnitPoint(x: 0.66, y: 1.02)
            )
        case .reverb:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.22, y: -0.08),
                bottomCenter: UnitPoint(x: 0.38, y: 1.02)
            )
        case .echo:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.64, y: -0.07),
                bottomCenter: UnitPoint(x: 0.42, y: 1.04)
            )
        case .bassBoost:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.24, y: -0.06),
                bottomCenter: UnitPoint(x: 0.42, y: 1.03)
            )
        case .pitchUp:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.36, y: -0.10),
                bottomCenter: UnitPoint(x: 0.62, y: 1.00)
            )
        case .warmth:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.22, y: -0.08),
                bottomCenter: UnitPoint(x: 0.56, y: 1.02)
            )
        case .chorus:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.22, y: -0.07),
                bottomCenter: UnitPoint(x: 0.42, y: 1.04)
            )
        }
    }

    var lighting: EffectLightingLayout {
        switch self {
        case .auto:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.47, y: 0.66),
                orbCenter:  CGPoint(x: 0.62, y: 0.43),
                dotCenter:  CGPoint(x: 0.72, y: 0.28),
                blobSize: 24,
                orbSize: 11,
                dotSize: 3.8,
                intensity: 0.80
            )
        case .reverb:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.48, y: 0.65),
                orbCenter:  CGPoint(x: 0.60, y: 0.48),
                dotCenter:  CGPoint(x: 0.67, y: 0.35),
                blobSize: 25,
                orbSize: 11,
                dotSize: 3.8,
                intensity: 0.82
            )
        case .echo:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.46, y: 0.70),
                orbCenter:  CGPoint(x: 0.64, y: 0.45),
                dotCenter:  CGPoint(x: 0.72, y: 0.31),
                blobSize: 22,
                orbSize: 12,
                dotSize: 4.2,
                intensity: 0.76
            )
        case .bassBoost:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.43, y: 0.67),
                orbCenter:  CGPoint(x: 0.56, y: 0.40),
                dotCenter:  CGPoint(x: 0.63, y: 0.30),
                blobSize: 24,
                orbSize: 10,
                dotSize: 3.4,
                intensity: 0.74
            )
        case .pitchUp:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.42, y: 0.68),
                orbCenter:  CGPoint(x: 0.56, y: 0.42),
                dotCenter:  CGPoint(x: 0.64, y: 0.30),
                blobSize: 23,
                orbSize: 11,
                dotSize: 3.7,
                intensity: 0.78
            )
        case .warmth:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.44, y: 0.64),
                orbCenter:  CGPoint(x: 0.58, y: 0.43),
                dotCenter:  CGPoint(x: 0.66, y: 0.32),
                blobSize: 21,
                orbSize: 10.5,
                dotSize: 3.6,
                intensity: 0.72
            )
        case .chorus:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.45, y: 0.66),
                orbCenter:  CGPoint(x: 0.57, y: 0.42),
                dotCenter:  CGPoint(x: 0.64, y: 0.31),
                blobSize: 24,
                orbSize: 10,
                dotSize: 3.5,
                intensity: 0.74
            )
        }
    }
}

struct EffectIconGlowLayout {
    let topCenter: UnitPoint
    let bottomCenter: UnitPoint
}

struct EffectLightingLayout {
    let blobCenter: CGPoint   // large soft glow
    let orbCenter:  CGPoint   // medium visible orb
    let dotCenter:  CGPoint   // small bright dot
    let blobSize: CGFloat
    let orbSize: CGFloat
    let dotSize: CGFloat
    let intensity: Double
}

// MARK: - Layout

enum EffectCardMetrics {
    static let width: CGFloat          = 152
    static let height: CGFloat         = 66
    static let cornerRadius: CGFloat   = 11
    static let inset: CGFloat          = 10
    static let iconTileSize: CGFloat   = 46
    static let iconTileRadius: CGFloat = 12
    static let iconSize: CGFloat       = 22
    static let titleGap: CGFloat       = 9
    static let glassBubbleSize: CGFloat    = 13
    static let reflectionArcSize: CGFloat  = 28
}

// MARK: - Effect Card

struct EffectCard: View {
    let effect: MixrEffect
    var isSelected: Bool = false

    @State private var isHovered = false

    private var isAuto: Bool { effect == .auto }
    private var needsHigherActiveContrast: Bool { effect == .auto || effect == .echo }
    private var isActive: Bool { isSelected || isHovered }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            cardBloom
            EffectLightingLayer(effect: effect, isSelected: isActive)
            foregroundContent
            glassBubbleDecoration
        }
        .frame(width: EffectCardMetrics.width, height: EffectCardMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous))
        .overlay {
            EffectCardBorderGlow(effect: effect, isSelected: isActive)
        }
        .background {
            EffectCardSpillGlow(effect: effect, isActive: isActive)
        }
        .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        .shadow(
            color: effect.color.opacity(isActive ? (needsHigherActiveContrast ? 0.33 : 0.264) : (isAuto ? 0.08 : 0.07)),
            radius: isActive ? (needsHigherActiveContrast ? 13.2 : 11) : 5,
            x: 0,
            y: 0
        )
        .contentShape(RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    private var cardBackground: some View {
        EffectCardGlassBackground(effect: effect, isSelected: isActive)
    }

    @ViewBuilder
    private var cardBloom: some View {
        if isAuto {
            AutoIridescentBloom()
        } else {
            RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(isActive ? (effect == .echo ? 0.16 : 0.10) : 0.045),
                            effect.color.opacity(0),
                        ],
                        center: UnitPoint(x: 0.78, y: 0.48),
                        startRadius: 0,
                        endRadius: 90
                    )
                )
        }
    }

    private var foregroundContent: some View {
        HStack(alignment: .top, spacing: EffectCardMetrics.titleGap) {
            GlassIconTile(effect: effect)
            VStack(alignment: .leading, spacing: 1) {
                Text(effect.title)
                    .mixrFont(.metadata)
                    .fontWeight(.semibold)
                    .foregroundStyle(MixrColors.textPrimary)
                    .lineLimit(1)

                if let subtitle = effect.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary.opacity(0.92))
                        .lineLimit(1)
                }
            }
            .padding(.top, effect.subtitle == nil ? 3 : 1)
        }
        .padding(.leading, EffectCardMetrics.inset)
        .padding(.top, EffectCardMetrics.inset - 1)
    }

    private var glassBubbleDecoration: some View {
        GeometryReader { geo in
            let bx = geo.size.width  - 24
            let by = geo.size.height - 15

            ZStack {
                ClearGlassBubble()
                    .frame(
                        width: EffectCardMetrics.reflectionArcSize,
                        height: EffectCardMetrics.reflectionArcSize
                    )
                    .position(x: bx + 7, y: by - 1)

                EffectReflectionArc()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                effect.color.opacity(0.18),
                                Color.white.opacity(0.03),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                    )
                    .frame(
                        width: EffectCardMetrics.reflectionArcSize,
                        height: EffectCardMetrics.reflectionArcSize
                    )
                    .shadow(color: effect.color.opacity(0.10), radius: 2)
                    .position(x: bx + 7, y: by - 1)

                GlassMarble()
                    .position(x: bx, y: by)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Effect Card Glass

private struct AutoIridescentBloom: View {
    var body: some View {
        RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "A78BFA").opacity(0.20),
                        Color(hex: "A78BFA").opacity(0.055),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.26, y: 0.24),
                    startRadius: 0,
                    endRadius: 86
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                MixrColors.waveformPink.opacity(0.20),
                                MixrColors.waveformPink.opacity(0.050),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.18, y: 0.96),
                            startRadius: 0,
                            endRadius: 76
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                MixrColors.waveformYellow.opacity(0.14),
                                MixrColors.waveformYellow.opacity(0.035),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.92, y: 0.92),
                            startRadius: 0,
                            endRadius: 68
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "38BDF8").opacity(0.17),
                                Color(hex: "38BDF8").opacity(0.045),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.96, y: 0.14),
                            startRadius: 0,
                            endRadius: 82
                        )
                    )
            }
    }
}

private struct EffectCardGlassBackground: View {
    let effect: MixrEffect
    var isSelected: Bool

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)

        if effect == .auto {
            shape
                .fill(Color(hex: "05070D").opacity(0.34))
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.015)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.075),
                                Color(hex: "A78BFA").opacity(0.020),
                                Color.black.opacity(0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "38BDF8").opacity(0.045),
                                Color.clear,
                                MixrColors.waveformPink.opacity(0.050),
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.045),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.15, y: 0.04),
                            startRadius: 0,
                            endRadius: 72
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.45)
                }
        } else {
            shape
                .fill(Color(hex: "05070D").opacity(0.56))
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.04)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.075),
                                Color.white.opacity(0.016),
                                Color.black.opacity(0.18),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                effect.color.opacity(isSelected ? 0.10 : 0.035),
                                Color.clear,
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.18, y: 0.04),
                            startRadius: 0,
                            endRadius: 82
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.045), lineWidth: 0.45)
                }
        }
    }
}

private struct EffectCardSpillGlow: View {
    let effect: MixrEffect
    var isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius + 8, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(isActive ? 0.154 : 0),
                            effect.color.opacity(isActive ? 0.061 : 0),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.52, y: 0.60),
                        startRadius: 0,
                        endRadius: 92
                    )
                )
                .frame(width: EffectCardMetrics.width + 48, height: EffectCardMetrics.height + 18)
                .blur(radius: 11)

            RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius + 5, style: .continuous)
                .stroke(effect.color.opacity(isActive ? 0.132 : 0), lineWidth: 0.8)
                .frame(width: EffectCardMetrics.width + 28, height: EffectCardMetrics.height + 10)
                .blur(radius: 5)
        }
        .allowsHitTesting(false)
    }
}

private struct EffectCardBorderGlow: View {
    let effect: MixrEffect
    var isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)

        ZStack {
            // Fine perimeter rim: every card should read as polished glass, not a flat pane.
            shape.strokeBorder(
                Color.white.opacity(isSelected ? 0.11 : 0.075),
                lineWidth: isSelected ? 0.72 : 0.55
            )

            if effect == .auto {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hex: "38BDF8").opacity(isSelected ? 0.44 : 0.20),
                            Color(hex: "A78BFA").opacity(isSelected ? 0.36 : 0.18),
                            MixrColors.waveformPink.opacity(isSelected ? 0.46 : 0.20),
                            MixrColors.waveformYellow.opacity(isSelected ? 0.38 : 0.15),
                            Color.white.opacity(isSelected ? 0.20 : 0.10),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    lineWidth: isSelected ? 0.62 : 0.40
                )

                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            MixrColors.waveformPink.opacity(isSelected ? 0.42 : 0.16),
                            MixrColors.waveformYellow.opacity(isSelected ? 0.36 : 0.12),
                            Color(hex: "38BDF8").opacity(isSelected ? 0.30 : 0.12),
                            Color.clear,
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    lineWidth: isSelected ? 0.72 : 0.36
                )

                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(hex: "38BDF8").opacity(isSelected ? 0.32 : 0.10),
                            MixrColors.waveformYellow.opacity(isSelected ? 0.26 : 0.08),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: isSelected ? 0.48 : 0.28
                )
            }

            // Glass catchlight along the top/upper-left rim.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.28 : 0.20),
                        Color.white.opacity(isSelected ? 0.11 : 0.075),
                        Color.white.opacity(0.018),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected ? 0.90 : 0.72
            )

            // Uniform low-edge reflection, like a real glass shelf catching light.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(isSelected ? 0.055 : 0.04),
                        effect.color.opacity(isSelected ? (effect == .auto ? 0.16 : 0.34) : 0.16),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: isSelected ? 0.82 : 0.62
            )

            // Colored lower/side rim, like the reference cards' glowing outlines.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        effect.color.opacity(isSelected ? (effect == .auto ? 0.18 : 0.72) : 0.32),
                        effect.color.opacity(isSelected ? (effect == .auto ? 0.14 : 0.44) : 0.16),
                        effect.color.opacity(isSelected ? (effect == .auto ? 0.06 : 0.12) : 0.04),
                        Color.clear,
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ),
                lineWidth: isSelected ? 1.28 : 0.72
            )

            // Thin full outline keeps selection legible without flattening the glass edge.
            shape.strokeBorder(effect.color.opacity(isSelected ? (effect == .auto ? 0.12 : 0.24) : 0.10), lineWidth: isSelected ? 0.64 : 0.48)

            if isSelected, effect == .echo {
                shape.strokeBorder(effect.color.opacity(0.28), lineWidth: 0.88)
                    .blur(radius: 0.55)
                    .mask {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.88),
                                Color.clear,
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    }
            }

            // Soft halo concentrated where the glass catches color most strongly.
            shape.strokeBorder(effect.color.opacity(isSelected ? (effect == .auto ? 0.26 : 0.55) : 0.14), lineWidth: isSelected ? 1.45 : 1.05)
                .blur(radius: isSelected ? 1.25 : 0.9)
                .mask {
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(isSelected ? 0.42 : 0),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.02, y: 0.98),
                        startRadius: 0,
                        endRadius: 128
                    )
                }
        }
    }
}

// MARK: - Glass Icon Tile

private struct GlassIconTile: View {
    let effect: MixrEffect

    var body: some View {
        let r     = EffectCardMetrics.iconTileRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let size  = EffectCardMetrics.iconTileSize
        let glow  = effect.iconGlow

        ZStack {
            // Clean transparent glass base: dark, glossy, not frosted.
            shape
                .fill(
                    LinearGradient(
                        colors: effect == .auto
                            ? [
                                Color(hex: "111521").opacity(0.72),
                                Color(hex: "05070D").opacity(0.90),
                            ]
                            : [
                                Color(hex: "111521").opacity(0.96),
                                Color(hex: "05070D").opacity(0.99),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Medium color glow from the top edge.
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(0.60),
                            effect.color.opacity(0.24),
                            effect.color.opacity(0.055),
                            Color.clear,
                        ],
                        center: glow.topCenter,
                        startRadius: 0,
                        endRadius: size * 0.54
                    )
                )

            // More vibrant glow rising from the bottom of the glass.
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(0.98),
                            effect.color.opacity(0.42),
                            effect.color.opacity(0.11),
                            Color.clear,
                        ],
                        center: glow.bottomCenter,
                        startRadius: 0,
                        endRadius: size * 0.42
                    )
                )

            if effect == .auto {
                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                MixrColors.waveformPink.opacity(0.42),
                                MixrColors.waveformPink.opacity(0.12),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.88, y: 0.92),
                            startRadius: 0,
                            endRadius: size * 0.42
                        )
                    )

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "38BDF8").opacity(0.28),
                                Color(hex: "38BDF8").opacity(0.08),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.08, y: 0.12),
                            startRadius: 0,
                            endRadius: size * 0.54
                        )
                    )

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                MixrColors.waveformYellow.opacity(0.22),
                                MixrColors.waveformYellow.opacity(0.06),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.70, y: 1.02),
                            startRadius: 0,
                            endRadius: size * 0.42
                        )
                    )
            }

            // Crisp glass highlights: thin, clean reflections instead of a cloudy slab.
            shape
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.55)
                .mask {
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.15),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            Path { path in
                path.move(to: CGPoint(x: size * 0.18, y: size * 0.08))
                path.addLine(to: CGPoint(x: size * 0.78, y: size * 0.08))
            }
            .stroke(Color.white.opacity(0.13), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))

            // Crisp colored rim
            shape.strokeBorder(
                LinearGradient(
                    colors: effect == .auto
                        ? [
                            Color.white.opacity(0.22),
                            Color(hex: "C084FC").opacity(0.64),
                            MixrColors.waveformPink.opacity(0.52),
                            MixrColors.waveformYellow.opacity(0.36),
                            Color(hex: "38BDF8").opacity(0.48),
                        ]
                        : [
                            Color.white.opacity(0.12),
                            effect.color.opacity(0.58),
                            effect.color.opacity(0.30),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )

            // Icon — bright, color-saturated, with bloom
            Image(systemName: effect.icon)
                .font(.system(size: EffectCardMetrics.iconSize, weight: .semibold))
                .scaleEffect(effect.iconScale)
                .foregroundStyle(effect == .auto ? Color.white : effect.color)
                .shadow(color: (effect == .auto ? Color(hex: "F5D0FE") : effect.color).opacity(1.0), radius: 4)
                .shadow(color: (effect == .auto ? Color(hex: "C084FC") : effect.color).opacity(0.55), radius: 9)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Glass Marble

private struct GlassMarble: View {
    var body: some View {
        let s = EffectCardMetrics.glassBubbleSize

        ZStack {
            // Dark rim / outer shadow ring
            Circle()
                .fill(Color.black.opacity(0.52))
                .frame(width: s + 3, height: s + 3)
                .blur(radius: 0.8)

            // Base sphere — bright white
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.88),
                            Color.white.opacity(0.78),
                        ],
                        center: UnitPoint(x: 0.45, y: 0.40),
                        startRadius: 0,
                        endRadius: s * 0.55
                    )
                )
                .frame(width: s, height: s)
                .shadow(color: .black.opacity(0.50), radius: 3, x: 0, y: 1.5)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.6)
                }

            // Top-left specular glint — small, sharp
            Circle()
                .fill(Color.white)
                .frame(width: s * 0.24, height: s * 0.24)
                .offset(x: -(s * 0.20), y: -(s * 0.20))
                .blur(radius: 0.3)
        }
        .frame(width: s, height: s)
    }
}

private struct ClearGlassBubble: View {
    var body: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.055),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .background {
                Circle()
                    .fill(Color.white.opacity(0.018))
            }
            .shadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Lighting Layer

private struct EffectLightingLayer: View {
    let effect: MixrEffect
    var isSelected: Bool

    private var color: Color { effect.color }
    private var layout: EffectLightingLayout { effect.lighting }
    private var boost: Double { (isSelected ? 1.0 : 0.82) * layout.intensity }

    @ViewBuilder
    var body: some View {
        if effect == .auto {
            AutoIridescentParticles()
                .allowsHitTesting(false)
        } else {
            GeometryReader { geo in
                ZStack {
                // 1. Large card bubble, softer than the icon tile glows.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.055 * boost),
                                color.opacity(0.26 * boost),
                                color.opacity(0.08 * boost),
                                color.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 15
                        )
                    )
                    .frame(width: layout.blobSize, height: layout.blobSize)
                    .blur(radius: 2.4)
                    .position(
                        x: geo.size.width  * layout.blobCenter.x,
                        y: geo.size.height * layout.blobCenter.y
                    )

                // 2. Medium floating bubble with restrained color.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.18 * boost),
                                color.opacity(0.50 * boost),
                                color.opacity(0.14 * boost),
                                color.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 6.5
                        )
                    )
                    .frame(width: layout.orbSize, height: layout.orbSize)
                    .blur(radius: 0.55)
                    .position(
                        x: geo.size.width  * layout.orbCenter.x,
                        y: geo.size.height * layout.orbCenter.y
                    )

                // 3. Small bright dot — sharp punctuation
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                color,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 3.5
                        )
                    )
                    .frame(width: layout.dotSize, height: layout.dotSize)
                    .shadow(color: color.opacity(0.55), radius: 2.5)
                    .position(
                        x: geo.size.width  * layout.dotCenter.x,
                        y: geo.size.height * layout.dotCenter.y
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct AutoIridescentParticles: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                AutoLightParticle(
                    color: MixrColors.waveformPink,
                    size: 6.2,
                    blur: 0.85,
                    opacity: 0.60
                )
                .position(x: geo.size.width * 0.62, y: geo.size.height * 0.43)

                AutoLightParticle(
                    color: Color(hex: "38BDF8"),
                    size: 3.8,
                    blur: 0.45,
                    opacity: 0.54
                )
                .position(x: geo.size.width * 0.76, y: geo.size.height * 0.24)

                AutoLightParticle(
                    color: Color(hex: "A78BFA"),
                    size: 9.0,
                    blur: 1.85,
                    opacity: 0.34
                )
                .position(x: geo.size.width * 0.52, y: geo.size.height * 0.67)
            }
        }
    }
}

private struct AutoLightParticle: View {
    let color: Color
    let size: CGFloat
    let blur: CGFloat
    let opacity: Double

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(opacity * 0.55),
                        color.opacity(opacity),
                        color.opacity(0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blur)
            .shadow(color: color.opacity(opacity * 0.7), radius: size * 0.55)
    }
}

// MARK: - Reflection Arc

private struct EffectReflectionArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: .degrees(195),
            endAngle: .degrees(345),
            clockwise: false
        )
        return path
    }
}

#Preview("Effect Cards") {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MixrSpacing.sm) {
            ForEach(MixrEffect.allCases) { effect in
                EffectCard(
                    effect: effect,
                    isSelected: false
                )
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
