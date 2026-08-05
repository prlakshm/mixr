import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let layoutURL = root.appendingPathComponent("Mixr/DesignSystem/EditorLayoutMetrics.swift")
let timelineURL = root.appendingPathComponent("Mixr/TimelineScreen.swift")
let layoutSource = (try? String(contentsOf: layoutURL, encoding: .utf8)) ?? ""
let timelineSource = try String(contentsOf: timelineURL, encoding: .utf8)

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

check(
    "Responsive layout rules are centralized in a reusable model",
    layoutSource.contains("struct EditorLayoutMetrics")
        && layoutSource.contains("minimumTracksWidth")
        && layoutSource.contains("idealTracksWidth")
        && layoutSource.contains("minimumControlsWidth")
        && layoutSource.contains("idealControlsWidth")
)

check(
    "Layout mode comes from actual available width",
    layoutSource.contains("containerSize.width")
        && !layoutSource.contains("UIDevice")
        && !layoutSource.contains("userInterfaceIdiom")
        && !layoutSource.contains("device.name")
)

check(
    "Timeline receives adaptive Tracks, Controls, and footer dimensions",
    timelineSource.contains("sidebarWidth: layout.tracksWidth")
        && timelineSource.contains("controlsWidth: layout.controlsWidth")
        && timelineSource.contains("importFooterHeight: layout.importFooterHeight")
)

check(
    "Effects state is scene-persistent and drives non-overlay reflow",
    timelineSource.contains("@SceneStorage(\"editor.effects.isCollapsed\")")
        && timelineSource.contains(".frame(height: layout.effectsHeight)")
        && timelineSource.contains(".frame(height: layout.timelineHeight)")
)

check(
    "Compact transport is selected by content-driven layout mode",
    timelineSource.contains("layoutMode: layout.mode")
        && timelineSource.contains("case .compact")
        && timelineSource.contains("case .regular")
)

check(
    "Effects cards continue to scroll inside their own component",
    timelineSource.contains("ScrollView(.horizontal")
        && timelineSource.contains("TLK.compactEffectCardWidth")
        && !timelineSource.contains("scaleEffect(layout")
)

check(
    "Effects panel size comes from the layout model, not the screen it is on",
    layoutSource.contains("baseEffectCardWidth")
        && layoutSource.contains("effectsHeightShareCeiling")
        && timelineSource.contains("cardWidth: layout.effectCardWidth")
        && timelineSource.contains("cardHeight: layout.effectCardHeight")
        && timelineSource.contains("contentScale: layout.contentScale")
)

check(
    "Editor content is laid out inside the window's chrome bands",
    layoutSource.contains("struct EditorSafeArea")
        && layoutSource.contains("minimumTopChrome")
        && timelineSource.contains("onWindowSafeAreaChange")
        && timelineSource.contains(".padding(safeArea.edgeInsets)")
        && timelineSource.contains("EditorEdgeFade(")
        && timelineSource.contains("safeArea: safeArea,")
        && timelineSource.contains(".statusBarHidden(prefersStatusBarHidden)")
)

check(
    "Toolbar groups are placed by the tested transport model",
    layoutSource.contains("struct EditorTransportLayout")
        && layoutSource.contains("minimumClusterGap")
        && timelineSource.contains("transportPlacement: layout.transport")
        && timelineSource.contains(".offset(x: transportPlacement.centreOffset)")
        // The old fixed nudge must not come back.
        && !timelineSource.contains(".offset(x: 63)")
)

check(
    "Transport buttons stay plain so Mac Catalyst adds no bordered chrome",
    timelineSource.contains("Button(\"Skip to Start\", systemImage: \"backward.end.fill\")")
        && timelineSource.range(
            of: "playback.skipToStart\\(\\)[\\s\\S]{0,240}buttonStyle\\(\\.plain\\)",
            options: .regularExpression
        ) != nil
        && timelineSource.range(
            of: "playback.togglePlayPause\\(\\)[\\s\\S]{0,240}buttonStyle\\(\\.plain\\)",
            options: .regularExpression
        ) != nil
        && timelineSource.range(
            of: "playback.skipToEnd\\(\\)[\\s\\S]{0,240}buttonStyle\\(\\.plain\\)",
            options: .regularExpression
        ) != nil
)

check(
    "The nav-title frame preference ignores empty sibling contributions",
    timelineSource.contains("guard next != .zero else { return }")
)

check(
    "Debug-only QA state hooks never ship in the editor",
    !timelineSource.contains("-MixrQA")
)

// The editor's modals are the hand-built Mixr alert chrome, not system
// alerts — they carry the app's glass, party-mode borders and press styling,
// and they scale with the layout the way the rest of the chrome does.
check(
    "Destructive project confirmation uses the Mixr confirm dialog",
    timelineSource.contains("DeleteProjectConfirmDialog(")
        && timelineSource.contains("projectName: library.projectName")
        && !timelineSource.contains("Button(\"Delete\", role: .destructive")
)

check(
    "Auto scope uses the Mixr scope dialog",
    timelineSource.contains("AutoScopeDialog(")
        && timelineSource.contains("hasSelectedClip: selectedClipID != nil")
        && !timelineSource.contains(".confirmationDialog(")
)

check(
    "Auto failure uses the Mixr error sheet",
    timelineSource.contains("AutoRemixErrorSheet(")
        && !timelineSource.contains("\"Auto couldn't finish\",")
)

let alertURL = root.appendingPathComponent("Mixr/DesignSystem/MixrAlertChrome.swift")
let alertSource = (try? String(contentsOf: alertURL, encoding: .utf8)) ?? ""
check(
    "Alert chrome scales with the layout, capped short of it",
    alertSource.contains("static func scale(forContentScale")
        && alertSource.contains("maximumScale")
        && timelineSource.contains("MixrAlertChrome.scale(forContentScale:")
        && timelineSource.contains("scale: alertScale")
)

check(
    "Project selection uses the custom Mixr menu while preserving long-press rename",
    timelineSource.contains("@State private var showProjectMenu = false")
        && timelineSource.contains("ProjectDropdownMenu(")
        && timelineSource.contains("ProjectTitleFrameKey.self")
        && timelineSource.contains("TLProjectTitleInteractionModifier(")
        && timelineSource.contains("y: layout.transportHeight - 4")
        && !timelineSource.contains("TLNativeProjectMenuButton")
)

// The library panel brings its own glass, so it is presented as an in-app
// overlay — a system sheet or popover would draw an opaque slab behind it.
check(
    "SFX library is presented as an in-app overlay over a dimmed timeline",
    timelineSource.contains("SFXLibraryPanel(")
        && timelineSource.contains("dismissSFXPanel()")
        && !timelineSource.contains("TLSFXLibraryPresentation")
        && !timelineSource.contains(".presentationCompactAdaptation(")
)

check(
    "Transport controls remain named native buttons with minimum hit targets",
    timelineSource.contains("Button(\"Skip to Start\", systemImage: \"backward.end.fill\")")
        && timelineSource.contains("playback.isPlaying ? \"Pause\" : \"Play\"")
        && timelineSource.contains("Button(\"Skip to End\", systemImage: \"forward.end.fill\")")
        && timelineSource.contains(".frame(minWidth: 44, minHeight: 44)")
        && timelineSource.contains(".frame(width: 44, height: 44)")
)

check(
    "Import remains wired to a native file importer from both editor entry points",
    timelineSource.contains(".fileImporter(")
        && timelineSource.contains("private var importSongsButton")
        && timelineSource.contains("onImport: { showFilePicker = true }")
        && timelineSource.contains("showFilePicker = true")
)

check(
    "Effects tap and drag share the tested interaction rules",
    timelineSource.contains(
        "isCollapsed = EditorEffectsInteraction.toggled(isCollapsed)"
    )
        && timelineSource.contains(
            "EditorEffectsInteraction.collapsedState("
        )
        && timelineSource.contains(
            ".accessibilityLabel(isCollapsed ? \"Expand Effects\" : \"Collapse Effects\")"
        )
)

check(
    "Narrow resizable windows keep the editor instead of showing a rotate gate",
    !timelineSource.contains("TLRotateOverlay()")
)

let typographyURL = root.appendingPathComponent("Mixr/DesignSystem/MixrTypography.swift")
let typographySource = (try? String(contentsOf: typographyURL, encoding: .utf8)) ?? ""
check(
    "Dense editor typography responds to accessibility text sizes",
    typographySource.contains("@ScaledMetric")
        && typographySource.contains("relativeTo: style.relativeTextStyle")
        && timelineSource.contains(".mixrScaledFont(")
)

if failures > 0 {
    exit(1)
}
