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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: MixrProjectRecord.self)
    }
}
