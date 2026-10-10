import XCTest

/// Native UI smoke tests for acceptance A-01.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(seenFirstHello: Bool, backTapSetup: String = "deferred") -> XCUIApplication {
        let app = XCUIApplication()
        // Overrides UserDefaults for this launch only.
        app.launchArguments += ["-hasSeenFirstHello", seenFirstHello ? "YES" : "NO", "-appearance", "system", "-inMemoryStore", "YES", "-backTapSetupStatus", backTapSetup]
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
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testThreeTabsAndHonestPlaceholders() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].exists)

        app.buttons["tab.memories"].tap()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        for _ in 0..<5 {
            if app.staticTexts["Microphone"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only while talking"].exists, "V1: the microphone is used only during a voice conversation")
    }

    @MainActor
    func testBackTapCardCanBeDeferredAndNeverShowsAsVerified() {
        let app = launch(seenFirstHello: true, backTapSetup: "notStarted")
        XCTAssertTrue(app.buttons["home.backTap.later"].waitForExistence(timeout: 5))
        for _ in 0..<4 {
            // A partially visible card can report hittable behind the pill bar;
            // bring the whole button above navigation before sending the tap.
            let later = app.buttons["home.backTap.later"]
            if later.isHittable && later.frame.maxY < app.buttons["tab.home"].frame.minY { break }
            app.swipeUp()
        }
        app.buttons["home.backTap.later"].tap()
        XCTAssertTrue(app.buttons["home.backTap.later"].waitForNonExistence(timeout: 5), app.debugDescription)

        app.buttons["tab.settings"].tap()
        let status = app.descendants(matching: .any)["settings.backTap.status"].firstMatch
        // The long Settings form lazily creates rows; scroll to the status rather than
        // treating an off-screen label as a product failure.
        for _ in 0..<8 {
            if status.exists && status.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.label.contains("Set up later"))
        XCTAssertFalse(status.label.localizedCaseInsensitiveContains("verified"))
    }

    @MainActor
    func testNoFakeListeningOrMicControls() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        for label in ["Listening…", "Tap to talk", "Record", "Mic"] {
            XCTAssertFalse(app.buttons[label].exists, label)
            XCTAssertFalse(app.staticTexts[label].exists, label)
        }
    }
}
