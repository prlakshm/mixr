import SwiftUI

// MARK: - Auto Scope Dialog

/// Compact Apple-style alert shown before Auto touches the timeline.
/// The presenter dims the background and dismisses on outside taps.
struct AutoScopeDialog: View {
    /// When a clip is selected the left action targets it; otherwise it
    /// targets the clips around the playhead.
    var hasSelectedClip: Bool
    var onChooseFocused: () -> Void = {}
    var onChooseEntireProject: () -> Void = {}

    private let cornerRadius: CGFloat = 14
    private let alertWidth: CGFloat = 300

    private var focusedTitle: String {
        hasSelectedClip ? "Selected Clip" : "Playhead Clips"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("What should Auto remix?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                Button(focusedTitle, action: onChooseFocused)
                    .buttonStyle(AutoScopeAlertActionStyle())

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 0.5)

                Button("Entire Project", action: onChooseEntireProject)
                    .buttonStyle(AutoScopeAlertActionStyle())
            }
            .frame(height: 44)
        }
        .frame(width: alertWidth)
        .background { alertBackground }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What should Auto remix?")
    }

    private var alertBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(Color(hex: "050810").opacity(0.68))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.10)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.045),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                    )
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            }
    }
}

// MARK: - Action Style

/// Light-gray label that darkens and dips on press — same press language as
/// the clip toolbar actions.
private struct AutoScopeAlertActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(
                configuration.isPressed
                    ? MixrColors.textTertiary
                    : MixrColors.textSecondary
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 1.25 : 0)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                .spring(response: 0.17, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

// MARK: - Auto Loading Overlay

/// Mixr-branded "analyzing & arranging" overlay — pulsing waveform logo
/// inside a shimmering ring. No generic spinner.
struct MixrAutoLoadingOverlay: View {
    var message: String = "Analyzing songs & arranging your mashup"

    @State private var pulse = false
    @State private var ringAngle: Angle = .degrees(0)

    var body: some View {
        VStack(spacing: MixrSpacing.lg) {
            ZStack {
                // Soft ambient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                MixrColors.primaryPurple.opacity(pulse ? 0.34 : 0.18),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 62
                        )
                    )
                    .frame(width: 124, height: 124)

                // Shimmering waveform ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                MixrColors.primaryPurple.opacity(0.0),
                                MixrColors.secondaryPurple.opacity(0.55),
                                Color(hex: "38BDF8").opacity(0.65),
                                MixrColors.waveformPink.opacity(0.55),
                                MixrColors.primaryPurple.opacity(0.0),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 74, height: 74)
                    .rotationEffect(ringAngle)

                Circle()
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
                    .frame(width: 74, height: 74)

                // Mixr logo mark
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(MixrColors.primaryPurple)
                    .shadow(color: MixrColors.primaryPurple.opacity(0.85), radius: pulse ? 12 : 6)
                    .scaleEffect(pulse ? 1.08 : 0.94)
            }

            VStack(spacing: MixrSpacing.xs) {
                Text("Auto")
                    .mixrFont(.sectionTitle)
                    .foregroundStyle(MixrColors.textPrimary)

                Text(message)
                    .mixrFont(.metadata)
                    .foregroundStyle(MixrColors.textSecondary)
                    .opacity(pulse ? 1.0 : 0.62)
            }
        }
        .padding(.horizontal, MixrSpacing.xl * 1.5)
        .padding(.vertical, MixrSpacing.xl)
        .background {
            GlassBackground(level: .strong, cornerRadius: MixrRadius.glass)
        }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .mixrShadow(.glassStrong)
        .mixrGlow(.purplePrimary)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                ringAngle = .degrees(360)
            }
        }
    }
}

#Preview("Auto Scope Dialog") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        AutoScopeDialog(hasSelectedClip: true)
    }
    .frame(width: 932, height: 430)
    .preferredColorScheme(.dark)
}

#Preview("Auto Loading") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        MixrAutoLoadingOverlay()
    }
    .frame(width: 932, height: 430)
    .preferredColorScheme(.dark)
}
