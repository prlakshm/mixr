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

    /// The sound-effects library, both pages.
    func testCaptureSFXLibrary() {
        launch(fresh: true, tourDone: true, songs: true)
        tap(app.buttons["Sound Effects"])
        sleep(1)
        capture("sfx-library")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        capture("sfx-library-page2")
    }

    /// Waveforms at load (empty clips until the real peaks are read, never a
    /// generated shape) and on a sound-effect clip (its own audio file).
    func testCaptureRealWaveforms() {
        launch(fresh: true, tourDone: true, songs: true)
        capture("waveforms-at-load")
        sleep(2)
        capture("waveforms-ready")
        tap(app.buttons["Sound Effects"])
        tap(app.buttons["Riser, 4s"])
        sleep(1)
        capture("waveforms-sfx")
    }

    /// The clip toolbar on its own, for optical-alignment review.
    func testCaptureClipToolbar() {
        launch(fresh: true, tourDone: true, songs: true)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Night Signals clip'")).firstMatch)
        sleep(1)
        capture("clip-toolbar")
    }

    /// Speed editing: the toolbar morphs into the ×-field and the keypad
    /// opens with the preset-speed bar above it.
    func testCaptureSpeedEditor() {
        launch(fresh: true, tourDone: true, songs: true)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Night Signals clip'")).firstMatch)
        tap(app.buttons["Speed"])
        sleep(2)
        capture("speed-editor")
        app.textFields.firstMatch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "0.75")
        sleep(1)
        capture("speed-editor-075")
    }

    /// Device-feedback review: header, bottom margin, dial number, clip
    /// volume, Done, transition lengths, and the tour's step 4 tap.
    func testCaptureDeviceFeedback() {
        launch(fresh: true, tourDone: true, songs: true)
        sleep(1)
        capture("fb-01-editor")

        let clip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Night Signals clip'")).firstMatch
        tapPoint(clip.frame.minX + 120, clip.frame.midY)
        sleep(1)
        capture("fb-02-clip-toolbar")

        tap(app.buttons["Volume"])
        sleep(1)
        let volume = app.descendants(matching: .any)["Clip volume"]
        volume.swipeLeft()
        sleep(1)
        capture("fb-03-clip-volume")
        tap(app.buttons["Back"])
        sleep(1)

        tap(app.buttons["Reverb"])
        let level = app.descendants(matching: .any)["Reverb level"]
        _ = level.waitForExistence(timeout: 3)
        level.swipeRight()
        sleep(1)
        capture("fb-04-reverb-tray")
        tap(app.buttons["Reverb"])
        sleep(1)
        capture("fb-05-dial-number")

        tap(app.buttons["Speed"])
        sleep(2)
        capture("fb-06-speed-done")
        app.buttons["Done"].tap()
        sleep(1)

        // Leading transition grip of the selected clip.
        tapPoint(clip.frame.minX + 1, clip.frame.midY)
        sleep(1)
        if app.buttons["Crossfade"].waitForExistence(timeout: 2) {
            tap(app.buttons["Crossfade"])
            sleep(1)
            let eight = app.buttons["8 beats"]
            if eight.waitForExistence(timeout: 2) { eight.tap(); sleep(1) }
        }
        capture("fb-07-transition-lengths")
        app.terminate()

        // Tour step 4: tapping the clip puts its toolbar (with tail) there.
        launch(fresh: true, tourDone: false, songs: true)
        _ = app.buttons["Next"].waitForExistence(timeout: 5)
        app.buttons["Next"].tap(); sleep(1)
        app.buttons["Next"].tap(); sleep(1)
        app.buttons["Next"].tap(); sleep(1)
        capture("fb-08-tour-step4")
        let tourClip = app.buttons.matching(NSPredicate(format: "label CONTAINS ' clip'")).allElementsBoundByIndex
            .filter { $0.frame.width > 0 }
            .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        if let tourClip { tapPoint(tourClip.frame.minX + 140, tourClip.frame.midY) }
        sleep(1)
        capture("fb-09-tour-step4-tapped")
    }
}
