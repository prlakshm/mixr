import CoreGraphics
import Foundation
import ImageIO

// The app icon is an Icon Composer file (Mixr/AppIcon.icon) whose one layer
// is rendered by Scripts/render_app_icon.py. These checks measure the
// rendered pixels, so a re-render can't drift the mark off its grid.

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print("\(passed ? "PASS" : "FAIL")  \(name)")
    if !passed { failures += 1 }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDir = root.appendingPathComponent("Mixr/AppIcon.icon")
let layerName = "mixr logo 4.png"
let layerURL = iconDir.appendingPathComponent("Assets/\(layerName)")

let manifest = (try? String(contentsOf: iconDir.appendingPathComponent("icon.json"), encoding: .utf8)) ?? ""
check("Icon Composer manifest references the rendered layer", manifest.contains("\"image-name\" : \"\(layerName)\"")
      || manifest.contains("\"image-name\": \"\(layerName)\""))

guard let source = CGImageSourceCreateWithURL(layerURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    check("Icon layer exists", false)
    exit(1)
}
check("Icon layer is 1254 × 1254", image.width == 1254 && image.height == 1254)

// Read pixels, find the bars as columns that differ from the background.
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
}
let bg = px(4, 4)
func isMark(_ x: Int, _ y: Int) -> Bool {
    let p = px(x, y)
    return abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 60
}
var runs: [(Int, Int)] = []
var start: Int?
for x in 0..<w {
    let on = (0..<h).contains { isMark(x, $0) }
    if on, start == nil { start = x }
    if !on, let s = start { runs.append((s, x - 1)); start = nil }
}
check("Six bars", runs.count == 6)
let centres = runs.map { Double($0.0 + $0.1) / 2 }
let pitches = zip(centres.dropFirst(), centres).map { $0 - $1 }
check("Bars are evenly spaced (one pitch, ±0.5 px)", (pitches.max() ?? 0) - (pitches.min() ?? 0) <= 0.5)
if let first = runs.first, let last = runs.last {
    check("Mark is centred left-right (margins within 1 px)", abs(first.0 - (w - 1 - last.1)) <= 1)
}
let verticalCentres: [Double] = runs.map { run in
    let mid = (run.0 + run.1) / 2
    let ys = (0..<h).filter { isMark(mid, $0) }
    return Double(ys.first! + ys.last!) / 2
}
check("Every bar sits on the canvas mid-line (±1 px)", verticalCentres.allSatisfy { abs($0 - Double(h) / 2 + 0.5) <= 1 })
let widths = runs.map { $0.1 - $0.0 + 1 }
let peak = runs.map { run -> Int in
    let mid = (run.0 + run.1) / 2
    return (0..<h).filter { isMark(mid, $0) }.count
}.max() ?? 0
check("Bars are tall like the in-app waveform (peak ≥ 10× bar width)", Double(peak) >= 10 * Double(widths.max() ?? 1))

exit(failures == 0 ? 0 : 1)
