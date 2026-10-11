import Foundation

let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/SFXComponents.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let timelineURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/TimelineScreen.swift")
let timelineSource = try String(contentsOf: timelineURL, encoding: .utf8)
let songChipURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/MixrSongColorChip.swift")
let songChipSource = try String(contentsOf: songChipURL, encoding: .utf8)
let iconProfileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/SFXIconBoxRenderingProfile.swift")
let iconProfileSource = (try? String(contentsOf: iconProfileURL, encoding: .utf8)) ?? ""
let trackRowBackgroundURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/MixrTrackRowBackground.swift")
let trackRowBackgroundSource = (
    try? String(contentsOf: trackRowBackgroundURL, encoding: .utf8)
) ?? ""
let panelURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/SFXLibraryPanel.swift")
let panelSource = try String(contentsOf: panelURL, encoding: .utf8)
let designPreviewURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/DesignSystemPreviewView.swift")
let designPreviewSource = try String(contentsOf: designPreviewURL, encoding: .utf8)
let colorsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/MixrColors.swift")
let colorsSource = try String(contentsOf: colorsURL, encoding: .utf8)
let waveformStyleURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/WaveformStyle.swift")
let waveformStyleSource = try String(contentsOf: waveformStyleURL, encoding: .utf8)
let compactProfileStart = iconProfileSource.range(of: "static let compact")?.lowerBound
    ?? iconProfileSource.endIndex
let compactProfileSource = String(iconProfileSource[compactProfileStart...])

let cardStart = source.range(of: "struct SFXCard: View")?.lowerBound ?? source.startIndex
let cardEnd = source.range(of: "// MARK: - SFX Library Panel")?.lowerBound ?? source.endIndex
let cardSource = String(source[cardStart..<cardEnd])
let overlayStart = timelineSource.range(
    of: "private struct TLSFXLibraryPresentation"
)?.lowerBound
    ?? timelineSource.startIndex
let overlayEnd = timelineSource.range(
    of: "// MARK: - Toolbar History Button",
    range: overlayStart..<timelineSource.endIndex
)?.lowerBound ?? timelineSource.endIndex
let sfxOverlaySource = String(timelineSource[overlayStart..<overlayEnd])

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

func matches(_ pattern: String, in text: String = source) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

check(
    "SFX icons sit closer to their titles",
    matches(#"cardIconVerticalOffsetFraction\s*:\s*CGFloat\s*=\s*0\.055"#)
        && cardSource.contains(
            ".offset(y: height * SFXMetrics.cardIconVerticalOffsetFraction)"
        )
)

check(
    "SFX cards sit slightly lighter than the modal",
    cardSource.contains("Color(hex: \"1B1F2E\").opacity(0.90)")
        && cardSource.contains("Color(hex: \"101421\").opacity(0.95)")
        && cardSource.contains("Color(hex: \"9B78C5\").opacity(0.10)")
        && cardSource.contains("Color(hex: \"C27DA6\").opacity(0.045)")
        && !cardSource.contains("cardPearlGlowRadius")
)

check(
    "SFX cards use the reference low-contrast edge",
    matches(#"cardBorderLineWidth\s*:\s*CGFloat\s*=\s*0\.85"#)
        && cardSource.contains(
            "Color.white.opacity(0.16), lineWidth: SFXMetrics.cardBorderLineWidth"
        )
        && !cardSource.contains("cardRimGlowRadius")
        && !cardSource.contains("cardRimGlowLineWidth")
)

check(
    "SFX preserves Version 1 and activates Version 2 gray-lavender",
    cardSource.contains("enum Colorway")
        && cardSource.contains("case version1Colored")
        && cardSource.contains("case version2GrayLavender")
        && cardSource.contains(
            "static let activeColorway: Colorway = .version2GrayLavender"
        )
        && cardSource.contains("Color(hex: \"D88BC8\").opacity(0.20)")
        && cardSource.contains("Color(hex: \"D1B9FA\").opacity(0.91)")
        && cardSource.contains("Color(hex: \"8E739F\").opacity(0.21)")
        && cardSource.contains("pearlLavender.opacity(0.30)")
        && cardSource.contains("MixrColors.sfxMenuLavender.opacity(0.88)")
        && cardSource.contains("Color.white.opacity(0.14)")
)

check(
    "SFX icon wells use one shared active-colorway surface",
    matches(#"cardIconTileSizeFraction\s*:\s*CGFloat\s*=\s*0\.47"#)
        && matches(#"cardIconTileCornerRadius\s*:\s*CGFloat\s*=\s*12"#)
        && cardSource.contains("min(68, max(49, height * SFXMetrics.cardIconTileSizeFraction))")
        && cardSource.contains(".background { iconTile }")
        && cardSource.contains("private var iconTile: some View")
        && cardSource.contains("struct SFXIconBoxSurface: View")
        && cardSource.contains("SFXIconBoxSurface(")
        && cardSource.contains("var profile: SFXIconBoxRenderingProfile = .standard")
        && cardSource.contains("tileShape.strokeBorder(profile.borderColor, lineWidth: 0.75)")
        && iconProfileSource.contains("baseTopColor: Color(hex: \"272337\")")
        && iconProfileSource.contains("radialPrimaryOpacity: 0.10")
        && iconProfileSource.contains("radialSecondaryOpacity: 0.05")
        && iconProfileSource.contains("borderOpacity: 0.14")
        && iconProfileSource.contains("usesActiveColorwayBorder: true")
)

check(
    "SFX song chip is a miniature effects tile with the footer button's sfx glyph",
    songChipSource.contains("if usesSFXMark && artworkData == nil")
        && songChipSource.contains("private var sfxChipContent: some View")
        && songChipSource.contains("let s = size / EffectCardMetrics.iconTileSize")
        && songChipSource.contains("SFXCard.pearlIconFill")
        && songChipSource.contains("MixrSFXMarkGlyph(size: 13 * 0.95 * 0.95 * (size / 34)")
        && songChipSource.contains(".shadow(color: Color.white.opacity(0.42), radius: 1.6)")
        && songChipSource.contains(".shadow(color: Color(hex: \"A281BC\").opacity(0.35), radius: 2.5)")
)

check(
    "SFX reference row uses an inset purple-black-navy glass card",
    timelineSource.contains(
        ".background(MixrTrackRowBackground(isSFXTrack: track.isSFXTrack))"
    )
        && designPreviewSource.contains(
            ".background(MixrTrackRowBackground(isSFXTrack: true))"
        )
        && trackRowBackgroundSource.contains("struct MixrTrackRowBackground: View")
        && trackRowBackgroundSource.contains("RoundedRectangle(cornerRadius: 9")
        && matches(
            #"Color\(hex: \"241A39\"\)\.opacity\(0\.48\)[\s\S]*?location: 0[\s\S]*?Color\(hex: \"090B13\"\)\.opacity\(0\.56\)[\s\S]*?location: 0\.5325[\s\S]*?Color\(hex: \"162239\"\)\.opacity\(0\.50\)[\s\S]*?location: 1"#,
            in: trackRowBackgroundSource
        )
        && trackRowBackgroundSource.contains("Color(hex: \"A281BC\").opacity(0.38 * rim)")
)

check(
    "SFX compact profile is the library panel's glossy navy, not the row's purple",
    iconProfileSource.contains("struct SFXIconBoxRenderingProfile")
        && iconProfileSource.contains("static let standard")
        && compactProfileSource.contains("baseTopColor: Color(hex: \"171927\")")
        && compactProfileSource.contains("baseBottomColor: Color(hex: \"0B0E19\")")
        && compactProfileSource.contains("navyWashColor: MixrColors.glassNavyDefault")
        && compactProfileSource.contains("radialPrimaryOpacity: 0.14")
        && compactProfileSource.contains("radialSecondaryOpacity: 0.08")
        && compactProfileSource.contains("borderOpacity: 0.14")
        && compactProfileSource.contains("iconCoreGlowOpacity: 0.42")
        && compactProfileSource.contains("iconCoreGlowRadius: 1.6")
        && compactProfileSource.contains("iconBloomRadius: 2.5")
        && cardSource.contains("var profile: SFXIconBoxRenderingProfile = .standard")
)

check(
    "SFX compact profile keeps a cool lavender bloom and a full-strength rim",
    compactProfileSource.contains("iconBloomColor: Color(hex: \"A281BC\").opacity(0.35)")
        && compactProfileSource.contains("outerGlowColor: Color(hex: \"8C7DAA\").opacity(0.10)")
        && compactProfileSource.contains("outerGlowRadius: 4")
        && compactProfileSource.contains("rimStrength: 1.0")
        && compactProfileSource.contains("usesActiveColorwayBorder: false")
)

check(
    "SFX cards return to their neutral ambient shadow",
    cardSource.contains("Color(hex: \"B987C5\").opacity(0.07)")
        && cardSource.contains("radius: 8")
        && !cardSource.contains("Color(hex: \"C77AC0\").opacity(0.12)")
)

check(
    "SFX icons use a gentle pearl-lavender glow",
    matches(#"cardIconCoreGlowRadius\s*:\s*CGFloat\s*=\s*2\.8"#)
        && matches(#"cardIconBloomRadius\s*:\s*CGFloat\s*=\s*6"#)
        && cardSource.contains("Color.white.opacity(0.56)")
        && cardSource.contains("color: Self.iconBloomColor")
        && cardSource.contains("Color(hex: \"D88BC8\").opacity(0.20)")
        && cardSource.contains("pearlLavender.opacity(0.30)")
        && cardSource.contains("radius: SFXMetrics.cardIconCoreGlowRadius")
        && cardSource.contains("radius: SFXMetrics.cardIconBloomRadius")
)

check(
    "SFX duration text uses the active colorway",
    cardSource.contains(".foregroundStyle(durationColor)")
        && cardSource.contains(
            ".shadow(color: durationGlowColor, radius: durationGlowRadius)"
        )
        && cardSource.contains("private var durationGlowRadius: CGFloat")
        && cardSource.contains("Color(hex: \"D1B9FA\").opacity(0.91)")
        && cardSource.contains("Color(hex: \"D88BC8\").opacity(0.14)")
        && cardSource.contains("MixrColors.sfxMenuLavender.opacity(0.88)")
)

check(
    "SFX Refined B palette uses shared semantic tokens",
    colorsSource.contains("static let sfxClipBodyTint = Color(hex: \"8A839D\")")
        && colorsSource.contains("static let sfxClipInnerTint = Color(hex: \"B9B0D2\")")
        && colorsSource.contains("static let sfxWaveformTop = Color(hex: \"E4DBFA\")")
        && colorsSource.contains("static let sfxMenuLavender = Color(hex: \"C9B9F4\")")
        // Near-duplicates folded onto the identity lavender / waveform top.
        && colorsSource.contains("static let sfxOutline = sfxMenuLavender")
        && colorsSource.contains("static let sfxWaveformBottom = sfxMenuLavender")
        && colorsSource.contains("static let sfxWaveformGlow = sfxWaveformTop")
)

check(
    "SFX silver clip uses the dedicated dark B-style layers and resting outline",
    colorsSource.contains("MixrColors.sfxClipBodyTint.opacity(0.152)")
        && colorsSource.contains("MixrColors.sfxOutline.opacity(0.48)")
        && colorsSource.contains("case .silver: 0.94")
        && waveformStyleSource.contains("MixrColors.glassClipNavy")
        && waveformStyleSource.contains("MixrColors.sfxClipInnerTint.opacity(0.076)")
)

check(
    "SFX waveform uses the restrained pearl gradient and embedded glow",
    waveformStyleSource.contains("MixrColors.sfxWaveformTop")
        && waveformStyleSource.contains("MixrColors.sfxWaveformBottom")
        && waveformStyleSource.contains("MixrColors.sfxWaveformGlow.opacity(0.08)")
        && waveformStyleSource.contains("MixrColors.sfxWaveformTop.opacity(0.08)")
        && waveformStyleSource.contains("radius: 2.5")
)

check(
    "SFX slider shares the menu lavender without changing music mappings",
    colorsSource.contains("var volumeAccentColor: Color")
        && colorsSource.contains("var volumeTrackColor: Color")
        && colorsSource.contains("case .silver: MixrColors.sfxMenuLavender")
        && colorsSource.contains("default: peakColor")
        && colorsSource.contains("default: color")
        && timelineSource.contains("accentColor: track.color.volumeAccentColor")
        && timelineSource.contains("trackColor: track.color.volumeTrackColor")
        && designPreviewSource.contains("accentColor: sample.color.volumeAccentColor")
        && designPreviewSource.contains("trackColor: sample.color.volumeTrackColor")
        && designPreviewSource.contains("accentColor: color.volumeAccentColor")
        && designPreviewSource.contains("trackColor: color.volumeTrackColor")
        && cardSource.contains("MixrColors.sfxMenuLavender.opacity(0.88)")
)

check(
    "SFX symbols are smaller inside the reference-sized wells",
    cardSource.contains("min(36, max(24, height * 0.26))")
)

check(
    "SFX type follows the reference hierarchy",
    cardSource.contains("size: titleSize,")
        && cardSource.contains("relativeTo: .subheadline")
        && cardSource.contains(".foregroundStyle(durationColor)")
        && cardSource.contains("VStack(spacing: 4)")
        && cardSource.contains("VStack(spacing: height * 0.10)")
        && cardSource.contains(".padding(.vertical, height * 0.08)")
)

check(
    "SFX panel dims the timeline with the editor's shared 0.52 scrim",
    sfxOverlaySource.contains("Color.black.opacity(0.52)")
        && sfxOverlaySource.contains(".ignoresSafeArea()")
)

check(
    "SFX library is one glass panel over the dimmed timeline, sized to its grid",
    sfxOverlaySource.contains("SFXLibraryPanel(")
        && sfxOverlaySource.contains("Color.black.opacity(0.52)")
        && sfxOverlaySource.contains(".onTapGesture { dismissSFXPanel() }")
        && sfxOverlaySource.contains(".frame(width: min(geo.size.width - 48, 456))")
        && sfxOverlaySource.contains(".fixedSize(horizontal: false, vertical: true)")
        && !timelineSource.contains("sfxPanelWidth")
)

check(
    "SFX panel glass is system material with a navy coat, hairline rim and soft shadow",
    panelSource.contains("shape.fill(.ultraThinMaterial)")
        && panelSource.contains("MixrColors.glassNavyDefault.opacity(0.55)")
        && panelSource.contains("Color.white.opacity(0.12), lineWidth: 0.6")
        && panelSource.contains(".shadow(color: .black.opacity(0.4), radius: 24, y: 10)")
)

check(
    "SFX tiles all share the Import / Export glass with a light lavender tint",
    panelSource.contains("GlassBackground(level: .default, cornerRadius: 17)")
        && panelSource.contains("MixrColors.sfxMenuLavender.opacity(0.10)")
        && panelSource.contains("SFXCard.pearlIconFill")
        && panelSource.contains(".frame(width: 68, height: 68)")
        && !panelSource.contains("family.color")
)

check(
    "SFX library shows six per page and pages horizontally",
    panelSource.contains("stride(from: 0, to: all.count, by: 6)")
        && panelSource.contains("count: 3")
        && panelSource.contains(".scrollTargetBehavior(.paging)")
        && panelSource.contains(".scrollPosition(id: $page)")
        && panelSource.contains(".id(index)")
)

check(
    "SFX pages use the shared minimal page dots in menu lavender",
    panelSource.contains("MixrPageDots(count: pages.count, current: page ?? 0, accent: MixrColors.sfxMenuLavender)")
        && panelSource.contains("Page \\((page ?? 0) + 1) of \\(pages.count)")
)

check(
    "SFX close is a bare secondary X with a full 44 pt target",
    panelSource.contains("Image(systemName: \"xmark\")")
        && panelSource.contains(".frame(width: 44, height: 44)")
        && panelSource.contains(".accessibilityLabel(\"Close\")")
        && !panelSource.contains("Circle()")
)

check(
    "Only one SFX library exists (no preview styles left behind)",
    !source.contains("struct SFXLibraryPanel")
        && !panelSource.contains("SFXLibraryStyle")
        && !panelSource.contains("SFXLiquidGlassMenu")
        && !timelineSource.contains("sfxPreviewStyle")
)

check(
    "Clips only ever draw real waveforms: songs and sound effects read their audio, nothing generated while loading",
    timelineSource.contains("WaveformClip(waveformColor: track.color, bars: bars, showsMockWhileLoading: false)")
        && timelineSource.contains("SoundEffectLibrary.definition(for: id)?.bundledURL")
        && !timelineSource.contains("guard !clip.isSoundEffect, let url = track.url")
)

if failures > 0 {
    exit(1)
}
