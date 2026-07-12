import SwiftUI
import SwiftData

struct DesignSystemPreviewView: View {
    @State private var volumeSamples: [MixrWaveformColor: Double] = [
        .pink: 0.82,
        .purple: 0.74,
        .red: 0.68,
        .yellow: 0.91,
        .blue: 0.77,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MixrSpacing.xl) {
                header
                mainScreenSection
                colorPaletteSection
                typographySection
                glassCardsSection
                buttonsSection
                songChipsSection
                songRowsSection
                trackControlsSection
                soloMuteSection
                volumeSlidersSection
                waveformsSection
                effectCardsSection
                effectTraysSection
                sfxSection
                autoSection
                toolbarHistorySection
                toolbarHistoryIconOptionsSection
                projectDropdownSection
            }
            .padding(MixrSpacing.lg)
        }
        .background { previewBackground }
        .preferredColorScheme(.dark)
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
            Text("Final components and states from the main timeline screen")
                .mixrFont(.metadata)
                .foregroundStyle(MixrColors.textSecondary)
        }
    }

    // MARK: - Main Screen

    private var mainScreenSection: some View {
        PreviewSection(title: "Main Screen") {
            TimelineScreen()
                .frame(width: 932, height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(MixrColors.divider, lineWidth: 0.5)
                }
                .mixrShadow(.subtle)
        }
    }

    // MARK: - Colors

    private var colorPaletteSection: some View {
        PreviewSection(title: "Color Palette") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                PreviewSubsection(title: "Surfaces & Text") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: MixrSpacing.md
                    ) {
                        ColorSwatch(name: "Background", color: MixrColors.background)
                        ColorSwatch(name: "Background Secondary", color: MixrColors.backgroundSecondary)
                        ColorSwatch(name: "Surface", color: MixrColors.surface)
                        ColorSwatch(name: "Elevated Surface", color: MixrColors.elevatedSurface)
                        ColorSwatch(name: "Divider", color: MixrColors.divider)
                        ColorSwatch(name: "Text Secondary", color: MixrColors.textSecondary)
                    }
                }

                PreviewSubsection(title: "Accent") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: MixrSpacing.md
                    ) {
                        ColorSwatch(name: "Primary Purple", color: MixrColors.primaryPurple)
                        ColorSwatch(name: "Secondary Purple", color: MixrColors.secondaryPurple)
                    }
                }

                PreviewSubsection(title: "Waveform Base") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: MixrSpacing.md
                    ) {
                        ForEach(MixrWaveformColor.allCases) { color in
                            ColorSwatch(name: color.label, color: color.color)
                        }
                    }
                }

                PreviewSubsection(title: "Waveform Peak") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: MixrSpacing.md
                    ) {
                        ForEach(MixrWaveformColor.allCases) { color in
                            ColorSwatch(name: "\(color.label) Peak", color: color.peakColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        PreviewSection(title: "Typography") {
            VStack(alignment: .leading, spacing: MixrSpacing.md) {
                TypographySample(style: .displayLogo, label: "Logo · 24pt Bold", text: "Mixr")
                TypographySample(style: .sectionTitle, label: "Section Title · 15pt Semibold", text: "Effects")
                TypographySample(style: .songTitle, label: "Song Title · 13pt Semibold", text: "Blinding Lights")
                TypographySample(style: .body, label: "Body · 12pt Regular", text: "Adjust reverb and echo levels")
                TypographySample(style: .button, label: "Button · 12pt Medium", text: "Import Songs")
                TypographySample(style: .timecode, label: "Timecode · 13pt Monospaced", text: "1:24 / 3:45")
                TypographySample(style: .metadata, label: "Metadata · 10pt Medium", text: "The Weeknd · 03:20 · 124 BPM")
                TypographySample(style: .caption, label: "Caption · 9pt Regular", text: "KEY")

                VStack(alignment: .leading, spacing: MixrSpacing.xxs) {
                    Text("Effect Title · 11pt Semibold")
                        .mixrFont(.caption)
                        .foregroundStyle(MixrColors.textTertiary)
                    Text("Bass Boost")
                        .font(.system(size: EffectCardMetrics.titleFontSize, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                }
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
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                PreviewSubsection(title: "Primary & Secondary") {
                    HStack(spacing: MixrSpacing.md) {
                        Button {} label: {
                            Text("Primary Action")
                        }
                        .buttonStyle(.mixrPrimary)

                        Button {} label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.mixrSecondaryGlass)
                    }
                }

                PreviewSubsection(title: "Icon Buttons") {
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
                }

                PreviewSubsection(title: "Track Toggles · 28pt") {
                    HStack(spacing: MixrSpacing.sm) {
                        Button("S") {}
                            .buttonStyle(.mixrCompactTrackToggle)
                        Button("M") {}
                            .buttonStyle(.mixrCompactTrackToggle)
                    }
                }

                PreviewSubsection(title: "Legacy Toggles · 32pt") {
                    HStack(spacing: MixrSpacing.sm) {
                        Button("S") {}
                            .buttonStyle(.mixrToggle)
                        Button("M") {}
                            .buttonStyle(.mixrToggle)
                    }
                }

                PreviewSubsection(title: "Import Outline") {
                    Button {} label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Import Songs")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(MixrColors.textSecondary)
                        .frame(maxWidth: 220)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(MixrColors.divider, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }

                PreviewSubsection(title: "Transport Bar") {
                    DSPreviewTransportBar()
                }
            }
        }
    }

    // MARK: - Song Chips

    private var songChipsSection: some View {
        PreviewSection(title: "Song Color Chips") {
            HStack(spacing: MixrSpacing.md) {
                ForEach(MixrWaveformColor.allCases) { color in
                    VStack(spacing: MixrSpacing.xs) {
                        MixrSongColorChip(color: color)
                        Text(color.label)
                            .mixrFont(.caption)
                            .foregroundStyle(MixrColors.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Song Rows

    private var songRowsSection: some View {
        PreviewSection(title: "Song Rows") {
            VStack(spacing: 0) {
                DSPreviewSongRow(
                    title: "Blinding Lights",
                    artist: "The Weeknd",
                    duration: "3:20",
                    bpm: 124,
                    color: .pink
                )
                DSPreviewSongRow(
                    title: "Levitating",
                    artist: "Dua Lipa",
                    duration: "3:23",
                    bpm: 124,
                    color: .purple
                )
            }
            .background(MixrColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Track Controls

    private var trackControlsSection: some View {
        PreviewSection(title: "Track Controls") {
            VStack(spacing: 0) {
                ForEach(MixrWaveformColor.allCases) { color in
                    DSPreviewTrackControlRow(
                        color: color,
                        volume: Binding(
                            get: { volumeSamples[color] ?? 0.75 },
                            set: { volumeSamples[color] = $0 }
                        )
                    )
                    .frame(height: 46)

                    if color != MixrWaveformColor.allCases.last {
                        MixrColors.divider.frame(height: 0.5)
                    }
                }
            }
            .padding(.horizontal, 8)
            .background(MixrColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Volume Sliders

    private var volumeSlidersSection: some View {
        PreviewSection(title: "Volume Sliders") {
            VStack(alignment: .leading, spacing: MixrSpacing.md) {
                ForEach(Array(volumeSliderSamples.enumerated()), id: \.offset) { _, sample in
                    HStack(spacing: MixrSpacing.md) {
                        Text(sample.label)
                            .mixrFont(.metadata)
                            .foregroundStyle(MixrColors.textSecondary)
                            .frame(width: 52, alignment: .leading)

                        TLVolumeSlider(
                            value: .constant(sample.value),
                            accentColor: sample.color.peakColor,
                            trackColor: sample.color.color
                        )
                        .frame(width: 120)

                        Text("\(Int(sample.value * 100))%")
                            .mixrFont(.caption)
                            .foregroundStyle(MixrColors.textTertiary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .padding(MixrSpacing.md)
            .glassCard(.default)
        }
    }

    private var volumeSliderSamples: [(label: String, color: MixrWaveformColor, value: Double)] {
        [
            ("Pink", .pink, 0.82),
            ("Purple", .purple, 0.55),
            ("Red", .red, 0.32),
            ("Yellow", .yellow, 0.68),
            ("Blue", .blue, 1.0),
        ]
    }

    // MARK: - Waveforms

    private var waveformsSection: some View {
        PreviewSection(title: "Waveforms") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                ForEach(MixrWaveformColor.allCases) { color in
                    VStack(alignment: .leading, spacing: MixrSpacing.xxs) {
                        Text(color.label)
                            .mixrFont(.caption)
                            .foregroundStyle(MixrColors.textTertiary)

                        WaveformClip(waveformColor: color, height: 34)
                            .frame(width: 280)
                    }
                }
            }
        }
    }

    // MARK: - Effect Cards

    private var effectCardsSection: some View {
        PreviewSection(title: "Effect Cards") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                PreviewSubsection(title: "Default") {
                    effectCardRow(isSelected: { _ in false })
                }

                PreviewSubsection(title: "Selected") {
                    effectCardRow(isSelected: { _ in true })
                }

                PreviewSubsection(title: "Featured Glow · Auto / Reverb / Echo") {
                    HStack(spacing: MixrSpacing.md) {
                        ForEach([MixrEffect.auto, .reverb, .echo]) { effect in
                            VStack(spacing: MixrSpacing.xs) {
                                EffectCard(effect: effect, isSelected: true)
                                Text(effect.title)
                                    .mixrFont(.caption)
                                    .foregroundStyle(MixrColors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func effectCardRow(isSelected: @escaping (MixrEffect) -> Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MixrSpacing.md) {
                ForEach(MixrEffect.allCases) { effect in
                    EffectCard(
                        effect: effect,
                        isSelected: isSelected(effect)
                    )
                }
            }
        }
    }

    // MARK: - Solo / Mute States

    private var soloMuteSection: some View {
        PreviewSection(title: "Solo & Mute States") {
            HStack(spacing: MixrSpacing.xl) {
                PreviewSubsection(title: "Solo · Inactive / Active") {
                    HStack(spacing: MixrSpacing.sm) {
                        TLTrackToggle(label: "S", isActive: false, accent: MixrColors.secondaryPurple) {}
                        TLTrackToggle(label: "S", isActive: true, accent: MixrColors.secondaryPurple) {}
                    }
                }

                PreviewSubsection(title: "Mute · Inactive / Active") {
                    HStack(spacing: MixrSpacing.sm) {
                        TLTrackToggle(label: "M", isActive: false, accent: MixrColors.primaryPurple) {}
                        TLTrackToggle(label: "M", isActive: true, accent: MixrColors.primaryPurple) {}
                    }
                }
            }
        }
    }

    // MARK: - Effect Trays (expanded effect cards)

    private var effectTraysSection: some View {
        PreviewSection(title: "Expanded Effect Cards") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                PreviewSubsection(title: "Slider at 0 · gray labels") {
                    HStack(spacing: MixrSpacing.sm) {
                        EffectCard(effect: .reverb, isSelected: true)
                        EffectControlTray(effect: .reverb, level: 0)
                    }
                }

                PreviewSubsection(title: "After drag · current value in white (64)") {
                    HStack(spacing: MixrSpacing.sm) {
                        EffectCard(effect: .echo, isSelected: true)
                        EffectControlTray(effect: .echo, level: 64, echoPreset: .pingPong)
                    }
                }

                PreviewSubsection(title: "Reverb presets · effect color accent") {
                    EffectControlTray(effect: .reverb, level: 32, reverbPreset: .hall)
                }

                PreviewSubsection(title: "Echo presets · effect color accent") {
                    EffectControlTray(effect: .echo, level: 48, echoPreset: .reverse)
                }

                PreviewSubsection(title: "Slider-only effects") {
                    HStack(spacing: MixrSpacing.sm) {
                        EffectControlTray(effect: .blur, level: 25)
                        EffectControlTray(effect: .pitchUp, level: 80)
                    }
                }
            }
        }
    }

    // MARK: - Sound Effects

    private var sfxSection: some View {
        PreviewSection(title: "Sound Effects") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                PreviewSubsection(title: "SFX Button · closed / pressed–open") {
                    HStack(spacing: MixrSpacing.md) {
                        SFXTileMark(isActive: false)
                        SFXTileMark(isActive: true)
                    }
                }

                PreviewSubsection(title: "SFX Icon Options") {
                    SFXIconOptionsGallery()
                        .frame(height: 640)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                PreviewSubsection(title: "Import Songs + SFX footer layout") {
                    HStack(spacing: 7) {
                        Button {} label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Import Songs")
                                    .mixrFont(.button)
                            }
                            .foregroundStyle(MixrColors.textMuted.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, MixrSpacing.sm)
                            .padding(.vertical, MixrLayout.buttonPaddingV)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {} label: {
                            MixrSFXOutlineButtonLabel(style: .d)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 220)
                }

                PreviewSubsection(title: "Silver SFX cards") {
                    HStack(spacing: MixrSpacing.md) {
                        ForEach(SoundEffectLibrary.all.prefix(5)) { effect in
                            SFXCard(effect: effect)
                        }
                    }
                }

                PreviewSubsection(title: "Silver SFX track row") {
                    HStack(spacing: 9) {
                        MixrSongColorChip(color: .silver, usesSFXMark: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sound Effects")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MixrColors.textPrimary)
                            Text("Built-in SFX · 3 clips")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(MixrColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 208, height: 46)
                    .background(MixrColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                            .strokeBorder(MixrColors.divider, lineWidth: 0.5)
                    }
                }

                PreviewSubsection(title: "Silver SFX clips") {
                    HStack(spacing: MixrSpacing.md) {
                        WaveformClip(waveformColor: .silver, height: 34)
                            .frame(width: 120)
                        WaveformClip(waveformColor: .silver, height: 34)
                            .frame(width: 64)
                        WaveformClip(waveformColor: .silver, height: 34)
                            .frame(width: 28)
                    }
                }

                PreviewSubsection(title: "SFX library panel") {
                    SFXLibraryPanel()
                        .frame(width: 760, height: 340)
                }
            }
        }
    }

    // MARK: - Auto

    private var autoSection: some View {
        PreviewSection(title: "Auto") {
            VStack(alignment: .leading, spacing: MixrSpacing.lg) {
                PreviewSubsection(title: "Scope dialog · clip selected") {
                    AutoScopeDialog(hasSelectedClip: true)
                }

                PreviewSubsection(title: "Scope dialog · no selection (playhead)") {
                    AutoScopeDialog(hasSelectedClip: false)
                }

                PreviewSubsection(title: "Loading overlay") {
                    MixrAutoLoadingOverlay()
                }
            }
        }
    }

    // MARK: - Undo / Redo

    private var toolbarHistorySection: some View {
        PreviewSection(title: "Undo & Redo (Current)") {
            ToolbarHistoryContextRow(
                undoCustom: { TLHistoryActionIcon(kind: .undo) },
                redoCustom: { TLHistoryActionIcon(kind: .redo) }
            )
        }
    }

    private var toolbarHistoryIconOptionsSection: some View {
        PreviewSection(title: "Undo / Redo Icon Options") {
            UndoRedoIconOptionsGallery()
                .frame(height: 720)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Project Dropdown

    private var projectDropdownSection: some View {
        PreviewSection(title: "Project Dropdown") {
            ProjectDropdownMenu(
                projects: [
                    ProjectSummary(id: DSPreviewIDs.projectA, name: "My Remix", modifiedAt: Date()),
                    ProjectSummary(id: DSPreviewIDs.projectB, name: "Festival Set", modifiedAt: Date()),
                    ProjectSummary(id: DSPreviewIDs.projectC, name: "Sunset Mix", modifiedAt: Date()),
                ],
                currentProjectID: DSPreviewIDs.projectA,
                currentName: "My Remix"
            )
        }
    }
}

private enum DSPreviewIDs {
    static let projectA = UUID()
    static let projectB = UUID()
    static let projectC = UUID()
}

// MARK: - Preview Helpers

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

private struct PreviewSubsection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MixrSpacing.sm) {
            Text(title)
                .mixrFont(.metadata)
                .foregroundStyle(MixrColors.textTertiary)

            content
        }
    }
}

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

private struct DSPreviewTransportBar: View {
    var body: some View {
        ZStack {
            HStack(spacing: 24) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MixrColors.primaryPurple)
                    Text("Mixr")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MixrColors.textPrimary)
                }

                HStack(spacing: 4) {
                    Text("My Remix")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button {} label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 74)
                }
                .buttonStyle(.mixrSecondaryGlass)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 12) {
                Button {} label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary)
                }

                Button {} label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(MixrColors.primaryPurple))
                .shadow(color: MixrColors.primaryPurple.opacity(0.50), radius: 10)

                Button {} label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MixrColors.textSecondary)
                }

                HStack(spacing: 3) {
                    Text("1:24")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(MixrColors.textSecondary)
                    Text("3:45")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(MixrColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(MixrColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MixrRadius.glass, style: .continuous)
                .strokeBorder(MixrColors.divider, lineWidth: 0.5)
        }
    }
}

private struct DSPreviewSongRow: View {
    let title: String
    let artist: String
    let duration: String
    let bpm: Int
    let color: MixrWaveformColor

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                VStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(MixrColors.textSecondary.opacity(0.62))
                            .frame(width: 2.4, height: 2.4)
                    }
                }
                .frame(width: 8, height: 34)

                MixrSongColorChip(color: color)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(duration)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                }
                HStack(spacing: 0) {
                    Text(artist)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(bpm) BPM")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            MixrColors.divider.frame(height: 0.5)
        }
    }
}

private struct DSPreviewTrackControlRow: View {
    let color: MixrWaveformColor
    @Binding var volume: Double

    @State private var isSoloed = false
    @State private var isMuted = false

    var body: some View {
        HStack(spacing: 5) {
            TLTrackToggle(label: "S", isActive: isSoloed, accent: MixrColors.secondaryPurple) {
                isSoloed.toggle()
            }

            TLTrackToggle(label: "M", isActive: isMuted, accent: MixrColors.primaryPurple) {
                isMuted.toggle()
            }

            HStack(spacing: 4) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MixrColors.textSecondary.opacity(0.85))
                    .frame(width: 11)

                TLVolumeSlider(
                    value: $volume,
                    accentColor: color.peakColor,
                    trackColor: color.color
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var volumeIcon: String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Waveform Color Label

private extension MixrWaveformColor {
    var label: String {
        switch self {
        case .pink: "Pink"
        case .purple: "Purple"
        case .red: "Red"
        case .yellow: "Yellow"
        case .blue: "Blue"
        case .silver: "Silver · SFX"
        }
    }
}

#Preview {
    DesignSystemPreviewView()
        .modelContainer(for: MixrProjectRecord.self, inMemory: true)
}
