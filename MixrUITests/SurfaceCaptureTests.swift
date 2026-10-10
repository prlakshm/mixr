import XCTest

/// Design-review captures of every editor surface on the current device.
/// Opt-in: runs only when MIXR_DESIGN_CAPTURE=1 (Scripts/run_ui_tests.sh
/// forwards it), so the regular suite stays fast.
final class SurfaceCaptureTests: MixrUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MIXR_DESIGN_CAPTURE"] == "1",
                          "set MIXR_DESIGN_CAPTURE=1 to capture design-review screenshots")
    }

    private var device: String {
        let size = XCUIScreen.main.screenshot().image.size
        return "\(Int(max(size.width, size.height)))"
    }

    func testCaptureSurfaces() {
        launch(fresh: true, tourDone: true)
        let d = device
        capture("\(d)-01-empty")

        app.terminate()
        launch(fresh: true, tourDone: true, songs: true)
        sleep(1)
        capture("\(d)-02-editor")

        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Night Signals clip'")).firstMatch)
        sleep(1)
        capture("\(d)-03-clip-toolbar")

        tap(app.buttons["Reverb"])
        sleep(1)
        capture("\(d)-04-effect-tray")
        // Deselect: tap the empty timeline just below the last lane.
        let lastClip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Paper Suns clip'")).firstMatch
        tapPoint(lastClip.frame.midX, lastClip.frame.maxY + 14)
        sleep(1)

        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Project, '")).firstMatch)
        sleep(1)
        capture("\(d)-05-project-menu")
        tapPoint(app.frame.width * 0.9, app.frame.height * 0.9)
        sleep(1)

        tap(app.buttons["Sound Effects"])
        sleep(1)
        capture("\(d)-06-sfx")
        tap(app.buttons["Close"])
        sleep(1)

        tap(app.buttons["Auto"])
        sleep(1)
        capture("\(d)-07-auto")
        tap(app.buttons["Cancel"])
        sleep(1)

        songTitle("Paper Suns").swipeLeft()
        sleep(1)
        capture("\(d)-08-swipe-delete")
    }

    /// The empty editor's Import Songs pulse, sampled across two breaths.
    func testCaptureImportPulse() {
        launch(fresh: true, tourDone: true)
        sleep(1)
        for i in 0..<16 {
            capture(String(format: "pulse-%02d", i))
            usleep(150_000)
        }
    }

    /// Effect cards' level rings after giving a clip some Reverb and Echo.
    func testCaptureEffectLevels() {
        launch(fresh: true, tourDone: true, songs: true)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Night Signals clip'")).firstMatch)
        for effect in ["Reverb", "Echo"] {
            tap(app.buttons[effect])
            let level = app.descendants(matching: .any)["\(effect) level"]
            XCTAssertTrue(level.waitForExistence(timeout: 3))
            level.coordinate(withNormalizedOffset: CGVector(dx: effect == "Reverb" ? 0.7 : 0.35, dy: 0.5)).tap()
            tap(app.buttons[effect]) // close the tray
            sleep(1)
        }
        capture("effect-levels")
    }

    /// The Import Songs halo, filmed at half speed (the GIF script plays
    /// the frames back at real speed).
    func testCaptureHalo() {
        launch(fresh: true, tourDone: true, extra: ["-MixrSlowMotion", "0.5"])
        sleep(1)
        for i in 0..<64 {
            capture(String(format: "halo-%02d", i))
        }
    }
}
