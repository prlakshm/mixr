import Foundation

let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/SFXComponents.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let timelineURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/TimelineScreen.swift")
let timelineSource = try String(contentsOf: timelineURL, encoding: .utf8)

let cardStart = source.range(of: "struct SFXCard: View")?.lowerBound ?? source.startIndex
let cardEnd = source.range(of: "// MARK: - SFX Library Panel")?.lowerBound ?? source.endIndex
let cardSource = String(source[cardStart..<cardEnd])
let overlayStart = timelineSource.range(of: "if showSFXPanel")?.lowerBound
    ?? timelineSource.startIndex
let overlayEnd = timelineSource.range(
    of: "// Auto scope dialog",
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
    "SFX menu scales uniformly with a ten point upward optical correction",
    sfxOverlaySource.contains("ZStack(alignment: .center)")
        && sfxOverlaySource.contains(
            ".scaleEffect(SFXMetrics.panelDisplayScale, anchor: .center)"
        )
        && matches(#"panelOpticalOffsetY\s*:\s*CGFloat\s*=\s*-10"#)
        && sfxOverlaySource.contains(".offset(y: SFXMetrics.panelOpticalOffsetY)")
        && matches(
            #"\.frame\(\s*width:\s*screenSize\.width,\s*height:\s*screenSize\.height,\s*alignment:\s*\.center\s*\)"#,
            in: sfxOverlaySource
        )
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
        && source.contains(".padding(.bottom, padV)")
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
    cardSource.contains("private enum Colorway")
        && cardSource.contains("case version1Colored")
        && cardSource.contains("case version2GrayLavender")
        && cardSource.contains(
            "private static let activeColorway: Colorway = .version2GrayLavender"
        )
        && cardSource.contains("Color(hex: \"D88BC8\").opacity(0.20)")
        && cardSource.contains("Color(hex: \"D1B9FA\").opacity(0.91)")
        && cardSource.contains("Color(hex: \"8E739F\").opacity(0.21)")
        && cardSource.contains("pearlLavender.opacity(0.30)")
        && cardSource.contains("Color(hex: \"C9B9F4\").opacity(0.88)")
        && cardSource.contains("Color.white.opacity(0.14)")
)

check(
    "SFX icon wells use the active colorway border",
    matches(#"cardIconTileSizeFraction\s*:\s*CGFloat\s*=\s*0\.47"#)
        && matches(#"cardIconTileCornerRadius\s*:\s*CGFloat\s*=\s*12"#)
        && cardSource.contains("min(68, max(49, height * SFXMetrics.cardIconTileSizeFraction))")
        && cardSource.contains(".background { iconTile }")
        && cardSource.contains("private var iconTile: some View")
        && cardSource.contains("Color(hex: \"272337\").opacity(0.90)")
        && cardSource.contains("Color(hex: \"C78BC4\").opacity(0.13)")
        && cardSource.contains("pearlLavender.opacity(0.07)")
        && cardSource.contains(
            "tileShape.strokeBorder(iconTileBorderColor, lineWidth: 0.75)"
        )
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
        && cardSource.contains("color: iconBloomColor")
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
        && cardSource.contains("Color(hex: \"C9B9F4\").opacity(0.88)")
)

check(
    "SFX symbols are smaller inside the reference-sized wells",
    cardSource.contains("min(36, max(24, height * 0.26))")
)

check(
    "SFX type follows the reference hierarchy",
    cardSource.contains(".font(.system(size: titleSize, weight: .semibold))")
        && cardSource.contains(".foregroundStyle(durationColor)")
        && cardSource.contains("VStack(spacing: 4)")
        && cardSource.contains("VStack(spacing: height * 0.10)")
        && cardSource.contains(".padding(.vertical, height * 0.08)")
)

check(
    "SFX backdrop keeps the timeline sharp behind the original dim overlay",
    sfxOverlaySource.contains("Color.black.opacity(0.52)")
        && !sfxOverlaySource.contains(".fill(.ultraThinMaterial)")
)

if failures > 0 {
    exit(1)
}
