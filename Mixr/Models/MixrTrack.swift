import SwiftUI

// MARK: - Clip Transition Types

enum ClipTransitionType: String, CaseIterable, Equatable, Sendable, Identifiable {
    case none      = "None / Hard Cut"
    case crossfade = "Crossfade"
    case fadeOut   = "Fade Out"
    case echoOut   = "Echo Out"
    case auto      = "Auto"

    var id: Self { self }
}

struct ClipTransition: Equatable, Sendable {
    var type:     ClipTransitionType = .none
    var duration: Double = 0.5
    var strength: Double = 1.0
    var curve:    String = "linear"

    static let none = ClipTransition()
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
    var url: URL?
    var artworkData: Data?
    var clips: [MixrClip]

    /// Display BPM; shows "~N" when estimated with moderate confidence, "--" when unknown.
    var bpmDisplay: String {
        guard let bpm else { return "--" }
        if let conf = bpmConfidence, conf < 0.6 { return "~\(bpm)" }
        return String(bpm)
    }

    /// Display key; shows "~Key" when estimated with moderate confidence, "--" when unknown.
    var keyDisplay: String {
        guard let key, !key.isEmpty else { return "--" }
        if let conf = keyConfidence, conf < 0.6 { return "~\(key)" }
        return key
    }
}

struct MixrClip: Identifiable {
    let id: UUID
    var start:         CGFloat   // timeline units (0–totalUnits)
    var length:        CGFloat   // timeline units
    var transitionIn:  ClipTransition = .none
    var transitionOut: ClipTransition = .none
}
