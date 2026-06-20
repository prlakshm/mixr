import SwiftUI

struct DesignSystemPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MixrSpacing.xl) {
                header
                colorPaletteSection
                typographySection
                glassCardsSection
                buttonsSection
                waveformsSection
                effectCardsSection
            }
            .padding(MixrSpacing.lg)
        }
        .background { previewBackground }
    }

    private var previewBackground: some View {
        ZStack {
            MixrGradients.backgroundLinear
            MixrGradients.backgroundRadial
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MixrSpacing.xs) {
            Text("Design System")
                .mixrFont(.displayLogo)
                .foregroundStyle(MixrColors.textPrimary)
            Text("Visual validation for Mixr tokens and components")
                .mixrFont(.metadata)
                .foregroundStyle(MixrColors.textSecondary)
        }
    }

    // MARK: - Colors

    private var colorPaletteSection: some View {
        PreviewSection(title: "Color Palette") {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: MixrSpacing.md
            ) {
                ColorSwatch(name: "Background", color: MixrColors.background)
                ColorSwatch(name: "Surface", color: MixrColors.surface)
                ColorSwatch(name: "Elevated Surface", color: MixrColors.elevatedSurface)
                ColorSwatch(name: "Primary Purple", color: MixrColors.primaryPurple)
                ColorSwatch(name: "Secondary Purple", color: MixrColors.secondaryPurple)
                ColorSwatch(name: "Waveform Pink", color: MixrColors.waveformPink)
                ColorSwatch(name: "Waveform Purple", color: MixrColors.waveformPurple)
                ColorSwatch(name: "Waveform Red", color: MixrColors.waveformRed)
                ColorSwatch(name: "Waveform Yellow", color: MixrColors.waveformYellow)
                ColorSwatch(name: "Waveform Blue", color: MixrColors.waveformBlue)
            }
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        PreviewSection(title: "Typography") {
            VStack(alignment: .leading, spacing: MixrSpacing.md) {
                TypographySample(style: .displayLogo, label: "Logo", text: "Mixr")
                TypographySample(style: .sectionTitle, label: "Section Title", text: "Effects")
                TypographySample(style: .songTitle, label: "Song Title", text: "Blinding Lights")
                TypographySample(style: .body, label: "Body", text: "Adjust reverb and echo levels")
                TypographySample(style: .metadata, label: "Metadata", text: "The Weeknd · 03:20 · 171 BPM")
                TypographySample(style: .button, label: "Button", text: "Import Songs")
            }
        }
    }

    // MARK: - Glass

    private var glassCardsSection: some View {
        PreviewSection(title: "Glass Cards") {
            VStack(spacing: MixrSpacing.md) {
                GlassCardSample(level: .default, label: "Default")
                GlassCardSample(level: .selected, label: "Selected")
                GlassCardSample(level: .elevated, label: "Elevated")
                GlassCardSample(level: .strong, label: "Strong")
            }
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        PreviewSection(title: "Buttons") {
            VStack(alignment: .leading, spacing: MixrSpacing.md) {
                Button {} label: {
                    Label("AI Suggestions", systemImage: "sparkles")
                }
                    .buttonStyle(.mixrPrimary)

                Button {} label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                    .buttonStyle(.mixrSecondaryGlass)

                HStack(spacing: MixrSpacing.md) {
                    Button {} label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.mixrIcon)

                    Button {} label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.mixrIconGlass)
                }

                HStack(spacing: MixrSpacing.sm) {
                    Button("S") {}
                        .buttonStyle(.mixrToggle)
                    Button("M") {}
                        .buttonStyle(.mixrToggle)
                }
            }
        }
    }

    // MARK: - Waveforms

    private var waveformsSection: some View {
        PreviewSection(title: "Waveforms") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                WaveformClip(waveformColor: .pink)
                WaveformClip(waveformColor: .purple)
                WaveformClip(waveformColor: .red)
                WaveformClip(waveformColor: .yellow)
                WaveformClip(waveformColor: .blue)
            }
        }
    }

    // MARK: - Effect Cards

    private var effectCardsSection: some View {
        PreviewSection(title: "Effect Cards") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MixrSpacing.md) {
                    ForEach(MixrEffect.allCases) { effect in
                        EffectCard(
                            effect: effect,
                            isSelected: effect == .reverb
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Section

private struct PreviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MixrSpacing.md) {
            Text(title)
                .mixrFont(.sectionTitle)
                .foregroundStyle(MixrColors.textPrimary)

            content
        }
    }
}

// MARK: - Color Swatch

private struct ColorSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MixrSpacing.xs) {
            RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                .fill(color)
                .frame(height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                        .strokeBorder(MixrColors.glassBorderDefault, lineWidth: MixrLayout.borderWidth)
                }

            Text(name)
                .mixrFont(.caption)
                .foregroundStyle(MixrColors.textSecondary)
        }
    }
}

// MARK: - Typography Sample

private struct TypographySample: View {
    let style: MixrTextStyle
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: MixrSpacing.xxs) {
            Text(label)
                .mixrFont(.caption)
                .foregroundStyle(MixrColors.textTertiary)

            Text(text)
                .mixrFont(style)
                .foregroundStyle(MixrColors.textPrimary)
        }
    }
}

// MARK: - Glass Card Sample

private struct GlassCardSample: View {
    let level: GlassLevel
    let label: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: MixrSpacing.xxs) {
                Text(label)
                    .mixrFont(.songTitle)
                    .foregroundStyle(MixrColors.textPrimary)
                Text("Glass / \(label)")
                    .mixrFont(.metadata)
                    .foregroundStyle(MixrColors.textSecondary)
            }
            Spacer()
        }
        .padding(MixrSpacing.md)
        .glassCard(level)
        .mixrShadow(.subtle)
    }
}

#Preview {
    DesignSystemPreviewView()
}
