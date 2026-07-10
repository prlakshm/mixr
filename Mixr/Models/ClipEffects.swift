import Foundation

// MARK: - Effect Presets

enum ReverbPreset: String, CaseIterable, Identifiable, Equatable, Sendable, Codable {
    case smallRoom
    case hall
    case ambient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smallRoom: "Small Room"
        case .hall: "Hall"
        case .ambient: "Ambient"
        }
    }
}

enum EchoPreset: String, CaseIterable, Identifiable, Equatable, Sendable, Codable {
    case classic
    case pingPong
    case reverse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .pingPong: "Ping Pong"
        case .reverse: "Reverse"
        }
    }
}

// MARK: - Per-Clip Effect Settings

/// Per-clip effect state. Levels are 0…100 keyed by `MixrEffect.rawValue`.
/// AVAudioEngine integration point: map these levels/presets onto
/// AVAudioUnitReverb / AVAudioUnitDelay / AVAudioUnitEQ nodes once
/// per-clip audio routing exists in MixrPlaybackEngine.
struct ClipEffectSettings: Equatable, Sendable, Codable {
    /// Effect level 0…100 per effect id (see MixrEffect.rawValue).
    var levels: [String: Double] = [:]
    var reverbPreset: ReverbPreset = .smallRoom
    var echoPreset: EchoPreset = .classic

    func level(for effectID: String) -> Double {
        levels[effectID] ?? 0
    }

    mutating func setLevel(_ value: Double, for effectID: String) {
        levels[effectID] = min(100, max(0, value))
    }

    var hasAnyActiveEffect: Bool {
        levels.values.contains { $0 > 0.5 }
    }
}
