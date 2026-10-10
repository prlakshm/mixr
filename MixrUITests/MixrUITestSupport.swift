import XCTest

/// Shared launch, import and capture helpers for the Mixr UI tests.
///
/// Demo songs are copyright-free and synthesized by
/// `Scripts/generate_demo_songs.py`. `Scripts/run_ui_tests.sh` generates them,
/// stages them in the simulator's Files app ("On My iPhone › Mixr Demo") for
/// picker imports, and passes the host folder for direct seeding.
enum DemoSongs {
    static let titles = ["Night Signals", "Velvet Static", "Paper Suns"]
    static let folderName = "Mixr Demo"

    /// Host folder with the generated .m4a files.
    static var hostFolder: String {
        if let dir = ProcessInfo.processInfo.environment["MIXR_DEMO_SONGS_DIR"], !dir.isEmpty {
            return dir
        }
        // Fallback for Xcode runs: <repo>/output/demo-songs, from this file's path.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("output/demo-songs").path
    }
}

class MixrUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .landscapeLeft
        super.tearDown()
    }

    /// Launches the app.
    /// - fresh: wipe projects and tour progress first (a first install).
    /// - tourDone: mark the onboarding tour finished.
    /// - songs: seed the empty project with the demo songs.
    func launch(fresh: Bool = true, tourDone: Bool = true, songs: Bool = false,
                orientation: UIDeviceOrientation = .landscapeLeft, extra: [String] = []) {
        var args: [String] = []
        if fresh { args.append("-MixrUITestReset") }
        if tourDone { args.append("-MixrUITestTourDone") }
        if songs { args += ["-MixrUITestSongs", DemoSongs.hostFolder] }
        app.launchArguments = args + extra
        XCUIDevice.shared.orientation = orientation
        app.launch()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 10), "editor did not load")
        if songs { waitForSongs(DemoSongs.titles.count) }
    }

    /// Relaunches without wiping anything (persistence checks).
    func relaunch(extra: [String] = []) {
        app.terminate()
        launch(fresh: false, tourDone: false, extra: extra)
    }

    // MARK: Queries

    var tourCard: XCUIElement { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step '")).firstMatch }
    var nextButton: XCUIElement { app.buttons["Next"] }
    var skipButton: XCUIElement { app.buttons["Skip"] }
    var finishButton: XCUIElement { app.buttons["Start mixing"] }

    /// The footer Import Songs button (the empty-state CTA shares the label).
    var footerImportButton: XCUIElement {
        let all = app.buttons.matching(identifier: "Import Songs").allElementsBoundByIndex
        return all.max { $0.frame.minY < $1.frame.minY } ?? app.buttons["Import Songs"]
    }

    func songTitle(_ title: String) -> XCUIElement { app.staticTexts[title] }

    func songRowCount() -> Int {
        DemoSongs.titles.filter { app.staticTexts[$0].exists }.count
    }

    func waitForSongs(_ count: Int, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if songRowCount() == count { return }
            usleep(200_000)
        }
        XCTFail("expected \(count) songs, saw \(songRowCount())", file: file, line: line)
    }

    func assertTourStep(_ step: Int, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["Step \(step) of 6"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "tour step \(step) not shown", file: file, line: line)
    }

    func assertNoTour(after seconds: TimeInterval = 1.5, file: StaticString = #filePath, line: UInt = #line) {
        let gone = NSPredicate(format: "exists == false")
        let e = expectation(for: gone, evaluatedWith: tourCard)
        wait(for: [e], timeout: seconds + 3)
        XCTAssertFalse(tourCard.exists, "tour should be hidden", file: file, line: line)
    }

    /// Waits until `element` exists and is hittable, then taps it.
    func tap(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)", file: file, line: line)
        element.tap()
    }

    /// Taps a point in the app window (points, landscape coordinates).
    func tapPoint(_ x: CGFloat, _ y: CGFloat) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    // MARK: Import through the real Files picker

    /// From an open document picker: Browse › On My iPhone › Mixr Demo,
    /// select the given songs (all by default) and Open.
    func pickDemoSongs(_ titles: [String] = DemoSongs.titles, file: StaticString = #filePath, line: UInt = #line) {
        let browse = app.tabBars.buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10), "document picker did not open", file: file, line: line)
        browse.tap()
        // Browse may open at the root list or inside the last location.
        let onMyPhone = app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if !app.staticTexts[DemoSongs.folderName].waitForExistence(timeout: 2) {
            if !onMyPhone.waitForExistence(timeout: 3) {
                // Inside a folder: go back to the Browse root.
                browse.tap()
            }
            tap(app.staticTexts["On My iPhone"], timeout: 5, file: file, line: line)
        }
        tap(app.staticTexts[DemoSongs.folderName], timeout: 5, file: file, line: line)
        for title in titles {
            let cell = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@", title)).firstMatch
            tap(cell, timeout: 5, file: file, line: line)
        }
        let open = app.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    // MARK: Screenshots

    /// Saves a landscape PNG of the screen to $MIXR_SCREENSHOT_DIR (if set)
    /// and attaches it to the test result.
    @discardableResult
    func capture(_ name: String) -> XCUIScreenshot {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["MIXR_SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return shot
    }
}
