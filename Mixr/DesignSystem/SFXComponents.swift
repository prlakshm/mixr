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
    static let panelScreenWidthFraction: CGFloat = 0.637
    static let panelDisplayScale: CGFloat = 1.05
    static let panelOpticalOffsetY: CGFloat = -10
    static let cardBorderLineWidth: CGFloat = 0.85
    static let cardIconTileSizeFraction: CGFloat = 0.47
    static let cardIconTileCornerRadius: CGFloat = 12
    static let cardIconCoreGlowRadius: CGFloat = 2.8
    static let cardIconBloomRadius: CGFloat = 6
    static let cardIconVerticalOffsetFraction: CGFloat = 0.055
    static let libraryColumns: Int = 3
    static let libraryVisibleRows: Int = 2
    static let libraryPageSize: Int = libraryColumns * libraryVisibleRows
    static let panelPadH: CGFloat = MixrSpacing.xl
    static let panelPadV: CGFloat = MixrSpacing.lg
    static let panelCardSpacing: CGFloat = 10
    /// Space above the card grid so the close control sits in panel chrome.
    static let panelCloseClearance: CGFloat = 28
    static let panelCloseTopInset: CGFloat = 4
    static let panelCloseTrailingInset: CGFloat = 6
    static let pageIndicatorDotSize: CGFloat = 4
    static let pageIndicatorSpacing: CGFloat = 5
    static let pageIndicatorBottomInset: CGFloat = 6
    /// Extra space under the card grid so page dots have breathing room.
    static let pageIndicatorCardLift: CGFloat = 5

    static func cardWidth(forPanelWidth width: CGFloat) -> CGFloat {
        let columns = CGFloat(libraryColumns)
        return (width - panelPadH * 2 - panelCardSpacing * (columns - 1)) / columns
    }

    /// Panel height for a given width so a centered 3 × 2 page fits exactly.
    static func panelHeight(forWidth width: CGFloat) -> CGFloat {
        let rows = CGFloat(libraryVisibleRows)
        let cardHeight = cardWidth(forPanelWidth: width) / cardAspectRatio
        return panelCloseClearance
            + panelPadV * 2
            + pageIndicatorCardLift
            + cardHeight * rows
            + panelCardSpacing * (rows - 1)
    }
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
                        Color(hex: "272337").opacity(0.90),
                        Color(hex: "161724").opacity(0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
                tileShape.fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "C78BC4").opacity(profile.radialPrimaryOpacity),
                            profile.radialSecondaryColor.opacity(profile.radialSecondaryOpacity),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: bloomEndRadius
                    )
                )
            }
            .overlay {
                tileShape.strokeBorder(profile.borderColor, lineWidth: 0.75)
            }
            .shadow(color: profile.outerGlowColor, radius: profile.outerGlowRadius)
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
    }
}

// MARK: - SFX Library Panel

/// Headerless SFX library — 3 × 2 card pages in a restrained modal glass,
/// with horizontal paging for the remaining effects.
struct SFXLibraryPanel: View {
    var onSelect: (SoundEffectDefinition) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State private var selectedPage: Int? = 0

    /// Display order — first page matches the reference set; remaining
    /// effects follow on the next horizontal page.
    private static let displayOrder: [String] = [
        "riser", "downlifter", "impact",
        "crash", "snareBuild", "clapFill",
    ]

    private static var orderedEffects: [SoundEffectDefinition] {
        let front = displayOrder.compactMap { SoundEffectLibrary.definition(for: $0) }
        let rest = SoundEffectLibrary.all.filter { !displayOrder.contains($0.id) }
        return front + rest
    }

    private static var pages: [[SoundEffectDefinition]] {
        let all = orderedEffects
        let size = SFXMetrics.libraryPageSize
        guard !all.isEmpty else { return [] }
        return stride(from: 0, to: all.count, by: size).map {
            Array(all[$0..<min($0 + size, all.count)])
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                let spacing = SFXMetrics.panelCardSpacing
                let padV = SFXMetrics.panelPadV
                let padH = SFXMetrics.panelPadH
                let cardWidth = SFXMetrics.cardWidth(forPanelWidth: geo.size.width)
                let cardHeight = cardWidth / SFXMetrics.cardAspectRatio
                let pageWidth = geo.size.width

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.fixed(cardWidth), spacing: spacing),
                                    count: SFXMetrics.libraryColumns
                                ),
                                spacing: spacing
                            ) {
                                ForEach(page) { effect in
                                    SFXCard(effect: effect, width: cardWidth, height: cardHeight) {
                                        onSelect(effect)
                                    }
                                }
                            }
                            .padding(.horizontal, padH)
                            .padding(.top, SFXMetrics.panelCloseClearance + padV)
                            .padding(.bottom, padV + SFXMetrics.pageIndicatorCardLift)
                            .frame(width: pageWidth, height: geo.size.height)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedPage)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MixrColors.textSecondary)
                    .frame(
                        width: MixrLayout.iconButtonSize,
                        height: MixrLayout.iconButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(SFXPlainIconPressStyle())
            .accessibilityLabel("Close")
            .padding(.top, SFXMetrics.panelCloseTopInset)
            .padding(.trailing, SFXMetrics.panelCloseTrailingInset)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: SFXMetrics.pageIndicatorSpacing) {
                ForEach(Self.pages.indices, id: \.self) { page in
                    Circle()
                        .fill(
                            page == (selectedPage ?? 0)
                                ? MixrColors.textPrimary.opacity(0.86)
                                : MixrColors.sfxMenuLavender.opacity(0.34)
                        )
                        .frame(
                            width: SFXMetrics.pageIndicatorDotSize,
                            height: SFXMetrics.pageIndicatorDotSize
                        )
                }
            }
            .padding(.bottom, SFXMetrics.pageIndicatorBottomInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .background { panelGlass }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .partyModeBorder(
            shape: RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous),
            role: .dialog,
            lighting: .clockwise,
            glintOffset: .near
        )
        .shadow(color: Color(hex: "8C7DAA").opacity(0.06), radius: 16)
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
    }

    /// A restrained, heavier modal material over the dimmed timeline.
    private var panelGlass: some View {
        let shape = RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous)
        return shape
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "171927").opacity(0.88),
                        Color(hex: "0B0E19").opacity(0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.16)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "8C7DAA").opacity(0.055),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.5, y: 0.08),
                        startRadius: 0,
                        endRadius: 460
                    )
                )
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            }
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

/// Bare secondary-gray icon button — no glass chrome, standard press dim.
private struct SFXPlainIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview("SFX Library Panel") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        let width: CGFloat = 800
        SFXLibraryPanel()
            .frame(width: width, height: SFXMetrics.panelHeight(forWidth: width))
    }
    .frame(width: 932, height: 430)
    .preferredColorScheme(.dark)
}
