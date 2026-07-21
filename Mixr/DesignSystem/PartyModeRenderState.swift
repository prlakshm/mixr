import Foundation
import SwiftUI

struct PartyModeRenderState: Equatable, Sendable {
    var chromeOpacity: Double = 0
    var activationProgress: CGFloat = 0
    var activationStartedAt: TimeInterval?
    var isActivationActive = false
    var settledBorderOpacity: Double = 0

    static let off = PartyModeRenderState()

    var usesLiveActivationClock: Bool {
        isActivationActive && activationStartedAt != nil
    }

    func advanced(to time: TimeInterval) -> PartyModeRenderState {
        guard let activationStartedAt, isActivationActive else { return self }
        var copy = self
        copy.activationProgress = min(
            1,
            max(
                0,
                CGFloat(
                    (time - activationStartedAt)
                        / PartyModeTokens.activationSequenceDuration
                )
            )
        )
        return copy
    }

    func animationPhase(
        for role: PartyModeSurfaceRole,
        offset: PartyModeGlintOffset
    ) -> PartyModeSurfaceAnimationPhase {
        guard isActivationActive else {
            return PartyModeSurfaceAnimationPhase(
                traceProgress: settledBorderOpacity > 0 ? 1 : 0,
                reconnectFlareProgress: 0,
                afterglintProgress: 1,
                settledBorderOpacity: settledBorderOpacity,
                isTransient: false
            )
        }

        let elapsed = Double(activationProgress) * PartyModeTokens.activationSequenceDuration
        let delay = role.activationDelay(for: offset)
        let traceDuration = role.traceDuration
        let traceProgress = normalized(elapsed, from: delay, duration: traceDuration)
        let traceEnd = delay + traceDuration
        let flareUnit = normalized(
            elapsed,
            from: traceEnd,
            duration: PartyModeTokens.reconnectFlareDuration
        )
        let flareProgress = flareUnit > 0 && flareUnit < 1
            ? sin(flareUnit * .pi)
            : 0
        let afterglintProgress = normalized(
            elapsed,
            from: PartyModeTokens.globalAfterglintStartTime,
            duration: role.afterglintDuration
        )

        return PartyModeSurfaceAnimationPhase(
            traceProgress: traceProgress,
            reconnectFlareProgress: flareProgress,
            afterglintProgress: afterglintProgress,
            settledBorderOpacity: traceProgress,
            isTransient: role.tracesDuringActivation
        )
    }

    private func normalized(
        _ value: TimeInterval,
        from start: TimeInterval,
        duration: TimeInterval
    ) -> CGFloat {
        guard duration > 0 else { return value >= start ? 1 : 0 }
        return min(1, max(0, CGFloat((value - start) / duration)))
    }
}

struct PartyModeSurfaceAnimationPhase: Equatable, Sendable {
    let traceProgress: CGFloat
    let reconnectFlareProgress: CGFloat
    let afterglintProgress: CGFloat
    let settledBorderOpacity: Double
    let isTransient: Bool
}

private struct PartyModeRenderStateKey: EnvironmentKey {
    static let defaultValue = PartyModeRenderState.off
}

extension EnvironmentValues {
    var partyModeRenderState: PartyModeRenderState {
        get { self[PartyModeRenderStateKey.self] }
        set { self[PartyModeRenderStateKey.self] = newValue }
    }
}
