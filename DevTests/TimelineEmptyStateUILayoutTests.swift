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
    "Empty timeline adds a working import action while keeping the group centered",
    matches(
        #"TLEmptyTimelineState\(\s*isDropTarget:\s*isTimelineDropTarget,\s*onImport:\s*\{\s*showFilePicker\s*=\s*true\s*\}\s*\)"#
    )
        && source.contains(
            ".position(x: min(contentW, viewportW) / 2, y: lanesH / 2)"
        )
        && !matches(
            #"TLEmptyTimelineState\([\s\S]{0,220}\.allowsHitTesting\(false\)"#
        )
)

check(
    "Empty timeline CTA uses the existing Party Mode button treatment",
    source.contains("let onImport: () -> Void")
        && source.contains("Button(action: onImport)")
        && matches(
            #"Button\(action:\s*onImport\)[\s\S]{0,2800}\.partyModeBorder\([\s\S]{0,260}role:\s*\.button,[\s\S]{0,160}lighting:\s*\.coolLeading,[\s\S]{0,160}glintOffset:\s*\.near"#
        )
)

check(
    "Empty timeline CTA is slightly lighter than the left import button",
    matches(
        #"Button\(action:\s*onImport\)[\s\S]{0,520}\.foregroundStyle\(MixrColors\.textMuted\.opacity\(0\.84\)\)"#
    )
)

check(
    "Left import button remains at its existing opacity",
    matches(
        #"private var importButton:[\s\S]{0,900}\.foregroundStyle\(MixrColors\.textMuted\.opacity\(0\.82\)\)"#
    )
)

check(
    "Empty timeline keeps a twelve-point gap between its copy and import button",
    matches(
        #"Text\(\"Drag audio files here or use Import Songs\"\)[\s\S]{0,600}Button\(action:\s*onImport\)[\s\S]{0,3200}\.padding\(\.top,\s*MixrSpacing\.md\)"#
    )
)

check(
    "Approved text colors move only to the measured contrast thresholds",
    source.contains(
        ".foregroundStyle(MixrColors.textSecondary.opacity(0.73))"
    )
        && source.contains(
            ".foregroundStyle(MixrColors.textSecondary.opacity(isDropTarget ? 0.86 : 0.73))"
        )
        && matches(
            #"Text\(\"Drag audio files here or use Import Songs\"\)[\s\S]{0,180}textSecondary\.opacity\(0\.73\)"#
        )
        && matches(
            #"Text\(\"Select a clip to shape its effects\"\)[\s\S]{0,220}textSecondary\.opacity\(0\.87\)"#
        )
)

check(
    "Unavailable effects preserve their complete glass cards and dim to forty-five percent",
    matches(
        #"let restingOpacity:\s*Double\s*=\s*effect\.isAdjustable\s*&&\s*!hasTarget\s*\?\s*0\.45\s*:\s*1"#
    )
        && matches(
            #"TLCompactEffectCard\([\s\S]{0,260}\.opacity\(isAway\s*\?\s*0\s*:\s*restingOpacity\)"#
        )
)

if failures > 0 {
    exit(1)
}
