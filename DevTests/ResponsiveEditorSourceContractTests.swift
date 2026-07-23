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
    "Destructive project confirmation uses a native alert",
    timelineSource.contains(".alert(")
        && timelineSource.contains("Button(\"Delete\", role: .destructive")
        && !timelineSource.contains("DeleteProjectConfirmDialog(")
)

check(
    "Auto scope uses a native confirmation dialog",
    timelineSource.contains(".confirmationDialog(")
        && timelineSource.contains("Button(\"Entire Project\")")
        && timelineSource.contains("Button(\"Cancel\", role: .cancel)")
        && !timelineSource.contains("AutoScopeDialog(")
)

check(
    "Project selection uses a native menu while preserving long-press rename",
    timelineSource.contains("private struct TLNativeProjectMenuButton: UIViewRepresentable")
        && timelineSource.contains("showsMenuAsPrimaryAction = true")
        && timelineSource.contains("attributes: .destructive")
        && timelineSource.contains("UILongPressGestureRecognizer")
        && !timelineSource.contains("ProjectDropdownMenu(")
)

check(
    "SFX presentation adapts between native popover and sheet",
    timelineSource.contains("private struct TLSFXLibraryPresentation: ViewModifier")
        && timelineSource.contains("content.popover(")
        && timelineSource.contains("content.sheet(isPresented:")
        && timelineSource.contains(".presentationCompactAdaptation(.sheet)")
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
