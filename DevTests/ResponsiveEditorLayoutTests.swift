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

let approvedPhone = EditorLayoutMetrics(
    containerSize: CGSize(width: 932, height: 430),
    effectsState: .expanded
)
check("Approved phone uses the regular one-row transport", approvedPhone.mode == .regular)
checkClose("Approved phone keeps the Tracks ideal width", approvedPhone.tracksWidth, 208)
checkClose("Approved phone keeps the Controls ideal width", approvedPhone.controlsWidth, 130)
checkClose("Approved phone gives remaining width to the timeline", approvedPhone.timelineWidth, 594)
checkClose("Expanded Effects uses the approved height", approvedPhone.effectsHeight, 118)
checkClose("Regular transport uses the approved height", approvedPhone.transportHeight, 50)

let largeTablet = EditorLayoutMetrics(
    containerSize: CGSize(width: 1366, height: 1024),
    effectsState: .expanded
)
checkClose("Tracks stops growing at its ideal width", largeTablet.tracksWidth, 208)
checkClose("Controls stops growing at its ideal width", largeTablet.controlsWidth, 130)
check(
    "Additional tablet width goes to the timeline",
    largeTablet.timelineWidth > approvedPhone.timelineWidth
)

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
    containerSize: CGSize(width: 932, height: 430),
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

if failures > 0 {
    exit(1)
}
