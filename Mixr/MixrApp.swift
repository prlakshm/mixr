//
//  MixrApp.swift
//  Mixr
//
//  Created by Pranavi Lakshminarayanan on 6/19/26.
//

import SwiftUI
import SwiftData

@main
struct MixrApp: App {
    @State private var appearanceState = AppAppearanceState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appearanceState)
        }
        .modelContainer(for: MixrProjectRecord.self)
    }
}
