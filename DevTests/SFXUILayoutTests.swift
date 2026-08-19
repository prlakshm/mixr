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
    "SFX panel keeps the reference base geometry with a five percent display scale",
    matches(#"panelScreenWidthFraction\s*:\s*CGFloat\s*=\s*0\.637"#)
        && matches(#"panelDisplayScale\s*:\s*CGFloat\s*=\s*1\.05"#)
        && !source.contains("panelBaseWidthFraction")
        && !source.contains("panelScale")
)

check(
    "SFX menu uses adaptive native presentation with compact sheet adaptation",
    sfxOverlaySource.contains("content.popover(")
        && sfxOverlaySource.contains("content.sheet(isPresented:")
        && sfxOverlaySource.contains(".presentationCompactAdaptation(.sheet)")
        && matches(#"panelOpticalOffsetY\s*:\s*CGFloat\s*=\s*-10"#)
)

check(
    "SFX cards match the reference grid geometry",
    matches(#"cardRadius\s*:\s*CGFloat\s*=\s*14"#)
        && matches(#"panelCardSpacing\s*:\s*CGFloat\s*=\s*10"#)
        && matches(
            #"return\s+\(width\s*-\s*panelPadH\s*\*\s*2\s*-\s*panelCardSpacing\s*\*\s*\(columns\s*-\s*1\)\)\s*/\s*columns"#
        )
        && !source.contains("cardScaleWithinPanel")
)

check(
    "SFX grid uses the reference outer and internal padding",
    matches(#"panelPadH\s*:\s*CGFloat\s*=\s*MixrSpacing\.xl"#)
        && matches(#"panelPadV\s*:\s*CGFloat\s*=\s*MixrSpacing\.lg"#)
        && source.contains("let spacing = SFXMetrics.panelCardSpacing")
        && source.contains("let padH = SFXMetrics.panelPadH")
        && source.contains(".padding(.horizontal, padH)")
        && source.contains(".padding(.top, SFXMetrics.panelCloseClearance + padV)")
        && source.contains(
            ".padding(.bottom, padV + SFXMetrics.pageIndicatorCardLift)"
        )
)

check(
    "SFX icons sit closer to their titles",
    matches(#"cardIconVerticalOffsetFraction\s*:\s*CGFloat\s*=\s*0\.055"#)
        && cardSource.contains(
            ".offset(y: height * SFXMetrics.cardIconVerticalOffsetFraction)"
        )
)

check(
    "SFX modal uses subdued frosted navy glass",
    source.contains("Color(hex: \"171927\").opacity(0.88)")
        && source.contains("Color(hex: \"0B0E19\").opacity(0.94)")
        && matches(#"fill\(\.ultraThinMaterial\)[\s\S]*?\.opacity\(0\.16\)"#)
        && source.contains("Color.white.opacity(0.14), lineWidth: 0.75")
        && source.contains(".shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)")
)

check(
    "SFX modal returns to its neutral lavender ambient wash",
    source.contains("Color(hex: \"8C7DAA\").opacity(0.055)")
        && source.contains(
            ".shadow(color: Color(hex: \"8C7DAA\").opacity(0.06), radius: 16)"
        )
        && !source.contains("Color(hex: \"A36FC7\").opacity(0.10)")
        && !source.contains("Color(hex: \"D07CAD\").opacity(0.045)")
)

check(
    "SFX cards sit slightly lighter than the modal",
    cardSource.contains("Color(hex: \"1B1F2E\").opacity(0.90)")
        && cardSource.contains("Color(hex: \"101421\").opacity(0.95)")
        && cardSource.contains("Color(hex: \"9B78C5\").opacity(0.10)")
        && cardSource.contains("Color(hex: \"C27DA6\").opacity(0.045)")
        && !cardSource.contains(".fill(.ultraThinMaterial)")
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
        && cardSource.contains("Color(hex: \"272337\").opacity(0.90)")
        && cardSource.contains("var profile: SFXIconBoxRenderingProfile = .standard")
        && cardSource.contains("tileShape.strokeBorder(profile.borderColor, lineWidth: 0.75)")
        && iconProfileSource.contains("radialPrimaryOpacity: 0.13")
        && iconProfileSource.contains("radialSecondaryOpacity: 0.07")
        && iconProfileSource.contains("borderOpacity: 0.14")
        && iconProfileSource.contains("usesActiveColorwayBorder: true")
)

check(
    "SFX song chip uses compact optical compensation at its original icon size",
    songChipSource.contains("if usesSFXMark && artworkData == nil")
        && songChipSource.contains("private var sfxChipContent: some View")
        && songChipSource.contains("let profile = SFXIconBoxRenderingProfile.compact")
        && songChipSource.contains("profile: profile")
        && songChipSource.contains("SFXCard.pearlIconFill")
        && songChipSource.contains("profile.iconBloomColor")
        && songChipSource.contains("MixrSFXMarkGlyph(size: 13 * 0.95 * 0.95")
        && songChipSource.contains("Color.white.opacity(profile.iconCoreGlowOpacity)")
        && songChipSource.contains("radius: profile.iconCoreGlowRadius")
        && songChipSource.contains("radius: profile.iconBloomRadius")
        && songChipSource.contains(".frame(width: 34, height: 34)")
)

check(
    "SFX reference row uses an inset purple-black-navy glass card",
    timelineSource.contains(
        ".background(MixrTrackRowBackground(isSFXTrack: track.isSFXTrack))"
    )
        && timelineSource.contains(".frame(maxWidth: .infinity, alignment: .leading)")
        && designPreviewSource.contains(
            ".background(MixrTrackRowBackground(isSFXTrack: true))"
        )
        && trackRowBackgroundSource.contains("struct MixrTrackRowBackground: View")
        && trackRowBackgroundSource.contains("RoundedRectangle(cornerRadius: 9")
        && matches(
            #"Color\(hex: \"241A39\"\)\.opacity\(0\.96\)[\s\S]*?location: 0[\s\S]*?Color\(hex: \"090B13\"\)\.opacity\(0\.98\)[\s\S]*?location: 0\.5325[\s\S]*?Color\(hex: \"162239\"\)\.opacity\(0\.96\)[\s\S]*?location: 1"#,
            in: trackRowBackgroundSource
        )
        && trackRowBackgroundSource.contains("Color(hex: \"A281BC\").opacity(0.34)")
        && trackRowBackgroundSource.contains("lineWidth: 0.6")
        && trackRowBackgroundSource.contains(".padding(.leading, 19.5)")
        && trackRowBackgroundSource.contains(".padding(.trailing, 5)")
        && trackRowBackgroundSource.contains(".padding(.vertical, 2)")
        && !trackRowBackgroundSource.contains(".offset(x: -0.5)")
        && trackRowBackgroundSource.contains("Color.black.opacity(0.32)")
        && trackRowBackgroundSource.contains("radius: 3")
)

check(
    "SFX compact profile balances full-strength color with the menu navy",
    iconProfileSource.contains("struct SFXIconBoxRenderingProfile")
        && iconProfileSource.contains("static let standard")
        && iconProfileSource.contains("static let compact")
        && iconProfileSource.contains("navyWashColor: Color(hex: \"172238\")")
        && iconProfileSource.contains("navyWashOpacity: 0.16")
        && iconProfileSource.contains("luminanceWashOpacity: 0.12")
        && compactProfileSource.contains("radialPrimaryOpacity: 0.28")
        && compactProfileSource.contains("radialSecondaryOpacity: 0.16")
        && compactProfileSource.contains("borderOpacity: 0.32")
        && compactProfileSource.contains("iconCoreGlowOpacity: 0.34")
        && compactProfileSource.contains("iconCoreGlowRadius: 1.6")
        && compactProfileSource.contains("iconBloomRadius: 2.5")
        && cardSource.contains("var profile: SFXIconBoxRenderingProfile = .standard")
        && cardSource.contains("profile.navyWashColor.opacity(profile.navyWashOpacity)")
        && cardSource.contains("profile.luminanceWashColor.opacity(profile.luminanceWashOpacity)")
        && cardSource.contains("Color(hex: \"C78BC4\").opacity(profile.radialPrimaryOpacity)")
        && cardSource.contains("profile.radialSecondaryColor.opacity(profile.radialSecondaryOpacity)")
        && cardSource.contains("tileShape.strokeBorder(profile.borderColor, lineWidth: 0.75)")
        && iconProfileSource.contains("borderTint.opacity(borderOpacity)")
)

check(
    "SFX compact profile keeps the pink-purple edge but matches the menu icon glow",
    iconProfileSource.contains("luminanceWashColor: Color(hex: \"D88BC8\")")
        && iconProfileSource.contains("radialSecondaryColor: Color(hex: \"A98BE8\")")
        && iconProfileSource.contains("borderTint: Color(hex: \"D9B6EE\")")
        && compactProfileSource.contains(
            "iconBloomColor: SFXCard.iconBloomColor.opacity(0.35)"
        )
        && !compactProfileSource.contains(
            "iconBloomColor: Color(hex: \"D88BC8\").opacity(0.40)"
        )
        && !compactProfileSource.contains("iconCoreGlowOpacity: 0.56")
        && iconProfileSource.contains(
            "outerGlowColor: Color(hex: \"D88BC8\").opacity(0.10)"
        )
        && compactProfileSource.contains("outerGlowRadius: 3.5")
        && cardSource.contains("profile.luminanceWashColor.opacity")
        && cardSource.contains("profile.radialSecondaryColor.opacity")
        && cardSource.contains("color: profile.outerGlowColor")
        && cardSource.contains("radius: profile.outerGlowRadius")
        && songChipSource.contains("color: profile.iconBloomColor")
        && !songChipSource.contains("color: SFXCard.iconBloomColor")
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
        && colorsSource.contains("static let sfxWaveformBottom = Color(hex: \"CFC6EE\")")
        && colorsSource.contains("static let sfxOutline = Color(hex: \"CDC2F4\")")
        && colorsSource.contains("static let sfxWaveformGlow = Color(hex: \"E6E1F4\")")
        && colorsSource.contains("static let sfxMenuLavender = Color(hex: \"C9B9F4\")")
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
    "SFX uses the system presentation backdrop without a custom blur overlay",
    sfxOverlaySource.contains(".presentationBackground(.clear)")
        && !sfxOverlaySource.contains("Color.black.opacity(0.52)")
        && !sfxOverlaySource.contains(".fill(.ultraThinMaterial)")
)

check(
    "SFX menu tracks its two horizontal pages",
    source.contains("@State private var selectedPage: Int? = 0")
        && source.contains(".scrollPosition(id: $selectedPage)")
        && matches(
            #"ForEach\(Array\(Self\.pages\.enumerated\(\)\), id:\s*\\\.offset\)\s*\{\s*index, page in"#
        )
        && source.contains(".id(index)")
)

check(
    "SFX menu shows exactly one small dot per available page at the bottom",
    matches(#"pageIndicatorDotSize\s*:\s*CGFloat\s*=\s*4"#)
        && matches(#"pageIndicatorSpacing\s*:\s*CGFloat\s*=\s*5"#)
        && matches(#"pageIndicatorBottomInset\s*:\s*CGFloat\s*=\s*6"#)
        && source.contains(".overlay(alignment: .bottom)")
        && matches(
            #"ForEach\(Self\.pages\.indices, id:\s*\\\.self\)\s*\{\s*page in"#
        )
        && matches(
            #"\.frame\(\s*width:\s*SFXMetrics\.pageIndicatorDotSize,\s*height:\s*SFXMetrics\.pageIndicatorDotSize\s*\)"#
        )
)

let playbackSource = try! String(
    contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Mixr/Models/MixrPlaybackEngine.swift"),
    encoding: .utf8
)
let exportSource = try! String(
    contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Mixr/Models/MixrExportRenderer.swift"),
    encoding: .utf8
)
let soundEffectsSource = try! String(
    contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Mixr/Models/SoundEffects.swift"),
    encoding: .utf8
)
let applierSource = try! String(
    contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Mixr/Models/AutoRemixApplier.swift"),
    encoding: .utf8
)

check(
    "Extra SFX rows have no extra header chrome (top row owns chip)",
    timelineSource.contains("showsSFXChrome:")
        && timelineSource.contains("isSFXSpillLane")
        && timelineSource.contains("Spill SFX rows: gradient only")
        && timelineSource.contains("primarySFXID")
)

check(
    "SFX packing keeps per-row nonOverlappingStart and placeExact spill lanes",
    soundEffectsSource.contains("static func placeExact(")
        && soundEffectsSource.contains("static func fitsExactly(")
        && soundEffectsSource.contains("static func nonOverlappingStart(")
        && applierSource.contains("SoundEffectLibrary.placeExact(")
        && !applierSource.contains("overlappingStart")
)

check(
    "Playback mixes every SFX track (not first-only)",
    playbackSource.contains("sfxChains")
        && playbackSource.contains("for sfxTrack in snapshot where sfxTrack.isSFXTrack")
        && !playbackSource.contains("first(where: { $0.isSFXTrack })")
        && playbackSource.contains("ensureSFXChain(trackID:")
)

check(
    "Export mixes every SFX track (not first-only)",
    exportSource.contains("sfxPlayers")
        && exportSource.contains("for sfxTrack in tracks where sfxTrack.isSFXTrack")
        && !exportSource.contains("first(where: { $0.isSFXTrack })")
)

if failures > 0 {
    exit(1)
}
