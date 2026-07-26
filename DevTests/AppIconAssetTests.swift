import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print("\(passed ? "PASS" : "FAIL")  \(name)")
    if !passed { failures += 1 }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Mixr/Assets.xcassets/AppIcon.appiconset")
let contentsURL = iconSet.appendingPathComponent("Contents.json")
let iconFilename = "MixrAppIcon.png"
let iconURL = iconSet.appendingPathComponent(iconFilename)
let approvedArtworkSHA256 =
    "1cee50ba4fc96df34f4ca58beea7cbaddf48188f1b9b6e1579fe3f297108aca2"

let contentsData = try Data(contentsOf: contentsURL)
let contents = try JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
let images = contents?["images"] as? [[String: Any]] ?? []
let universalIcon = images.first {
    $0["idiom"] as? String == "universal"
        && $0["platform"] as? String == "ios"
        && $0["size"] as? String == "1024x1024"
        && $0["appearances"] == nil
}

check(
    "Universal iOS app icon references the production artwork",
    universalIcon?["filename"] as? String == iconFilename
)
check("Production app icon exists", FileManager.default.fileExists(atPath: iconURL.path))

if let iconData = try? Data(contentsOf: iconURL) {
    let digest = SHA256.hash(data: iconData)
        .map { String(format: "%02x", $0) }
        .joined()
    check("Production app icon uses the approved revised artwork", digest == approvedArtworkSHA256)
} else {
    check("Production app icon uses the approved revised artwork", false)
}

if let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
    check("Production app icon is 1024 pixels wide", image.width == 1024)
    check("Production app icon is 1024 pixels high", image.height == 1024)

    let opaqueAlphaModes: Set<CGImageAlphaInfo> = [
        .none,
        .noneSkipFirst,
        .noneSkipLast,
    ]
    check(
        "Production app icon has no alpha channel",
        opaqueAlphaModes.contains(image.alphaInfo)
    )
} else {
    check("Production app icon can be decoded", false)
}

if failures > 0 {
    exit(1)
}
