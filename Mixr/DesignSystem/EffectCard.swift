import SwiftUI

// MARK: - Effect Model

enum MixrEffect: String, CaseIterable, Identifiable {
    case reverb
    case echo
    case bassBoost
    case pitchUp
    case flanger
    case chorus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reverb: "Reverb"
        case .echo: "Echo"
        case .bassBoost: "Bass Boost"
        case .pitchUp: "Pitch Up"
        case .flanger: "Flanger"
        case .chorus: "Chorus"
        }
    }

    var color: Color {
        switch self {
        case .reverb: Color(hex: "0EA5E9")
        case .echo: MixrColors.waveformPurple
        case .bassBoost: MixrColors.waveformYellow
        case .pitchUp: MixrColors.waveformPink
        case .flanger: MixrColors.waveformRed
        case .chorus: Color(hex: "F97316")
        }
    }

    var icon: String {
        switch self {
        case .reverb: "water.waves"
        case .echo: "wind"
        case .bassBoost: "bolt.fill"
        case .pitchUp: "star.fill"
        case .flanger: "flame.fill"
        case .chorus: "drop.fill"
        }
    }

    var iconGlow: EffectIconGlowLayout {
        switch self {
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
        case .flanger:
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
        case .flanger:
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            cardBloom
            EffectLightingLayer(effect: effect, isSelected: isSelected)
            foregroundContent
            glassBubbleDecoration
        }
        .frame(width: EffectCardMetrics.width, height: EffectCardMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous))
        .overlay {
            EffectCardBorderGlow(effect: effect, isSelected: isSelected)
        }
        .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        .shadow(
            color: effect.color.opacity(isSelected ? 0.22 : 0.08),
            radius: isSelected ? 10 : 5,
            x: 0,
            y: 0
        )
    }

    private var cardBackground: some View {
        EffectCardGlassBackground(effect: effect, isSelected: isSelected)
    }

    private var cardBloom: some View {
        RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        effect.color.opacity(isSelected ? 0.10 : 0.045),
                        effect.color.opacity(0),
                    ],
                    center: UnitPoint(x: 0.78, y: 0.48),
                    startRadius: 0,
                    endRadius: 90
                )
            )
    }

    private var foregroundContent: some View {
        HStack(alignment: .top, spacing: EffectCardMetrics.titleGap) {
            GlassIconTile(effect: effect)
            Text(effect.title)
                .mixrFont(.metadata)
                .fontWeight(.semibold)
                .foregroundStyle(MixrColors.textPrimary)
                .lineLimit(1)
                .padding(.top, 3)
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

private struct EffectCardGlassBackground: View {
    let effect: MixrEffect
    var isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)

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

private struct EffectCardBorderGlow: View {
    let effect: MixrEffect
    var isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)

        ZStack {
            // Fine perimeter rim: every card should read as polished glass, not a flat pane.
            shape.strokeBorder(Color.white.opacity(isSelected ? 0.10 : 0.075), lineWidth: isSelected ? 0.65 : 0.55)

            // Glass catchlight along the top/upper-left rim.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.26 : 0.20),
                        Color.white.opacity(isSelected ? 0.10 : 0.075),
                        Color.white.opacity(0.018),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected ? 0.9 : 0.72
            )

            // Uniform low-edge reflection, like a real glass shelf catching light.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(isSelected ? 0.055 : 0.04),
                        effect.color.opacity(isSelected ? 0.34 : 0.16),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: isSelected ? 0.85 : 0.62
            )

            // Colored lower/side rim, like the reference cards' glowing outlines.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        effect.color.opacity(isSelected ? 1.0 : 0.32),
                        effect.color.opacity(isSelected ? 0.72 : 0.16),
                        effect.color.opacity(isSelected ? 0.18 : 0.04),
                        Color.clear,
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ),
                lineWidth: isSelected ? 1.45 : 0.72
            )

            // Thin full outline keeps selection legible without flattening the glass edge.
            shape.strokeBorder(effect.color.opacity(isSelected ? 0.30 : 0.10), lineWidth: isSelected ? 0.72 : 0.48)

            // Soft halo concentrated where the glass catches color most strongly.
            shape.strokeBorder(effect.color.opacity(isSelected ? 0.76 : 0.14), lineWidth: isSelected ? 1.7 : 1.05)
                .blur(radius: isSelected ? 1.55 : 0.9)
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
                        colors: [
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
                    colors: [
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
                .foregroundStyle(effect.color)
                .shadow(color: effect.color.opacity(1.0), radius: 4)
                .shadow(color: effect.color.opacity(0.55), radius: 9)
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

    var body: some View {
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
                    isSelected: effect == .reverb
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
