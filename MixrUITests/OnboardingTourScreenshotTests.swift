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
            capture("tour-step-\(step)")
        }
        XCTAssertTrue(finishButton.exists)
        XCTAssertFalse(skipButton.exists, "Skip is hidden on the last step")
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
