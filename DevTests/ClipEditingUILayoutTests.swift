import Foundation

// Source-level UI contract checks for the clip editing chrome. The app does not
// currently have an XCTest target, so this lightweight harness protects the
// important layout and platform-API choices without changing project structure.

let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Mixr/DesignSystem/ClipEditingUI.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let selectIndex = source.range(of: "select:")?.lowerBound ?? source.endIndex
let selectAllIndex = source.range(of: "selectAll:")?.lowerBound ?? source.endIndex
let pasteIndex = source.range(of: "paste:")?.lowerBound ?? source.endIndex

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

func matches(_ pattern: String) -> Bool {
    source.range(of: pattern, options: .regularExpression) != nil
}

check(
    "Speed bubble shares the toolbar and transition-menu background",
    !matches(#"mode\s*==\s*\.speed[\s\S]*?glassEffect\s*\(\s*\.regular\.tint"#)
        && !source.contains("speedSurfaceFillOpacity")
        && source.contains("Color(hex: \"050810\").opacity(0.68)")
)
check(
    "Speed toolbar has a dedicated compact height",
    matches(#"toolbarSpeedBodyHeight\s*:\s*CGFloat\s*=\s*ts\s*\(\s*46\s*\)"#)
)
check(
    "Speed value field is visually shorter",
    matches(#"fieldHeight\s*=\s*24\s*\*\s*s"#)
)
check(
    "Speed pane padding is 6/10/0/2",
    matches(#"toolbarSpeedLeadingPadding\s*:\s*CGFloat\s*=\s*ts\s*\(\s*6\s*\)"#)
        && matches(#"toolbarSpeedTrailingPadding\s*:\s*CGFloat\s*=\s*ts\s*\(\s*10\s*\)"#)
        && matches(#"toolbarSpeedContentTopPadding\s*:\s*CGFloat\s*=\s*0"#)
        && matches(#"toolbarSpeedContentBottomPadding\s*:\s*CGFloat\s*=\s*ts\s*\(\s*2\s*\)"#)
)
check(
    "Action toolbar uses less top padding for optical vertical balance",
    matches(#"toolbarContentTopPadding\s*:\s*CGFloat\s*=\s*ts\s*\(\s*6\s*\)"#)
        && matches(#"toolbarContentBottomPadding\s*:\s*CGFloat\s*=\s*ts\s*\(\s*10\s*\)"#)
        && matches(#"toolbarActionTopPadding\s*:\s*CGFloat\s*=\s*ts\s*\(\s*2\s*\)"#)
)
check(
    "Speed field background extends two points lower",
    matches(#"speedFieldBottomExtension\s*:\s*CGFloat\s*=\s*2"#)
        && matches(#"frame\s*\(\s*height:\s*fieldHeight\s*\+\s*bottomExtension"#)
)
check(
    "Speed multiplier uses × and is bottom-aligned to the value field",
    source.contains("Text(\"×\")")
        && matches(#"HStack\s*\(\s*alignment:\s*\.bottom"#)
        && source.contains("field.contentVerticalAlignment = .bottom")
        && matches(#"speedMultiplierBottomSpacing\s*:\s*CGFloat\s*="#)
)
check(
    "Speed field keeps Paste available in the native edit menu",
    source.contains("private final class TLSpeedPasteTextField")
        && source.contains("override func canPerformAction")
        && source.contains("action == #selector(paste(_:))")
)
check(
    "Native edit menu places Paste after Select All",
    selectIndex < selectAllIndex
        && selectAllIndex < pasteIndex
        && source.contains("editMenuForCharactersIn range: NSRange")
)

if failures > 0 {
    exit(1)
}
