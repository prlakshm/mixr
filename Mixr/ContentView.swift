import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppAppearanceState.self) private var appearanceState

    var body: some View {
        TimelineScreen()
            .modifier(PartyModeAnimationHost(appearanceState: appearanceState))
#if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("-MixrPartyModeScreenshot"),
                   !appearanceState.isPartyModeEnabled {
                    // Leaves a stable pre-activation frame for automated visual QA.
                    try? await Task.sleep(for: .seconds(8))
                    appearanceState.togglePartyMode()
                }
            }
#endif
    }
}

#Preview {
    ContentView()
        .frame(width: 932, height: 430)
        .environment(AppAppearanceState())
        .modelContainer(for: MixrProjectRecord.self, inMemory: true)
}
