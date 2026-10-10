import Foundation

// First-launch spotlight tour — the step model, copy and persistence.
// Pure Foundation (no SwiftUI) so the flow is unit-tested off-device;
// the overlay that draws it lives in DesignSystem/OnboardingTourOverlay.swift.

/// A control the tour can spotlight. Views report their frame for one of
/// these with `.onboardingTarget(_:)`.
nonisolated enum OnboardingTarget: Hashable, Sendable {
    case importSongs
    case firstSongRow
    case volumeControls
    case firstClip
    case effectsPanel
    case soundEffectsButton
}

/// The motion the animated finger demonstrates over a target.
nonisolated enum OnboardingGesture: Sendable {
    case tap
    case swipeLeft
    case drag
    case scroll
}

nonisolated enum OnboardingStep: Int, CaseIterable, Sendable {
    case importSongs
    case deleteSong
    case volume
    case clipTools
    case tuneSound
    case soundEffects

    var title: String {
        switch self {
        case .importSongs: "Import your songs"
        case .deleteSong: "Swipe left to delete"
        case .volume: "Set each song\u{2019}s volume"
        case .clipTools: "Tap a clip for tools"
        case .tuneSound: "Tune the sound"
        case .soundEffects: "Add sound effects"
        }
    }

    var message: String {
        switch self {
        case .importSongs: "Tap Import Songs to bring in the tracks you want to remix."
        case .deleteSong: "Slide a song to the left, then tap Delete to remove it."
        case .volume: "Drag a slider on the right. S solos a song, M mutes it."
        case .clipTools: "Split it, change its speed, duplicate it or delete it."
        case .tuneSound: "With a clip selected, add Reverb, Echo, Pitch and more."
        case .soundEffects: "Tap sfx for risers, impacts, bass drops and more."
        }
    }

    var target: OnboardingTarget {
        switch self {
        case .importSongs: .importSongs
        case .deleteSong: .firstSongRow
        case .volume: .volumeControls
        case .clipTools: .firstClip
        case .tuneSound: .effectsPanel
        case .soundEffects: .soundEffectsButton
        }
    }

    var gesture: OnboardingGesture {
        switch self {
        case .deleteSong: .swipeLeft
        case .volume: .drag
        case .tuneSound: .scroll
        case .importSongs, .clipTools, .soundEffects: .tap
        }
    }

    /// Steps that point at a song row, a slider or a clip need a song.
    var needsSongs: Bool {
        switch self {
        case .deleteSong, .volume, .clipTools, .tuneSound: true
        case .importSongs, .soundEffects: false
        }
    }

    /// Taps inside the spotlight reach the real control (step 1 only:
    /// tapping Import Songs opens the file picker and the tour continues
    /// once the first song lands).
    var passesTouchesToTarget: Bool { self == .importSongs }

    /// Steps 3–5 show the clip toolbar / live effects on a selected clip.
    var selectsClip: Bool { self == .clipTools || self == .tuneSound }

    var isLast: Bool { self == Self.allCases.last }

    /// "2 OF 6"
    var progressLabel: String { "\(rawValue + 1) OF \(Self.allCases.count)" }
    var accessibilityProgress: String { "Step \(rawValue + 1) of \(Self.allCases.count)" }
}

nonisolated enum OnboardingCopy {
    static let skip = "Skip"
    static let next = "Next"
    static let finish = "Start mixing"
    static let replay = "Replay tour"
}

/// Where a person is in the tour, across launches.
nonisolated enum OnboardingProgress: String, Sendable {
    /// Never seen (or asked to replay): step 1 shows on the next editor visit.
    case notStarted
    /// Saw step 1 on an empty editor; steps 2–6 continue once a song exists.
    case awaitingFirstSong
    /// Finished or skipped.
    case finished
}

/// The tour's state machine. `hasSongs` = the project has at least one
/// non-SFX track with a clip.
nonisolated struct OnboardingTourState: Equatable, Sendable {
    var progress: OnboardingProgress
    var activeStep: OnboardingStep?

    init(progress: OnboardingProgress, activeStep: OnboardingStep? = nil) {
        self.progress = progress
        self.activeStep = activeStep
    }

    /// Call when the editor appears and whenever the song list changes.
    mutating func update(hasSongs: Bool) {
        if let step = activeStep {
            if step == .importSongs, hasSongs {
                // They imported straight from step 1: carry on with the song.
                activeStep = .deleteSong
            } else if step.needsSongs, !hasSongs {
                // The last song was removed mid-tour: pause until one is back.
                activeStep = nil
                progress = .awaitingFirstSong
            }
            return
        }
        switch progress {
        case .notStarted:
            activeStep = .importSongs
        case .awaitingFirstSong:
            if hasSongs { activeStep = .deleteSong }
        case .finished:
            break
        }
    }

    mutating func next(hasSongs: Bool) {
        guard let step = activeStep else { return }
        if step.isLast {
            finish()
            return
        }
        let following = OnboardingStep(rawValue: step.rawValue + 1)!
        if following.needsSongs, !hasSongs {
            // Step 1 on an empty editor: wait for the first import.
            activeStep = nil
            progress = .awaitingFirstSong
        } else {
            activeStep = following
        }
    }

    mutating func skip() { finish() }

    mutating func replay(hasSongs: Bool) {
        progress = .notStarted
        activeStep = nil
        update(hasSongs: hasSongs)
    }

    private mutating func finish() {
        activeStep = nil
        progress = .finished
    }
}

/// UserDefaults-backed storage for the tour's progress.
nonisolated struct OnboardingTourStore {
    static let defaultsKey = "mixr.onboardingTour.progress"
    var defaults: UserDefaults = .standard

    func load() -> OnboardingProgress {
        defaults.string(forKey: Self.defaultsKey).flatMap(OnboardingProgress.init(rawValue:)) ?? .notStarted
    }

    func save(_ progress: OnboardingProgress) {
        defaults.set(progress.rawValue, forKey: Self.defaultsKey)
    }
}
