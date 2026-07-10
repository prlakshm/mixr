import SwiftUI

// MARK: - Metrics

enum SFXMetrics {
    static let markWidth: CGFloat = 46
    static let markHeight: CGFloat = 34
    static let markRadius: CGFloat = 8
    static let cardSize: CGFloat = 104
    static let cardRadius: CGFloat = MixrRadius.button
    static let cardIconSize: CGFloat = 24
    static let panelScreenFraction: CGFloat = 0.86
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

struct SFXCard: View {
    let effect: SoundEffectDefinition
    var onTap: () -> Void = {}

    @GestureState private var isPressed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SFXMetrics.cardRadius, style: .continuous)
    }

    private var silver: Color { MixrColors.waveformSilver }
    private var silverPeak: Color { MixrWaveformColor.silver.peakColor }

    var body: some View {
        VStack(spacing: MixrSpacing.sm) {
            Image(systemName: effect.icon)
                .font(.system(size: SFXMetrics.cardIconSize, weight: .semibold))
                .foregroundStyle(silverPeak)
                .shadow(color: silverPeak.opacity(0.65), radius: 5)
                .shadow(color: silver.opacity(0.35), radius: 10)
                .frame(height: SFXMetrics.cardIconSize + 4)

            VStack(spacing: 2) {
                Text(effect.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(Self.durationLabel(effect.durationSeconds))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary.opacity(0.85))
            }
        }
        .frame(width: SFXMetrics.cardSize, height: SFXMetrics.cardSize)
        .background { silverGlass }
        .clipShape(shape)
        .overlay { silverRim }
        .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        .shadow(color: silver.opacity(isPressed ? 0.30 : 0.10), radius: isPressed ? 10 : 6)
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
            .fill(Color(hex: "05070D").opacity(0.56))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.05)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.085),
                            silver.opacity(0.028),
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
                            silver.opacity(0.10),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.5, y: 0.30),
                        startRadius: 0,
                        endRadius: SFXMetrics.cardSize * 0.75
                    )
                )
            }
    }

    private var silverRim: some View {
        ZStack {
            shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.55)
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        silver.opacity(0.30),
                        silver.opacity(0.10),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.clear,
                        silver.opacity(0.24),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.7
            )
        }
    }
}

// MARK: - SFX Library Panel

/// Large silver library panel — same open/close overlay model as the rest
/// of Mixr's floating panels. Sizing is applied by the presenting overlay.
struct SFXLibraryPanel: View {
    var onSelect: (SoundEffectDefinition) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let columns = [
        GridItem(.adaptive(minimum: SFXMetrics.cardSize, maximum: SFXMetrics.cardSize + 24), spacing: MixrSpacing.md),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, MixrSpacing.xl)
                .padding(.top, MixrSpacing.lg)
                .padding(.bottom, MixrSpacing.md)

            MixrColors.divider.frame(height: 0.5)
                .padding(.horizontal, MixrSpacing.lg)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: MixrSpacing.md) {
                    ForEach(SoundEffectLibrary.all) { effect in
                        SFXCard(effect: effect) {
                            onSelect(effect)
                        }
                    }
                }
                .padding(MixrSpacing.xl)
            }
        }
        .background {
            GlassBackground(level: .strong, cornerRadius: MixrRadius.glass)
        }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous)
                .strokeBorder(MixrColors.waveformSilver.opacity(0.16), lineWidth: 0.6)
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
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.mixrIconGlass)
        }
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
