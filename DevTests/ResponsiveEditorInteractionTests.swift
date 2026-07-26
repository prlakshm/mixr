import CoreGraphics
import Foundation

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print("\(passed ? "PASS" : "FAIL")  \(name)")
    if !passed { failures += 1 }
}

check(
    "Tapping the Effects header collapses an expanded panel",
    EditorEffectsInteraction.toggled(false)
)
check(
    "Tapping the Effects header expands a collapsed panel",
    !EditorEffectsInteraction.toggled(true)
)
check(
    "A downward drag past the threshold collapses Effects",
    EditorEffectsInteraction.collapsedState(
        afterDrag: CGSize(width: 2, height: 25),
        current: false
    )
)
check(
    "An upward drag past the threshold expands Effects",
    !EditorEffectsInteraction.collapsedState(
        afterDrag: CGSize(width: 2, height: -25),
        current: true
    )
)
check(
    "Horizontal scrolling does not accidentally toggle Effects",
    !EditorEffectsInteraction.collapsedState(
        afterDrag: CGSize(width: 40, height: 30),
        current: false
    )
)
check(
    "A sub-threshold vertical drag preserves Effects state",
    EditorEffectsInteraction.collapsedState(
        afterDrag: CGSize(width: 0, height: -23),
        current: true
    )
)

let collapsedBeforeResize = EditorLayoutMetrics(
    containerSize: CGSize(width: 932, height: 430),
    effectsState: .collapsed
)
let collapsedAfterResize = EditorLayoutMetrics(
    containerSize: CGSize(width: 600, height: 744),
    effectsState: collapsedBeforeResize.effectsState
)
check(
    "Effects collapse state survives a regular-to-compact resize",
    collapsedAfterResize.effectsState == .collapsed
        // The handle band grows a little with the panel scale, but stays a
        // handle — never the expanded panel.
        && collapsedAfterResize.effectsHeight
            >= EditorLayoutMetrics.collapsedEffectsHeight
        && collapsedAfterResize.effectsHeight
            <= EditorLayoutMetrics.collapsedEffectsHeight + 12
)
check(
    "A collapsed handle band still clears its scaled title",
    EditorLayoutMetrics(
        containerSize: CGSize(width: 1366, height: 1024),
        effectsState: .collapsed
    ).effectsHeight >= 48
)
check(
    "Resizing still switches the surrounding transport layout",
    collapsedBeforeResize.mode == .regular
        && collapsedAfterResize.mode == .compact
)

if failures > 0 {
    exit(1)
}
