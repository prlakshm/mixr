import SwiftUI

// MARK: - Effect Model

enum MixrEffect: String, CaseIterable, Identifiable {
    case auto
    case reverb
    case echo
    case pitchUp
    case blur
    case bassBoost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .reverb: "Reverb"
        case .echo: "Echo"
        case .pitchUp: "Pitch Up"
        case .blur: "Blur"
        case .bassBoost: "Bass Boost"
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
        case .pitchUp: MixrColors.waveformPink
        case .blur: MixrColors.waveformRed
        case .bassBoost: MixrColors.waveformYellow
        }
    }

    var icon: String {
        switch self {
        case .auto: "sparkles"
        case .reverb: "water.waves"
        case .echo: "wind"
        case .pitchUp: "star.fill"
        case .blur: "drop.fill"
        case .bassBoost: "bolt.fill"
        }
    }

    /// Non-Auto effects expose a 0–100 level slider per clip.
    var isAdjustable: Bool { self != .auto }

    var iconScale: CGFloat {
        1.0
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
        case .pitchUp:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.36, y: -0.10),
                bottomCenter: UnitPoint(x: 0.62, y: 1.00)
            )
        case .blur:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.22, y: -0.08),
                bottomCenter: UnitPoint(x: 0.56, y: 1.02)
            )
        case .bassBoost:
            EffectIconGlowLayout(
                topCenter: UnitPoint(x: 0.24, y: -0.06),
                bottomCenter: UnitPoint(x: 0.42, y: 1.03)
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
        default:
            EffectLightingLayout.standard(for: self)
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

    // Shared cluster geometry — blob lower-left → orb mid → dot upper-right.
    private static let baseBlob = CGPoint(x: 0.44, y: 0.67)
    private static let baseOrb  = CGPoint(x: 0.58, y: 0.43)
    private static let baseDot  = CGPoint(x: 0.74, y: 0.40)

    /// Tiered nudge: cluster shift plus per-bubble horizontal spread.
    private struct Tier {
        let cluster: CGPoint
        let blobSpreadX: CGFloat
        let orbSpreadX: CGFloat
        let dotSpreadX: CGFloat
    }

    private static let tiers: [MixrEffect: Tier] = [
        .reverb:    Tier(cluster: CGPoint(x:  0.04, y:  0.02), blobSpreadX: -0.03, orbSpreadX:  0.02, dotSpreadX: 0.04),
        .echo:      Tier(cluster: CGPoint(x: -0.03, y:  0.05), blobSpreadX: -0.02, orbSpreadX:  0.04, dotSpreadX: 0.05),
        .pitchUp:   Tier(cluster: CGPoint(x: -0.06, y:  0.03), blobSpreadX:  0.04, orbSpreadX:  0.03, dotSpreadX: 0.06),
        .blur:      Tier(cluster: CGPoint(x:  0.01, y: -0.01), blobSpreadX:  0.02, orbSpreadX:  0.03, dotSpreadX: 0.04),
        .bassBoost: Tier(cluster: CGPoint(x: -0.05, y:  0.02), blobSpreadX:  0.03, orbSpreadX:  0.01, dotSpreadX: 0.07),
    ]

    static func standard(for effect: MixrEffect) -> EffectLightingLayout {
        let tier = tiers[effect] ?? Tier(cluster: .zero, blobSpreadX: 0, orbSpreadX: 0, dotSpreadX: 0)
        let metrics = metrics(for: effect)

        let blob = clampBlob(
            baseBlob + tier.cluster + CGPoint(x: tier.blobSpreadX, y: 0),
            blobSize: metrics.blobSize
        )
        let orb = clamp(
            baseOrb + tier.cluster + CGPoint(x: tier.orbSpreadX, y: 0),
            radius: metrics.orbSize * 0.5 + 2
        )
        let dot = clampDot(
            baseDot + tier.cluster + CGPoint(x: tier.dotSpreadX, y: 0),
            radius: metrics.dotSize * 0.5 + 3
        )

        return EffectLightingLayout(
            blobCenter: blob,
            orbCenter: orb,
            dotCenter: dot,
            blobSize: metrics.blobSize,
            orbSize: metrics.orbSize,
            dotSize: metrics.dotSize,
            intensity: metrics.intensity
        )
    }

    private static func metrics(for effect: MixrEffect) -> (blobSize: CGFloat, orbSize: CGFloat, dotSize: CGFloat, intensity: Double) {
        switch effect {
        case .reverb:    (25, 11,   3.8, 0.82)
        case .echo:      (22, 12,   4.2, 0.76)
        case .pitchUp:   (23, 11,   3.7, 0.78)
        case .blur:      (21, 10.5, 3.6, 0.72)
        case .bassBoost: (24, 10,   3.4, 0.74)
        default:         (24, 11,   3.8, 0.76)
        }
    }

    private static func clamp(_ point: CGPoint, radius: CGFloat) -> CGPoint {
        let marginX = radius / EffectCardMetrics.width
        let marginY = radius / EffectCardMetrics.height
        return CGPoint(
            x: min(max(point.x, marginX), 1 - marginX),
            y: min(max(point.y, marginY), 1 - marginY)
        )
    }

    /// Nudges the bottom blob slightly right when it would be heavily clipped by the icon tile.
    private static func clampBlob(_ point: CGPoint, blobSize: CGFloat) -> CGPoint {
        let radius = blobSize * 0.5 + 4
        let clamped = clamp(point, radius: radius)

        let cardW = EffectCardMetrics.width
        var centerX = clamped.x * cardW
        let leftEdge = centerX - radius

        let iconTrailing = EffectCardMetrics.iconTileTrailingX
        let allowedOverlap: CGFloat = 14
        let maxNudge: CGFloat = 12

        if leftEdge < iconTrailing - allowedOverlap {
            let deficit = (iconTrailing - allowedOverlap) - leftEdge
            centerX += min(deficit, maxNudge)
        }

        let marginX = radius / cardW
        let x = min(max(centerX / cardW, marginX), 1 - marginX)
        return CGPoint(x: x, y: clamped.y)
    }

    /// Keeps the accent dot below headings and inset from card edges.
    private static func clampDot(_ point: CGPoint, radius: CGFloat) -> CGPoint {
        let clamped = clamp(point, radius: radius)
        return CGPoint(
            x: min(max(clamped.x, 0.72), 0.86),
            y: min(max(clamped.y, 0.38), 0.72)
        )
    }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
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
    static let titleFontSize: CGFloat  = 11
    static let titleGap: CGFloat       = 9
    static let glassBubbleSize: CGFloat    = 13
    static let reflectionArcSize: CGFloat  = 28

    /// Icon tile occupies the leading foreground — keep blobs out of this rect.
    static var iconTileTrailingX: CGFloat { inset + iconTileSize }
    static var iconTileBottomY: CGFloat { (inset - 1) + iconTileSize }
}

// MARK: - Selected Glow Tuning

private enum EffectSelectedGlow {
    static func multiplier(for effect: MixrEffect) -> Double {
        switch effect {
        case .echo: 1.10
        case .reverb: 1.08
        case .auto: 1.20
        default: 1.0
        }
    }
}

/// Softens resting (unselected) glow for effects that read too bright at idle.
private enum EffectUnselectedGlow {
    static func multiplier(for effect: MixrEffect) -> Double {
        switch effect {
        case .pitchUp: 0.855
        case .bassBoost: 0.7695 // −5% then −10% then −10%
        case .blur: 0.9025 // −5% then −5%
        default: 1.0
        }
    }
}

/// Extra pullback on the symbol bloom inside the icon tile.
private enum EffectIconGlow {
    static func multiplier(for effect: MixrEffect) -> Double {
        switch effect {
        case .pitchUp: 0.90
        case .blur: 0.95
        case .bassBoost: 0.95
        default: 1.0
        }
    }
}

/// Colored card-rim intensity (yellow / red / pink outlines).
private enum EffectRimGlow {
    static func multiplier(for effect: MixrEffect) -> Double {
        switch effect {
        case .bassBoost: 0.81225 // −10% then −5% then −5%
        case .blur: 0.9025 // −5% then −5%
        case .pitchUp: 0.9025 // −5% then −5%
        default: 1.0
        }
    }
}

// MARK: - Effect Card

struct EffectCard: View {
    let effect: MixrEffect
    var isSelected: Bool = false

    @State private var isHovered = false

    private var isAuto: Bool { effect == .auto }
    private var isActive: Bool { isSelected || isHovered }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            cardBloom
            EffectLightingLayer(effect: effect, isSelected: isActive)
            foregroundContent
                .zIndex(1)
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
            color: effect.color.opacity(activeShadowOpacity),
            radius: activeShadowRadius,
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

    private var activeShadowOpacity: Double {
        guard isActive else {
            return (isAuto ? 0.08 : 0.07) * EffectUnselectedGlow.multiplier(for: effect)
        }

        let boost = EffectSelectedGlow.multiplier(for: effect)
        switch effect {
        case .auto:
            return 0.46 * boost
        case .echo:
            return 0.40 * boost
        case .reverb:
            return 0.32 * boost
        default:
            return 0.264
        }
    }

    private var activeShadowRadius: CGFloat {
        guard isActive else { return 5 }

        let boost = CGFloat(EffectSelectedGlow.multiplier(for: effect))
        switch effect {
        case .auto:
            return 15 * boost
        case .echo:
            return 14 * boost
        case .reverb:
            return 12.5 * boost
        default:
            return 11
        }
    }

    private var cardBackground: some View {
        EffectCardGlassBackground(effect: effect, isSelected: isActive)
    }

    @ViewBuilder
    private var cardBloom: some View {
        if isAuto {
            AutoIridescentBloom(isSelected: isActive)
        } else {
            RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(cardBloomOpacity),
                            effect.color.opacity(0),
                        ],
                        center: UnitPoint(x: 0.78, y: 0.48),
                        startRadius: 0,
                        endRadius: 90
                    )
                )
        }
    }

    private var cardBloomOpacity: Double {
        guard isActive else {
            return 0.045 * EffectUnselectedGlow.multiplier(for: effect)
        }

        let boost = EffectSelectedGlow.multiplier(for: effect)
        switch effect {
        case .reverb:
            return 0.12 * boost
        case .echo:
            return 0.19 * boost
        default:
            return 0.10
        }
    }

    private var foregroundContent: some View {
        HStack(alignment: .top, spacing: EffectCardMetrics.titleGap) {
            GlassIconTile(effect: effect, isSelected: isActive)
            VStack(alignment: .leading, spacing: 1) {
                Text(effect.title)
                    .font(.system(size: EffectCardMetrics.titleFontSize, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                    .lineLimit(1)

                if let subtitle = effect.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary.opacity(0.92))
                        .lineLimit(1)
                }
            }
            .padding(.top, effect.subtitle == nil ? 5 : 3)
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
    var isSelected: Bool

    private var selectedBoost: Double { isSelected ? 1.4 * EffectSelectedGlow.multiplier(for: .auto) : 1.0 }

    var body: some View {
        RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "A78BFA").opacity(0.225 * selectedBoost),
                        Color(hex: "A78BFA").opacity(0.062 * selectedBoost),
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
                                MixrColors.waveformPink.opacity(0.225 * selectedBoost),
                                MixrColors.waveformPink.opacity(0.056 * selectedBoost),
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
                                MixrColors.waveformYellow.opacity(0.16 * selectedBoost),
                                MixrColors.waveformYellow.opacity(0.040 * selectedBoost),
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
                                Color(hex: "38BDF8").opacity(0.19 * selectedBoost),
                                Color(hex: "38BDF8").opacity(0.050 * selectedBoost),
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
                                effect.color.opacity(isSelected ? 0.10 : 0.035 * EffectUnselectedGlow.multiplier(for: effect)),
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

    private var intensity: Double {
        guard isActive else { return 0 }

        switch effect {
        case .auto:
            return 1.4 * EffectSelectedGlow.multiplier(for: .auto)
        case .reverb:
            return 1.2 * EffectSelectedGlow.multiplier(for: .reverb)
        case .echo:
            return 1.2 * EffectSelectedGlow.multiplier(for: .echo)
        default:
            return 1.0
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius + 8, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            effect.color.opacity(0.154 * intensity),
                            effect.color.opacity(0.061 * intensity),
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
                .stroke(effect.color.opacity(0.132 * intensity), lineWidth: 0.8)
                .frame(width: EffectCardMetrics.width + 28, height: EffectCardMetrics.height + 10)
                .blur(radius: 5)
        }
        .allowsHitTesting(false)
    }
}

private struct EffectCardBorderGlow: View {
    let effect: MixrEffect
    var isSelected: Bool

    private var selectedBoost: Double {
        guard isSelected else { return EffectUnselectedGlow.multiplier(for: effect) }

        switch effect {
        case .auto:
            return 1.4 * EffectSelectedGlow.multiplier(for: .auto)
        case .reverb:
            return 1.2 * EffectSelectedGlow.multiplier(for: .reverb)
        case .echo:
            return 1.2 * EffectSelectedGlow.multiplier(for: .echo)
        default:
            return 1.0
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EffectCardMetrics.cornerRadius, style: .continuous)
        let rimScale = EffectRimGlow.multiplier(for: effect)

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
	                            Color(hex: "38BDF8").opacity(isSelected ? 0.54 : 0.23),
	                            Color(hex: "A78BFA").opacity(isSelected ? 0.46 : 0.20),
	                            MixrColors.waveformPink.opacity(isSelected ? 0.58 : 0.23),
	                            MixrColors.waveformYellow.opacity(isSelected ? 0.48 : 0.17),
	                            Color.white.opacity(isSelected ? 0.26 : 0.11),
	                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    lineWidth: isSelected ? 0.62 : 0.40
                )

                shape.strokeBorder(
                    LinearGradient(
	                        colors: [
	                            MixrColors.waveformPink.opacity(isSelected ? 0.54 : 0.18),
	                            MixrColors.waveformYellow.opacity(isSelected ? 0.46 : 0.14),
	                            Color(hex: "38BDF8").opacity(isSelected ? 0.38 : 0.14),
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
	                            Color(hex: "38BDF8").opacity(isSelected ? 0.40 : 0.11),
	                            MixrColors.waveformYellow.opacity(isSelected ? 0.34 : 0.09),
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
	                            effect.color.opacity((isSelected ? (effect == .auto ? 0.20 : 0.34 * selectedBoost) : 0.16 * selectedBoost) * rimScale),
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
	                        effect.color.opacity((isSelected ? (effect == .auto ? 0.24 : 0.72 * selectedBoost) : 0.32 * selectedBoost) * rimScale),
	                        effect.color.opacity((isSelected ? (effect == .auto ? 0.20 : 0.44 * selectedBoost) : 0.16 * selectedBoost) * rimScale),
	                        effect.color.opacity((isSelected ? (effect == .auto ? 0.09 : 0.12 * selectedBoost) : 0.04 * selectedBoost) * rimScale),
	                        Color.clear,
	                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ),
                lineWidth: isSelected ? 1.28 : 0.72
            )

            // Thin full outline keeps selection legible without flattening the glass edge.
	            shape.strokeBorder(effect.color.opacity((isSelected ? (effect == .auto ? 0.18 : 0.24 * selectedBoost) : 0.10 * selectedBoost) * rimScale), lineWidth: isSelected ? 0.64 : 0.48)

            if isSelected, effect == .echo {
                shape.strokeBorder(effect.color.opacity(0.34 * EffectSelectedGlow.multiplier(for: .echo)), lineWidth: 0.92)
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
	            shape.strokeBorder(effect.color.opacity((isSelected ? (effect == .auto ? 0.42 : 0.55 * selectedBoost) : 0.14 * selectedBoost) * rimScale), lineWidth: isSelected ? 1.45 : 1.05)
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
    var isSelected: Bool

    var body: some View {
        let r     = EffectCardMetrics.iconTileRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let size  = EffectCardMetrics.iconTileSize
        let glow  = effect.iconGlow
        let iconGlow = isSelected ? 1.0 : EffectIconGlow.multiplier(for: effect)
        let glowScale = (effect == .auto
            ? (isSelected ? 1.25 * EffectSelectedGlow.multiplier(for: .auto) : 1.13)
            : (isSelected ? EffectSelectedGlow.multiplier(for: effect) : EffectUnselectedGlow.multiplier(for: effect)))
            * iconGlow
        let autoAccentScale = effect == .auto && isSelected
            ? 1.16 * EffectSelectedGlow.multiplier(for: .auto)
            : 1.0

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
                            effect.color.opacity(0.60 * glowScale),
                            effect.color.opacity(0.24 * glowScale),
                            effect.color.opacity(0.055 * glowScale),
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
                            effect.color.opacity(min(1.0, 0.98 * glowScale)),
                            effect.color.opacity(0.42 * glowScale),
                            effect.color.opacity(0.11 * glowScale),
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
	                                MixrColors.waveformPink.opacity(0.48 * autoAccentScale),
	                                MixrColors.waveformPink.opacity(0.14 * autoAccentScale),
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
	                                Color(hex: "38BDF8").opacity(0.32 * autoAccentScale),
	                                Color(hex: "38BDF8").opacity(0.09 * autoAccentScale),
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
	                                MixrColors.waveformYellow.opacity(0.25 * autoAccentScale),
	                                MixrColors.waveformYellow.opacity(0.07 * autoAccentScale),
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
	                            Color.white.opacity(0.26 * autoAccentScale),
	                            Color(hex: "C084FC").opacity(0.72 * autoAccentScale),
	                            MixrColors.waveformPink.opacity(0.60 * autoAccentScale),
	                            MixrColors.waveformYellow.opacity(0.41 * autoAccentScale),
	                            Color(hex: "38BDF8").opacity(0.55 * autoAccentScale),
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
                .shadow(
                    color: (effect == .auto ? Color(hex: "F5D0FE") : effect.color)
                        .opacity(1.0 * (effect == .auto ? 1.0 : iconGlow)),
                    radius: effect == .auto ? (isSelected ? 5.4 * EffectSelectedGlow.multiplier(for: .auto) : 4.6) : 4
                )
                .shadow(
                    color: (effect == .auto ? Color(hex: "C084FC") : effect.color)
                        .opacity(
                            (effect == .auto
                                ? (isSelected ? 0.76 * EffectSelectedGlow.multiplier(for: .auto) : 0.64)
                                : 0.55) * (effect == .auto ? 1.0 : iconGlow)
                        ),
                    radius: effect == .auto ? (isSelected ? 12 * EffectSelectedGlow.multiplier(for: .auto) : 10) : 9
                )
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
    private var selectedBoost: Double {
        guard isSelected else { return 1.0 }

        switch effect {
        case .reverb:
            return 1.2 * EffectSelectedGlow.multiplier(for: .reverb)
        case .echo:
            return 1.2 * EffectSelectedGlow.multiplier(for: .echo)
        default:
            return 1.0
        }
    }

    private var boost: Double {
        let resting = 0.82 * EffectUnselectedGlow.multiplier(for: effect)
        return (isSelected ? selectedBoost : resting) * layout.intensity
    }

    @ViewBuilder
    var body: some View {
        if effect == .auto {
            AutoIridescentParticles(isSelected: isSelected)
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
    var isSelected: Bool

    private var selectedBoost: Double { isSelected ? 1.4 * EffectSelectedGlow.multiplier(for: .auto) : 1.0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AutoLightParticle(
                    color: MixrColors.waveformPink,
                    size: 6.2,
                    blur: 0.85,
                    opacity: 0.68 * selectedBoost
                )
                .position(x: geo.size.width * 0.62, y: geo.size.height * 0.43)

                AutoLightParticle(
                    color: Color(hex: "38BDF8"),
                    size: 3.8,
                    blur: 0.45,
                    opacity: 0.61 * selectedBoost
                )
                .position(x: geo.size.width * 0.76, y: geo.size.height * 0.24)

                AutoLightParticle(
                    color: Color(hex: "A78BFA"),
                    size: 9.0,
                    blur: 1.85,
                    opacity: 0.39 * selectedBoost
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
