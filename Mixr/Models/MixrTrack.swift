import SwiftUI

// MARK: - Track Model

struct MixrTrack: Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var duration: String        // display string e.g. "3:20"; "--:--" while loading
    var durationSeconds: Double?
    var bpm: Int
    var color: MixrWaveformColor
    var volume: Double
    var url: URL?
    var clips: [MixrClip]
}

struct MixrClip: Identifiable {
    let id: UUID
    var start: CGFloat   // timeline units (0 – totalUnits)
    var length: CGFloat  // timeline units
}
