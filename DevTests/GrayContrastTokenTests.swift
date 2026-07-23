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
let clipEditingSource = try String(
    contentsOf: rootURL.appendingPathComponent("Mixr/DesignSystem/ClipEditingUI.swift"),
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
        && colorsSource.contains("static let interactiveHandle = textSecondary.opacity(0.70)")
)

check(
    "Project rename uses an inline UITextField, not a SwiftUI TextField chrome morph",
    timelineSource.contains("private struct TLProjectNameField: UIViewRepresentable")
        && timelineSource.contains("private final class TLProjectNameTextField: UITextField")
        && timelineSource.contains("initialCaretX")
        && timelineSource.contains("placeInitialCaret(in:")
        && timelineSource.contains("titleLabel.lineBreakMode = .byTruncatingTail")
        && timelineSource.contains("private struct TLNativeProjectMenuButton: UIViewRepresentable")
        && timelineSource.contains("static let width: CGFloat = 76")
        && timelineSource.contains("static var controlWidth: CGFloat")
        && matches(
            #"private var projectTitleControl:[\s\S]{0,5000}\.frame\(\s*width:\s*TLProjectTitleMetrics\.controlWidth"#,
            in: timelineSource
        )
        && matches(
            #"private var projectTitleControl:[\s\S]{0,4000}\.fixedSize\(horizontal: true, vertical: true\)"#,
            in: timelineSource
        )
        && !matches(
            #"if isRenamingProject \{[\s\S]{0,80}TextField\([\s\n]*"Project name""#,
            in: timelineSource
        )
        && !matches(
            #"isRenamingProject[\s\S]{0,400}RoundedRectangle\(cornerRadius: 6"#,
            in: timelineSource
        )
)

check(
    "Project rename caret matches the speed toolbar gray tint",
    matches(
        #"field\.tintColor = UIColor\(white: 0\.62, alpha: 1\)"#,
        in: timelineSource
    )
        && matches(
            #"field\.tintColor = UIColor\(white: 0\.62, alpha: 1\)"#,
            in: clipEditingSource
        )
)

check(
    "Effects handle uses the shared interactive affordance role",
    matches(
        #"private var effectsHeader:[\s\S]{0,420}Capsule\(\)[\s\n]*\.fill\(MixrColors\.interactiveHandle\)"#,
        in: timelineSource
    )
)

if failures > 0 {
    exit(1)
}
