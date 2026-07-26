import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate_app_icon.swift source.png destination.png")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
let dimension = 1024

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil,
          width: dimension,
          height: dimension,
          bitsPerComponent: 8,
          bytesPerRow: dimension * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
else {
    fatalError("Could not decode or prepare the supplied artwork")
}

context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
context.interpolationQuality = .high
context.draw(
    sourceImage,
    in: CGRect(x: 0, y: 0, width: dimension, height: dimension)
)

guard let outputImage = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          destinationURL as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      )
else {
    fatalError("Could not prepare the app icon output")
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write the app icon")
}
