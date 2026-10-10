// Mixr app-icon lab: every variant is drawn from geometry, not pixels, so
// spacing, centring and alignment are exact and reproducible.
//
//   swift Scripts/icon_lab.swift <out_dir> [variant ...]
//
// For each variant it writes:
//   <name>.png            1024² full icon (background + mark), for review
//   <name>-foreground.png 1024² transparent mark only (Icon Composer layer)
//   <name>-background.txt the background gradient stops (Icon Composer fill)
//
// Geometry rules shared by every variant:
//   * 1024 canvas, 8 px grid; strokes and bar widths are multiples of 8.
//   * Apple's icon grid: the mark lives inside the 824 px "content" circle
//     (≈ 80%); nothing important outside the 920 px keyline.
//   * Optical centring: marks are balanced by area, not bounding box.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let centre = CGPoint(x: canvas / 2, y: canvas / 2)

// MARK: - Colour

struct RGB {
    var r, g, b: CGFloat
    var a: CGFloat = 1
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        self.a = a
    }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func alpha(_ v: CGFloat) -> RGB { var c = self; c.a = v; return c }
}

// Brand palette (MixrColors): primary purple, secondary lavender, waveform pink.
let violetTop = RGB(0xA45CFF), violetMid = RGB(0x7E2BEA), violetDeep = RGB(0x4A12B4)
let pink = RGB(0xF472B6), pinkDeep = RGB(0xC0267E)
let lavender = RGB(0x9873EB)
let cyan = RGB(0x38BDF8), magenta = RGB(0xE879F9)
let fieldTop = RGB(0x22093F), fieldBottom = RGB(0x0B0418)

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(RGB, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: space,
        colors: stops.map { $0.0.cg } as CFArray,
        locations: stops.map { $0.1 }
    )!
}

// MARK: - Drawing helpers

func makeContext() -> CGContext {
    let ctx = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Top-left origin, like the design spec.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func drawField(_ ctx: CGContext, _ top: RGB = fieldTop, _ bottom: RGB = fieldBottom) {
    ctx.drawLinearGradient(
        gradient([(top, 0), (bottom, 1)]),
        start: CGPoint(x: canvas * 0.3, y: 0),
        end: CGPoint(x: canvas * 0.7, y: canvas),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    // A soft light from the top so the field isn't flat.
    ctx.drawRadialGradient(
        gradient([(RGB(0x7E2BEA, 0.22), 0), (RGB(0x7E2BEA, 0), 1)]),
        startCenter: CGPoint(x: canvas / 2, y: canvas * 0.18), startRadius: 0,
        endCenter: CGPoint(x: canvas / 2, y: canvas * 0.18), endRadius: canvas * 0.62,
        options: []
    )
}

/// A capsule filled with a vertical gradient, plus a faint top sheen.
func capsule(_ ctx: CGContext, _ rect: CGRect, _ stops: [(RGB, CGFloat)], sheen: Bool = true) {
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width / 2, cornerHeight: rect.width / 2, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(
        gradient(stops),
        start: CGPoint(x: rect.midX, y: rect.minY),
        end: CGPoint(x: rect.midX, y: rect.maxY), options: []
    )
    if sheen {
        ctx.drawLinearGradient(
            gradient([(RGB(0xFFFFFF, 0.30), 0), (RGB(0xFFFFFF, 0), 0.35)]),
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.minY + rect.width * 1.2), options: []
        )
    }
    ctx.restoreGState()
}

func glow(_ ctx: CGContext, colour: RGB, blur: CGFloat, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: colour.cg)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: - Bars (shared by the waveform variants)

struct Bars {
    var heights: [CGFloat]          // fraction of the mark height
    var width: CGFloat = 72         // multiple of 8
    var gap: CGFloat = 56           // centre spacing = width + gap
    var markHeight: CGFloat = 560
    /// Bars share a centre line (waveform) or a baseline (equalizer).
    var bottomAligned = false

    var pitch: CGFloat { width + gap }

    /// Bar rects, optically centred: the group's area centroid sits on the
    /// canvas centre horizontally; vertically, the waveform's centre line
    /// (or the equalizer's area centroid) does.
    func rects() -> [CGRect] {
        let n = CGFloat(heights.count)
        let span = n * width + (n - 1) * gap
        var rects: [CGRect] = heights.enumerated().map { i, h in
            let x = (canvas - span) / 2 + CGFloat(i) * pitch
            let height = (h * markHeight / 8).rounded() * 8
            let y = bottomAligned
                ? centre.y + markHeight / 2 - height
                : centre.y - height / 2
            return CGRect(x: x, y: y, width: width, height: height)
        }
        let area = rects.reduce(0) { $0 + $1.width * $1.height }
        let cx = rects.reduce(0) { $0 + $1.midX * $1.width * $1.height } / area
        let cy = rects.reduce(0) { $0 + $1.midY * $1.width * $1.height } / area
        let dx = centre.x - cx
        let dy = bottomAligned ? centre.y - cy : 0
        rects = rects.map { $0.offsetBy(dx: dx, dy: dy) }
        return rects
    }
}

let violetBar: [(RGB, CGFloat)] = [(violetTop, 0), (violetMid, 0.18), (violetDeep, 1)]
let pinkBar: [(RGB, CGFloat)] = [(RGB(0xFDA4D4), 0), (pink, 0.2), (pinkDeep, 1)]

// The app logo's order: short, tall, peak, dip, tall, short.
let signalHeights: [CGFloat] = [0.29, 0.72, 1.0, 0.45, 0.72, 0.29]

// MARK: - Variants

struct Variant {
    let name: String
    let title: String
    let note: String
    let field: (CGContext) -> Void
    let mark: (CGContext) -> Void
    let background: String
}

let defaultBackground = "linear 22093F → 0B0418 (top-left → bottom-right) + violet top light"

let variants: [Variant] = [
    Variant(
        name: "signal", title: "Signal",
        note: "The brand mark rebuilt exactly: equal 128 px pitch, one centre line, optically centred.",
        field: { drawField($0) },
        mark: { ctx in
            let bars = Bars(heights: signalHeights)
            glow(ctx, colour: RGB(0x7A24F0, 0.55), blur: 40) {
                for r in bars.rects() { capsule(ctx, r, violetBar) }
            }
        },
        background: defaultBackground
    ),
    Variant(
        name: "crossfade", title: "Crossfade",
        note: "One waveform whose colour crossfades pink → violet: two songs becoming one mix.",
        field: { drawField($0) },
        mark: { ctx in
            let bars = Bars(heights: [0.3, 0.62, 0.86, 1.0, 0.56, 0.78, 0.36], width: 64, gap: 40, markHeight: 580)
            let rects = bars.rects()
            glow(ctx, colour: RGB(0x9B2FD0, 0.5), blur: 40) {
                for (i, r) in rects.enumerated() {
                    // Each bar mixes the two songs' colours by its position.
                    let t = CGFloat(i) / CGFloat(rects.count - 1)
                    func mix(_ a: RGB, _ b: RGB) -> RGB {
                        var c = a
                        c.r = a.r + (b.r - a.r) * t; c.g = a.g + (b.g - a.g) * t; c.b = a.b + (b.b - a.b) * t
                        return c
                    }
                    capsule(ctx, r, [(mix(RGB(0xFDA4D4), violetTop), 0),
                                     (mix(pink, violetMid), 0.2),
                                     (mix(pinkDeep, violetDeep), 1)])
                }
            }
        },
        background: defaultBackground
    ),

    Variant(
        name: "m-wave", title: "M-Wave",
        note: "Equalizer bars on one baseline whose tops trace an M for Mixr.",
        field: { drawField($0) },
        mark: { ctx in
            let bars = Bars(heights: [1.0, 0.62, 0.84, 0.62, 1.0], width: 88, gap: 40,
                            markHeight: 520, bottomAligned: true)
            glow(ctx, colour: RGB(0x7A24F0, 0.55), blur: 40) {
                for r in bars.rects() { capsule(ctx, r, violetBar) }
            }
        },
        background: defaultBackground
    ),
    Variant(
        name: "turntable", title: "Turntable",
        note: "A radial waveform around a vinyl hub: 32 bars, lengths from a real-feeling envelope.",
        field: { drawField($0) },
        mark: { ctx in
            let count = 32
            let inner: CGFloat = 168
            // Deterministic envelope: two beats per revolution plus texture.
            func length(_ i: Int) -> CGFloat {
                let t = Double(i) / Double(count) * 2 * .pi
                let env = 0.55 + 0.45 * pow(abs(sin(t)), 0.8)
                let tex = 0.78 + 0.22 * sin(Double(i) * 2.399)
                return CGFloat(env * tex) * 200
            }
            glow(ctx, colour: RGB(0x7A24F0, 0.35), blur: 20) {
                for i in 0..<count {
                    let angle = CGFloat(i) / CGFloat(count) * 2 * .pi - .pi / 2
                    let len = (length(i) / 8).rounded() * 8
                    ctx.saveGState()
                    ctx.translateBy(x: centre.x, y: centre.y)
                    ctx.rotate(by: angle + .pi / 2)
                    let rect = CGRect(x: -14, y: -(inner + len), width: 28, height: len)
                    // Colour sweeps violet → pink → violet around the record.
                    let w = (1 - cos(CGFloat(i) / CGFloat(count) * 2 * .pi)) / 2
                    func mix(_ a: RGB, _ b: RGB) -> RGB {
                        var c = a
                        c.r = a.r + (b.r - a.r) * w; c.g = a.g + (b.g - a.g) * w; c.b = a.b + (b.b - a.b) * w
                        return c
                    }
                    let stops: [(RGB, CGFloat)] = [(mix(violetTop, RGB(0xFDA4D4)), 0), (mix(violetDeep, pinkDeep), 1)]
                    capsule(ctx, rect, stops, sheen: false)
                    ctx.restoreGState()
                }
            }
            // Vinyl hub: grooves and a label dot.
            ctx.setStrokeColor(RGB(0xFFFFFF, 0.10).cg)
            ctx.setLineWidth(2)
            for r in stride(from: CGFloat(72), through: 144, by: 24) {
                ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
            }
            let label = CGRect(x: centre.x - 48, y: centre.y - 48, width: 96, height: 96)
            ctx.saveGState()
            ctx.addEllipse(in: label); ctx.clip()
            ctx.drawLinearGradient(gradient([(violetTop, 0), (violetDeep, 1)]),
                                   start: CGPoint(x: label.midX, y: label.minY),
                                   end: CGPoint(x: label.midX, y: label.maxY), options: [])
            ctx.restoreGState()
            ctx.setFillColor(fieldBottom.cg)
            ctx.fillEllipse(in: CGRect(x: centre.x - 10, y: centre.y - 10, width: 20, height: 20))
        },
        background: defaultBackground
    ),
    Variant(
        name: "shockwave", title: "Shockwave",
        note: "The mark at the centre of concentric squircle rings: the Import pulse, as an icon.",
        field: { drawField($0) },
        mark: { ctx in
            for (k, inset) in [CGFloat(120), 184].enumerated() {
                let rect = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
                let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.28,
                                  cornerHeight: rect.width * 0.28, transform: nil)
                ctx.addPath(path)
                ctx.setStrokeColor(lavender.alpha([0.22, 0.5][k]).cg)
                ctx.setLineWidth(16)
                ctx.strokePath()
            }
            let bars = Bars(heights: signalHeights, width: 56, gap: 40, markHeight: 440)
            glow(ctx, colour: RGB(0x7A24F0, 0.6), blur: 28) {
                for r in bars.rects() { capsule(ctx, r, violetBar) }
            }
        },
        background: defaultBackground
    ),
    Variant(
        name: "neon", title: "Neon",
        note: "Signal in Party Mode light: indigo → violet → pink, glowing on near-black.",
        field: { ctx in drawField(ctx, RGB(0x120A22), RGB(0x05030B)) },
        mark: { ctx in
            let bars = Bars(heights: signalHeights)
            let rects = bars.rects()
            let palette: [RGB] = [RGB(0x818CF8), RGB(0xA78BFA), violetTop, RGB(0xC084FC), magenta, pink]
            for (i, r) in rects.enumerated() {
                let c = palette[i]
                glow(ctx, colour: c.alpha(0.85), blur: 48) {
                    capsule(ctx, r, [(RGB(0xFFFFFF, 0.95), 0), (c, 0.22), (c.alpha(0.85), 1)])
                }
            }
        },
        background: "linear 120A22 → 05030B"
    ),
]

// MARK: - Output

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "output/app-icon-options")
let wanted = Set(args.dropFirst(2))
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for v in variants where wanted.isEmpty || wanted.contains(v.name) {
    let full = makeContext()
    v.field(full)
    v.mark(full)
    writePNG(full.makeImage()!, outDir.appendingPathComponent("\(v.name).png"))

    let fg = makeContext()
    v.mark(fg)
    writePNG(fg.makeImage()!, outDir.appendingPathComponent("\(v.name)-foreground.png"))

    try "\(v.title): \(v.note)\nbackground: \(v.background)\n"
        .write(to: outDir.appendingPathComponent("\(v.name)-background.txt"), atomically: true, encoding: .utf8)
    print(v.name)
}
