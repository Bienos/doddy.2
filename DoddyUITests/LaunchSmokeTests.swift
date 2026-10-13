import XCTest

/// UI smoke tests (A-01 and the first-use flow). NOT RUN in the authoring environment (no
/// Xcode). Every launch uses an in-memory store, so each test starts as a fresh install.
final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(onboardingDone: Bool, backTapSetup: String = "deferred", pauseAll: Bool = false, opening: Bool = false,
                        listen: Bool = false, firstVisit: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Overrides UserDefaults for this launch only. The opening and listening on open are on by
        // default; most tests turn them off and start straight on Home (UITestLaunch).
        app.launchArguments += UITestLaunch.arguments(
            store: .inMemory, onboardingDone: onboardingDone, backTapSetup: backTapSetup, opening: opening, listen: listen)
        // The Quick start (ADR-324) shows once per install; UserDefaults outlive the in-memory store.
        if !onboardingDone { app.launchArguments += ["-quickStartOffered", "NO"] }
        // Most tests are about someone who has talked to Doddy before; Home's first visit
        // (ADR-326) holds back the Back Tap and Today cards until then.
        app.launchArguments += ["-hadFirstConversation", firstVisit ? "NO" : "YES"]
        if pauseAll { app.launchArguments += ["-connections.pauseAll", "YES"] }
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

        // Quick start (ADR-324): the notifications are offered; with nothing saved, the profile isn't.
        XCTAssertTrue(app.buttons["quickStart.notNow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["quickStart.morning"].exists)
        XCTAssertEqual(app.switches["quickStart.evening"].value as? String, "0", "Reminders is off on a fresh install")
        XCTAssertFalse(app.switches["quickStart.profile"].exists, "nothing saved, nothing to share")
        // ADR-402: where Siri, the Action Button and the control are, without claiming they're set.
        XCTAssertTrue(app.descendants(matching: .any)["quickStart.quickAccess"].exists)
        // The tips box can push Not now below the fold; the tab bar behind this cover isn't in the way.
        let notNow = app.buttons["quickStart.notNow"]
        for _ in 0..<10 where !notNow.isHittable { app.scrollStep() }
        notNow.tap()

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

        // Sharing the saved answers with the voice is offered, but never pre-ticked (ADR-324).
        let share = app.switches["quickStart.profile"]
        XCTAssertTrue(app.reveal(share))
        XCTAssertEqual(share.value as? String, "0")
        // Quick start is a full-screen cover: the tab bar behind it still exists, so reveal(_:)
        // would wait for Not now to rise above a bar that isn't in the way. Step until it's tappable.
        let notNow = app.buttons["quickStart.notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        for _ in 0..<10 where !notNow.isHittable { app.scrollStep() }
        notNow.tap()

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
        XCTAssertTrue(app.text("No memories yet").waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        // Settings is a lazy Form under a header section; scroll until the row has been created.
        XCTAssertTrue(app.reveal(app.text("Nothing saved. Doddy only keeps what you review and save.")))
        // Privacy sits below About you and Your memories.
        XCTAssertTrue(app.reveal(app.text("Microphone")))
        XCTAssertTrue(app.text("Only while talking").exists)
    }

    @MainActor
    func testFirstVisitHomeKeepsToTalkingAndLinksToPrivacy() {
        // ADR-326: before the first conversation, a hint under Talk and no setup cards.
        let app = launch(onboardingDone: true, backTapSetup: "notStarted", firstVisit: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.firstHint"].exists)
        XCTAssertFalse(app.buttons["home.backTap.setup"].exists, "held back until the first conversation")
        XCTAssertFalse(app.buttons["today.openSettings"].exists, "nothing connected yet, so no Today card")
        XCTAssertFalse(app.segmentedControls["home.voiceProvider"].exists, "the voice picker waits for the first conversation (ADR-443)")

        let link = app.buttons["home.dataFlow"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForNonExistence(timeout: 5))

        // Settings › Voice has the picker from the start.
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.reveal(app.segmentedControls["settings.voiceProvider"]))
    }

    @MainActor
    func testVoicePickerIsOnHomeAfterTheFirstConversation() {
        // ADR-443: the provider (and OpenAI's model) picker from ADR-442, once there has been a conversation.
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.reveal(app.segmentedControls["home.voiceProvider"]))
        XCTAssertFalse(app.staticTexts["home.firstHint"].exists)
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
        XCTAssertTrue(app.reveal(consent))
        XCTAssertEqual(consent.value as? String, "0")
        // The status row sits below the gateway and invite fields, so it may not be built yet.
        let status = app.descendants(matching: .any)["settings.assistantStatus"].firstMatch
        XCTAssertTrue(app.reveal(status))
        XCTAssertTrue(status.label.contains("Off"), status.label)
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
        XCTAssertTrue(app.reveal(status))
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
        let link = app.button(labelled: "What leaves this iPhone")
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForExistence(timeout: 5))
        // Ask Doddy starts off, so it is listed under "Not sent right now". Each row reads as one
        // element (destination and note combined), so the note is checked in the row's label.
        let askRow = app.descendants(matching: .any)["dataFlow.askDoddy"].firstMatch
        XCTAssertTrue(app.reveal(askRow))
        XCTAssertTrue(askRow.label.contains("Ask Doddy is off, so nothing goes there."), askRow.label)
    }

    @MainActor
    func testWhatDoddyDidOpensFromSettings() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let row = app.buttons["settings.activity"]
        XCTAssertTrue(app.reveal(row))
        row.tap()
        XCTAssertTrue(app.navigationBars["What Doddy did"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPracticePlanCardCountsTicksAndNeverSaysDone() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let row = app.buttons["settings.planPractice"]
        XCTAssertTrue(app.reveal(row))
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
        // Save sits below Doddy and the scenery on Home; it is reachable once the opening is gone.
        XCTAssertTrue(app.reveal(app.buttons["home.save"]), "the app is usable as soon as the opening is gone")
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
        // It fades out on its own after its timeline (OpeningScene.Beat.end, 2.4 s); the margin is for slow
        // simulators, since this checks that it ends by itself, not how long it takes.
        XCTAssertTrue(scene.waitForNonExistence(timeout: 10))
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
    func testListeningOnOpenIsOnByDefaultButWaitsForTheMicrophone() {
        // ADR-325: with the microphone never asked about, nothing opens by itself, so iOS's
        // question can only follow a tap on Talk to Doddy. (Opening once it's allowed is covered
        // by OpeningPolicyTests; a UI test can't grant the microphone.)
        XCUIApplication().resetAuthorizationStatus(for: .microphone)
        let app = launch(onboardingDone: true, listen: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Talk to Doddy"].waitForExistence(timeout: 3), "nothing opens before the microphone is allowed")

        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        let toggle = app.switches["settings.listenOnOpen"]
        XCTAssertTrue(app.reveal(toggle))
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
