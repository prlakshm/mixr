import Foundation

let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/TimelineScreen.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

func matches(_ pattern: String) -> Bool {
    source.range(of: pattern, options: .regularExpression) != nil
}

check(
    "Empty timeline is copy only, centred, and lets drops through",
    source.contains("TLEmptyTimelineState(isDropTarget: isTimelineDropTarget)")
        && matches(
            #"TLEmptyTimelineState\(isDropTarget: isTimelineDropTarget\)\s*\.allowsHitTesting\(false\)"#
        )
        && source.contains(
            ".position(x: min(contentW, viewportW) / 2, y: lanesH / 2)"
        )
        && !source.contains("let onImport: () -> Void")
)

check(
    "Empty timeline points at the one Import Songs button instead of repeating it",
    source.contains("Text(\"Tap Import Songs on the left, or drag audio files here\")")
        && !source.contains("Button(action: onImport)")
)

check(
    "Import Songs wears Export's glass and breathes only on an empty project",
    matches(
        #"private var importSongsButton:[\s\S]{0,1400}\.background \{ MixrGlassButtonChrome\(isPulsing: importPulses\) \}"#
    )
        && source.contains("!tracks.contains { !$0.isSFXTrack }")
)

check(
    "Approved text colors move only to the measured contrast thresholds",
    source.contains(
        ".foregroundStyle(MixrColors.textSecondary.opacity(isDropTarget ? 0.86 : 0.73))"
    )
        && matches(
            #"Text\(\"Tap Import Songs on the left, or drag audio files here\"\)[\s\S]{0,360}textSecondary\.opacity\(0\.73\)"#
        )
        && matches(
            #"Text\(\"Select a clip to shape its effects\"\)[\s\S]{0,420}textSecondary\.opacity\(0\.87\)"#
        )
)

check(
    "Unavailable effects preserve their complete glass cards and dim to forty-five percent",
    matches(
        #"let restingOpacity:\s*Double\s*=\s*effect\.isAdjustable\s*&&\s*!hasTarget\s*\?\s*0\.45\s*:\s*1"#
    )
        && matches(
            #"TLCompactEffectCard\([\s\S]{0,520}\.opacity\(isAway\s*\?\s*0\s*:\s*restingOpacity\)"#
        )
)

if failures > 0 {
    exit(1)
}
