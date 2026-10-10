import XCTest

/// UI smoke tests (A-01 and the first-use flow). NOT RUN in the authoring environment (no
/// Xcode). Every launch uses an in-memory store, so each test starts as a fresh install.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(onboardingDone: Bool, backTapSetup: String = "deferred", pauseAll: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // Overrides UserDefaults for this launch only.
        app.launchArguments += ["-appearance", "system", "-inMemoryStore", "YES", "-backTapSetupStatus", backTapSetup]
        if onboardingDone { app.launchArguments += ["-onboardingDone", "YES"] }
        if pauseAll { app.launchArguments += ["-connections.pauseAll", "YES"] }
        app.launch()
        return app
    }

    @MainActor
    func testFirstLaunchOffersIntroductionThatCanBeSkipped() {
        let app = launch(onboardingDone: false)
        XCTAssertTrue(app.buttons["intro.begin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["intro.skip"].exists)
        app.buttons["intro.skip"].tap()

        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.greeting"].label, "Hi, Ola.")
        XCTAssertFalse(app.staticTexts["Useful help"].exists, "removed in the review, so not stored")
    }

    @MainActor
    func testThreeTabsAndHonestPlaceholders() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].exists)
        // Calendar and Reminders start off, so Today only points to Settings.
        XCTAssertTrue(app.buttons["today.openSettings"].waitForExistence(timeout: 5))

        app.buttons["tab.memories"].tap()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.staticTexts["Nothing saved. Doddy only keeps what you review and save."].waitForExistence(timeout: 5))
        // Privacy sits below About you and Your memories.
        let microphone = app.staticTexts["Microphone"]
        for _ in 0..<6 {
            if microphone.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only while talking"].exists)
    }

    @MainActor
    func testAskDoddyIsOffByDefaultAndSaysWhyWithoutAnyNetworkCall() {
        let app = launch(onboardingDone: true)
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
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let consent = app.switches["settings.assistantConsent"]
        // The long Settings form creates rows lazily; scroll until the section is on screen.
        for _ in 0..<10 {
            if consent.exists && consent.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(consent.exists)
        XCTAssertEqual(consent.value as? String, "0")
        let status = app.descendants(matching: .any)["settings.assistantStatus"].firstMatch
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.label.contains("Off"))
    }

    @MainActor
    func testBackTapCardCanBeDeferredAndNeverShowsAsVerified() {
        let app = launch(onboardingDone: true, backTapSetup: "notStarted")
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
    func testPauseAllStopsTodayReadingCalendarAndReminders() {
        let app = launch(onboardingDone: true, pauseAll: true)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today.openSettings.paused"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.openSettings"].exists)
    }

    @MainActor
    func testWhatDoddyDidOpensFromSettings() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let row = app.buttons["settings.activity"]
        for _ in 0..<8 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["What Doddy did"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNoFakeListeningOrMicControls() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        for label in ["Listening…", "Tap to talk", "Record", "Mic"] {
            XCTAssertFalse(app.buttons[label].exists, label)
            XCTAssertFalse(app.staticTexts[label].exists, label)
        }
    }
}
