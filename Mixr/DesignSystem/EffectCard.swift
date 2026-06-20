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

    var lighting: EffectLightingLayout {
        switch self {
        case .reverb:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.55, y: 0.54),
                orbCenter:  CGPoint(x: 0.65, y: 0.46),
                dotCenter:  CGPoint(x: 0.73, y: 0.34)
            )
        case .echo:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.53, y: 0.55),
                orbCenter:  CGPoint(x: 0.63, y: 0.48),
                dotCenter:  CGPoint(x: 0.71, y: 0.35)
            )
        case .bassBoost:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.56, y: 0.52),
                orbCenter:  CGPoint(x: 0.66, y: 0.44),
                dotCenter:  CGPoint(x: 0.74, y: 0.32)
            )
        case .pitchUp:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.54, y: 0.53),
                orbCenter:  CGPoint(x: 0.64, y: 0.47),
                dotCenter:  CGPoint(x: 0.72, y: 0.33)
            )
        case .flanger:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.55, y: 0.52),
                orbCenter:  CGPoint(x: 0.65, y: 0.45),
                dotCenter:  CGPoint(x: 0.73, y: 0.33)
            )
        case .chorus:
            EffectLightingLayout(
                blobCenter: CGPoint(x: 0.53, y: 0.54),
                orbCenter:  CGPoint(x: 0.63, y: 0.47),
                dotCenter:  CGPoint(x: 0.71, y: 0.34)
            )
        }
    }
}

struct EffectLightingLayout {
    let blobCenter: CGPoint   // large soft glow
    let orbCenter:  CGPoint   // medium visible orb
    let dotCenter:  CGPoint   // small bright dot
}

// MARK: - Layout

enum EffectCardMetrics {
    static let width: CGFloat          = 152
    static let height: CGFloat         = 62
    static let cornerRadius: CGFloat   = 11
    static let inset: CGFloat          = 11
    static let iconTileSize: CGFloat   = 40
    static let iconTileRadius: CGFloat = 10
    static let iconSize: CGFloat       = 16
    static let titleGap: CGFloat       = 8
    static let glassBubbleSize: CGFloat    = 12
    static let reflectionArcSize: CGFloat  = 19
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
            RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? effect.color.opacity(0.45) : MixrColors.glassBorderDefault,
                    lineWidth: isSelected ? 0.8 : MixrLayout.glassBorderWidth
                )
        }
        .shadow(
            color: effect.color.opacity(isSelected ? 0.18 : 0.07),
            radius: isSelected ? 9 : 4,
            x: 0,
            y: 1
        )
    }

    private var cardBackground: some View {
        GlassBackground(level: .strong, cornerRadius: EffectCardMetrics.cornerRadius)
    }

    // Subtle colored bloom throughout the card interior
    private var cardBloom: some View {
        RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        effect.color.opacity(0.07),
                        effect.color.opacity(0),
                    ],
                    center: UnitPoint(x: 0.68, y: 0.5),
                    startRadius: 0,
                    endRadius: 70
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
                .padding(.top, 2)
        }
        .padding(.leading, EffectCardMetrics.inset)
        .padding(.top, EffectCardMetrics.inset - 1)
    }

    private var glassBubbleDecoration: some View {
        GeometryReader { geo in
            let bx = geo.size.width  - 14
            let by = geo.size.height - 13

            ZStack {
                // Arc behind the bubble
                EffectReflectionArc()
                    .stroke(
                        Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                    )
                    .frame(
                        width: EffectCardMetrics.reflectionArcSize,
                        height: EffectCardMetrics.reflectionArcSize
                    )
                    .shadow(color: Color.white.opacity(0.12), radius: 2)
                    .position(x: bx + 2, y: by)

                // Glass marble
                GlassMarble()
                    .position(x: bx, y: by)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Glass Icon Tile

private struct GlassIconTile: View {
    let effect: MixrEffect

    var body: some View {
        let r     = EffectCardMetrics.iconTileRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let size  = EffectCardMetrics.iconTileSize

        ZStack {
            // Base: near-black dark glass
            shape
                .fill(Color(hex: "07090F").opacity(0.96))

            // Very faint color bleed — top-leading only
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            effect.color.opacity(0.10),
                            effect.color.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Diagonal specular glass reflection
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0),
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.65, y: 0.65)
                    )
                )

            // Colored bloom behind the icon — the color source
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(0.60),
                            effect.color.opacity(0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.36
                    )
                )
                .blur(radius: 4.5)

            // Thin colored border
            shape.strokeBorder(effect.color.opacity(0.28), lineWidth: 0.6)

            // Icon — bright, color-saturated, with bloom
            Image(systemName: effect.icon)
                .font(.system(size: EffectCardMetrics.iconSize, weight: .medium))
                .foregroundStyle(effect.color)
                .shadow(color: effect.color.opacity(0.85), radius: 5)
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
                .fill(Color.black.opacity(0.45))
                .frame(width: s + 2, height: s + 2)
                .blur(radius: 1)

            // Base sphere — bright white
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.78),
                        ],
                        center: UnitPoint(x: 0.45, y: 0.40),
                        startRadius: 0,
                        endRadius: s * 0.55
                    )
                )
                .frame(width: s, height: s)
                .shadow(color: .black.opacity(0.40), radius: 2.5, x: 0, y: 1.5)

            // Top-left specular glint — small, sharp
            Circle()
                .fill(Color.white)
                .frame(width: s * 0.28, height: s * 0.28)
                .offset(x: -(s * 0.20), y: -(s * 0.20))
                .blur(radius: 0.3)
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Lighting Layer

private struct EffectLightingLayer: View {
    let effect: MixrEffect
    var isSelected: Bool

    private var color: Color { effect.color }
    private var layout: EffectLightingLayout { effect.lighting }
    private var boost: Double { isSelected ? 1.15 : 1.0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Large soft glow blob — wide ambient spread, low blur radius for definition
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                color.opacity(0.52 * boost),
                                color.opacity(0.20 * boost),
                                color.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .frame(width: 30, height: 30)
                    .blur(radius: 5)
                    .position(
                        x: geo.size.width  * layout.blobCenter.x,
                        y: geo.size.height * layout.blobCenter.y
                    )

                // 2. Medium orb — clearly visible floating bubble
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                color.opacity(0.88 * boost),
                                color.opacity(0.42 * boost),
                                color.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 7
                        )
                    )
                    .frame(width: 14, height: 14)
                    .blur(radius: 1.0)
                    .position(
                        x: geo.size.width  * layout.orbCenter.x,
                        y: geo.size.height * layout.orbCenter.y
                    )

                // 3. Small bright dot — sharp punctuation
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: color.opacity(0.80), radius: 3)
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
