import XCTest

/// UI smoke tests (A-01 and the first-use flow). NOT RUN in the authoring environment (no
/// Xcode). Every launch uses an in-memory store, so each test starts as a fresh install.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(onboardingDone: Bool, backTapSetup: String = "deferred", pauseAll: Bool = false, opening: Bool = false,
                        listen: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Overrides UserDefaults for this launch only.
        app.launchArguments += ["-appearance", "system", "-inMemoryStore", "YES", "-backTapSetupStatus", backTapSetup]
        if onboardingDone { app.launchArguments += ["-onboardingDone", "YES"] }
        // The Quick start (ADR-310) shows once per install; UserDefaults outlive the in-memory store.
        if !onboardingDone { app.launchArguments += ["-quickStartOffered", "NO"] }
        if pauseAll { app.launchArguments += ["-connections.pauseAll", "YES"] }
        // The opening (ADR-225) is on by default; most tests start straight on Home.
        if !opening { app.launchArguments += ["-openingScene", "NO"] }
        // Listening on open is on by default too; it would open a conversation over every test.
        if !listen { app.launchArguments += ["-listenOnOpen", "NO"] }
        app.launchArguments += extra
        app.launch()
        return app
    }

    @MainActor
    func testFirstLaunchOffersIntroductionThatCanBeSkipped() {
        let app = launch(onboardingDone: false)
        XCTAssertTrue(app.buttons["intro.begin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["intro.skip"].exists)
        app.buttons["intro.skip"].tap()

        // Quick start (ADR-310): the notifications are offered; with nothing saved, the profile isn't.
        XCTAssertTrue(app.buttons["quickStart.notNow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["quickStart.morning"].exists)
        XCTAssertFalse(app.switches["quickStart.profile"].exists, "nothing saved, nothing to share")
        app.buttons["quickStart.notNow"].tap()

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

        // Sharing the saved answers with the voice is offered, but never pre-ticked (ADR-310).
        let share = app.switches["quickStart.profile"]
        for _ in 0..<3 where !share.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertEqual(share.value as? String, "0")
        app.buttons["quickStart.notNow"].tap()

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
        // Settings is a lazy Form under a header section; scroll until the row has been created.
        let nothingSaved = app.staticTexts["Nothing saved. Doddy only keeps what you review and save."]
        for _ in 0..<4 where !nothingSaved.waitForExistence(timeout: 1) { app.swipeUp() }
        XCTAssertTrue(nothingSaved.exists)
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
    func testWhatLeavesThisIPhoneFollowsSettings() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let link = app.buttons["settings.dataFlow"]
        for _ in 0..<6 {
            if link.exists && link.isHittable { break }
            app.swipeUp()
        }
        link.tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForExistence(timeout: 5))
        // Ask Doddy starts off, so it is listed under "Not sent right now".
        XCTAssertTrue(app.staticTexts["Ask Doddy is off, so nothing goes there."].waitForExistence(timeout: 5))
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
    func testPracticePlanCardCountsTicksAndNeverSaysDone() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let row = app.buttons["settings.planPractice"]
        for _ in 0..<8 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Try a plan card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["practice.banner"].exists)
        let confirm = app.buttons["practice.confirm"]
        XCTAssertTrue(confirm.label.contains("Do 4 things"), confirm.label)
        app.buttons["practice.step4"].tap()
        XCTAssertTrue(confirm.label.contains("Do 3 things"), confirm.label)
        confirm.tap()
        let results = app.descendants(matching: .any)["practice.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Nothing was done.")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Unticked")).firstMatch.exists)
    }

    @MainActor
    func testOpeningPlaysOnLaunchCanBeSkippedAndWithListeningOffOpensNothing() {
        let app = launch(onboardingDone: true, opening: true)
        let scene = app.descendants(matching: .any)["opening.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        XCTAssertTrue(scene.label.contains("Doddy"), scene.label)
        scene.tap()
        XCTAssertTrue(scene.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].isHittable, "the app is usable as soon as the opening is gone")
        // "Start listening when I open Doddy" is switched off for this launch: no conversation, no microphone.
        XCTAssertFalse(app.navigationBars["Talk to Doddy"].exists)
        XCTAssertFalse(app.staticTexts["Listening"].exists)
        XCTAssertFalse(app.staticTexts["Connecting…"].exists)
    }

    @MainActor
    func testOpeningEndsByItselfAndIsNotRepeatedOnAQuickReturn() {
        let app = launch(onboardingDone: true, opening: true)
        let scene = app.descendants(matching: .any)["opening.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        // Just over the timeline's length: it fades out on its own.
        XCTAssertTrue(scene.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(scene.exists, "a quick switch away and back is not an opening")
    }

    @MainActor
    func testOpeningOffShowsHomeStraightAway() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["opening.scene"].exists)
    }

    @MainActor
    func testListeningOnOpenIsOnByDefaultAndOpensTheConversation() {
        // Default listening switch; no agent ID, so the conversation stops at "Couldn't connect"
        // before it ever asks for the microphone or reaches ElevenLabs.
        let app = launch(onboardingDone: true, listen: true, extra: ["-voiceAgentID", ""])
        XCTAssertTrue(app.navigationBars["Talk to Doddy"].waitForExistence(timeout: 5), "opened by itself")
        XCTAssertEqual(app.staticTexts["voice.status"].label, "Couldn't connect")
        app.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let toggle = app.switches["settings.listenOnOpen"]
        for _ in 0..<10 {
            if toggle.exists && toggle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "1")
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
