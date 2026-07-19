import Foundation

// Minimal stubs so the Auto pipeline harness can compile without the full
// DesignSystem / playback / SwiftData stack. Not used by the app target.

enum MixrEffect: String, CaseIterable, Identifiable {
    case auto, reverb, echo, pitchUp, flanger, blur
    var id: String { rawValue }
}

enum MixrWaveformColor: String, CaseIterable, Identifiable, Codable {
    case pink, purple, red, yellow, blue, silver
    var id: Self { self }
}
