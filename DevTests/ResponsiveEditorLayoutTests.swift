import CoreGraphics
import Foundation

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print("\(passed ? "PASS" : "FAIL")  \(name)")
    if !passed { failures += 1 }
}

func checkClose(
    _ name: String,
    _ actual: CGFloat,
    _ expected: CGFloat,
    tolerance: CGFloat = 0.001
) {
    check(name, abs(actual - expected) <= tolerance)
}

// iPhone 17 Pro landscape once the Dynamic Island bands are removed — the
// geometry the phone actually renders, and the baseline every other screen
// scales up from.
let approvedPhone = EditorLayoutMetrics(
    containerSize: CGSize(width: 750, height: 382),
    effectsState: .expanded
)
check("Approved phone uses the regular one-row transport", approvedPhone.mode == .regular)
checkClose("Approved phone keeps the Tracks ideal width", approvedPhone.tracksWidth, 208)
checkClose("Approved phone keeps the Controls ideal width", approvedPhone.controlsWidth, 130)
checkClose("Approved phone gives remaining width to the timeline", approvedPhone.timelineWidth, 412)
checkClose("Expanded Effects uses the approved height", approvedPhone.effectsHeight, 118)
checkClose("Regular transport uses the approved height", approvedPhone.transportHeight, 50)

checkClose("Approved phone keeps the phone-baseline toolbar", approvedPhone.transport.scale, 1)
checkClose("Approved phone keeps the phone-baseline card", approvedPhone.effectCardWidth, 152)
check("Approved phone leaves the transport uncramped", !approvedPhone.transport.isCramped)

let largeTablet = EditorLayoutMetrics(
    containerSize: CGSize(width: 1366, height: 1024),
    effectsState: .expanded
)
checkClose(
    "Tracks keeps the desktop share of a tablet's width",
    largeTablet.tracksWidth,
    1366 * EditorLayoutMetrics.tracksWidthShare
)
checkClose(
    "Controls keeps the desktop share of a tablet's width",
    largeTablet.controlsWidth,
    1366 * EditorLayoutMetrics.controlsWidthShare
)
check(
    "Side panels never fall below the phone's ideals",
    EditorLayoutMetrics(
        containerSize: CGSize(width: 750, height: 382),
        effectsState: .expanded
    ).tracksWidth == EditorLayoutMetrics.idealTracksWidth
)
check(
    "A full track stack fills most of the timeline on a tablet",
    (0.8...0.92).contains(
        6 * EditorLayoutMetrics.trackRowHeight(
            timelineHeight: largeTablet.timelineHeight,
            rulerHeight: 20,
            trackCount: 6
        ) / (largeTablet.timelineHeight - 20)
    )
)
check(
    "The phone keeps its 46pt rows",
    EditorLayoutMetrics.trackRowHeight(
        timelineHeight: 214, rulerHeight: 20, trackCount: 6
    ) == EditorLayoutMetrics.baseTrackRowHeight
)
check(
    "Additional tablet width goes to the timeline",
    largeTablet.timelineWidth > approvedPhone.timelineWidth
)
check("Tablets take the large toolbar density", largeTablet.density == .large)
check(
    "Tablet cards span the panel at the phone's rhythm",
    abs(
        largeTablet.effectCardWidth
            - 1366 / EditorLayoutMetrics.effectRowSpanPerCard
            * EditorLayoutMetrics.baseEffectCardWidth
    ) <= 1
)
check(
    "Five and a half cards span the panel, so the last is always half-cut",
    {
        let inset = (EditorLayoutMetrics.effectRowInset * largeTablet.contentScale)
            .rounded()
        let gap = (EditorLayoutMetrics.baseEffectCardGap * largeTablet.contentScale)
            .rounded()
        let across = (1366 - inset) / (largeTablet.effectCardWidth + gap)
        return (5.2...5.8).contains(across)
    }()
)
check(
    "Tablet effects panel grows with its cards",
    largeTablet.effectsHeight > approvedPhone.effectsHeight * 1.3
)
check(
    "Effects never take more than the panel share ceiling",
    largeTablet.effectsHeight
        <= largeTablet.containerSize.height * EditorLayoutMetrics.effectsHeightShareCeiling
)
check(
    "Toolbar keeps a constant share of the editor's height",
    abs(
        largeTablet.transportHeight / largeTablet.containerSize.height
            - approvedPhone.transportHeight / 590
    ) < 0.02
)
check(
    "A desktop-sized window keeps the toolbar it already had",
    EditorLayoutMetrics(
        containerSize: CGSize(width: 1024, height: 736),
        effectsState: .expanded
    ).transportHeight == 62
)
check("Tablet transport bar grows with its controls", largeTablet.transportHeight > 56)

let narrowWindow = EditorLayoutMetrics(
    containerSize: CGSize(width: 600, height: 744),
    effectsState: .expanded
)
check("Narrow iPad windows use the two-row transport", narrowWindow.mode == .compact)
check(
    "Tracks stays inside its compact minimum and ideal widths",
    (EditorLayoutMetrics.minimumTracksWidth...EditorLayoutMetrics.idealTracksWidth)
        .contains(narrowWindow.tracksWidth)
)
check(
    "Controls stays inside its compact minimum and ideal widths",
    (EditorLayoutMetrics.minimumControlsWidth...EditorLayoutMetrics.idealControlsWidth)
        .contains(narrowWindow.controlsWidth)
)
check("Narrow windows retain a useful timeline", narrowWindow.timelineWidth >= 300)
checkClose("Compact transport reserves a second row", narrowWindow.transportHeight, 94)
checkClose("Compact Tracks footer stacks without clipping", narrowWindow.importFooterHeight, 82)

let compressedWindow = EditorLayoutMetrics(
    containerSize: CGSize(width: 393, height: 744),
    effectsState: .expanded
)
check("Compressed windows keep a positive timeline", compressedWindow.timelineWidth > 0)
check(
    "All three editor columns fit without whole-screen horizontal overflow",
    compressedWindow.tracksWidth
        + compressedWindow.timelineWidth
        + compressedWindow.controlsWidth
        <= compressedWindow.containerSize.width + 0.001
)

let collapsedPhone = EditorLayoutMetrics(
    containerSize: CGSize(width: 750, height: 382),
    effectsState: .collapsed
)
checkClose("Collapsed Effects uses the approved handle-only height", collapsedPhone.effectsHeight, 42)
checkClose(
    "Collapsing Effects reflows all reclaimed height into the timeline",
    collapsedPhone.timelineHeight - approvedPhone.timelineHeight,
    76
)

let resizedCollapsed = EditorLayoutMetrics(
    containerSize: CGSize(width: 1194, height: 834),
    effectsState: collapsedPhone.effectsState
)
check(
    "Effects state survives ordinary resizing",
    resizedCollapsed.effectsState == .collapsed
)

check(
    "Compact presentation contexts choose a sheet",
    EditorPresentationRules.style(availableWidth: 599) == .sheet
)
check(
    "Regular presentation contexts choose an anchored popover",
    EditorPresentationRules.style(availableWidth: 600) == .popover
)

// MARK: - Safe-area bands

let phoneLandscapeChrome = EditorSafeArea(top: 0, leading: 62, bottom: 20, trailing: 62)
    .resolved
checkClose(
    "Phone landscape keeps its edge-to-edge toolbar",
    phoneLandscapeChrome.top,
    0
)
checkClose(
    "Dynamic Island bands stay out of the editor",
    phoneLandscapeChrome.horizontal,
    124
)
let catalystChrome = EditorSafeArea(top: 32, leading: 0, bottom: 0, trailing: 0).resolved
checkClose("A Mac title bar keeps its full band", catalystChrome.top, 32)
let tabletChrome = EditorSafeArea(top: 24, leading: 0, bottom: 20, trailing: 0).resolved
checkClose(
    "A tablet status bar grows to the minimum chrome band",
    tabletChrome.top,
    EditorSafeArea.minimumTopChrome
)
let phoneContent = phoneLandscapeChrome.contentSize(
    in: CGSize(width: 874, height: 402)
)
check(
    "Phone landscape still fits the one-row transport after insetting",
    EditorLayoutMetrics(containerSize: phoneContent, effectsState: .expanded).mode
        == .regular
)
check(
    "Phone landscape effects stay at the approved size after insetting",
    EditorLayoutMetrics(containerSize: phoneContent, effectsState: .expanded)
        .effectCardWidth == 152
)
check(
    "Short screens hide the status bar; taller ones keep the clock visible",
    EditorLayoutMetrics.prefersStatusBarHidden(containerHeight: 402)
        && !EditorLayoutMetrics.prefersStatusBarHidden(containerHeight: 736)
)
check(
    "An unmeasured container keeps the status bar rather than flashing hidden",
    !EditorLayoutMetrics.prefersStatusBarHidden(containerHeight: 0)
)

// MARK: - Transport placement sweep

var overlaps: [CGFloat] = []
var offCentre: [CGFloat] = []
var width: CGFloat = EditorLayoutMetrics.regularTransportMinimumWidth
while width <= 1600 {
    let metrics = EditorLayoutMetrics(
        containerSize: CGSize(width: width, height: 900),
        effectsState: .expanded
    )
    let placement = metrics.transport
    let home = EditorTransportMetrics.homeGroupWidth(
        metrics.density,
        scale: placement.scale
    )
    let export = EditorTransportMetrics.exportGroupWidth(
        metrics.density,
        scale: placement.scale
    )
    let leadingGap = placement.clusterLeading - home
    let trailingGap = (width - export)
        - (placement.clusterLeading + placement.clusterWidth)
    if min(leadingGap, trailingGap) < EditorTransportMetrics.minimumClusterGap - 0.01 {
        overlaps.append(width)
    }
    // Wide bars can afford to put the play button dead centre.
    if width >= 1000, abs(placement.playCentreX - width / 2) > 0.5 {
        offCentre.append(width)
    }
    if placement.scale < 1 { overlaps.append(width) }
    width += 1
}
check(
    "Transport groups never collide at any one-row width",
    overlaps.isEmpty
)
check(
    "Roomy bars centre the play button on the editor",
    offCentre.isEmpty
)
check(
    "The narrowest one-row width is the phone landscape content width",
    EditorLayoutMetrics.regularTransportMinimumWidth
        >= EditorTransportMetrics.minimumOneRowWidth(.tight)
)

if failures > 0 {
    exit(1)
}
