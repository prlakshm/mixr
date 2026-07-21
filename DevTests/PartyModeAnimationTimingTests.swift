import Foundation
import SwiftUI

@main
struct PartyModeAnimationTimingTests {
    private static var failures = 0
    private static let tolerance = 0.001

    static func main() {
        checkClose(
            "Major-panel trace runs at 75 percent velocity",
            PartyModeSurfaceRole.majorPanel.traceDuration,
            1.28
        )
        checkClose(
            "Button trace runs at 75 percent velocity",
            PartyModeSurfaceRole.button.traceDuration,
            0.62 / 0.75
        )
        checkClose(
            "Dialog trace runs at 75 percent velocity",
            PartyModeSurfaceRole.dialog.traceDuration,
            0.88 / 0.75
        )
        checkClose(
            "Play trace runs at 75 percent velocity",
            PartyModeSurfaceRole.play.traceDuration,
            0.68 / 0.75
        )
        checkClose(
            "Compact trace runs at 75 percent velocity",
            PartyModeSurfaceRole.compactControl.traceDuration,
            0.54 / 0.75
        )

        checkClose(
            "Major-panel afterglint runs at 75 percent velocity",
            PartyModeSurfaceRole.majorPanel.afterglintDuration,
            0.50 / 0.75
        )
        checkClose(
            "Play afterglint runs at 75 percent velocity",
            PartyModeSurfaceRole.play.afterglintDuration,
            0.48 / 0.75
        )
        checkClose(
            "Button afterglint runs at 75 percent velocity",
            PartyModeSurfaceRole.button.afterglintDuration,
            0.46 / 0.75
        )
        checkClose(
            "Compact afterglint runs at 75 percent velocity",
            PartyModeSurfaceRole.compactControl.afterglintDuration,
            0.42 / 0.75
        )

        let afterglintStart = PartyModeTokens.afterglintTravelPosition(for: 0)
        let afterglintEnd = PartyModeTokens.afterglintTravelPosition(for: 1)
        checkClose(
            "Afterglint fades after one complete perimeter lap",
            TimeInterval(afterglintEnd - afterglintStart),
            1.0
        )

        let opacityCheckpoints: [(CGFloat, Double)] = [
            (0, 1.0),
            (0.20, 0.92),
            (0.75, 0.35),
            (0.90, 0.30),
            (0.95, 0.27),
            (0.99, 0.07),
            (1, 0),
        ]
        for (progress, minimumOpacity) in opacityCheckpoints {
            let opacity = PartyModeTokens.afterglintOpacity(for: progress)
            check(
                "Afterglint remains perceptible at \(Int(progress * 100)) percent",
                progress == 1
                    ? opacity == 0
                    : opacity >= minimumOpacity
            )
        }

        let sampledOpacities = stride(from: 0, through: 100, by: 1).map {
            PartyModeTokens.afterglintOpacity(for: CGFloat($0) / 100)
        }
        check(
            "Afterglint opacity decays monotonically across the complete lap",
            zip(sampledOpacities, sampledOpacities.dropFirst()).allSatisfy(>=)
        )

        let unwrappedTrail = PartyModeTrimSegments.wrapped(from: 0.20, to: 0.32)
        check(
            "Afterglint keeps two stable trim fragments before the seam",
            unwrappedTrail.count == 2
                && unwrappedTrail[0].from == 0.20
                && unwrappedTrail[0].to == 0.32
                && unwrappedTrail[1].from == 0
                && unwrappedTrail[1].to == 0
        )

        let wrappedTrail = PartyModeTrimSegments.wrapped(from: 0.94, to: 1.04)
        check(
            "Afterglint keeps the same two fragments while crossing the seam",
            wrappedTrail.count == 2
                && wrappedTrail[0].from == 0.94
                && wrappedTrail[0].to == 1
                && wrappedTrail[1].from == 0
                && abs(wrappedTrail[1].to - 0.04) <= 0.0001
        )

        let finalTraceEnd = 0.075 + 0.96 / 0.75
        let globalGlintStart = finalTraceEnd + 0.10
        let expectedSequenceEnd = globalGlintStart + 0.50 / 0.75

        checkClose(
            "Activation duration covers the final connection and longest glint",
            PartyModeTokens.activationSequenceDuration,
            expectedSequenceEnd
        )

        let tracedSurfaces: [(PartyModeSurfaceRole, PartyModeGlintOffset)] = [
            (.majorPanel, .far),
            (.dialog, .far),
            (.export, .far),
            (.play, .far),
            (.button, .far),
            (.effectCard, .far),
            (.compactControl, .far),
            (.sfxSurface, .far),
        ]

        let beforeConnection = state(at: globalGlintStart - 0.001)
        for (role, offset) in tracedSurfaces {
            let phase = beforeConnection.animationPhase(for: role, offset: offset)
            check(
                "No \(role) afterglint before the final connection",
                phase.afterglintProgress == 0
            )
        }

        let finalFlare = state(at: globalGlintStart - 0.05)
            .animationPhase(for: .majorPanel, offset: .far)
        check(
            "The last panel reconnect flare occurs before the global glint",
            finalFlare.reconnectFlareProgress > 0.99
                && finalFlare.afterglintProgress == 0
        )

        let afterConnection = state(at: globalGlintStart + 0.01)
        for (role, offset) in tracedSurfaces {
            let phase = afterConnection.animationPhase(for: role, offset: offset)
            check(
                "\(role) is closed before its synchronized glint begins",
                phase.traceProgress == 1
                    && phase.reconnectFlareProgress == 0
                    && phase.afterglintProgress > 0
                    && phase.afterglintProgress < 1
            )
        }

        if failures > 0 {
            exit(1)
        }
    }

    private static func state(at elapsed: TimeInterval) -> PartyModeRenderState {
        PartyModeRenderState(
            chromeOpacity: 1,
            activationProgress: CGFloat(
                elapsed / PartyModeTokens.activationSequenceDuration
            ),
            isActivationActive: true,
            settledBorderOpacity: 0
        )
    }

    private static func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL")  \(name)")
        if !condition { failures += 1 }
    }

    private static func checkClose(
        _ name: String,
        _ actual: TimeInterval,
        _ expected: TimeInterval
    ) {
        check(name, abs(actual - expected) <= tolerance)
    }
}
