import XCTest

/// The first-launch tour, end to end, in landscape.
final class OnboardingTourFlowTests: MixrUITestCase {
    /// Fresh install with songs already in the project: the tour opens on
    /// step 1 (Import Songs); Next moves to step 2.
    private func launchSeededAtStepTwo() {
        launch(fresh: true, tourDone: false, songs: true)
        assertTourStep(1)
        nextButton.tap()
        assertTourStep(2)
    }

    // MARK: First launch

    func testFirstLaunchShowsOnlyStepOne() {
        launch(fresh: true, tourDone: false)
        assertTourStep(1)
        XCTAssertTrue(skipButton.exists && nextButton.exists)
        for step in 2...6 {
            XCTAssertFalse(app.staticTexts["Step \(step) of 6"].exists, "no flash of step \(step)")
        }
    }

    func testImportFromStepOneContinuesAtStepTwo() {
        launch(fresh: true, tourDone: false)
        assertTourStep(1)
        footerImportButton.tap()
        pickDemoSongs()
        waitForSongs(3)
        assertTourStep(2)
    }

    func testNextWithoutImportingWaitsThenResumes() {
        launch(fresh: true, tourDone: false)
        assertTourStep(1)
        nextButton.tap()
        assertNoTour()
        footerImportButton.tap()
        pickDemoSongs(["Paper Suns"])
        waitForSongs(1)
        assertTourStep(2)
    }

    func testWalkAllStepsAndFinish() {
        launchSeededAtStepTwo()
        for step in 3...6 {
            nextButton.tap()
            assertTourStep(step)
        }
        XCTAssertFalse(skipButton.exists, "no Skip on the last step")
        finishButton.tap()
        assertNoTour()
        relaunch()
        assertNoTour()
    }

    // MARK: Skip

    func testSkipOnEveryStepEndsTheTourForGood() {
        for step in 1...5 {
            if step == 1 {
                launch(fresh: true, tourDone: false)
                assertTourStep(1)
            } else {
                launchSeededAtStepTwo()
                for s in stride(from: 3, through: step, by: 1) {
                    nextButton.tap()
                    assertTourStep(s)
                }
            }
            skipButton.tap()
            assertNoTour()
            relaunch()
            assertNoTour()
            app.terminate()
        }
    }

    func testReplayFromProjectMenu() {
        launch(fresh: true, tourDone: true, songs: true)
        assertNoTour()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Project, '")).firstMatch)
        tap(app.buttons["Replay tour"])
        assertTourStep(1)
        nextButton.tap()
        assertTourStep(2)
    }

    // MARK: Persistence

    func testRelaunchKeepsTheCurrentStep() {
        launchSeededAtStepTwo()
        nextButton.tap()
        nextButton.tap()
        assertTourStep(4)
        relaunch()
        assertTourStep(4)
        nextButton.tap()
        assertTourStep(5)
    }

    func testRelaunchWhileWaitingForFirstSong() {
        launch(fresh: true, tourDone: false)
        assertTourStep(1)
        nextButton.tap()
        assertNoTour()
        relaunch()
        assertNoTour()
        footerImportButton.tap()
        pickDemoSongs(["Night Signals"])
        waitForSongs(1)
        assertTourStep(2)
    }

    // MARK: Spotlight behaviour

    func testScrimBlocksTheEditorOnSongSteps() {
        launchSeededAtStepTwo()
        nextButton.tap()
        assertTourStep(3)
        let mute = app.buttons["Mute Night Signals"]
        XCTAssertFalse(mute.isHittable, "the scrim covers the editor")
        tapPoint(mute.frame.midX, mute.frame.midY) // a real tap, inside the spotlight
        XCTAssertEqual(mute.value as? String, "Off", "the tour does not edit the mix by accident")
    }

    func testClipStepsShowTheToolbarAndRestoreSelection() {
        launchSeededAtStepTwo()
        nextButton.tap(); nextButton.tap()
        assertTourStep(4)
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 2), "step 4 shows the real clip toolbar")
        nextButton.tap()
        assertTourStep(5)
        nextButton.tap()
        assertTourStep(6)
        XCTAssertFalse(app.buttons["Split"].waitForExistence(timeout: 1), "selection is restored after the clip steps")
    }

    func testRotatingToPortraitHidesAndRestoresTheStep() {
        launchSeededAtStepTwo()
        nextButton.tap()
        assertTourStep(3)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Rotate iPhone"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Step 3 of 6"].exists, "tour hidden behind the rotate prompt")
        XCUIDevice.shared.orientation = .landscapeRight
        assertTourStep(3)
    }
}
