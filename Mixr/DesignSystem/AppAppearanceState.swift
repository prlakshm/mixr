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

#if DEBUG
    /// Editor surface requested by a visual-QA launch argument ("sfx",
    /// "delete", "hscroll"). `ContentView` sets it after launch settles;
    /// `TimelineScreen` opens the matching surface so headless capture can
    /// screenshot states that normally need interaction.
    var editorVisualQAState: String?
#endif
}
