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
let iconBundle = root.appendingPathComponent("Mixr/AppIcon.icon")
let manifestURL = iconBundle.appendingPathComponent("icon.json")
let assetsDirectory = iconBundle.appendingPathComponent("Assets")

// Artwork approved for release, keyed by the `image-name` used in icon.json.
// Re-pin deliberately when the icon changes — a surprise digest here means the
// shipping icon moved without anyone signing off on it.
let approvedArtworkSHA256 = [
    "mixr-bars-neon.png": "1033bd28547307141f28eb3dca4aaae0e587961b3989aa6a305e2c5d9abbc110"
]

guard let manifestData = try? Data(contentsOf: manifestURL) else {
    check("Icon Composer manifest exists at Mixr/AppIcon.icon/icon.json", false)
    exit(1)
}

let manifest = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any]
check("Icon Composer manifest parses as a JSON object", manifest != nil)

let groups = manifest?["groups"] as? [[String: Any]] ?? []
check("Manifest declares at least one layer group", !groups.isEmpty)

let layers = groups.flatMap { $0["layers"] as? [[String: Any]] ?? [] }
check("Manifest declares at least one layer", !layers.isEmpty)

// Layers may be fill-only, so only the image-backed ones need artwork on disk.
let imageNames = layers.compactMap { $0["image-name"] as? String }
check("Manifest references at least one image layer", !imageNames.isEmpty)

for name in imageNames {
    let artworkURL = assetsDirectory.appendingPathComponent(name)

    guard let artworkData = try? Data(contentsOf: artworkURL) else {
        check("Layer artwork \"\(name)\" exists under AppIcon.icon/Assets", false)
        continue
    }
    check("Layer artwork \"\(name)\" exists under AppIcon.icon/Assets", true)

    let digest = SHA256.hash(data: artworkData)
        .map { String(format: "%02x", $0) }
        .joined()

    if let approved = approvedArtworkSHA256[name] {
        check("Layer artwork \"\(name)\" matches the approved revision", digest == approved)
    } else {
        check("Layer artwork \"\(name)\" is pinned in approvedArtworkSHA256", false)
        print("      unpinned digest: \(digest)")
    }

    guard let source = CGImageSourceCreateWithURL(artworkURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        check("Layer artwork \"\(name)\" decodes", false)
        continue
    }
    check("Layer artwork \"\(name)\" decodes", true)
    check(
        "Layer artwork \"\(name)\" is square (\(image.width)x\(image.height))",
        image.width == image.height
    )
}

if failures > 0 {
    exit(1)
}
