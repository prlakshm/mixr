import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let colorsSource = try String(
    contentsOf: rootURL.appendingPathComponent("Mixr/DesignSystem/MixrColors.swift"),
    encoding: .utf8
)
let timelineSource = try String(
    contentsOf: rootURL.appendingPathComponent("Mixr/TimelineScreen.swift"),
    encoding: .utf8
)

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

func matches(_ pattern: String, in source: String) -> Bool {
    source.range(of: pattern, options: .regularExpression) != nil
}

check(
    "Secondary text stays at the approved global value",
    colorsSource.contains(#"static let textSecondary = Color(hex: "9CA3AF")"#)
)

check(
    "Tertiary text uses the minimum globally accessible value",
    colorsSource.contains(#"static let textTertiary = Color(hex: "7F8694")"#)
)

check(
    "Semantic gray roles use the approved minimum opacities",
    colorsSource.contains("static let textPlaceholder = textSecondary.opacity(0.79)")
        && colorsSource.contains("static let interactiveHandle = textSecondary.opacity(0.64)")
)

check(
    "Project rename explicitly uses the shared placeholder role",
    matches(
        #"TextField\([\s\n]*"Project name",[\s\n]*text:\s*\$renameText,[\s\n]*prompt:\s*Text\("Project name"\)[\s\n]*\.foregroundStyle\(MixrColors\.textPlaceholder\)[\s\n]*\)"#,
        in: timelineSource
    )
)

check(
    "Effects handle uses the shared interactive affordance role",
    matches(
        #"private var effectsHeader:[\s\S]{0,180}Capsule\(\)[\s\n]*\.fill\(MixrColors\.interactiveHandle\)"#,
        in: timelineSource
    )
)

if failures > 0 {
    exit(1)
}
