import SwiftUI

// MARK: - Auto Scope Dialog

/// Centered Apple-style scope dialog shown before Auto touches the timeline.
/// The presenter dims the background and dismisses on outside taps.
struct AutoScopeDialog: View {
    /// When a clip is selected the left card targets it; otherwise it
    /// targets the clips around the playhead.
    var hasSelectedClip: Bool
    var onChooseFocused: () -> Void = {}
    var onChooseEntireProject: () -> Void = {}

    var body: some View {
        VStack(spacing: MixrSpacing.lg) {
            VStack(spacing: MixrSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MixrColors.secondaryPurple)
                    .shadow(color: MixrColors.primaryPurple.opacity(0.75), radius: 7)

                Text("What should Auto remix?")
                    .mixrFont(.sectionTitle)
                    .foregroundStyle(MixrColors.textPrimary)

                Text("Auto adds transitions, sound effects, and per-clip effects")
                    .mixrFont(.metadata)
                    .foregroundStyle(MixrColors.textSecondary)
            }

            HStack(spacing: MixrSpacing.md) {
                AutoScopeOptionCard(
                    icon: hasSelectedClip ? "scope" : "timeline.selection",
                    title: hasSelectedClip ? "Selected Clip" : "Playhead Clips",
                    subtitle: hasSelectedClip
                        ? "A focused edit inside the clip you selected"
                        : "A focused edit around the playhead",
                    badge: "Recommended",
                    accent: MixrColors.secondaryPurple,
                    action: onChooseFocused
                )

                AutoScopeOptionCard(
                    icon: "rectangle.grid.1x2",
                    title: "Entire Project",
                    subtitle: "A full build, drop, and release arrangement across the timeline",
                    badge: nil,
                    accent: MixrColors.waveformPink,
                    action: onChooseEntireProject
                )
            }
        }
        .padding(MixrSpacing.xl)
        .frame(width: 520)
        .background {
            GlassBackground(level: .strong, cornerRadius: MixrRadius.glass)
        }
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .mixrShadow(.glassStrong)
        .mixrGlow(.glassAmbientStrong)
    }
}

// MARK: - Option Card

private struct AutoScopeOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let accent: Color
    let action: () -> Void

    @GestureState private var isPressed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
    }

    var body: some View {
        VStack(spacing: MixrSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.70), radius: 6)
                .frame(height: 26)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(MixrColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let badge {
                Text(badge)
                    .font(.system(size: 8.5, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.13))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(accent.opacity(0.38), lineWidth: 0.5)
                            }
                    }
            } else {
                // Keeps both cards the same height.
                Color.clear.frame(height: 18)
            }
        }
        .padding(.horizontal, MixrSpacing.md)
        .padding(.vertical, MixrSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .top)
        .background {
            GlassBackground(level: .elevated, cornerRadius: MixrRadius.button)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                accent.opacity(isPressed ? 0.60 : 0.22),
                lineWidth: isPressed ? 1 : 0.6
            )
        }
        .shadow(color: accent.opacity(isPressed ? 0.28 : 0.08), radius: isPressed ? 12 : 6)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isPressed)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
                .onEnded { _ in action() }
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
