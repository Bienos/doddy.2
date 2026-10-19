import XCTest

/// Doddy's pictures in the app (ADR-299 to ADR-331), checked through the UI-test markers
/// (`-doddyArtMarkers YES`, ADR-336): each picture is then an element named for its pose.
/// NOT RUN in the authoring environment (no Xcode). In-memory store: each test is a fresh install.
final class DoddyArtTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(hideArt: Bool = false, pauseAll: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "YES", "-onboardingDone", "YES", "-backTapSetupStatus", "deferred",
                               "-appearance", "light", "-openingScene", "NO", "-listenOnOpen", "NO",
                               "-doddyArtMarkers", "YES", "-hideCharacterArt", hideArt ? "YES" : "NO"]
        if pauseAll { app.launchArguments += ["-connections.pauseAll", "YES"] }
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    private func marker(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        app.reveal(element)
    }

    /// Find with no match shows the shrug (ADR-299); "Hide character artwork" removes it.
    @MainActor
    func testNoMatchShrugsAndHidingTheArtRemovesIt() {
        for hide in [false, true] {
            let app = launch(hideArt: hide)
            app.buttons["home.find"].tap()
            let query = app.textFields["memories.query"]
            XCTAssertTrue(query.waitForExistence(timeout: 5))
            query.tap(); query.typeText("zzqx nothing like this\n")
            XCTAssertTrue(app.staticTexts["memories.noMatch"].waitForExistence(timeout: 6))
            // Motion v2 (MV3, Q4): the one Doddy comes out from behind the page and shrugs on
            // Find's spot, so the shrug arrives after his hop.
            if hide {
                XCTAssertFalse(marker("doddy.pose.shrug", in: app).exists, "hide artwork: \(hide)")
            } else {
                XCTAssertTrue(marker("doddy.pose.shrug", in: app).waitForExistence(timeout: 5), "hide artwork: \(hide)")
            }
            app.terminate()
        }
    }

    /// A save that fails shows no celebration: no pop (ADR-313).
    @MainActor
    func testAFailedSaveNeverPops() {
        let app = launch()
        app.buttons["home.save"].tap()
        XCTAssertTrue(app.buttons["capture.save"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["capture.save"], app: app)
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(marker("doddy.motion.pop", in: app).exists)
        XCTAssertFalse(app.staticTexts["capture.saved"].exists)
    }

    /// No lists yet: Doddy waits, cross-legged (ADR-313).
    @MainActor
    func testEmptyListsShowDoddyWaiting() {
        let app = launch()
        app.buttons["tab.memories"].tap()
        let picker = app.segmentedControls["memories.notesOrLists"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Lists"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lists.empty"].waitForExistence(timeout: 5))
        // Motion v2 (MV3): the one Doddy hops to the Lists spot and sits there.
        XCTAssertTrue(marker("doddy.pose.crosslegged", in: app).waitForExistence(timeout: 5))
    }

    /// Pause all connections: Doddy lies low beside the explanation, only while paused (ADR-323).
    @MainActor
    func testPauseAllShowsDoddyLyingLowOnlyWhilePaused() {
        for paused in [true, false] {
            let app = launch(pauseAll: paused)
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.pauseAll"]
            // A lazy Form row: it exists only once scrolled to.
            XCTAssertTrue(app.reveal(toggle))
            // Doddy sits in the section's footer, beside its text. Step until that text is on screen:
            // a swipeUp flings an unknown distance and the lazy Form drops a footer it has passed.
            let footer = app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@", paused ? "Paused: Doddy" : "Each one starts off. Turning one on")).firstMatch
            XCTAssertTrue(app.reveal(footer))
            XCTAssertEqual(marker("doddy.pose.sneaky_crouch", in: app).exists, paused, "paused: \(paused)")
            app.terminate()
        }
    }

    /// What Doddy did, empty: Doddy waits, cross-legged (ADR-313).
    @MainActor
    func testEmptyActivityShowsDoddyWaiting() {
        let app = launch()
        app.buttons["tab.settings"].tap()
        let row = app.buttons["settings.activity"]
        XCTAssertTrue(app.reveal(row))
        row.tap()
        XCTAssertTrue(app.navigationBars["What Doddy did"].waitForExistence(timeout: 5))
        XCTAssertTrue(marker("doddy.pose.crosslegged", in: app).waitForExistence(timeout: 5))
    }
}
