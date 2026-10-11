import SwiftUI

// MARK: - Metrics

enum SFXMetrics {
    static let markWidth: CGFloat = 46
    static let markHeight: CGFloat = 34
    static let markRadius: CGFloat = 8
    /// Default card size — slightly wider than tall (reference aspect).
    static let cardDefaultWidth: CGFloat = 200
    static let cardDefaultHeight: CGFloat = 138
    /// Width ÷ height — a little longer than tall.
    static let cardAspectRatio: CGFloat = cardDefaultWidth / cardDefaultHeight
    static let cardRadius: CGFloat = 14
    static let cardBorderLineWidth: CGFloat = 0.85
    static let cardIconTileSizeFraction: CGFloat = 0.47
    static let cardIconTileCornerRadius: CGFloat = 12
    static let cardIconCoreGlowRadius: CGFloat = 2.8
    static let cardIconBloomRadius: CGFloat = 6
    static let cardIconVerticalOffsetFraction: CGFloat = 0.055
}

// MARK: - SFX Tile Mark

/// Original creative-tool-coded "SFX" mark — compact dark rounded-square
/// tile with an indigo/purple glass gradient and bold lettering. Built
/// natively; no external assets.
struct SFXTileMark: View {
    var isActive: Bool = false
    var width: CGFloat = SFXMetrics.markWidth
    var height: CGFloat = SFXMetrics.markHeight

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SFXMetrics.markRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            // Dark tile base
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "12142A"),
                            Color(hex: "07091A"),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Indigo/purple/blue glass wash
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "6366F1").opacity(isActive ? 0.34 : 0.20),
                            Color(hex: "7C3AED").opacity(isActive ? 0.22 : 0.12),
                            Color(hex: "38BDF8").opacity(isActive ? 0.16 : 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Bottom-corner bloom — motion-tool energy without noise
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "818CF8").opacity(isActive ? 0.30 : 0.16),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.82, y: 0.95),
                        startRadius: 0,
                        endRadius: height * 0.9
                    )
                )

            // Top catchlight
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.42)
                    )
                )

            Text("SFX")
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .kerning(0.6)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(hex: "C7D2FE"),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(hex: "818CF8").opacity(isActive ? 0.85 : 0.55), radius: isActive ? 6 : 4)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        // Thin glowing rim
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isActive ? 0.30 : 0.18),
                        Color(hex: "818CF8").opacity(isActive ? 0.65 : 0.38),
                        Color(hex: "38BDF8").opacity(isActive ? 0.40 : 0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .shadow(color: Color(hex: "6366F1").opacity(isActive ? 0.40 : 0.18), radius: isActive ? 9 : 5)
        .shadow(color: .black.opacity(0.30), radius: 3, x: 0, y: 1.5)
        .animation(.easeOut(duration: 0.16), value: isActive)
    }
}

// MARK: - SFX Card

/// Calm charcoal-indigo glass with an integrated pearl icon tile.
struct SFXCard: View {
    let effect: SoundEffectDefinition
    var width: CGFloat = SFXMetrics.cardDefaultWidth
    var height: CGFloat = SFXMetrics.cardDefaultHeight
    var onTap: () -> Void = {}

    enum Colorway {
        case version1Colored
        case version2GrayLavender
    }

    /// Change this one selector to compare the preserved treatments.
    static let activeColorway: Colorway = .version2GrayLavender

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SFXMetrics.cardRadius, style: .continuous)
    }

    static var pearlLavender: Color { Color(hex: "E6DCFF") }

    static var iconBloomColor: Color {
        switch Self.activeColorway {
        case .version1Colored:
            Color(hex: "D88BC8").opacity(0.20)
        case .version2GrayLavender:
            Self.pearlLavender.opacity(0.30)
        }
    }

    static var iconTileBorderColor: Color {
        switch Self.activeColorway {
        case .version1Colored:
            Color(hex: "8E739F").opacity(0.21)
        case .version2GrayLavender:
            Color.white.opacity(0.14)
        }
    }

    private var durationColor: Color {
        switch Self.activeColorway {
        case .version1Colored:
            Color(hex: "D1B9FA").opacity(0.91)
        case .version2GrayLavender:
            MixrColors.sfxMenuLavender.opacity(0.88)
        }
    }

    private var durationGlowColor: Color {
        switch Self.activeColorway {
        case .version1Colored:
            Color(hex: "D88BC8").opacity(0.14)
        case .version2GrayLavender:
            Color.clear
        }
    }

    private var durationGlowRadius: CGFloat {
        switch Self.activeColorway {
        case .version1Colored: 3
        case .version2GrayLavender: 0
        }
    }

    private var iconTileSize: CGFloat {
        min(68, max(49, height * SFXMetrics.cardIconTileSizeFraction))
    }

    private var iconSize: CGFloat { min(36, max(24, height * 0.26)) }
    private var titleSize: CGFloat { min(16, max(12, height * 0.115)) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: height * 0.10) {
                Image(systemName: effect.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Self.pearlIconFill)
                    .shadow(
                        color: Color.white.opacity(0.56),
                        radius: SFXMetrics.cardIconCoreGlowRadius
                    )
                    .shadow(
                        color: Self.iconBloomColor,
                        radius: SFXMetrics.cardIconBloomRadius
                    )
                    .frame(width: iconTileSize, height: iconTileSize)
                    .background { iconTile }
                    .offset(y: height * SFXMetrics.cardIconVerticalOffsetFraction)

                VStack(spacing: 4) {
                    Text(effect.title)
                        .mixrScaledFont(
                            size: titleSize,
                            weight: .semibold,
                            relativeTo: .subheadline
                        )
                        .foregroundStyle(Color.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(Self.durationLabel(effect.durationSeconds))
                        .mixrScaledFont(
                            size: titleSize * 0.78,
                            weight: .medium,
                            relativeTo: .caption
                        )
                        .foregroundStyle(durationColor)
                        .shadow(color: durationGlowColor, radius: durationGlowRadius)
                }
            }
            .padding(.horizontal, MixrSpacing.sm)
            .padding(.vertical, height * 0.08)
            .frame(width: width, height: height)
            .background { cardSurface }
            .clipShape(shape)
            .overlay { cardBorder }
            .partyModeBorder(
                shape: shape,
                role: .semantic,
                lighting: .counterClockwise,
                semanticColor: MixrColors.sfxGlow,
                glintOffset: .far
            )
            .shadow(color: Color(hex: "B987C5").opacity(0.07), radius: 8)
            .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(SFXCardPressStyle())
        .accessibilityLabel("\(effect.title), \(Self.durationLabel(effect.durationSeconds))")
    }

    /// Soft pearl luminance with a restrained lavender falloff.
    static var pearlIconFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white,
                Color(hex: "F8F5FF"),
                Color(hex: "D8CEEF"),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func durationLabel(_ seconds: Double) -> String {
        seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }

    private var iconTile: some View {
        SFXIconBoxSurface(
            cornerRadius: SFXMetrics.cardIconTileCornerRadius,
            bloomEndRadius: iconTileSize * 0.62
        )
    }

    private var cardSurface: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "1B1F2E").opacity(0.90),
                        Color(hex: "101421").opacity(0.95),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "9B78C5").opacity(0.10),
                            Color(hex: "C27DA6").opacity(0.045),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.5, y: 0.10),
                        startRadius: 0,
                        endRadius: max(width, height) * 0.72
                    )
                )
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.035),
                            Color.clear,
                            Color.black.opacity(0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
    }

    private var cardBorder: some View {
        shape
            .strokeBorder(
                Color.white.opacity(0.16), lineWidth: SFXMetrics.cardBorderLineWidth
            )
            .allowsHitTesting(false)
    }
}

/// Shared card/chip surface so the SFX track chip cannot drift from the menu icons.
/// Liquid-glass stack: clear dark pane, edge-weighted color, specular rim.
struct SFXIconBoxSurface: View {
    let cornerRadius: CGFloat
    let bloomEndRadius: CGFloat
    var profile: SFXIconBoxRenderingProfile = .standard

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        tileShape
            .fill(
                LinearGradient(
                    colors: [
                        profile.baseTopColor.opacity(profile.baseTopOpacity),
                        profile.baseBottomColor.opacity(profile.baseBottomOpacity),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background {
                tileShape
                    .fill(.ultraThinMaterial)
                    .opacity(profile.materialOpacity)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                tileShape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.07),
                            Color.white.opacity(0.015),
                            Color.black.opacity(0.16),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                tileShape.fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.18, y: 0.08),
                        startRadius: 0,
                        endRadius: bloomEndRadius * 0.85
                    )
                )
            }
            .overlay {
                tileShape.fill(
                    profile.luminanceWashColor.opacity(profile.luminanceWashOpacity)
                )
            }
            .overlay {
                tileShape.fill(
                    profile.navyWashColor.opacity(profile.navyWashOpacity)
                )
            }
            .overlay {
                // Edge-weighted bloom — color at the rim, clear center.
                tileShape.fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            profile.radialPrimaryColor.opacity(profile.radialPrimaryOpacity * 0.35),
                            profile.radialSecondaryColor.opacity(profile.radialSecondaryOpacity),
                            profile.radialPrimaryColor.opacity(profile.radialPrimaryOpacity),
                        ],
                        center: .center,
                        startRadius: bloomEndRadius * 0.18,
                        endRadius: bloomEndRadius
                    )
                )
            }
            .overlay { glassRim }
            .shadow(color: profile.outerGlowColor, radius: profile.outerGlowRadius)
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.2)
    }

    private var glassRim: some View {
        let rim = profile.rimStrength
        return ZStack {
            tileShape.strokeBorder(Color.white.opacity(0.08 * rim), lineWidth: 0.55)

            tileShape.strokeBorder(profile.borderColor, lineWidth: 0.75)

            // Top-leading specular lip
            tileShape
                .strokeBorder(Color.white.opacity(0.42 * rim), lineWidth: 0.65)
                .mask {
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.45),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.62, y: 0.55)
                    )
                }

            // Bottom-trailing dark rim catch
            tileShape
                .strokeBorder(Color.black.opacity(0.30 * rim), lineWidth: 0.55)
                .mask {
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.9)],
                        startPoint: UnitPoint(x: 0.35, y: 0.35),
                        endPoint: .bottomTrailing
                    )
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Press Styles

private struct SFXCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
