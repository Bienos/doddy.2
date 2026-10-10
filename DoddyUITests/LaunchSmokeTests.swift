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

    /// Constitution DOD-07/08 simulation flow. NOT RUN in the authoring environment (no Xcode).
    @MainActor
    func testSimulatedApprovalFlowSaysSimulationAndNeverClaimsUnconfirmedSuccess() {
        let app = launch(seenFirstHello: true)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        let link = app.buttons["settings.actionDemo"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        link.tap()

        XCTAssertTrue(app.descendants(matching: .any)["actions.banner"].waitForExistence(timeout: 5))
        // The demo loads saved actions first; a fresh in-memory launch has none.
        XCTAssertTrue(app.buttons["actions.draftSample"].waitForExistence(timeout: 5))
        app.buttons["actions.draftSample"].tap()
        let status = app.staticTexts["actions.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Needs approval")

        // Default simulated result: delivered.
        app.buttons["actions.approve"].tap()
        XCTAssertTrue(app.staticTexts["Confirmed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["actions.summary"].label.contains("Nothing actually left this iPhone"))

        // No answer: shown as "Couldn't confirm", then reconciled without re-sending.
        app.buttons["actions.startOver"].tap()
        app.buttons["actions.draftSample"].tap()
        XCTAssertTrue(app.buttons["actions.approve"].waitForExistence(timeout: 5))
        app.buttons["actions.outcome"].tap()
        app.buttons["No answer (later found delivered)"].tap()
        app.buttons["actions.approve"].tap()
        XCTAssertTrue(app.staticTexts["Couldn't confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Confirmed"].exists)
        app.buttons["actions.checkStatus"].tap()
        XCTAssertTrue(app.staticTexts["Confirmed"].waitForExistence(timeout: 5))
    }
}
