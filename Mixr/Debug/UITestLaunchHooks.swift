#if DEBUG
import Foundation

/// DEBUG-only launch hooks for the XCUITest suite (MixrUITests).
///
/// - `-MixrUITestReset`: starts from a fresh install — no projects, no tour
///   progress. Runs before the SwiftData container opens.
/// - `-MixrUITestTourDone`: marks the onboarding tour finished, so flow tests
///   that are not about the tour see the plain editor.
/// - `-MixrUITestSongs <dir>`: imports every audio file in `<dir>` (a host
///   path; the simulator can read it) once the editor appears, through the
///   same `TrackLibrary.addTracks(from:)` the file picker uses.
enum UITestLaunchHooks {
    static let arguments = ProcessInfo.processInfo.arguments

    static var isUITest: Bool { arguments.contains { $0.hasPrefix("-MixrUITest") } }

    static func prepareLaunch() {
        if arguments.contains("-MixrUITestReset") {
            let fm = FileManager.default
            if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let items = try? fm.contentsOfDirectory(at: support, includingPropertiesForKeys: nil) {
                for item in items where item.lastPathComponent.hasPrefix("default.store") {
                    try? fm.removeItem(at: item)
                }
            }
            UserDefaults.standard.removeObject(forKey: OnboardingTourStore.defaultsKey)
            UserDefaults.standard.removeObject(forKey: OnboardingTourStore.resumeStepKey)
        }
        if arguments.contains("-MixrUITestTourDone") {
            OnboardingTourStore().save(.finished)
        }
    }

    /// `-MixrSlowMotion <factor>`: slows frame-driven effects (the Import halo)
    /// so a test can capture them frame by frame.
    static let animationTimeScale: Double = {
        guard let i = arguments.firstIndex(of: "-MixrSlowMotion"),
              arguments.indices.contains(i + 1),
              let value = Double(arguments[i + 1]), value > 0 else { return 1 }
        return value
    }()

    /// Audio files to import once the editor's project has loaded.
    static var songURLs: [URL] {
        guard let i = arguments.firstIndex(of: "-MixrUITestSongs"),
              arguments.indices.contains(i + 1) else { return [] }
        let dir = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        let audio = Set(["m4a", "mp3", "wav", "aiff", "aif"])
        return files
            .filter { audio.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
#endif
