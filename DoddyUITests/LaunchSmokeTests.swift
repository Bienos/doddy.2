import XCTest

/// UI smoke tests for acceptance A-01. NOT RUN in the authoring environment (no Xcode).
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(seenFirstHello: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        // Overrides UserDefaults for this launch only.
        app.launchArguments += ["-hasSeenFirstHello", seenFirstHello ? "YES" : "NO", "-appearance", "system", "-inMemoryStore", "YES"]
        app.launch()
        return app
    }

    @MainActor
    func testFirstLaunchShowsHonestHelloWithStartAndSkip() {
        let app = launch(seenFirstHello: false)
        XCTAssertTrue(app.buttons["firstHello.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["firstHello.skip"].exists)
        XCTAssertTrue(app.staticTexts["Hey. I'm Doddy."].exists)
        app.buttons["firstHello.skip"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testThreeTabsAndHonestPlaceholders() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].exists)

        app.tabBars.buttons["Memories"].tap()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not used"].exists)
    }

    @MainActor
    func testNoFakeListeningOrMicControls() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        for label in ["Listening…", "Tap to talk", "Record", "Mic"] {
            XCTAssertFalse(app.buttons[label].exists, label)
            XCTAssertFalse(app.staticTexts[label].exists, label)
        }
    }

    @MainActor
    func testBackTapSetupOffersDirectLinksAndATapTest() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.buttons["home.backTap"].waitForExistence(timeout: 5))
        app.buttons["home.backTap"].tap()
        XCTAssertTrue(app.buttons["backTap.newShortcut"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["backTap.tryShortcut"].exists)
        XCTAssertTrue(app.buttons["backTap.openSettings"].exists)
        // Nothing claims Back Tap works until the user confirms a shortcut open during the test.
        XCTAssertFalse(app.buttons["backTap.confirm"].exists)
        app.swipeUp()
        app.buttons["backTap.startTest"].tap()
        XCTAssertTrue(app.buttons["Cancel test"].waitForExistence(timeout: 5))
    }
}
