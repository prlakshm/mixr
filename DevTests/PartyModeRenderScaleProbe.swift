import AppKit
import SwiftUI

@main
@MainActor
struct PartyModeRenderScaleProbe {
    static func main() throws {
        let outputDirectory = CommandLine.arguments.dropFirst().first
            ?? "PartyModeQAArtifacts"
        let settledState = PartyModeRenderState(
            chromeOpacity: 1,
            activationProgress: 1,
            isActivationActive: false,
            settledBorderOpacity: 1
        )

        for scale in [1.0, 2.0, 3.0] {
            try render(
                state: settledState,
                scale: scale,
                filename: "party-border-scale-\(Int(scale))x.png",
                outputDirectory: outputDirectory
            )
        }

        let activationFrames: [(String, CGFloat)] = [
            ("trace-initial", 0.12),
            ("trace-mid", 0.30),
            ("reconnect", 0.616),
            ("afterglint-early", 0.695),
            ("afterglint-late", 0.878),
        ]
        for (name, progress) in activationFrames {
            try render(
                state: PartyModeRenderState(
                    chromeOpacity: 1,
                    activationProgress: progress,
                    isActivationActive: true,
                    settledBorderOpacity: 0
                ),
                scale: 3,
                filename: "party-border-\(name)-3x.png",
                outputDirectory: outputDirectory
            )
        }

        let baseline = try renderPNG(content: normalBaselineContent(), scale: 3)
        let partyModifierOff = try renderPNG(content: normalPartyContent(), scale: 3)
        guard baseline == partyModifierOff else {
            throw ProbeError.normalModeChanged
        }
        try write(
            baseline,
            filename: "party-border-normal-baseline-3x.png",
            outputDirectory: outputDirectory
        )
        try write(
            partyModifierOff,
            filename: "party-border-normal-modifier-off-3x.png",
            outputDirectory: outputDirectory
        )
    }

    private static func sampleContent(
        state: PartyModeRenderState
    ) -> some View {
        ZStack {
            Color(hex: "050816")

            VStack(spacing: 32) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "080B16"))
                    .frame(width: 340, height: 104)
                    .partyModeBorder(
                        shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        role: .majorPanel,
                        lighting: .shared
                    )

                HStack(spacing: 42) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "080B16"))
                        .frame(width: 144, height: 44)
                        .partyModeBorder(
                            shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                            role: .export,
                            lighting: .violetTrailing
                        )

                    ZStack {
                        PartyModePlayButtonSurface()
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                        .frame(width: 40, height: 40)
                        .partyModePlayButton()
                }
            }
        }
        .frame(width: 420, height: 280)
        .environment(\.partyModeRenderState, state)
    }

    private static func render(
        state: PartyModeRenderState,
        scale: Double,
        filename: String,
        outputDirectory: String
    ) throws {
        let png = try renderPNG(content: sampleContent(state: state), scale: scale)
        try write(png, filename: filename, outputDirectory: outputDirectory)
    }

    private static func normalBaselineContent() -> some View {
        ZStack {
            Color(hex: "050816")
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "080B16"))
                .frame(width: 340, height: 104)
        }
        .frame(width: 420, height: 280)
    }

    private static func normalPartyContent() -> some View {
        ZStack {
            Color(hex: "050816")
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "080B16"))
                .frame(width: 340, height: 104)
                .partyModeBorder(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    role: .majorPanel,
                    lighting: .shared
                )
        }
        .frame(width: 420, height: 280)
        .environment(\.partyModeRenderState, .off)
    }

    private static func renderPNG<Content: View>(
        content: Content,
        scale: Double
    ) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw ProbeError.renderFailed(scale)
        }

        return png
    }

    private static func write(
        _ png: Data,
        filename: String,
        outputDirectory: String
    ) throws {
        let url = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url, options: .atomic)
    }
}

private enum ProbeError: Error {
    case renderFailed(Double)
    case normalModeChanged
}
