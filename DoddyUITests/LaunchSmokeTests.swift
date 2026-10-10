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
        // Since the voice work the microphone is used, but only inside a conversation the user starts.
        XCTAssertTrue(app.staticTexts["Only while talking"].exists)
    }

    @MainActor
    func testAskDoddyIsOffByDefaultAndSaysWhyWithoutAnyNetworkCall() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.buttons["home.ask"].waitForExistence(timeout: 5))
        app.buttons["home.ask"].tap()

        XCTAssertTrue(app.textFields["ask.input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ask.disclosure"].exists)
        XCTAssertTrue(app.staticTexts["Turn on Ask Doddy in Settings first. It sends your question to a server."].exists)
        // Nothing to send yet, so Send stays disabled.
        XCTAssertFalse(app.buttons["ask.send"].isEnabled)
    }

    @MainActor
    func testSettingsShowsAskDoddyOffUntilTheUserTurnsItOn() {
        let app = launch(seenFirstHello: true)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Ask Doddy (typed questions)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.assistantConsent"].exists)
        XCTAssertEqual(app.switches["settings.assistantConsent"].value as? String, "0")
        XCTAssertTrue(app.staticTexts["Off"].exists)
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
}
