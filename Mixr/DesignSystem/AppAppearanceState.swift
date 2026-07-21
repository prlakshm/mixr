import Observation

/// Ephemeral app appearance only. It deliberately owns no project or playback state.
@MainActor
@Observable
final class AppAppearanceState {
    private(set) var isPartyModeEnabled = false
    private(set) var partyModeActivationID: UInt64 = 0

    func togglePartyMode() {
        isPartyModeEnabled.toggle()
        if isPartyModeEnabled {
            partyModeActivationID &+= 1
        }
    }
}
