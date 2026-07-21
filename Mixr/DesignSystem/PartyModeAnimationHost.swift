import SwiftUI

struct PartyModeAnimationHost: ViewModifier {
    let appearanceState: AppAppearanceState

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var chromeOpacity: Double = 0
    @State private var glintPhase: CGFloat = 0
    @State private var isGlintActive = false
    @State private var glintTask: Task<Void, Never>?

    private var appearanceSnapshot: AppearanceSnapshot {
        AppearanceSnapshot(
            isEnabled: appearanceState.isPartyModeEnabled,
            activationID: appearanceState.partyModeActivationID,
            reduceMotion: accessibilityReduceMotion
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(
                \.partyModeRenderState,
                PartyModeRenderState(
                    chromeOpacity: chromeOpacity,
                    glintPhase: glintPhase,
                    isGlintActive: isGlintActive
                )
            )
            .onAppear {
                synchronize(to: appearanceSnapshot, animate: false)
            }
            .onChange(of: appearanceSnapshot) { _, snapshot in
                synchronize(to: snapshot, animate: true)
            }
            .onDisappear {
                glintTask?.cancel()
                glintTask = nil
            }
    }

    private func synchronize(to snapshot: AppearanceSnapshot, animate: Bool) {
        glintTask?.cancel()
        glintTask = nil

        guard snapshot.isEnabled else {
            isGlintActive = false
            glintPhase = 0
            if animate {
                withAnimation(.easeOut(duration: PartyModeTokens.exitFadeDuration)) {
                    chromeOpacity = 0
                }
            } else {
                chromeOpacity = 0
            }
            return
        }

        if snapshot.reduceMotion {
            isGlintActive = false
            glintPhase = 1
            if animate {
                withAnimation(.easeOut(duration: PartyModeTokens.reduceMotionFadeDuration)) {
                    chromeOpacity = 1
                }
            } else {
                chromeOpacity = 1
            }
            return
        }

        chromeOpacity = animate ? 0 : 1
        glintPhase = 0
        isGlintActive = animate

        guard animate else { return }

        let activationID = snapshot.activationID
        withAnimation(.easeOut(duration: PartyModeTokens.activationFadeDuration)) {
            chromeOpacity = 1
        }
        glintTask = Task { @MainActor in
            // Give SwiftUI one render turn with the transient layer installed at
            // phase zero. Starting the trim in the same update can coalesce the
            // insertion and final value, leaving no visible traveling glint.
            await Task.yield()
            try? await Task.sleep(for: .seconds(PartyModeTokens.glintArmingDelay))
            guard !Task.isCancelled,
                  appearanceState.isPartyModeEnabled,
                  appearanceState.partyModeActivationID == activationID
            else { return }
            withAnimation(.linear(duration: PartyModeTokens.glintDuration)) {
                glintPhase = 1
            }
            try? await Task.sleep(for: .seconds(PartyModeTokens.glintDuration))
            guard !Task.isCancelled,
                  appearanceState.isPartyModeEnabled,
                  appearanceState.partyModeActivationID == activationID
            else { return }
            isGlintActive = false
            glintTask = nil
        }
    }
}

private struct AppearanceSnapshot: Equatable {
    let isEnabled: Bool
    let activationID: UInt64
    let reduceMotion: Bool
}
