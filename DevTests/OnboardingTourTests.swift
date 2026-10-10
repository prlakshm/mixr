import Foundation

// Onboarding tour flow + wiring checks — NOT part of the app target.
//   Scripts/run_onboarding_tests.sh

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

// MARK: - Copy (the user's final text, verbatim)

let expected: [(String, String)] = [
    ("Import your songs", "Tap Import Songs to bring in the tracks you want to remix."),
    ("Swipe left to delete", "Slide a song to the left, then tap Delete to remove it."),
    ("Set each song\u{2019}s volume", "Drag a slider on the right. S solos a song, M mutes it."),
    ("Tap a clip for tools", "Split it, change its speed, duplicate it or delete it."),
    ("Tune the sound", "With a clip selected, add Reverb, Echo, Pitch and more."),
    ("Add sound effects", "Tap sfx for risers, impacts, bass drops and more."),
]
check("Six steps in order", OnboardingStep.allCases.count == 6)
for (step, copy) in zip(OnboardingStep.allCases, expected) {
    check("Copy step \(step.rawValue + 1): \(copy.0)", step.title == copy.0 && step.message == copy.1)
}
check("Button labels", OnboardingCopy.skip == "Skip" && OnboardingCopy.next == "Next"
      && OnboardingCopy.finish == "Start mixing" && OnboardingCopy.replay == "Replay tour")
check("Progress label", OnboardingStep.volume.progressLabel == "3 OF 6"
      && OnboardingStep.volume.accessibilityProgress == "Step 3 of 6")
check("Each step points at a different control",
      Set(OnboardingStep.allCases.map(\.target)).count == OnboardingStep.allCases.count)
check("Only step 1 lets touches through to its control",
      OnboardingStep.allCases.filter(\.passesTouchesToTarget) == [.importSongs])

// MARK: - Flow

do {
    // First launch, empty editor: step 1 only, then wait for a song.
    var t = OnboardingTourState(progress: .notStarted)
    t.update(hasSongs: false)
    check("First launch shows step 1", t.activeStep == .importSongs)
    t.next(hasSongs: false)
    check("Next on an empty editor waits for the first song",
          t.activeStep == nil && t.progress == .awaitingFirstSong)
    t.update(hasSongs: false)
    check("Still waiting while empty", t.activeStep == nil)
    t.update(hasSongs: true)
    check("First song resumes at step 2", t.activeStep == .deleteSong)
    for expectedStep in [OnboardingStep.volume, .clipTools, .tuneSound, .soundEffects] {
        t.next(hasSongs: true)
        check("Advances to \(expectedStep)", t.activeStep == expectedStep)
    }
    t.next(hasSongs: true)
    check("Start mixing finishes", t.activeStep == nil && t.progress == .finished)
    t.update(hasSongs: true)
    check("Finished tour never reappears on its own", t.activeStep == nil)
}

do {
    // Tapping Import Songs inside the spotlight: step 2 follows the import.
    var t = OnboardingTourState(progress: .notStarted)
    t.update(hasSongs: false)
    t.update(hasSongs: true)
    check("Importing during step 1 continues to step 2", t.activeStep == .deleteSong)
}

do {
    // Skip at any step ends the whole tour.
    for step in OnboardingStep.allCases where !step.isLast {
        var t = OnboardingTourState(progress: .notStarted, activeStep: step)
        t.skip()
        check("Skip on step \(step.rawValue + 1) ends the tour", t.activeStep == nil && t.progress == .finished)
    }
    var t = OnboardingTourState(progress: .notStarted)
    t.update(hasSongs: false)
    t.skip()
    t.update(hasSongs: true)
    check("Skipping step 1 also skips steps 2–6 after an import", t.activeStep == nil)
}

do {
    // Deleting the last song mid-tour pauses; the tour resumes where it was.
    var t = OnboardingTourState(progress: .notStarted, activeStep: .clipTools)
    t.update(hasSongs: false)
    check("Removing the last song pauses the tour", t.activeStep == nil && t.progress == .awaitingFirstSong)
    t.update(hasSongs: true)
    check("…and resumes at the same step", t.activeStep == .clipTools)

    var sfx = OnboardingTourState(progress: .notStarted, activeStep: .soundEffects)
    sfx.update(hasSongs: false)
    check("The sfx step doesn't need a song", sfx.activeStep == .soundEffects)
}

do {
    // Existing projects (songs already there): full tour from step 1.
    var t = OnboardingTourState(progress: .notStarted)
    t.update(hasSongs: true)
    check("With songs already loaded, the tour still opens on step 1", t.activeStep == .importSongs)
    var u = OnboardingTourState(progress: .notStarted, activeStep: .importSongs)
    u.next(hasSongs: true)
    check("Next from step 1 with songs goes straight to step 2", u.activeStep == .deleteSong)
}

do {
    // Replay restarts from step 1.
    var t = OnboardingTourState(progress: .finished)
    t.replay(hasSongs: true)
    check("Replay restarts at step 1", t.activeStep == .importSongs && t.progress == .notStarted)
}

do {
    // Progress survives relaunch.
    let suite = "mixr.onboarding.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = OnboardingTourStore(defaults: defaults)
    check("Fresh install starts not-started", store.load() == .notStarted)
    store.save(.awaitingFirstSong)
    check("Waiting-for-a-song survives relaunch", OnboardingTourStore(defaults: defaults).load() == .awaitingFirstSong)
    store.save(.finished)
    check("Finished survives relaunch", OnboardingTourStore(defaults: defaults).load() == .finished)

    // Relaunch mid-tour: each song step comes back as the same step.
    for step in OnboardingStep.allCases {
        store.save(OnboardingTourState(progress: .notStarted, activeStep: step))
        var relaunched = OnboardingTourStore(defaults: defaults).loadState()
        relaunched.update(hasSongs: true)
        let expected: OnboardingStep = step == .importSongs ? .importSongs : step
        check("Relaunch on step \(step.rawValue + 1) returns to step \(expected.rawValue + 1)",
              relaunched.activeStep == expected)
    }
    // Relaunch while waiting for the first song: nothing until a song lands.
    var waiting = OnboardingTourState(progress: .notStarted, activeStep: .importSongs)
    waiting.next(hasSongs: false)
    store.save(waiting)
    var restored = OnboardingTourStore(defaults: defaults).loadState()
    restored.update(hasSongs: false)
    check("Relaunch while waiting shows nothing on an empty editor", restored.activeStep == nil)
    restored.update(hasSongs: true)
    check("…and step 2 once a song lands", restored.activeStep == .deleteSong)
    defaults.removePersistentDomain(forName: suite)
}

// MARK: - Wiring (source contracts): every spotlight target is attached
// to the real control, so a refactor can't silently orphan a step.

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String {
    (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}
let timeline = source("Mixr/TimelineScreen.swift")
let menu = source("Mixr/DesignSystem/ProjectDropdown.swift")
let overlay = source("Mixr/DesignSystem/OnboardingTourOverlay.swift")
check("Sources found", !timeline.isEmpty && !menu.isEmpty && !overlay.isEmpty)
for target in ["importSongs", "firstSongRow", "volumeControls", "firstClip", "effectsPanel", "soundEffectsButton"] {
    check("Target .\(target) is attached in the editor", timeline.contains(".onboardingTarget(.\(target)"))
}
check("Overlay reads target frames at the editor root", timeline.contains(".overlayPreferenceValue(OnboardingTargetKey.self)"))
check("Tour starts after the project loads and follows song changes",
      timeline.contains(".onChange(of: [library.hasLoadedProject, tourHasSongs])")
        && timeline.contains("tour.update(hasSongs: inputs[1])"))
check("Progress is persisted on every change", timeline.contains("OnboardingTourStore().save(state)"))
check("Project menu offers Replay tour", menu.contains("OnboardingCopy.replay") && timeline.contains("onReplayTour:"))
check("Next button uses the approved purples (rest / hover / pressed)",
      overlay.contains("\"7231DD\"") && overlay.contains("\"8244E9\"") && overlay.contains("\"682BCF\""))
check("Reduce Motion is respected", overlay.contains("accessibilityReduceMotion"))
check("Tip changes are announced to VoiceOver", overlay.contains("AccessibilityNotification.Announcement"))
check("Skip sits left of Next", {
    guard let skip = overlay.range(of: "OnboardingCopy.skip"), let next = overlay.range(of: "OnboardingCopy.next") else { return false }
    return skip.lowerBound < next.lowerBound
}())

print(failures == 0 ? "\nALL PASSED" : "\nFAILED: \(failures)")
exit(failures == 0 ? 0 : 1)
