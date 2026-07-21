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
let renderStateSource = source("Mixr/DesignSystem/PartyModeRenderState.swift")
let traceShapesSource = source("Mixr/DesignSystem/PartyModeTraceShapes.swift")
let appSource = source("Mixr/MixrApp.swift")
let contentSource = source("Mixr/ContentView.swift")
let timelineSource = source("Mixr/TimelineScreen.swift")
let glassSource = source("Mixr/DesignSystem/GlassCardModifier.swift")
let buttonSource = source("Mixr/DesignSystem/MixrButtonStyles.swift")
let partyButtonSource = source("Mixr/DesignSystem/PartyModeButtonStyles.swift")
let mainChromeSource = source("Mixr/DesignSystem/PartyModeMainChromeOverlay.swift")
let mainChromeRowSource = source("Mixr/DesignSystem/PartyModeMainPanelRow.swift")
let visualCaptureSource = source("Mixr/DesignSystem/PartyModeVisualQACapture.swift")
let songChipSource = source("Mixr/DesignSystem/MixrSongColorChip.swift")
let playbackSource = source("Mixr/Models/MixrPlaybackEngine.swift")

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
    "Shared tokens centralize the five-layer glow and finite trace timing",
    ["electricBlue", "coolCyan", "violet", "lavender", "magenta", "glintWhite",
     "coreStrokeWidth", "nearGlowRadius", "mediumGlowRadius", "ambientGlowRadius",
     "nearGlowStrokeScale", "mediumGlowStrokeScale", "ambientGlowStrokeScale",
     "innerHighlightWidth", "activationSequenceDuration", "traceDurationPanel",
     "reconnectFlareDuration", "afterglintDuration", "exitFadeDuration"].allSatisfy(tokensSource.contains)
)

check(
    "Trace and afterglint share a centralized 75 percent velocity",
    matches(#"motionVelocity\s*:\s*Double\s*=\s*0\.75"#, in: tokensSource)
        && tokensSource.contains("durationAtPartyVelocity")
        && modifierSource.contains("PartyModeTokens.durationAtPartyVelocity")
)

check(
    "Returning glints use one global post-connection start",
    tokensSource.contains("globalAfterglintStartTime")
        && tokensSource.contains("activationSequenceDuration =")
        && renderStateSource.contains("PartyModeTokens.globalAfterglintStartTime")
        && !renderStateSource.contains("from: traceEnd + PartyModeTokens.reconnectFlareDuration")
)

check(
    "Bloom energy comes from wider blurred light strokes, not a thicker visible core",
    modifierSource.contains("PartyModeTokens.nearGlowStrokeScale")
        && modifierSource.contains("PartyModeTokens.mediumGlowStrokeScale")
        && modifierSource.contains("PartyModeTokens.ambientGlowStrokeScale")
        && matches(#"\.stroke\(gradient, lineWidth: role\.strokeWidth\)"#, in: modifierSource)
)

check(
    "Activation host drives one finite sequence, cancels stale runs, and honors Reduce Motion",
    hostSource.contains("accessibilityReduceMotion")
        && hostSource.contains("activationTask?.cancel()")
        && hostSource.contains("await Task.yield()")
        && hostSource.contains("PartyModeTokens.activationSequenceDuration")
        && hostSource.contains("isActivationActive = false")
        && !hostSource.contains("TimelineView")
        && !hostSource.contains("repeatForever")
)

check(
    "Per-surface animation exposes trace, reconnection flare, afterglint, and settled border state",
    ["activationProgress", "isActivationActive", "traceProgress",
     "reconnectFlareProgress", "afterglintProgress", "settledBorderOpacity"]
        .allSatisfy(renderStateSource.contains)
        && renderStateSource.contains("PartyModeSurfaceAnimationPhase")
        && renderStateSource.contains("role.activationDelay(for: offset)")
        && modifierSource.contains("func activationDelay(for offset:")
)

check(
    "Trace paths have deterministic starts and wrapping trim fragments",
    traceShapesSource.contains("PartyModeClockwiseRoundedRectangle")
        && traceShapesSource.contains("PartyModeClockwiseCircle")
        && traceShapesSource.contains("startPoint(in rect:")
        && traceShapesSource.contains("PartyModeTrimSegments")
        && traceShapesSource.contains("wrapped")
)

check(
    "Shared shape-aware modifier provides role and lighting variants",
    modifierSource.contains("enum PartyModeSurfaceRole")
        && modifierSource.contains("enum PartyModeLightingVariant")
        && modifierSource.contains("case play")
        && modifierSource.contains("case sfxSurface")
        && modifierSource.contains("case sfxClip")
        && modifierSource.contains("mediumGlowOpacity")
        && modifierSource.contains("innerHighlightOpacity")
        && modifierSource.contains("func partyModeBorder")
        && modifierSource.contains("PartyModeTraceHead")
        && modifierSource.contains("PartyModeReconnectFlare")
        && modifierSource.contains("PartyModeAfterglint")
        && modifierSource.contains("afterglintHeadSegments")
        && !modifierSource.contains("TimelineView")
)

check(
    "Timeline semantic clip outlines remain static rather than receiving racecar tracing",
    modifierSource.contains("var tracesDuringActivation")
        && modifierSource.contains("case .timelineClip, .sfxClip, .trackChip: false")
)

check(
    "Glass cards and shared glass buttons inherit Party Mode",
    glassSource.contains("partyModeBorder")
        && buttonSource.contains("partyModeBorder")
)

check(
    "Main panel ambient glow is rendered outside clipped application content",
    mainChromeSource.contains("struct PartyModeMainChromeOverlay")
        && mainChromeSource.contains("PartyModeMainPanelRow")
        && mainChromeRowSource.contains("struct PartyModeMainPanelRow")
        && mainChromeRowSource.contains("role: .majorPanel")
        && timelineSource.contains("PartyModeMainChromeOverlay(")
        && matches(
            #"\.clipped\(\)[\s\S]{0,240}PartyModeMainChromeOverlay\("#,
            in: timelineSource
        )
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
        && ["playOuterRimInset", "playInnerRingInset", "playNearAuraRadius",
            "playAmbientAuraRadius"].allSatisfy(tokensSource.contains)
        && partyButtonSource.contains("PartyModeTokens.playOuterRimInset")
        && partyButtonSource.contains("PartyModeTokens.playInnerRingInset")
        && partyButtonSource.contains("PartyModeTokens.playAmbientAuraRadius")
        && partyButtonSource.contains(".stroke(")
        && partyButtonSource.contains("animationPhase(for: .play")
        && partyButtonSource.contains("ringReveal")
)

check(
    "Party glass depth is centralized and guaranteed transparent in normal mode",
    glassSource.contains("partyModeDepthOpacity")
        && glassSource.contains("renderState.chromeOpacity")
        && glassSource.contains("Color.black.opacity")
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

check(
    "Screenshot verification avoids simulator-only audio graph RPC failures",
    playbackSource.contains("isPartyModeScreenshotVerification")
        && playbackSource.contains("-MixrVisualQAScreenshot")
        && playbackSource.contains("guard !isPartyModeScreenshotVerification else { return }")
)

check(
    "Screenshot verification preserves an existing landscape canvas and rotates only portrait hosts",
    contentSource.contains("PartyModeScreenshotVerificationContainer")
        && contentSource.contains("-MixrVisualQAScreenshot")
        && contentSource.contains("proxy.size.width >= proxy.size.height")
        && contentSource.contains("frame(width: proxy.size.height, height: proxy.size.width)")
        && contentSource.contains("rotationEffect(.degrees(90))")
)

check(
    "Debug visual QA captures the live app window without simctl framebuffer access",
    visualCaptureSource.contains("enum PartyModeVisualQACapture")
        && visualCaptureSource.contains("UIWindow")
        && visualCaptureSource.contains("window.layer.render")
        && visualCaptureSource.contains("documentDirectory")
        && contentSource.contains("PartyModeVisualQACapture.capture")
)

check(
    "Debug live capture requests the latest committed SwiftUI hierarchy",
    visualCaptureSource.contains("layoutIfNeeded")
        && visualCaptureSource.contains("drawHierarchy")
        && visualCaptureSource.contains("afterScreenUpdates: true")
        && visualCaptureSource.contains("window.layer.render")
)

check(
    "Debug screenshot capture can freeze the real activation renderer at an exact phase",
    contentSource.contains("-MixrPartyModeCaptureProgress")
        && hostSource.contains("partyModeCaptureProgress")
        && hostSource.contains("activationProgress = captureProgress")
)

check(
    "Debug visual QA captures the complete live activation in one launch",
    contentSource.contains("-MixrPartyModeCaptureSequence")
        && contentSource.contains("captureLiveActivationSequence")
        && contentSource.contains("PartyModeTokens.activationSequenceDuration")
        && contentSource.contains("mixr-party-live-settled.png")
)

check(
    "Visual QA checkpoints are derived from phase times instead of stale normalized values",
    contentSource.contains("elapsed: TimeInterval")
        && contentSource.contains("PartyModeTokens.globalAfterglintStartTime")
        && !contentSource.contains("(\"mixr-party-live-initial.png\", 0.120)")
)

check(
    "Live activation capture defers PNG encoding until after all timed snapshots",
    visualCaptureSource.contains("struct Frame")
        && visualCaptureSource.contains("static func snapshot")
        && visualCaptureSource.contains("static func write(_ frame: Frame)")
        && contentSource.contains("var frames: [PartyModeVisualQACapture.Frame]")
        && contentSource.contains("frames.append")
        && contentSource.contains("PartyModeVisualQACapture.write(frame)")
)

if failures > 0 {
    exit(1)
}
