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

/// Per-clip effect state — STORED on `MixrClip.effects`, so effects follow
/// the clip through moves, splits, duplication, trims, undo/redo, and
/// persist inside the project snapshot (ProjectSnapshot → SwiftData).
///
/// Levels are 0…100 keyed by `MixrEffect.rawValue`; 0 = true bypass.
/// The slider→parameter mapping lives in `ClipEffectDSP.targets(for:...)`
/// and is shared by live playback (MixrPlaybackEngine) and export
/// (MixrExportRenderer) so both sound identical:
/// Reverb → AVAudioUnitReverb, Echo → AVAudioUnitDelay,
/// Blur → EQ low-pass, Bass Boost → multi-band EQ + subtle saturation,
/// Pitch Up → AVAudioUnitTimePitch.
///
/// nonisolated: pure value type, read by the background export renderer.
nonisolated struct ClipEffectSettings: Equatable, Sendable, Codable {
    /// Effect level 0…100 per effect id (see MixrEffect.rawValue).
    var levels: [String: Double] = [:]
    var reverbPreset: ReverbPreset = .smallRoom
    var echoPreset: EchoPreset = .classic

    /// Legacy effect ids → their current id, ordered newest generation
    /// first so the most recent stored value wins when several coexist.
    /// History of this slot: "filter" (teal Filter) → "warmth" (red Warmth)
    /// → "haze" → "blur".
    private static let legacyEffectKeyAliases: [(legacy: String, current: String)] = [
        ("haze", "blur"),
        ("warmth", "blur"),
        ("filter", "blur"),
    ]

    func level(for effectID: String) -> Double {
        levels[effectID] ?? legacyValue(for: effectID) ?? 0
    }

    mutating func setLevel(_ value: Double, for effectID: String) {
        for alias in Self.legacyEffectKeyAliases where alias.current == effectID {
            levels.removeValue(forKey: alias.legacy)
        }
        levels[effectID] = min(100, max(0, value))
    }

    mutating func migrateLegacyEffectKeys() {
        for (legacy, current) in Self.legacyEffectKeyAliases {
            guard let value = levels.removeValue(forKey: legacy) else { continue }
            if levels[current] == nil {
                levels[current] = value
            }
        }
    }

    private func legacyValue(for effectID: String) -> Double? {
        for alias in Self.legacyEffectKeyAliases where alias.current == effectID {
            if let value = levels[alias.legacy] { return value }
        }
        return nil
    }

    var hasAnyActiveEffect: Bool {
        levels.values.contains { $0 > 0.5 }
    }
}
