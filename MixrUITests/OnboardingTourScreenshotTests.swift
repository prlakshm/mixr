import XCTest

/// Captures the six onboarding steps the way a new user meets them:
/// a fresh install, step 1 on the empty editor, a real import through the
/// Files picker, then Next through steps 2–6.
/// Run with MIXR_SCREENSHOT_DIR set (Scripts/run_ui_tests.sh does) to save
/// `tour-step-N.png`.
final class OnboardingTourScreenshotTests: MixrUITestCase {
    func testCaptureAllTourSteps() {
        launch(fresh: true, tourDone: false)

        assertTourStep(1)
        settle()
        capture("tour-step-1")

        // Step 1's spotlight passes the tap to the real Import Songs button.
        footerImportButton.tap()
        pickDemoSongs()
        waitForSongs(DemoSongs.titles.count)

        assertTourStep(2)
        waitForAnalysis()
        settle()
        capture("tour-step-2")

        for step in 3...6 {
            nextButton.tap()
            assertTourStep(step)
            settle()
            if step == 4 {
                // Step 4 shows what the tap does: the clip's toolbar,
                // right where it was tapped.
                tapTourClip()
                settle()
            }
            capture("tour-step-\(step)")
        }
        XCTAssertTrue(finishButton.exists)
        XCTAssertFalse(skipButton.exists, "Skip is hidden on the last step")
    }

    /// Taps the spotlit clip (the first clip in the top lane), a third of
    /// the way into its visible part.
    private func tapTourClip() {
        let clips = app.buttons.matching(NSPredicate(format: "label CONTAINS ' clip'")).allElementsBoundByIndex
            .filter { $0.frame.width > 0 }
        guard let clip = clips.min(by: { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }) else {
            return XCTFail("no clip to tap")
        }
        let laneEnd = app.staticTexts["Controls"].frame.minX
        let visibleWidth = max(40, min(clip.frame.maxX, laneEnd) - clip.frame.minX)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: clip.frame.minX + visibleWidth / 3, dy: clip.frame.midY))
            .tap()
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 2), "the tap shows the clip toolbar")
    }

    /// Lets springs and the finger animation reach a representative frame.
    private func settle() { usleep(1_400_000) }

    /// Waits until every demo song shows a detected BPM (not "--").
    private func waitForAnalysis(timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        let bpm = NSPredicate(format: "label MATCHES '^[0-9]+ BPM$'")
        while Date() < deadline {
            if app.staticTexts.matching(bpm).count >= DemoSongs.titles.count { return }
            usleep(300_000)
        }
    }
}
