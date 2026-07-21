import Foundation

// Lightweight architecture and behavior contracts for Party Mode. Mixr has no
// XCTest target, so this follows the existing DevTests source-harness pattern.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

let stateSource = source("Mixr/DesignSystem/AppAppearanceState.swift")
let tokensSource = source("Mixr/DesignSystem/PartyModeTokens.swift")
let modifierSource = source("Mixr/DesignSystem/PartyModeBorderModifier.swift")
let hostSource = source("Mixr/DesignSystem/PartyModeAnimationHost.swift")
let appSource = source("Mixr/MixrApp.swift")
let contentSource = source("Mixr/ContentView.swift")
let timelineSource = source("Mixr/TimelineScreen.swift")
let glassSource = source("Mixr/DesignSystem/GlassCardModifier.swift")
let buttonSource = source("Mixr/DesignSystem/MixrButtonStyles.swift")
let songChipSource = source("Mixr/DesignSystem/MixrSongColorChip.swift")

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

func matches(_ pattern: String, in text: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

check(
    "Appearance state is observable, main-actor isolated, and defaults off",
    stateSource.contains("@MainActor")
        && stateSource.contains("@Observable")
        && stateSource.contains("final class AppAppearanceState")
        && matches(#"isPartyModeEnabled\s*=\s*false"#, in: stateSource)
)

check(
    "Every activation advances a nonpersistent sequence",
    stateSource.contains("partyModeActivationID")
        && stateSource.contains("func togglePartyMode()")
        && stateSource.contains("partyModeActivationID &+= 1")
        && !stateSource.contains("UserDefaults")
        && !stateSource.contains("@AppStorage")
)

check(
    "Appearance and render state are owned above TimelineScreen",
    appSource.contains("@State private var appearanceState")
        && appSource.contains(".environment(appearanceState)")
        && contentSource.contains("PartyModeAnimationHost")
        && contentSource.contains("TimelineScreen()")
)

check(
    "Shared tokens centralize palette, stroke, glow, and timing",
    ["electricBlue", "coolCyan", "violet", "lavender", "magenta", "glintWhite",
     "primaryStrokeWidth", "nearGlowRadius", "ambientGlowRadius", "glintDuration",
     "exitFadeDuration"].allSatisfy(tokensSource.contains)
)

check(
    "Glint host is finite, cancellable, and honors Reduce Motion",
    hostSource.contains("accessibilityReduceMotion")
        && hostSource.contains("glintTask?.cancel()")
        && hostSource.contains("await Task.yield()")
        && hostSource.contains("PartyModeTokens.glintArmingDelay")
        && hostSource.contains("isGlintActive = false")
        && !hostSource.contains("TimelineView")
        && !hostSource.contains("repeatForever")
)

check(
    "Shared shape-aware modifier provides role and lighting variants",
    modifierSource.contains("enum PartyModeSurfaceRole")
        && modifierSource.contains("enum PartyModeLightingVariant")
        && modifierSource.contains("case play")
        && modifierSource.contains("case sfxSurface")
        && modifierSource.contains("case sfxClip")
        && modifierSource.contains("var glintOpacity")
        && modifierSource.contains("func partyModeBorder")
        && modifierSource.contains("Shape")
        && !modifierSource.contains("glintProgress > 0")
)

check(
    "Glass cards and shared glass buttons inherit Party Mode",
    glassSource.contains("partyModeBorder")
        && buttonSource.contains("partyModeBorder")
)

check(
    "Logo and wordmark are a single 44-point target separate from project title",
    timelineSource.contains("accessibilityLabel(\"Toggle Party Mode\")")
        && matches(#"Button\s*\{\s*appearanceState\.togglePartyMode\(\)[\s\S]*?frame\(minHeight:\s*44\)"#, in: timelineSource)
        && timelineSource.contains("projectTitleControl")
)

check(
    "Play button uses the specialized Party Mode treatment",
    timelineSource.contains("partyModePlayButton")
)

check(
    "Song chips preserve semantic color and current SFX pearl treatment",
    songChipSource.contains("semanticColor: color.color")
        && songChipSource.contains("semanticColor: MixrColors.sfxGlow")
        && songChipSource.contains("SFXIconBoxSurface")
)

check(
    "SFX clips and the current SFX row use dedicated pearl-lavender Party chrome",
    source("Mixr/DesignSystem/WaveformClip.swift").contains(".sfxClip")
        && source("Mixr/DesignSystem/MixrTrackRowBackground.swift").contains("role: .sfxSurface")
)

if failures > 0 {
    exit(1)
}
