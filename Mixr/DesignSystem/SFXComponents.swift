import SwiftUI

// MARK: - Metrics

enum SFXMetrics {
    static let markWidth: CGFloat = 46
    static let markHeight: CGFloat = 34
    static let markRadius: CGFloat = 8
    /// Default card size — the library grid overrides this so exactly
    /// 6 cards (3 × 2) fill the visible panel area.
    static let cardDefaultWidth: CGFloat = 200
    static let cardDefaultHeight: CGFloat = 118
    static let cardRadius: CGFloat = MixrRadius.glass
    static let panelScreenFraction: CGFloat = 0.86
    static let libraryColumns: Int = 3
    static let libraryVisibleRows: Int = 2
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

/// Wide glass SFX card — dark pane wrapped in a bright glowing silver rim,
/// with a large glowing silver icon over a title + duration stack. Colors
/// come from the silver song chip / silver SFX track family.
struct SFXCard: View {
    let effect: SoundEffectDefinition
    var width: CGFloat = SFXMetrics.cardDefaultWidth
    var height: CGFloat = SFXMetrics.cardDefaultHeight
    var onTap: () -> Void = {}

    @GestureState private var isPressed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SFXMetrics.cardRadius, style: .continuous)
    }

    private var silver: Color { MixrColors.sfxPrimary }
    private var silverSoft: Color { MixrColors.sfxSecondary }
    private var silverEdge: Color { MixrColors.sfxOutline }
    private var silverGlow: Color { MixrColors.sfxGlow }

    private var iconSize: CGFloat { min(44, max(24, height * 0.30)) }
    private var titleSize: CGFloat { min(16, max(12, height * 0.125)) }

    var body: some View {
        VStack(spacing: 0) {
            // Icon centered in the upper region
            Image(systemName: effect.icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            silver,
                            silverSoft.opacity(0.95),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.white.opacity(0.55), radius: 4)
                .shadow(color: silverGlow.opacity(0.45), radius: 10)
                .frame(maxHeight: .infinity)

            VStack(spacing: 2) {
                Text(effect.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(Self.durationLabel(effect.durationSeconds))
                    .font(.system(size: titleSize * 0.8, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary)
            }
            .padding(.bottom, height * 0.11)
        }
        .padding(.horizontal, MixrSpacing.sm)
        .frame(width: width, height: height)
        .background { silverGlass }
        .clipShape(shape)
        .overlay { silverRim }
        .shadow(color: silverGlow.opacity(isPressed ? 0.42 : 0.30), radius: isPressed ? 12 : 8)
        .shadow(color: silver.opacity(isPressed ? 0.26 : 0.16), radius: isPressed ? 22 : 16)
        .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isPressed)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
                .onEnded { _ in onTap() }
        )
    }

    private static func durationLabel(_ seconds: Double) -> String {
        seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }

    private var silverGlass: some View {
        shape
            .fill(Color(hex: "0B0F1A").opacity(0.62))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.07)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            silverSoft.opacity(0.05),
                            Color.black.opacity(0.18),
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
                            silverSoft.opacity(0.14),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.5, y: 0.32),
                        startRadius: 0,
                        endRadius: max(width, height) * 0.62
                    )
                )
            }
    }

    /// Bright silver rim with an inner bloom — the defining edge glow.
    private var silverRim: some View {
        ZStack {
            // Soft bloom hugging the rim
            shape
                .strokeBorder(silverGlow.opacity(isPressed ? 0.85 : 0.65), lineWidth: 2.5)
                .blur(radius: 3)
            // Crisp bright edge
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        silverEdge.opacity(0.80),
                        silver.opacity(0.70),
                        silverEdge.opacity(0.85),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.2
            )
            // Top catchlight lip
            shape
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.8)
                .mask {
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.25), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.55)
                    )
                }
        }
    }
}

// MARK: - SFX Library Panel

/// Large silver library panel — same open/close overlay model as the rest
/// of Mixr's floating panels. Sizing is applied by the presenting overlay.
struct SFXLibraryPanel: View {
    var onSelect: (SoundEffectDefinition) -> Void = { _ in }
    var onClose: () -> Void = {}

    /// Display order — first screenful (3 × 2) matches the reference set,
    /// remaining effects follow and are reached by scrolling.
    private static let displayOrder: [String] = [
        "riser", "downlifter", "impact",
        "crash", "snareBuild", "clapFill",
    ]

    private static var orderedEffects: [SoundEffectDefinition] {
        let front = displayOrder.compactMap { SoundEffectLibrary.definition(for: $0) }
        let rest = SoundEffectLibrary.all.filter { !displayOrder.contains($0.id) }
        return front + rest
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, MixrSpacing.xl)
                .padding(.top, MixrSpacing.lg)
                .padding(.bottom, MixrSpacing.md)

            MixrColors.divider.frame(height: 0.5)
                .padding(.horizontal, MixrSpacing.lg)

            // Exactly 6 cards (3 × 2) fill the visible area; scroll for the rest.
            GeometryReader { geo in
                let spacing = MixrSpacing.md
                let padH = MixrSpacing.xl
                let padV = MixrSpacing.lg
                let columns = CGFloat(SFXMetrics.libraryColumns)
                let rows = CGFloat(SFXMetrics.libraryVisibleRows)
                let cardWidth = (geo.size.width - padH * 2 - spacing * (columns - 1)) / columns
                let cardHeight = (geo.size.height - padV * 2 - spacing * (rows - 1)) / rows

                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(cardWidth), spacing: spacing),
                            count: SFXMetrics.libraryColumns
                        ),
                        spacing: spacing
                    ) {
                        ForEach(Self.orderedEffects) { effect in
                            SFXCard(effect: effect, width: cardWidth, height: cardHeight) {
                                onSelect(effect)
                            }
                        }
                    }
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
                }
            }
        }
        .background {
            GlassBackground(level: .strong, cornerRadius: MixrRadius.glass)
        }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous)
                .strokeBorder(MixrColors.sfxSecondary.opacity(0.22), lineWidth: 0.6)
        }
        .mixrShadow(.glassStrong)
        .mixrGlow(.glassAmbientStrong)
    }

    private var header: some View {
        HStack(spacing: MixrSpacing.md) {
            SFXTileMark(isActive: true, width: 40, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Sound Effects")
                    .mixrFont(.sectionTitle)
                    .foregroundStyle(MixrColors.textPrimary)
                Text("Tap to add at the playhead on the silver SFX track")
                    .mixrFont(.metadata)
                    .foregroundStyle(MixrColors.textSecondary)
            }

            Spacer()

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
        }
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
        SFXLibraryPanel()
            .frame(width: 800, height: 380)
    }
    .frame(width: 932, height: 430)
    .preferredColorScheme(.dark)
}
