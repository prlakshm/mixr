import SwiftUI

struct PartyModeAnimationHost: ViewModifier {
    let appearanceState: AppAppearanceState

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var chromeOpacity: Double = 0
    @State private var activationProgress: CGFloat = 0
    @State private var activationStartedAt: TimeInterval?
    @State private var isActivationActive = false
    @State private var settledBorderOpacity: Double = 0
    @State private var activationTask: Task<Void, Never>?

    private var appearanceSnapshot: AppearanceSnapshot {
        AppearanceSnapshot(
            isEnabled: appearanceState.isPartyModeEnabled,
            activationID: appearanceState.partyModeActivationID,
            reduceMotion: accessibilityReduceMotion
        )
    }

    private var partyModeCaptureProgress: CGFloat? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-MixrPartyModeCaptureProgress"),
              arguments.indices.contains(flagIndex + 1),
              let value = Double(arguments[flagIndex + 1])
        else { return nil }
        return min(1, max(0, CGFloat(value)))
#else
        return nil
#endif
    }

    func body(content: Content) -> some View {
        content
            .environment(
                \.partyModeRenderState,
                PartyModeRenderState(
                    chromeOpacity: chromeOpacity,
                    activationProgress: activationProgress,
                    activationStartedAt: activationStartedAt,
                    isActivationActive: isActivationActive,
                    settledBorderOpacity: settledBorderOpacity
                )
            )
            .onAppear {
                synchronize(to: appearanceSnapshot, animate: false)
            }
            .onChange(of: appearanceSnapshot) { _, snapshot in
                synchronize(to: snapshot, animate: true)
            }
            .onDisappear {
                activationTask?.cancel()
                activationTask = nil
            }
    }

    private func synchronize(to snapshot: AppearanceSnapshot, animate: Bool) {
        activationTask?.cancel()
        activationTask = nil

        guard snapshot.isEnabled else {
            if animate {
                withAnimation(.easeOut(duration: PartyModeTokens.exitFadeDuration)) {
                    chromeOpacity = 0
                }
                scheduleExitCleanup(for: snapshot.activationID)
            } else {
                chromeOpacity = 0
                activationProgress = 0
                activationStartedAt = nil
                isActivationActive = false
                settledBorderOpacity = 0
            }
            return
        }

        if snapshot.reduceMotion {
            activationProgress = 1
            activationStartedAt = nil
            isActivationActive = false
            if animate {
                withAnimation(.easeOut(duration: PartyModeTokens.reduceMotionFadeDuration)) {
                    chromeOpacity = 1
                    settledBorderOpacity = 1
                }
            } else {
                chromeOpacity = 1
                settledBorderOpacity = 1
            }
            return
        }

        chromeOpacity = animate ? 0 : 1
        activationProgress = animate ? 0 : 1
        activationStartedAt = nil
        isActivationActive = animate
        settledBorderOpacity = animate ? 0 : 1

        guard animate else { return }

        if let captureProgress = partyModeCaptureProgress {
            chromeOpacity = 1
            activationProgress = captureProgress
            activationStartedAt = nil
            isActivationActive = captureProgress < 1
            settledBorderOpacity = captureProgress >= 1 ? 1 : 0
            return
        }

        let activationID = snapshot.activationID
        withAnimation(.easeOut(duration: PartyModeTokens.activationFadeDuration)) {
            chromeOpacity = 1
        }
        activationTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .seconds(PartyModeTokens.activationArmingDelay))
            guard !Task.isCancelled,
                  appearanceState.isPartyModeEnabled,
                  appearanceState.partyModeActivationID == activationID
            else { return }

            activationStartedAt = Date.timeIntervalSinceReferenceDate
            try? await Task.sleep(
                for: .seconds(PartyModeTokens.activationSequenceDuration)
            )

            guard !Task.isCancelled,
                  appearanceState.isPartyModeEnabled,
                  appearanceState.partyModeActivationID == activationID
            else { return }
            activationProgress = 1
            activationStartedAt = nil
            settledBorderOpacity = 1
            isActivationActive = false
            activationTask = nil
        }
    }

    private func scheduleExitCleanup(for activationID: UInt64) {
        activationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(PartyModeTokens.exitFadeDuration))
            guard !Task.isCancelled,
                  !appearanceState.isPartyModeEnabled,
                  appearanceState.partyModeActivationID == activationID
            else { return }
            activationProgress = 0
            activationStartedAt = nil
            isActivationActive = false
            settledBorderOpacity = 0
            activationTask = nil
        }
    }
}

private struct AppearanceSnapshot: Equatable {
    let isEnabled: Bool
    let activationID: UInt64
    let reduceMotion: Bool
}
