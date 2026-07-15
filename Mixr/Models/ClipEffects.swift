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

/// Pitch direction for the Pitch effect. The slider is always 0…100
/// intensity; this chooses whether that amount raises or lowers pitch.
/// Segment labels follow the Duration control pattern — only the selected
/// option shows the "Pitch" prefix ("Pitch Up" | "Down", etc.).
enum PitchDirection: String, CaseIterable, Identifiable, Equatable, Sendable, Codable {
    case up
    case down

    var id: String { rawValue }

    /// +1 for up, −1 for down — multiplies the cents mapping.
    var centsSign: Double {
        switch self {
        case .up: 1
        case .down: -1
        }
    }

    func label(isSelected: Bool) -> String {
        switch self {
        case .up: isSelected ? "Pitch Up" : "Up"
        case .down: isSelected ? "Pitch Down" : "Down"
        }
    }
}

// MARK: - Per-Clip Effect Settings

/// Per-clip effect state — STORED on `MixrClip.effects`, so effects follow
/// the clip through moves, splits, duplication, trims, undo/redo, and
/// persist inside the project snapshot (ProjectSnapshot → SwiftData).
///
/// Levels are 0…100 keyed by `MixrEffect.rawValue`; 0 = true bypass.
/// Pitch intensity lives in `levels["pitchUp"]` (legacy key kept for
/// saved projects); `pitchDirection` chooses raise vs lower.
/// Flanger intensity lives in `levels["flanger"]` (exposed normalized
/// via `flangerAmount`). The slider→parameter mapping lives in
/// `ClipEffectDSP` and is shared by live playback and export.
///
/// nonisolated: pure value type, read by the background export renderer.
nonisolated struct ClipEffectSettings: Equatable, Sendable, Codable {
    /// Effect level 0…100 per effect id (see MixrEffect.rawValue).
    var levels: [String: Double] = [:]
    var reverbPreset: ReverbPreset = .smallRoom
    var echoPreset: EchoPreset = .classic
    /// Pitch Up (default) or Pitch Down. Older projects decode as `.up`.
    var pitchDirection: PitchDirection = .up

    /// Legacy effect ids → their current id, ordered newest generation
    /// first so the most recent stored value wins when several coexist.
    private static let legacyEffectKeyAliases: [(legacy: String, current: String)] = [
        ("haze", "blur"),
        ("warmth", "blur"),
        ("filter", "blur"),
    ]

    /// Effect ids that no longer exist and must NOT migrate anywhere —
    /// their stored values are dropped so old projects still load, but a
    /// retired Bass Boost / Stutter value never bleeds into Flanger.
    private static let retiredEffectKeys: Set<String> = ["bassBoost", "stutter"]

    private enum CodingKeys: String, CodingKey {
        case levels, reverbPreset, echoPreset, pitchDirection, pitchAmount
    }

    init(
        levels: [String: Double] = [:],
        reverbPreset: ReverbPreset = .smallRoom,
        echoPreset: EchoPreset = .classic,
        pitchDirection: PitchDirection = .up
    ) {
        self.levels = levels
        self.reverbPreset = reverbPreset
        self.echoPreset = echoPreset
        self.pitchDirection = pitchDirection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levels = try c.decodeIfPresent([String: Double].self, forKey: .levels) ?? [:]
        reverbPreset = try c.decodeIfPresent(ReverbPreset.self, forKey: .reverbPreset) ?? .smallRoom
        echoPreset = try c.decodeIfPresent(EchoPreset.self, forKey: .echoPreset) ?? .classic
        pitchDirection = try c.decodeIfPresent(PitchDirection.self, forKey: .pitchDirection) ?? .up
        if levels["pitchUp"] == nil,
           let amount = try c.decodeIfPresent(Double.self, forKey: .pitchAmount) {
            let normalized = amount <= 1.0 + 1e-9 ? amount * 100.0 : amount
            levels["pitchUp"] = min(100, max(0, normalized))
        }
        for key in Self.retiredEffectKeys { levels.removeValue(forKey: key) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(levels, forKey: .levels)
        try c.encode(reverbPreset, forKey: .reverbPreset)
        try c.encode(echoPreset, forKey: .echoPreset)
        try c.encode(pitchDirection, forKey: .pitchDirection)
        try c.encode(pitchAmount, forKey: .pitchAmount)
    }

    /// Pitch intensity 0…1 — backed by `levels["pitchUp"]` (0…100).
    var pitchAmount: Double {
        get { level(for: "pitchUp") / 100.0 }
        set { setLevel(newValue * 100.0, for: "pitchUp") }
    }

    /// Flanger intensity 0…1 — backed by `levels["flanger"]` (0…100).
    var flangerAmount: Double {
        get { level(for: "flanger") / 100.0 }
        set { setLevel(newValue * 100.0, for: "flanger") }
    }

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
        for key in Self.retiredEffectKeys { levels.removeValue(forKey: key) }
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
