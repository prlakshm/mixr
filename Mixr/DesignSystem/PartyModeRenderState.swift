import SwiftUI

struct PartyModeRenderState: Equatable, Sendable {
    var chromeOpacity: Double = 0
    var glintPhase: CGFloat = 0
    var isGlintActive = false

    static let off = PartyModeRenderState()
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
