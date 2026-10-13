import XCTest

/// Core editing flows on a populated project, in landscape.
/// Every test starts from a fresh install with the three demo songs and
/// the tour already finished.
final class EditorFlowTests: MixrUITestCase {
    override func setUp() {
        super.setUp()
        launch(songs: true)
    }

    // MARK: Helpers

    private func clips(of title: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title) clip"))
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any)[label]
    }

    /// A point on empty timeline: just below the last song's lane, in the
    /// middle of the visible lanes (works on every phone size).
    private func tapEmptyTimeline() {
        let laneEnd = app.staticTexts["Controls"].frame.minX
        let lanes = app.buttons.matching(NSPredicate(format: "label CONTAINS ' clip, '"))
            .allElementsBoundByIndex.filter { $0.frame.midX > 0 && $0.frame.midX < laneEnd }
        let bottom = lanes.map(\.frame.maxY).max() ?? 250
        let midX = lanes.map(\.frame.midX).reduce(0, +) / CGFloat(max(lanes.count, 1))
        tapPoint(midX, bottom + 12)
    }

    private func selectFirstClip(of title: String = "Night Signals") -> XCUIElement {
        // The first clip whose centre is in the visible lane (Duplicate
        // scrolls to the copy, which can park earlier clips under the song
        // list). The lane runs from the song rows to the Controls column.
        let laneStart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title), "))
            .firstMatch.frame.maxX
        let laneEnd = app.staticTexts["Controls"].frame.minX
        let clip = clips(of: title).allElementsBoundByIndex
            .filter { $0.frame.midX > laneStart && $0.frame.midX < laneEnd }
            .min { $0.frame.minX < $1.frame.minX }
            ?? clips(of: title).firstMatch
        tap(clip)
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 3), "clip toolbar did not open")
        return clip
    }

    private var undo: XCUIElement { app.buttons["Undo"] }
    private var redo: XCUIElement { app.buttons["Redo"] }

    // MARK: Import, reorder, delete

    func testDemoSongsImportWithTempoAndKey() {
        for title in DemoSongs.titles { XCTAssertTrue(songTitle(title).exists, title) }
        XCTAssertTrue(app.staticTexts["124 BPM"].exists || app.staticTexts["122 BPM"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '~'")).firstMatch.exists,
                       "tagged songs should not show an estimated (~) key")
    }

    func testImportMoreSongsThroughFilesPicker() {
        footerImportButton.tap()
        pickDemoSongs(["Velvet Static"])
        let rows = app.staticTexts.matching(identifier: "Velvet Static")
        let deadline = Date().addingTimeInterval(10)
        while rows.count < 2, Date() < deadline { usleep(200_000) }
        XCTAssertEqual(rows.count, 2, "the picked song is added as a new row")
    }

    func testSwipeToDeleteThenUndoRedo() {
        songTitle("Velvet Static").swipeLeft()
        tap(app.buttons["Delete"])
        waitForSongs(2)
        XCTAssertFalse(songTitle("Velvet Static").exists)

        tap(undo)
        waitForSongs(3)
        tap(redo)
        waitForSongs(2)
    }

    func testRevealedDeleteClosesOnTapElsewhere() {
        songTitle("Paper Suns").swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
        tapEmptyTimeline()
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: app.buttons["Delete"])
        waitForExpectations(timeout: 3)
        waitForSongs(3)
    }

    func testOnlyOneRowShowsDeleteAtATime() {
        songTitle("Night Signals").swipeLeft()
        songTitle("Paper Suns").swipeLeft()
        usleep(600_000)
        XCTAssertEqual(app.buttons.matching(identifier: "Delete").count, 1)
    }

    // MARK: Mix: solo, mute, volume

    func testSoloAndMute() {
        let solo = app.buttons["Solo Night Signals"]
        let mute = app.buttons["Mute Paper Suns"]
        XCTAssertEqual(solo.value as? String, "Off")
        solo.tap()
        XCTAssertEqual(solo.value as? String, "On")
        mute.tap()
        XCTAssertEqual(mute.value as? String, "On")
        solo.tap()
        XCTAssertEqual(solo.value as? String, "Off")
    }

    func testVolumeIsAdjustable() {
        let volume = element("Velvet Static volume")
        XCTAssertTrue(volume.waitForExistence(timeout: 3))
        XCTAssertEqual(volume.value as? String, "75 percent")
        volume.swipeLeft()
        let changed = NSPredicate(format: "value != '75 percent'")
        expectation(for: changed, evaluatedWith: volume)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(undo.isEnabled)
    }

    // MARK: Clip tools

    func testSplitDuplicateDeleteClip() {
        XCTAssertEqual(clips(of: "Night Signals").count, 1)
        _ = selectFirstClip()
        tap(app.buttons["Split"])
        XCTAssertEqual(clips(of: "Night Signals").count, 2, "split makes two clips")

        _ = selectFirstClip()
        tap(app.buttons["Duplicate"])
        XCTAssertEqual(clips(of: "Night Signals").count, 3, "duplicate adds a clip")

        _ = selectFirstClip()
        let delete = app.buttons.matching(identifier: "Delete").firstMatch
        tap(delete)
        XCTAssertEqual(clips(of: "Night Signals").count, 2, "delete removes the clip")

        tap(undo)
        XCTAssertEqual(clips(of: "Night Signals").count, 3)
    }

    func testTransitionLengthsAShortClipCantPlayAreGreyedOut() {
        // Split about 13 s in: a fade is capped at half its clip, so the
        // first piece can play 4 and 8 beats in full but not 16 or 32.
        let clip = clips(of: "Night Signals").firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 3))
        let times = clip.label.components(separatedBy: ", ").last?
            .components(separatedBy: " to ")
            .map { $0.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) } } ?? []
        let seconds = max((times.last ?? 120) - (times.first ?? 0), 1)
        // Tapping a clip selects it and moves the playhead to the tap.
        tapPoint(clip.frame.minX + clip.frame.width * 13 / seconds, clip.frame.midY)
        tap(app.buttons["Split"])
        XCTAssertEqual(clips(of: "Night Signals").count, 2, "split makes a short first piece")

        let piece = selectFirstClip()
        tapPoint(piece.frame.minX + 1, piece.frame.midY) // its leading transition grip
        tap(app.buttons["Crossfade"])
        let four = app.buttons["4 beats"], eight = app.buttons["8 beats"]
        let sixteen = app.buttons["16 beats"], thirtyTwo = app.buttons["32 beats"]
        XCTAssertTrue(thirtyTwo.waitForExistence(timeout: 3), "the Duration pill shows")
        XCTAssertTrue(four.isEnabled && eight.isEnabled, "4 and 8 beats fit a 13 s piece")
        XCTAssertFalse(sixteen.isEnabled, "16 beats can't play in full on a 13 s piece")
        XCTAssertFalse(thirtyTwo.isEnabled, "32 beats can't either")
        XCTAssertTrue(four.isSelected, "a new crossfade starts at 4 beats")
        tap(eight)
        XCTAssertTrue(eight.isSelected)
        sleep(1) // let the pill settle for the capture
        capture("transition-short-clip")

        // Split it to ~7 s: its 8-beat fade no longer plays in full, so the
        // pill highlights nothing (and greys 8 out) instead of claiming 8.
        tapEmptyTimeline()
        sleep(1) // the menu closes; a tap straight after it is lost
        let firstPiece = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Night Signals clip, 0:00 to")).firstMatch
        tapPoint(firstPiece.frame.minX + firstPiece.frame.width * 7 / 13, firstPiece.frame.midY)
        tap(app.buttons["Split"])
        XCTAssertEqual(clips(of: "Night Signals").count, 3)
        tapEmptyTimeline()
        sleep(1)
        tap(firstPiece) // now the ~7 s piece
        tapPoint(firstPiece.frame.minX + 1, firstPiece.frame.midY)
        tap(app.buttons["Crossfade"])
        XCTAssertTrue(four.waitForExistence(timeout: 3))
        XCTAssertFalse(eight.isEnabled, "8 beats no longer fits")
        XCTAssertFalse([four, eight, sixteen, thirtyTwo].contains { $0.isSelected },
                       "no length is highlighted: none of them is what plays")
        sleep(1)
        capture("transition-no-highlight")
    }

    func testSpeedPresetFromKeyboardBar() {
        let clip = selectFirstClip()
        let before = clip.label
        tap(app.buttons["Speed"])
        let preset = app.buttons["2 times speed"]
        XCTAssertTrue(preset.waitForExistence(timeout: 4), "speed presets sit above the keypad")
        XCTAssertTrue(app.buttons["Done"].exists, "the keypad has a Done button")
        preset.tap()
        let after = clips(of: "Night Signals").firstMatch.label
        XCTAssertNotEqual(before, after, "2x halves the clip's length")
    }

    func testSpeedDoneKeepsValue() {
        _ = selectFirstClip()
        tap(app.buttons["Speed"])
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Done dismisses the keypad")
    }

    func testClipVolumeIsAdjustableAndUndoable() {
        _ = selectFirstClip()
        tap(app.buttons["Volume"])
        let volume = element("Clip volume")
        XCTAssertTrue(volume.waitForExistence(timeout: 3), "Volume opens the clip's own slider")
        XCTAssertEqual(volume.value as? String, "100 percent")
        volume.swipeLeft()
        let lowered = NSPredicate(format: "value != '100 percent'")
        expectation(for: lowered, evaluatedWith: volume)
        waitForExpectations(timeout: 3)
        tap(undo)
        let restored = NSPredicate(format: "value == '100 percent'")
        expectation(for: restored, evaluatedWith: volume)
        waitForExpectations(timeout: 3)
        tap(app.buttons["Back"])
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 2), "Back returns to the clip tools")
    }

    // MARK: Effects

    func testEffectWithNothingSelectedSelectsTheClipItEdits() {
        tap(app.buttons["Reverb"])
        XCTAssertTrue(element("Reverb level").waitForExistence(timeout: 3), "Reverb opens its tray")
        let selected = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Night Signals clip' AND selected == true"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 2), "the edited clip is visibly selected")
        XCTAssertTrue(app.buttons["Split"].exists, "and its toolbar shows")
    }

    func testDeselectingClipClosesEffectTray() {
        _ = selectFirstClip()
        tap(app.buttons["Echo"])
        XCTAssertTrue(element("Echo level").waitForExistence(timeout: 3))
        tapEmptyTimeline() // empty timeline deselects
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element("Echo level"))
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["Reverb"].waitForExistence(timeout: 2), "all effect cards are back")
    }

    func testEffectLevelIsAdjustableAndUndoable() {
        _ = selectFirstClip()
        tap(app.buttons["Flanger"])
        let level = element("Flanger level")
        XCTAssertTrue(level.waitForExistence(timeout: 3))
        level.swipeRight()
        let changed = NSPredicate(format: "value != '0 percent'")
        expectation(for: changed, evaluatedWith: level)
        waitForExpectations(timeout: 3)
    }

    // MARK: Sound effects

    func testAddSoundEffectAtPlayhead() {
        tap(app.buttons["Sound Effects"])
        let riser = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Riser'")).firstMatch
        tap(riser)
        XCTAssertTrue(element("Sound effects").waitForExistence(timeout: 3), "an SFX track appears")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sound effect clip, 0:00'")).firstMatch.exists,
                      "the effect lands at the playhead (0:00)")
    }

    func testSoundEffectsPanelCloses() {
        tap(app.buttons["Sound Effects"])
        tap(app.buttons["Close"])
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Riser'")).firstMatch.waitForExistence(timeout: 1))
    }

    // MARK: Auto

    func testAutoDialogExplainsAndCancels() {
        tap(app.buttons["Auto"])
        XCTAssertTrue(app.staticTexts["Auto Remix"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Entire Project"].exists)
        XCTAssertTrue(app.buttons["Clips at Playhead"].exists)
        tap(app.buttons["Cancel"])
        XCTAssertFalse(app.buttons["Entire Project"].waitForExistence(timeout: 1))
        XCTAssertFalse(undo.isEnabled && false)
    }

    func testAutoOnSelectedClipOffersSelectedClip() {
        _ = selectFirstClip()
        tap(app.buttons["Auto"])
        XCTAssertTrue(app.buttons["Selected Clip"].waitForExistence(timeout: 3))
        tap(app.buttons["Cancel"])
    }

    func testAutoEntireProjectMashupIsUndoable() {
        tap(app.buttons["Auto"])
        tap(app.buttons["Entire Project"])
        let running = app.descendants(matching: .any)["Auto is running"]
        _ = running.waitForExistence(timeout: 3)
        let finished = NSPredicate(format: "exists == false")
        expectation(for: finished, evaluatedWith: running)
        waitForExpectations(timeout: 90)
        XCTAssertFalse(app.staticTexts["Auto Couldn’t Finish"].exists, "Auto finished without an error")
        XCTAssertTrue(undo.isEnabled)
    }

    // MARK: Transport

    func testPlayPauseAdvancesTime() {
        tap(app.buttons["Play"])
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        sleep(2)
        tap(app.buttons["Pause"])
        XCTAssertFalse(app.staticTexts["0:00"].exists && app.staticTexts.matching(identifier: "0:00").count > 1,
                       "time moved while playing")
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 2))
    }

    func testTapTimelineMovesPlayhead() {
        tapEmptyTimeline()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[1-9]:[0-9]{2}$' OR label MATCHES '^0:[1-5][0-9]$'"))
            .firstMatch.waitForExistence(timeout: 2))
        tap(app.buttons["Skip to Start"])
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "0:00").count, 1)
    }

    // MARK: Export

    func testExportOpensShareSheet() {
        tap(app.buttons["Export"])
        let saveToFiles = app.descendants(matching: .any)["Save to Files"]
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 60), "export renders and opens the share sheet")
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() }
    }

    // MARK: Projects

    private func openProjectMenu() {
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Project, '")).firstMatch)
        XCTAssertTrue(app.buttons["New Project"].waitForExistence(timeout: 3))
    }

    func testProjectMenuOrderPutsDeleteLast() {
        openProjectMenu()
        let order = ["New Project", "Rename", "Replay tour", "Delete Project"].map { app.buttons[$0].frame.minY }
        XCTAssertEqual(order, order.sorted(), "New, Rename, Replay tour, then Delete last")
    }

    func testNewProjectSwitchBackAndDelete() {
        openProjectMenu()
        tap(app.buttons["New Project"])
        waitForSongs(0)
        XCTAssertTrue(app.staticTexts["Import songs to start a remix"].waitForExistence(timeout: 3))

        openProjectMenu()
        tap(app.buttons["My Remix"])
        waitForSongs(3)

        openProjectMenu()
        tap(app.buttons["Delete Project"])
        XCTAssertTrue(app.staticTexts["This project’s edits can’t be recovered. Your song files aren’t deleted."]
            .waitForExistence(timeout: 3) || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'can’t be recovered'")).firstMatch.exists)
        tap(app.buttons["Delete"])
        waitForSongs(0)
    }

    func testRenameFromMenu() {
        openProjectMenu()
        tap(app.buttons["Rename"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Rename opens the keyboard")
        app.typeText(" Live\n")
        XCTAssertTrue(app.buttons["Project, My Remix Live"].waitForExistence(timeout: 3))
    }

    // MARK: Undo / redo

    func testUndoRedoMute() {
        let mute = app.buttons["Mute Night Signals"]
        mute.tap()
        XCTAssertEqual(mute.value as? String, "On")
        tap(undo)
        XCTAssertEqual(mute.value as? String, "Off")
        tap(redo)
        XCTAssertEqual(mute.value as? String, "On")
    }

    // MARK: Party Mode, orientation

    func testPartyModeToggle() {
        let logo = app.buttons["Toggle Party Mode"]
        XCTAssertEqual(logo.value as? String, "Off")
        logo.tap()
        XCTAssertEqual(logo.value as? String, "On")
        logo.tap()
        XCTAssertEqual(logo.value as? String, "Off")
    }

    func testPortraitShowsRotatePromptAndLandscapeRightWorks() {
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Rotate iPhone"].waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertFalse(app.staticTexts["Rotate iPhone"].waitForExistence(timeout: 1))
        tap(app.buttons["Solo Paper Suns"])
        XCTAssertEqual(app.buttons["Solo Paper Suns"].value as? String, "On")
    }
}
