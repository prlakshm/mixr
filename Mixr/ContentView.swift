import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TimelineScreen()
    }
}

#Preview {
    ContentView()
        .frame(width: 932, height: 430)
        .modelContainer(for: MixrProjectRecord.self, inMemory: true)
}
