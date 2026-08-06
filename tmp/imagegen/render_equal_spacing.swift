import AppKit
import CoreGraphics
import Foundation

private let canvasSize = 1254

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [red, green, blue, alpha]
    )!
}

private func gradient(
    _ colors: [CGColor],
    locations: [CGFloat]
) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors as CFArray,
        locations: locations
    )!
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render_equal_spacing.swift OUTPUT.png\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Unable to create bitmap context")
}

context.translateBy(x: 0, y: CGFloat(canvasSize))
context.scaleBy(x: 1, y: -1)

// Full-bleed opaque violet-black field matching the supplied artwork.
context.setFillColor(color(0x14052B))
context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

let ambient = gradient(
    [
        color(0x32105D, alpha: 0.24),
        color(0x260A49, alpha: 0.17),
        color(0x14052B, alpha: 0),
    ],
    locations: [0, 0.48, 1]
)
context.drawLinearGradient(
    ambient,
    start: CGPoint(x: 627, y: 80),
    end: CGPoint(x: 627, y: 1170),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

let barGradient = gradient(
    [color(0xA45CFF), color(0x7E2BEA), color(0x5C23BE), color(0x4610AD)],
    locations: [0, 0.12, 0.58, 1]
)
let topSheen = gradient(
    [color(0xFFFFFF, alpha: 0.34), color(0xCFA9FF, alpha: 0.12), color(0xFFFFFF, alpha: 0)],
    locations: [0, 0.36, 1]
)

// Exactly 137 px center-to-center. The group midpoint is the canvas midpoint.
let centers: [CGFloat] = [284.5, 421.5, 558.5, 695.5, 832.5, 969.5]
let frames: [CGRect] = [
    CGRect(x: centers[0] - 44, y: 510, width: 88, height: 250),
    CGRect(x: centers[1] - 44, y: 312, width: 88, height: 632),
    CGRect(x: centers[2] - 44, y: 195, width: 88, height: 880),
    CGRect(x: centers[3] - 44, y: 462, width: 88, height: 390),
    CGRect(x: centers[4] - 44, y: 310, width: 88, height: 634),
    CGRect(x: centers[5] - 44, y: 510, width: 88, height: 250),
]

for frame in frames {
    let path = CGPath(
        roundedRect: frame,
        cornerWidth: frame.width / 2,
        cornerHeight: frame.width / 2,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: 3),
        blur: 18,
        color: color(0x7A24F0, alpha: 0.30)
    )
    context.setFillColor(color(0x5C23BE))
    context.addPath(path)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        barGradient,
        start: CGPoint(x: frame.midX, y: frame.minY),
        end: CGPoint(x: frame.midX, y: frame.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.drawRadialGradient(
        topSheen,
        startCenter: CGPoint(x: frame.midX - 12, y: frame.minY + 10),
        startRadius: 0,
        endCenter: CGPoint(x: frame.midX - 12, y: frame.minY + 10),
        endRadius: 75,
        options: [.drawsAfterEndLocation]
    )
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.075))
    context.setLineWidth(1.5)
    context.strokePath()
    context.restoreGState()
}

guard let image = context.makeImage() else { fatalError("Unable to create image") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}
try png.write(to: outputURL, options: .atomic)
