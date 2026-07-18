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
    static let cardRadius: CGFloat = MixrRadius.glass
    static let panelScreenWidthFraction: CGFloat = 0.86
    static let libraryColumns: Int = 3
    static let libraryVisibleRows: Int = 2
    static let libraryPageSize: Int = libraryColumns * libraryVisibleRows
    static let panelPadH: CGFloat = MixrSpacing.xl
    static let panelPadV: CGFloat = MixrSpacing.lg
    static let panelCardSpacing: CGFloat = MixrSpacing.md
    /// Space above the card grid so the close control sits in panel chrome.
    static let panelCloseClearance: CGFloat = 28
    static let panelCloseTopInset: CGFloat = 4
    static let panelCloseTrailingInset: CGFloat = 6

    /// Panel height for a given width so a 3 × 2 page of cards fits exactly.
    static func panelHeight(forWidth width: CGFloat) -> CGFloat {
        let columns = CGFloat(libraryColumns)
        let rows = CGFloat(libraryVisibleRows)
        let cardWidth = (width - panelPadH * 2 - panelCardSpacing * (columns - 1)) / columns
        let cardHeight = cardWidth / cardAspectRatio
        return panelCloseClearance
            + panelPadV * 2
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

// MARK: - Silver SFX Card

/// Wide glass SFX card — dark pane wrapped in a thick glowing silver rim,
/// with a pearl-glow icon over a title + duration stack. Colors come from
/// the silver song chip / silver SFX track family.
struct SFXCard: View {
    let effect: SoundEffectDefinition
    var width: CGFloat = SFXMetrics.cardDefaultWidth
    var height: CGFloat = SFXMetrics.cardDefaultHeight
    var onTap: () -> Void = {}

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SFXMetrics.cardRadius, style: .continuous)
    }

    private var silver: Color { MixrColors.sfxPrimary }
    private var silverSoft: Color { MixrColors.sfxSecondary }
    private var silverEdge: Color { MixrColors.sfxOutline }
    private var silverGlow: Color { MixrColors.sfxGlow }

    private var iconSize: CGFloat { min(48, max(26, height * 0.32)) }
    private var titleSize: CGFloat { min(16, max(12, height * 0.115)) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Image(systemName: effect.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(pearlIconFill)
                    .shadow(color: Color.white.opacity(0.72), radius: 3.5)
                    .shadow(color: silverGlow.opacity(0.55), radius: 9)
                    .shadow(color: silver.opacity(0.28), radius: 16)
                    .frame(maxHeight: .infinity)

                VStack(spacing: 2) {
                    Text(effect.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(Self.durationLabel(effect.durationSeconds))
                        .font(.system(size: titleSize * 0.78, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary)
                }
                .padding(.bottom, height * 0.12)
            }
            .padding(.horizontal, MixrSpacing.sm)
            .frame(width: width, height: height)
            .background { silverGlass }
            .clipShape(shape)
            .overlay { silverRim }
            .shadow(color: silverGlow.opacity(0.38), radius: 12)
            .shadow(color: silver.opacity(0.22), radius: 22)
            .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(SFXCardPressStyle())
        .accessibilityLabel("\(effect.title), \(Self.durationLabel(effect.durationSeconds))")
    }

    /// Soft white-pearl luminance — luminous, not metallic chrome.
    private var pearlIconFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white,
                silverGlow.opacity(0.96),
                silver.opacity(0.92),
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

    private var silverGlass: some View {
        shape
            .fill(Color(hex: "0B0F1A").opacity(0.58))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.06)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear,
                            Color.black.opacity(0.16),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [
                            silverSoft.opacity(0.10),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.5, y: 0.30),
                        startRadius: 0,
                        endRadius: max(width, height) * 0.58
                    )
                )
            }
    }

    /// Thick bright silver rim with strong inner/outer bloom — reference look.
    private var silverRim: some View {
        ZStack {
            // Outer bloom
            shape
                .strokeBorder(silverGlow.opacity(0.55), lineWidth: 6)
                .blur(radius: 6)
            // Mid bloom
            shape
                .strokeBorder(Color.white.opacity(0.50), lineWidth: 3.8)
                .blur(radius: 2.8)
            // Crisp bright edge
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white,
                        silverEdge.opacity(0.92),
                        silver.opacity(0.78),
                        silverEdge.opacity(0.90),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 2.15
            )
            // Inner lip catchlight
            shape
                .strokeBorder(Color.white.opacity(0.88), lineWidth: 1.1)
                .mask {
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.30), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.55)
                    )
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - SFX Library Panel

/// Headerless SFX library — 3 × 2 card pages, horizontal scroll for the
/// rest. Menu glass matches Mixr alert / project-menu chrome.
struct SFXLibraryPanel: View {
    var onSelect: (SoundEffectDefinition) -> Void = { _ in }
    var onClose: () -> Void = {}

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
                let padH = SFXMetrics.panelPadH
                let padV = SFXMetrics.panelPadV
                let columns = CGFloat(SFXMetrics.libraryColumns)
                let cardWidth = (geo.size.width - padH * 2 - spacing * (columns - 1)) / columns
                let cardHeight = cardWidth / SFXMetrics.cardAspectRatio
                let pageWidth = geo.size.width

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(Self.pages.enumerated()), id: \.offset) { _, page in
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
                            .padding(.bottom, padV)
                            .frame(width: pageWidth, height: geo.size.height)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
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
        .background { MixrAlertChrome.background(cornerRadius: MixrRadius.glass) }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 9)
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
