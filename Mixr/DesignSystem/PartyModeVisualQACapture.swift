#if DEBUG
import UIKit

/// Debug-only live-window capture used by Party Mode visual QA. Capturing from
/// the app avoids Simulator framebuffer and device-cutout artifacts while
/// preserving the exact SwiftUI hierarchy currently on screen.
@MainActor
enum PartyModeVisualQACapture {
    struct Frame {
        fileprivate let filename: String
        fileprivate let image: UIImage
    }

    static func capture(filename: String) throws -> URL {
        try write(snapshot(filename: filename))
    }

    /// Captures the committed hierarchy without performing PNG compression.
    /// The live animation recorder holds these lightweight frame objects until
    /// its timing-sensitive sampling is complete, then encodes them afterward.
    static func snapshot(filename: String) throws -> Frame {
        guard let window = activeWindow else {
            throw CaptureError.missingWindow
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = window.screen.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: window.bounds.size,
            format: format
        )
        window.layoutIfNeeded()
        let image = renderer.image { context in
            let drewLatestHierarchy = window.drawHierarchy(
                in: window.bounds,
                afterScreenUpdates: true
            )
            if !drewLatestHierarchy {
                window.layer.render(in: context.cgContext)
            }
        }

        return Frame(filename: filename, image: image)
    }

    static func write(_ frame: Frame) throws -> URL {
        guard let data = frame.image.pngData() else {
            throw CaptureError.encodingFailed
        }

        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = directory.appendingPathComponent(frame.filename)
        try data.write(to: url, options: .atomic)
        print("Mixr visual QA capture: \(url.path)")
        return url
    }

    private static var activeWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private enum CaptureError: Error {
        case missingWindow
        case encodingFailed
    }
}
#endif
