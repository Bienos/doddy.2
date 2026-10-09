import XCTest

/// UI smoke tests (A-01 and the first-use flow). NOT RUN in the authoring environment (no
/// Xcode). Every launch uses an in-memory store, so each test starts as a fresh install.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(onboardingDone: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-appearance", "system", "-inMemoryStore", "YES"]
        if onboardingDone { app.launchArguments += ["-onboardingDone", "YES"] }
        app.launch()
        return app
    }

    @MainActor
    func testFirstLaunchOffersBackTapSetupThenIntroductionAndBothCanBeSkipped() {
        let app = launch(onboardingDone: false)
        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout: 5))
        app.buttons["setup.later"].tap()

        XCTAssertTrue(app.buttons["intro.begin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["intro.skip"].exists)
        app.buttons["intro.skip"].tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.greeting"].label, "A little less to carry.")
    }

    @MainActor
    func testWrittenGuideMovesOnTheUsersReportAndNeverClaimsVerification() {
        let app = launch(onboardingDone: false)
        app.buttons["setup.start"].tap()
        XCTAssertTrue(app.buttons["setup.shortcutDone"].waitForExistence(timeout: 5))
        app.buttons["setup.shortcutDone"].tap()

        // Jump to the page the user says they're on.
        XCTAssertTrue(app.buttons["setup.report.touch"].waitForExistence(timeout: 5))
        app.buttons["setup.report.touch"].tap()
        XCTAssertTrue(app.staticTexts["Find Back Tap"].waitForExistence(timeout: 5))
        app.buttons["setup.report.doubleTap"].tap()
        XCTAssertTrue(app.staticTexts["Choose your shortcut"].waitForExistence(timeout: 5))
        app.buttons["setup.next"].tap()

        XCTAssertTrue(app.buttons["setup.testSkip"].waitForExistence(timeout: 5))
        app.buttons["setup.testSkip"].tap()
        XCTAssertTrue(app.buttons["intro.skip"].waitForExistence(timeout: 5))
        app.buttons["intro.skip"].tap()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["You said it's set up"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Verified"].exists)
    }

    @MainActor
    func testIntroductionKeepsOnlyReviewedAnswers() {
        let app = launch(onboardingDone: false)
        app.buttons["setup.later"].tap()
        XCTAssertTrue(app.buttons["intro.begin"].waitForExistence(timeout: 5))
        app.buttons["intro.begin"].tap()

        let name = app.textFields["profile.field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ola")
        app.buttons["intro.next"].tap()
        XCTAssertTrue(app.buttons["Keep useful details"].waitForExistence(timeout: 5))
        app.buttons["Keep useful details"].tap()
        app.buttons["intro.review"].tap()

        // Removing an answer in the review means it is never stored.
        XCTAssertTrue(app.buttons["profile.save"].waitForExistence(timeout: 5))
        app.buttons["profile.remove.help"].tap()
        app.buttons["profile.save"].tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.greeting"].label, "Hi, Ola.")
        XCTAssertFalse(app.staticTexts["Useful help"].exists, "removed in the review, so not stored")
    }

    @MainActor
    func testThreeTabsAndHonestPlaceholders() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].exists)

        app.tabBars.buttons["Memories"].tap()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only while talking"].exists)
        XCTAssertTrue(app.staticTexts["Nothing saved. Doddy only keeps what you review and save."].exists)
    }

    @MainActor
    func testNoFakeListeningOrMicControls() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        for label in ["Listening…", "Tap to talk", "Record", "Mic"] {
            XCTAssertFalse(app.buttons[label].exists, label)
            XCTAssertFalse(app.staticTexts[label].exists, label)
        }
    }
}
