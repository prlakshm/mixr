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
        XCTAssertTrue(skipButton.exists && selectButton.exists, "empty project: step 1 offers Select, not Next")
        XCTAssertFalse(nextButton.exists)
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

    func testSelectPicksSongsThenContinuesAtStepTwo() {
        launch(fresh: true, tourDone: false)
        assertTourStep(1)
        selectButton.tap()
        pickDemoSongs(["Paper Suns"])
        waitForSongs(1)
        assertTourStep(2)
    }

    func testCancellingTheSelectPickerStaysOnStepOne() {
        launch(fresh: true, tourDone: false)
        assertTourStep(1)
        selectButton.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "document picker did not open")
        cancel.tap()
        assertTourStep(1)
        XCTAssertTrue(selectButton.waitForExistence(timeout: 3))
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

    // MARK: Spotlight behaviour

    /// The clip the tour spotlights: the first clip in the top lane.
    private var tourClip: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' clip'")).allElementsBoundByIndex
            .filter { $0.frame.width > 0 }
            .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            ?? app.buttons.matching(NSPredicate(format: "label CONTAINS ' clip'")).firstMatch
    }

    func testSpotlitControlsWorkButTheScrimBlocksTheRest() {
        launchSeededAtStepTwo()
        nextButton.tap()
        assertTourStep(3)
        let mute = app.buttons["Mute Night Signals"]
        tapPoint(mute.frame.midX, mute.frame.midY) // inside the spotlight
        XCTAssertEqual(mute.value as? String, "On", "the spotlit control really works")
        assertTourStep(3) // the tour waits for Next
        let play = app.buttons["Play"]
        tapPoint(play.frame.midX, play.frame.midY) // outside the spotlight
        XCTAssertFalse(app.buttons["Pause"].waitForExistence(timeout: 1), "the scrim blocks the rest of the editor")
    }

    func testSwipeOnStepTwoRevealsDeleteAndNextClosesIt() {
        launchSeededAtStepTwo()
        // Step 2 spotlights the top song row.
        let topTitle = DemoSongs.titles.map { songTitle($0) }
            .filter(\.exists)
            .min { $0.frame.minY < $1.frame.minY }
        guard let topTitle else { return XCTFail("no song rows") }
        topTitle.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2), "the swipe the finger shows reveals Delete")
        assertTourStep(2)
        nextButton.tap()
        assertTourStep(3)
        XCTAssertFalse(delete.waitForExistence(timeout: 1), "moving on closes the swiped row")
    }

    func testSwipingDeleteBackClosesItOnStepTwo() {
        launchSeededAtStepTwo()
        let topTitle = DemoSongs.titles.map { songTitle($0) }
            .filter(\.exists)
            .min { $0.frame.minY < $1.frame.minY }
        guard let topTitle else { return XCTFail("no song rows") }
        topTitle.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.swipeRight() // drag it back, as in Mail
        XCTAssertTrue(delete.waitForNonExistence(timeout: 2), "swiping back closes Delete")
        XCTAssertTrue(topTitle.exists, "and the song stays")
        assertTourStep(2)
    }

    func testTheTipCardNeverCoversTheLitToolbar() {
        launchSeededAtStepTwo()
        nextButton.tap(); nextButton.tap()
        assertTourStep(4)
        let clip = tourClip
        tapPoint(clip.frame.minX + 90, clip.frame.midY)
        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 2))
        sleep(1) // the spotlight glides onto the toolbar
        // Duplicate scrolls the copy into view and selects it; the clip the
        // card sits beside slides aside.
        tapPoint(duplicate.frame.midX, duplicate.frame.minY + 6)
        sleep(1)
        assertTourStep(4)
        let card = app.staticTexts["Tap a clip for tools"].frame.union(nextButton.frame)
        for tool in ["Split", "Speed", "Duplicate", "Volume", "Delete"] {
            let button = app.buttons[tool].firstMatch
            XCTAssertTrue(button.exists, "\(tool) shows")
            XCTAssertFalse(card.intersects(button.frame), "the tip card covers \(tool)")
        }
        capture("tour-step-4-after-duplicate")
    }

    func testTappingTheClipOnStepFourShowsItsToolbar() {
        launchSeededAtStepTwo()
        nextButton.tap(); nextButton.tap()
        assertTourStep(4)
        XCTAssertFalse(app.buttons["Split"].waitForExistence(timeout: 1), "step 4 waits for the tap")
        let clip = tourClip
        tapPoint(clip.frame.minX + 90, clip.frame.midY) // inside the spotlight
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 2), "the tap shows the clip toolbar")
        assertTourStep(4)
    }

    func testTheOpenedToolbarTakesTheSpotlightAndWorks() {
        launchSeededAtStepTwo()
        nextButton.tap(); nextButton.tap()
        assertTourStep(4)
        let clip = tourClip
        tapPoint(clip.frame.minX + 90, clip.frame.midY)
        let volume = app.buttons["Volume"]
        XCTAssertTrue(volume.waitForExistence(timeout: 2), "the tap shows the clip toolbar")
        sleep(1) // the spotlight glides onto the toolbar
        // Its icon sits above the clip: under the scrim until the
        // spotlight moved onto the toolbar.
        tapPoint(volume.frame.midX, volume.frame.minY + 6)
        XCTAssertTrue(app.descendants(matching: .any)["Clip volume"].waitForExistence(timeout: 2),
                      "the spotlit toolbar really works")
        assertTourStep(4) // the tip waits for Next
    }

    func testEffectsStepSelectsAClipAndRestoresSelection() {
        launchSeededAtStepTwo()
        nextButton.tap(); nextButton.tap(); nextButton.tap()
        assertTourStep(5)
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 2), "step 5 edits a selected clip")
        nextButton.tap()
        assertTourStep(6)
        XCTAssertFalse(app.buttons["Split"].waitForExistence(timeout: 1), "selection is restored after the effects step")
    }

    func testTappingSfxOnTheLastStepOpensTheMenuAndEndsTheTour() {
        launchSeededAtStepTwo()
        for step in 3...6 {
            nextButton.tap()
            assertTourStep(step)
        }
        let sfx = app.buttons["Sound Effects"]
        tapPoint(sfx.frame.midX, sfx.frame.midY) // inside the spotlight
        assertNoTour()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 2), "the sound effects menu is open")
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
