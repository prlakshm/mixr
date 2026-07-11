import SwiftUI

// MARK: - Clip Transition Types

enum ClipTransitionType: String, CaseIterable, Equatable, Sendable, Identifiable, Codable {
    case none      = "None"
    case crossfade = "Crossfade"
    case fadeOut   = "Fade Out"
    case echoOut   = "Echo Out"
    case auto      = "Auto"

    var id: Self { self }
}

struct ClipTransition: Equatable, Sendable, Codable {
    var type:     ClipTransitionType = .none
    var duration: Double = 0.5
    var curve:    String = "linear"

    nonisolated init(
        type: ClipTransitionType = .none,
        duration: Double = 0.5,
        curve: String = "linear"
    ) {
        self.type = type
        self.duration = duration
        self.curve = curve
    }

    nonisolated static let none = ClipTransition()
}

enum GripSide: Equatable {
    case leading   // Transition In
    case trailing  // Transition Out
}

struct ActiveGrip: Equatable {
    let clipID:  UUID
    let trackID: UUID
    let side:    GripSide
}

// MARK: - Track Type

enum TrackType: String, Codable, Equatable, Sendable {
    case song
    case soundEffect
}

// MARK: - Track Model

struct MixrTrack: Identifiable {
    let id: UUID
    var title: String
    var artist: String
    /// Display string, e.g. "3:20" or "--:--" while loading.
    var duration: String
    var durationSeconds: Double?
    var bpm: Int?
    var bpmConfidence: Double?  // nil = from metadata (trusted); 0–1 from analysis
    var key: String?
    var keyConfidence: Double?  // nil = from metadata (trusted); 0–1 from analysis
    var color: MixrWaveformColor
    var volume: Double
    var isMuted: Bool
    var isSoloed: Bool = false
    var trackType: TrackType = .song
    var url: URL?
    var artworkData: Data?
    var clips: [MixrClip]

    var isSFXTrack: Bool { trackType == .soundEffect }

    /// Display BPM; shows "~N" when estimated with moderate confidence, "--" when unknown.
    var bpmDisplay: String {
        guard let bpm else { return "--" }
        if let conf = bpmConfidence, conf < 0.6 { return "~\(bpm)" }
        return String(bpm)
    }

    /// Display key; e.g. "D# minor", "~G major", "--" when unknown.
    var keyDisplay: String {
        guard let key, !key.isEmpty else { return "--" }
        let spelled = Self.spelledOutKey(key)
        if let conf = keyConfidence, conf < 0.6 { return "~\(spelled)" }
        return spelled
    }

    /// Formats stored key codes (e.g. "D#m", "G") as "D# minor" / "G major".
    private static func spelledOutKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasSuffix(" minor") {
            let note = String(trimmed.dropLast(6)).trimmingCharacters(in: .whitespaces)
            return note.isEmpty ? trimmed : "\(note) minor"
        }
        if lower.hasSuffix(" major") {
            let note = String(trimmed.dropLast(6)).trimmingCharacters(in: .whitespaces)
            return note.isEmpty ? trimmed : "\(note) major"
        }

        // Analyzer / shorthand: trailing "m" = minor (D#m, Am, …)
        if trimmed.count > 1, trimmed.hasSuffix("m") {
            let note = String(trimmed.dropLast())
            if !note.isEmpty {
                return "\(note) minor"
            }
        }

        return "\(trimmed) major"
    }
}

struct MixrClip: Identifiable, Equatable {
    let id: UUID
    var start:         CGFloat   // timeline units (0–totalUnits)
    var length:        CGFloat   // timeline units
    /// Playback rate multiplier. 1.0 = normal; >1 faster/shorter; <1 slower/longer.
    var playbackSpeed: Double = 1.0
    var transitionIn:  ClipTransition = .none
    var transitionOut: ClipTransition = .none
    /// Per-clip gain 0…1 — applied live by MixrPlaybackEngine
    /// (track volume × clip volume × transition envelope).
    var volume:        Double = 1.0
    /// Per-clip effect levels and presets (Reverb, Echo, Filter, …).
    var effects:       ClipEffectSettings = ClipEffectSettings()
    /// Non-nil when this clip is a built-in sound effect on the SFX track.
    var soundEffectID: String? = nil
    /// Seconds into the source audio where this clip's content begins —
    /// set by splits/trims so each segment plays the right part of the song.
    var sourceOffsetSeconds: Double = 0

    var isSoundEffect: Bool { soundEffectID != nil }

    /// Song-time (seconds into the source) at a timeline unit inside this clip.
    func songSeconds(atUnit unit: CGFloat) -> Double {
        sourceOffsetSeconds + MixrTimeline.seconds(fromUnits: max(0, unit - start)) * playbackSpeed
    }

    /// Timeline unit inside this clip for a given song-time (seconds into source).
    func unit(forSongSeconds seconds: Double) -> CGFloat {
        let speed = max(playbackSpeed, 0.0001)
        return start + MixrTimeline.units(fromSeconds: (seconds - sourceOffsetSeconds) / speed)
    }
}

extension MixrClip: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, start, length, playbackSpeed, transitionIn, transitionOut
        case volume, effects, soundEffectID, sourceOffsetSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(CGFloat.self, forKey: .start)
        length = try c.decode(CGFloat.self, forKey: .length)
        playbackSpeed = try c.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1.0
        transitionIn = try c.decodeIfPresent(ClipTransition.self, forKey: .transitionIn) ?? .none
        transitionOut = try c.decodeIfPresent(ClipTransition.self, forKey: .transitionOut) ?? .none
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        effects = try c.decodeIfPresent(ClipEffectSettings.self, forKey: .effects) ?? ClipEffectSettings()
        soundEffectID = try c.decodeIfPresent(String.self, forKey: .soundEffectID)
        sourceOffsetSeconds = try c.decodeIfPresent(Double.self, forKey: .sourceOffsetSeconds) ?? 0
    }
}

// MARK: - Codable track (URL persisted as a security-scoped bookmark)

extension MixrTrack: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, artist, duration, durationSeconds
        case bpm, bpmConfidence, key, keyConfidence
        case color, volume, isMuted, isSoloed, trackType
        case urlBookmark, urlPath, artworkData, clips
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(String.self, forKey: .artist)
        duration = try c.decode(String.self, forKey: .duration)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm)
        bpmConfidence = try c.decodeIfPresent(Double.self, forKey: .bpmConfidence)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        keyConfidence = try c.decodeIfPresent(Double.self, forKey: .keyConfidence)
        color = try c.decode(MixrWaveformColor.self, forKey: .color)
        volume = try c.decode(Double.self, forKey: .volume)
        isMuted = try c.decode(Bool.self, forKey: .isMuted)
        isSoloed = try c.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
        trackType = try c.decodeIfPresent(TrackType.self, forKey: .trackType) ?? .song
        artworkData = try c.decodeIfPresent(Data.self, forKey: .artworkData)
        clips = try c.decode([MixrClip].self, forKey: .clips)

        if let bookmark = try c.decodeIfPresent(Data.self, forKey: .urlBookmark) {
            var isStale = false
            url = try? URL(
                resolvingBookmarkData: bookmark,
                bookmarkDataIsStale: &isStale
            )
        }
        if url == nil, let path = try c.decodeIfPresent(String.self, forKey: .urlPath) {
            url = URL(fileURLWithPath: path)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try c.encodeIfPresent(bpm, forKey: .bpm)
        try c.encodeIfPresent(bpmConfidence, forKey: .bpmConfidence)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(keyConfidence, forKey: .keyConfidence)
        try c.encode(color, forKey: .color)
        try c.encode(volume, forKey: .volume)
        try c.encode(isMuted, forKey: .isMuted)
        try c.encode(isSoloed, forKey: .isSoloed)
        try c.encode(trackType, forKey: .trackType)
        try c.encodeIfPresent(artworkData, forKey: .artworkData)
        try c.encode(clips, forKey: .clips)

        if let url {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let bookmark = try? url.bookmarkData() {
                try c.encode(bookmark, forKey: .urlBookmark)
            }
            try c.encode(url.path, forKey: .urlPath)
        }
    }
}
