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
        // Overrides UserDefaults for this launch only. Tests start on Home with the intro animation
        // and listening disabled unless a case opts into the first-launch animation.
        app.launchArguments += UITestLaunch.arguments(
            store: .inMemory, onboardingDone: onboardingDone, backTapSetup: backTapSetup, opening: opening, listen: listen)
        // The Quick start (ADR-324) shows once per install; UserDefaults outlive the in-memory store.
        if !onboardingDone { app.launchArguments += ["-quickStartOffered", "NO"] }
        // Most tests are about someone who has talked to Doddy before; Home's first visit
        // (ADR-326) holds back the Back Tap and Today cards until then.
        app.launchArguments += ["-hadFirstConversation", firstVisit ? "NO" : "YES"]
        app.launchArguments += ["-firstLaunchIntroSeen", firstVisit ? "NO" : "YES"]
        if pauseAll { app.launchArguments += ["-connections.pauseAll", "YES"] }
        app.launchArguments += extra
        app.launch()
        return app
    }

    @MainActor
    func testFirstLaunchLandsOnHomeAndOptionalConversationCanBeSkipped() {
        let app = launch(onboardingDone: false, firstVisit: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.getToKnow"].exists)
        XCTAssertFalse(app.textFields["profile.field.name"].exists, "questions never appear automatically")

        XCTAssertTrue(app.reveal(app.buttons["home.getToKnow"]))
        app.buttons["home.getToKnow"].tap()
        XCTAssertTrue(app.textFields["profile.field.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["intro.close"].exists)
        app.buttons["intro.close"].tap()
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.getToKnow"].exists, "Not now dismisses the offer")
    }

    @MainActor
    func testIntroductionReviewsAndSavesOnlyNameAndStyle() {
        let app = launch(onboardingDone: false, firstVisit: true)
        XCTAssertTrue(app.buttons["home.getToKnow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.reveal(app.buttons["home.getToKnow"]))
        app.buttons["home.getToKnow"].tap()
        let name = app.textFields["profile.field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ola")
        app.buttons["intro.next"].tap()
        XCTAssertTrue(app.buttons["Upbeat"].waitForExistence(timeout: 5))
        app.buttons["Upbeat"].tap()
        app.buttons["intro.next"].tap()

        // The review keeps the two explicit answers. Save confirms only after repository readback.
        XCTAssertTrue(app.buttons["profile.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["profile.field.name"].exists)
        XCTAssertTrue(app.textFields["profile.field.style"].exists)
        XCTAssertFalse(app.textFields["profile.field.help"].exists)
        XCTAssertTrue(app.reveal(app.buttons["profile.save"]))
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.alerts["Saved on this iPhone"].waitForExistence(timeout: 5))
        app.alerts.buttons["Done"].tap()
        XCTAssertTrue(app.waitForTab("home", timeout: 5))
        XCTAssertEqual(app.staticTexts["home.greeting"].label, "Hi, Ola.")
        app.goToTab("settings")
        let share = app.switches["settings.shareProfileWithVoice"]
        XCTAssertTrue(app.reveal(share))
        XCTAssertEqual(share.value as? String, "0", "saving preferences does not enable voice sharing")
    }

    @MainActor
    func testThreeTabsAndHonestPlaceholders() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.waitForTab("home", timeout: 5))
        XCTAssertTrue(app.buttons["home.save"].exists)
        // Calendar and Reminders start off, so Today (in Home's ••• menu, ADR-545) only points to Settings.
        app.tapHomeMenuItem("home.today")
        XCTAssertTrue(app.buttons["today.openSettings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["today.openSettings"].waitForNonExistence(timeout: 5))

        app.goToTab("memories")
        XCTAssertTrue(app.text("No memories yet").waitForExistence(timeout: 5))

        app.goToTab("settings")
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

        // In Home's ••• menu (ADR-545); before the first conversation it has no Today or Voice.
        app.buttons["home.more"].tap()
        XCTAssertFalse(app.buttons["home.today"].waitForExistence(timeout: 2), "nothing connected yet, so no Today")
        XCTAssertFalse(app.buttons["home.voice"].exists, "the voice picker waits for the first conversation (ADR-443)")
        let link = app.buttons["home.dataFlow"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForNonExistence(timeout: 5))

        // Settings › Voice has the picker from the start.
        app.goToTab("settings")
        XCTAssertTrue(app.reveal(app.segmentedControls["settings.voiceProvider"]))
    }

    @MainActor
    func testVoicePickerIsOnHomeAfterTheFirstConversation() {
        // ADR-443: the provider (and OpenAI's model) picker from ADR-442, once there has been a conversation.
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        // In Home's ••• menu (ADR-545).
        app.tapHomeMenuItem("home.voice")
        XCTAssertTrue(app.segmentedControls["home.voiceProvider"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["home.firstHint"].exists)
    }

    @MainActor
    func testWhatICanDoOpensFromTheHomeMenu() {
        // ADR-548: the capability list, generated from the catalog, in Home's ••• menu.
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        app.tapHomeMenuItem("home.capabilities")
        XCTAssertTrue(app.staticTexts["capabilities.introduction"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["capabilities.introduction"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testAskDoddyIsOffByDefaultAndSaysWhyWithoutAnyNetworkCall() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["home.ask"].waitForExistence(timeout: 5))
        app.buttons["home.ask"].tap()

        XCTAssertTrue(app.textFields["ask.input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ask.disclosure"].exists)
        XCTAssertTrue(app.staticTexts["Turn on Messages in Settings first. It sends your message to a server."].exists)
        // Nothing to send yet, so Send stays disabled.
        XCTAssertFalse(app.buttons["ask.send"].isEnabled)
    }

    @MainActor
    func testSettingsShowsAskDoddyOffUntilTheUserTurnsItOn() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.waitForTab("settings", timeout: 5))
        app.goToTab("settings")
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
    func testBackTapCardCanBeDeferredAndNeverShowsAsVerified() throws {
        // Back Tap is an iPhone setting; iPad hides it (ADR-337, covered by the test below).
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Back Tap is iPhone-only")
        let app = launch(onboardingDone: true, backTapSetup: "notStarted")
        XCTAssertTrue(app.buttons["home.backTap.later"].waitForExistence(timeout: 5))
        for _ in 0..<4 {
            // A partially visible card can report hittable behind the pill bar;
            // bring the whole button above navigation before sending the tap.
            let later = app.buttons["home.backTap.later"]
            if later.isHittable && later.frame.maxY < app.buttons["home.save"].frame.minY { break }
            app.swipeUp()
        }
        app.buttons["home.backTap.later"].tap()
        XCTAssertTrue(app.buttons["home.backTap.later"].waitForNonExistence(timeout: 5), app.debugDescription)

        app.goToTab("settings")
        let status = app.descendants(matching: .any)["settings.backTap.status"].firstMatch
        // The long Settings form lazily creates rows; scroll to the status rather than
        // treating an off-screen label as a product failure.
        XCTAssertTrue(app.reveal(status))
        XCTAssertTrue(status.label.contains("Set up later"))
        XCTAssertFalse(status.label.localizedCaseInsensitiveContains("verified"))
    }

    /// Ways to open Doddy (ADR-558): Settings opens a list with Double Back Tap and Siri on every
    /// iPhone; Back Tap is three steps on one screen, and nothing on the way says "verified".
    @MainActor
    func testWaysToOpenDoddyListsBackTapAndSiriAndBackTapIsOneScreen() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "the Settings entry is iPhone-only")
        let app = launch(onboardingDone: true, backTapSetup: "notStarted")
        app.goToTab("settings")
        let entry = app.buttons["settings.backTap"]
        XCTAssertTrue(app.reveal(entry))
        // The weekly reminder is on until the user turns it off; it only sends with notifications already allowed.
        let reminder = app.switches["settings.waysReminder"]
        XCTAssertTrue(app.reveal(reminder))
        XCTAssertEqual(reminder.value as? String, "1")
        entry.tap()
        XCTAssertTrue(app.buttons["ways.backTap"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["ways.siri"].exists, "Siri needs no setup, so it is always offered")

        app.buttons["ways.backTap"].tap()
        XCTAssertTrue(app.buttons["setup.startTest"].waitForExistence(timeout: 5), "the three steps and the test button share one screen")
        XCTAssertTrue(app.buttons["ways.openSettings"].exists)

        app.buttons["ways.all"].tap()
        XCTAssertTrue(app.buttons["ways.siri"].waitForExistence(timeout: 5))
        app.buttons["ways.siri"].tap()
        XCTAssertTrue(app.buttons["ways.all"].waitForExistence(timeout: 5), "a way without a test still has a way back")
    }

    /// iPad full screen (ADR-337, ADR-430): a sidebar in place of the tab bar, and no Back Tap
    /// card or row, even with Back Tap set up as "not started".
    @MainActor
    func testIPadHasASidebarAndNoBackTap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch(onboardingDone: true, backTapSetup: "notStarted")
        let memories = app.descendants(matching: .any)["tab.memories"].firstMatch
        XCTAssertTrue(memories.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["home.backTap.setup"].exists)
        XCTAssertFalse(app.buttons["home.backTap.later"].exists)

        app.descendants(matching: .any)["tab.settings"].firstMatch.tap()
        // The Back Tap row would sit in the same section as this switch, so look once it is on screen.
        let siri = app.switches["settings.siriReadsNotes"]
        for _ in 0..<8 {
            if siri.exists && siri.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(siri.exists, app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["settings.backTap.status"].firstMatch.exists)
        XCTAssertFalse(app.buttons["settings.backTap"].exists)
    }

    @MainActor
    func testPauseAllStopsTodayReadingCalendarAndReminders() {
        let app = launch(onboardingDone: true, pauseAll: true)
        XCTAssertTrue(app.waitForTab("home", timeout: 5))
        app.tapHomeMenuItem("home.today")
        XCTAssertTrue(app.buttons["today.openSettings.paused"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.openSettings"].exists)
    }

    @MainActor
    func testWhatLeavesThisIPhoneFollowsSettings() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.waitForTab("settings", timeout: 5))
        app.goToTab("settings")
        let link = app.button(labelled: "What leaves this iPhone")
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["What leaves this iPhone"].waitForExistence(timeout: 5))
        // Messages starts off, so it is listed under "Not sent right now". Each row reads as one
        // element (destination and note combined), so the note is checked in the row's label.
        let askRow = app.descendants(matching: .any)["dataFlow.askDoddy"].firstMatch
        XCTAssertTrue(app.reveal(askRow))
        XCTAssertTrue(askRow.label.contains("Messages is off, so nothing goes there."), askRow.label)
    }

    @MainActor
    func testWhatDoddyDidOpensFromSettings() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.waitForTab("settings", timeout: 5))
        app.goToTab("settings")
        let row = app.buttons["settings.activity"]
        XCTAssertTrue(app.reveal(row))
        row.tap()
        XCTAssertTrue(app.navigationBars["What Doddy did"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPracticePlanCardCountsTicksAndNeverSaysDone() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.waitForTab("settings", timeout: 5))
        app.goToTab("settings")
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
    func testFirstLaunchOpeningCanBeSkippedAndNeverStartsVoice() {
        let app = launch(onboardingDone: false, backTapSetup: "deferred", opening: true, firstVisit: true)
        let scene = app.descendants(matching: .any)["opening.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        XCTAssertTrue(scene.label.contains("Doddy"), scene.label)
        scene.tap()
        // A tap jumps to the hand-over; at the tests' slower clock that is under 3 s from the end.
        XCTAssertTrue(scene.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        // Save sits below Doddy and the scenery on Home; it is reachable once the opening is gone.
        XCTAssertTrue(app.reveal(app.buttons["home.save"]), "the app is usable as soon as the opening is gone")
        // "Start listening when I open Doddy" is switched off for this launch: no conversation, no microphone.
        XCTAssertFalse(app.navigationBars["Talk to Doddy"].exists)
        XCTAssertFalse(app.staticTexts["Listening"].exists)
        XCTAssertFalse(app.staticTexts["Connecting…"].exists)
    }

    @MainActor
    func testFirstLaunchOpeningEndsByItselfAndIsNotRepeatedOnAReturn() {
        let app = launch(onboardingDone: false, backTapSetup: "deferred", opening: true, firstVisit: true)
        let scene = app.descendants(matching: .any)["opening.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        // It fades out on its own after its timeline (OpeningScene.Beat.end, 2.4 s, played
        // UITestLaunch.openingTimeScale times slower here); the margin is for slow simulators,
        // since this checks that it ends by itself, not how long it takes.
        XCTAssertTrue(scene.waitForNonExistence(timeout: 30))
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
    func testListeningOnOpenIsOffByDefault() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Talk to Doddy"].waitForExistence(timeout: 3), "nothing opens before the microphone is allowed")

        XCTAssertTrue(app.waitForTab("settings", timeout: 5))
        app.goToTab("settings")
        let toggle = app.switches["settings.listenOnOpen"]
        XCTAssertTrue(app.reveal(toggle))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor
    func testNoFakeListeningOrMicControls() {
        let app = launch(onboardingDone: true)
        XCTAssertTrue(app.waitForTab("home", timeout: 5))
        for label in ["Listening…", "Tap to talk", "Record", "Mic"] {
            XCTAssertFalse(app.buttons[label].exists, label)
            XCTAssertFalse(app.staticTexts[label].exists, label)
        }
    }
}
