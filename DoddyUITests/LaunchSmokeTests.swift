import XCTest

/// UI smoke tests (A-01 and the first-use flow). NOT RUN in the authoring environment (no
/// Xcode). Every launch uses an in-memory store, so each test starts as a fresh install.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(onboardingDone: Bool, backTapSetup: String = "deferred") -> XCUIApplication {
        let app = XCUIApplication()
        // Overrides UserDefaults for this launch only.
        app.launchArguments += ["-appearance", "system", "-inMemoryStore", "YES", "-backTapSetupStatus", backTapSetup]
        if onboardingDone { app.launchArguments += ["-onboardingDone", "YES"] }
        app.launch()
        return app
    }

    @MainActor
    func testFirstLaunchOffersIntroductionThatCanBeSkipped() {
        let app = launch(onboardingDone: false)
        XCTAssertTrue(app.buttons["intro.begin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["intro.skip"].exists)
        app.buttons["intro.skip"].tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.greeting"].label, "A little less to carry.")
    }

    @MainActor
    func testIntroductionKeepsOnlyReviewedAnswers() {
        let app = launch(onboardingDone: false)
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
        XCTAssertTrue(app.staticTexts["Nothing saved. Doddy only keeps what you review and save."].waitForExistence(timeout: 5))
        // Privacy sits below About you and Your memories.
        let microphone = app.staticTexts["Microphone"]
        for _ in 0..<4 where !microphone.exists { app.swipeUp() }
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only while talking"].exists)
    }

    @MainActor
    func testBackTapCardCanBeDeferredAndNeverShowsAsVerified() {
        let app = launch(onboardingDone: true, backTapSetup: "notStarted")
        XCTAssertTrue(app.buttons["home.backTap.later"].waitForExistence(timeout: 5))
        app.buttons["home.backTap.later"].tap()
        XCTAssertFalse(app.buttons["home.backTap.later"].exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Set up later"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'verified'")).firstMatch.exists)
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
