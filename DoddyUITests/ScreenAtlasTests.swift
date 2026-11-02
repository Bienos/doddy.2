import XCTest

/// Pictures of Doddy's screens (ADR-693), for the owner's capability map: the real app on the
/// simulator, not mockups. It checks nothing about how a screen behaves. Each visit starts the app
/// fresh, walks to one screen, waits for it to settle and keeps a picture of the whole simulator
/// screen. A screen it can't reach is kept as "missed-…" with whatever was on screen, and listed
/// as missed in index.tsv, so one missed screen never stops the others or fails the run.
///
/// It runs only in the screens run (`scripts/ci_screens.sh`; Actions › iOS build and tests › Run
/// workflow, only: screens), which sets DODDY_SCREEN_ATLAS=1. In every other run each test skips
/// at once. The pictures go to build/screen-atlas/, which the job keeps, as the island's pictures
/// do (ADR-615). Everything runs offline: an in-memory or test store, no voice agent, no server,
/// so screens that need a server show what this build says without one.
///
/// NOT RUN in the authoring environment (Linux, no Xcode): the hosted Mac job is the first run.
final class ScreenAtlasTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DODDY_SCREEN_ATLAS"] == "1",
                          "Only in the screens run (scripts/ci_screens.sh, ADR-693)")
    }

    /// The repository's build/screen-atlas/, found from this file's path, as IslandScreenshotTests does.
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/screen-atlas", isDirectory: true)

    // MARK: 1. First run

    @MainActor
    func test1FirstRun() {
        for chapter in 0...4 {
            visit("1-first-0\(chapter + 1)-welcome-chapter-\(chapter + 1)", onboardingDone: false, welcome: true, firstVisit: true) { app in
                guard self.see(app.descendants(matching: .any)["welcome.chapter.0"], 10) else { return false }
                let pager = app.scrollViews["welcome.pager"]
                for _ in 0..<chapter where pager.exists { pager.swipeLeft(); self.settle(0.8) }
                return self.see(app.descendants(matching: .any)["welcome.chapter.\(chapter)"], 5)
            }
        }
        visit("1-first-06-sign-in-sheet", onboardingDone: false, welcome: true, firstVisit: true) { app in
            self.tap(app.buttons["welcome.getIn"], app, 10) && self.see(app.buttons["welcome.faceID"])
        }
        visit("1-first-07-sign-in-not-connected", onboardingDone: false, welcome: true, firstVisit: true) { app in
            self.tap(app.buttons["welcome.getIn"], app, 10) && self.tap(app.buttons["welcome.google"], app)
                && self.see(app.descendants(matching: .any)["welcome.notConnected"])
        }
        visit("1-first-08-before-we-start", legalAccepted: false, extra: ["-resetLegalAcceptanceForUITests"]) { app in
            self.see(app.staticTexts["legal.title"], 10)
        }
        visit("1-first-09-introduction", onboardingDone: false, firstVisit: true) { app in
            self.tap(app.buttons["home.getToKnow"], app, 8) && self.see(app.textFields["profile.field.name"])
        }
        visit("1-first-10-introduction-style", onboardingDone: false, firstVisit: true) { app in
            guard self.tap(app.buttons["home.getToKnow"], app, 8) else { return false }
            let name = app.textFields["profile.field.name"]
            guard self.see(name) else { return false }
            name.tapAndType("Pat")
            return self.tap(app.buttons["intro.next"], app) && self.see(app.buttons["Upbeat"])
        }
        visit("1-first-11-introduction-review", onboardingDone: false, firstVisit: true) { app in
            guard self.tap(app.buttons["home.getToKnow"], app, 8) else { return false }
            let name = app.textFields["profile.field.name"]
            guard self.see(name) else { return false }
            name.tapAndType("Pat")
            guard self.tap(app.buttons["intro.next"], app), self.tap(app.buttons["Upbeat"], app) else { return false }
            return self.tap(app.buttons["intro.next"], app) && self.see(app.buttons["profile.save"])
        }
        visit("1-first-12-what-i-can-do") { app in
            self.menu(app, ["home.capabilities"]) && self.see(app.staticTexts["capabilities.introduction"])
        }
    }

    // MARK: 2. Home and its menu

    @MainActor
    func test2Home() {
        visit("2-home-01-first-visit", firstVisit: true) { app in self.see(app.staticTexts["home.firstHint"], 10) }
        visit("2-home-02-at-rest") { app in self.see(app.buttons["home.talk"], 10) }
        visit("2-home-03-menu") { app in
            guard self.see(app.buttons["home.more"], 10) else { return false }
            app.buttons["home.more"].tap()
            return self.see(app.buttons["home.capabilities"])
        }
        visit("2-home-04-menu-focus-and-stopwatch") { app in self.menu(app, ["home.timers"]) && self.see(app.buttons["home.focus"]) }
        visit("2-home-05-voice-without-an-account") { app in
            guard self.tap(app.buttons["home.talk"], app, 10) else { return false }
            self.settle(2)
            return !app.buttons["home.talk"].isHittable
        }
        visit("2-home-06-messages") { app in self.tap(app.buttons["home.ask"], app, 10) && self.see(app.textFields["ask.input"]) }
        visit("2-home-07-files") { app in self.tap(app.buttons["home.files"], app, 10) && self.see(app.buttons["files.recordings"]) }
        visit("2-home-08-today") { app in self.menu(app, ["home.today"]) }
        visit("2-home-09-tasks") { app in self.menu(app, ["home.tasks"]) && self.see(app.navigationBars["Tasks"]) }
        visit("2-home-10-cheapest-this-week") { app in self.menu(app, ["home.deals"]) }
        visit("2-home-11-translate") { app in self.menu(app, ["home.translate"]) && self.see(app.buttons["translator.start"]) }
        visit("2-home-12-focus") { app in self.menu(app, ["home.timers", "home.focus"]) && self.see(app.buttons["focus.start"]) }
        visit("2-home-13-focus-running") { app in
            guard self.menu(app, ["home.timers", "home.focus"]), self.tap(app.buttons["focus.start"], app) else { return false }
            // The first start asks iOS for notifications (the first screens run kept the question
            // over the timer); allow, so the picture shows the timer.
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
            if allow.waitForExistence(timeout: 4) { allow.tap(); self.settle(0.8) }
            return self.see(app.buttons["focus.pause"])
        }
        visit("2-home-14-stopwatch-running") { app in
            self.menu(app, ["home.timers", "home.stopwatch"]) && self.tap(app.buttons["stopwatch.start"], app)
                && self.see(app.buttons["stopwatch.pause"])
        }
        visit("2-home-15-what-leaves-this-iphone") { app in self.menu(app, ["home.dataFlow"]) }
        visit("2-home-16-voice-picker") { app in self.menu(app, ["home.voice"]) }
        visit("2-home-17-recordings") { app in
            self.tap(app.buttons["home.files"], app, 10) && self.tap(app.buttons["files.recordings"], app)
                && self.see(app.buttons["recordings.record"])
        }
        visit("2-home-18-before-you-record") { app in
            guard self.tap(app.buttons["home.files"], app, 10), self.tap(app.buttons["files.recordings"], app) else { return false }
            // The first Record shows the notice; nothing records until "I understand, record".
            return self.tap(app.buttons["recordings.record"], app) && self.see(app.buttons["recordings.notice.decline"])
        }
    }

    // MARK: 3. Memory, with notes and a list saved first

    @MainActor
    func test3Memory() {
        let store = UITestLaunch.Store.persistent(UUID())
        visit("3-memory-01-notes-empty", store: store) { app in
            self.settings(app, ["settings.memory", "settings.memory.notes"]) && self.see(app.text("No memories yet"))
        }
        // Its own store: the words it leaves unsaved would come back as a draft in the next save.
        visit("3-memory-02-new-note") { app in
            guard self.tap(app.buttons["home.save"], app, 10) else { return false }
            let editor = app.textViews.firstMatch
            guard self.see(editor) else { return false }
            editor.tapAndType("Spare key is under the blue plant pot.")
            return true
        }
        visit("3-memory-03-saved", store: store) { app in self.saveNote(app, "Gate code for Ola's building is 4821.") }
        visit("3-memory-04-saved-again", store: store) { app in self.saveNote(app, "Spare key is under the blue plant pot.") }
        visit("3-memory-05-notes", store: store) { app in
            _ = self.saveNote(app, "Car insurance renews 3 December. The policy is in the blue folder.")
            if app.buttons["capture.done"].exists { self.reveal(app.buttons["capture.done"], app); app.buttons["capture.done"].tap() }
            return self.settings(app, ["settings.memory", "settings.memory.notes"])
                && self.see(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch)
        }
        visit("3-memory-06-find-a-match", store: store) { app in
            guard self.menu(app, ["home.find"]) else { return false }
            let query = app.textFields["memories.query"]
            guard self.see(query) else { return false }
            query.tapAndType("key\n")
            return self.see(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch)
        }
        visit("3-memory-07-find-nothing", store: store) { app in
            guard self.menu(app, ["home.find"]) else { return false }
            let query = app.textFields["memories.query"]
            guard self.see(query) else { return false }
            query.tapAndType("wifi password at the cabin\n")
            return self.see(app.descendants(matching: .any)["memories.noMatch"])
        }
        visit("3-memory-08-note", store: store) { app in self.openFirstNote(app) }
        visit("3-memory-09-correct", store: store) { app in
            self.openFirstNote(app) && self.tap(app.buttons["detail.edit"], app) && self.see(app.buttons["correction.save"])
        }
        visit("3-memory-10-remind-me", store: store) { app in
            self.openFirstNote(app) && self.tap(app.buttons["detail.remind"], app)
        }
        // UITestLaunch pins Memories to Notes (-memoriesShowsLists NO), which holds the picker on
        // Notes; these three visits override it.
        let lists = ["-memoriesShowsLists", "YES"]
        visit("3-memory-11-lists-empty", store: store, extra: lists) { app in self.openLists(app) && self.see(app.descendants(matching: .any)["lists.empty"]) }
        visit("3-memory-12-new-list", store: store, extra: lists) { app in
            guard self.openLists(app), self.tap(app.buttons["lists.new"], app) else { return false }
            let name = app.textFields["newList.name"]
            guard self.see(name) else { return false }
            name.tapAndType("Weekend shop")
            return true
        }
        visit("3-memory-13-a-list", store: store, extra: lists) { app in
            guard self.openLists(app), self.tap(app.buttons["lists.new"], app) else { return false }
            let name = app.textFields["newList.name"]
            guard self.see(name) else { return false }
            name.tapAndType("Weekend shop")
            guard self.tap(app.buttons["newList.create"], app) else { return false }
            let field = app.textFields["list.addField"]
            if !self.see(field) {
                // Create may land back on the lists; open the new one.
                let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Weekend shop'")).firstMatch
                guard self.tap(card, app) else { return false }
            }
            guard self.see(field) else { return false }
            for item in ["2 l milk", "eggs 10 szt.", "butter", "bread"] { field.tapAndType(item + "\n"); self.settle(0.5) }
            return true
        }
        visit("3-memory-14-what-doddy-did", store: store) { app in
            self.settings(app, ["settings.connectionsHub", "settings.activity"]) && self.see(app.navigationBars["What Doddy did"])
        }
    }

    // MARK: 4. Settings: Doddy, memory, this iPhone, about

    @MainActor
    func test4aSettings() {
        let pages: [(String, [String])] = [
            ("4-settings-01-settings", []),
            ("4-settings-02-voice", ["settings.voice"]),
            ("4-settings-03-voice-and-personality", ["settings.voice", "settings.personality"]),
            ("4-settings-04-voice-list", ["settings.voice", "settings.personality", "settings.voice.choice"]),
            ("4-settings-05-siri-and-back-tap", ["settings.voice", "settings.ways"]),
            ("4-settings-06-ways-to-open-doddy", ["settings.voice", "settings.ways", "settings.backTap"]),
            ("4-settings-07-doddys-memory", ["settings.memory"]),
            ("4-settings-08-my-profile", ["settings.memory", "settings.profile"]),
            ("4-settings-09-what-doddy-knows", ["settings.memory", "settings.knowledge"]),
            ("4-settings-10-what-ive-learned", ["settings.memory", "settings.knowledge", "settings.learned"]),
            ("4-settings-11-remembered-conversations", ["settings.memory", "settings.knowledge", "settings.rememberedConversations"]),
        ]
        for (name, path) in pages { visit(name) { app in self.settings(app, path) } }
    }

    /// Split from 4a: one test with all of Settings ran past the 10-minute limit (ADR-680) in the
    /// first screens run (41475441329).
    @MainActor
    func test4bSettings() {
        let pages: [(String, [String])] = [
            ("4-settings-12-export-backup-delete", ["settings.memory", "settings.memories"]),
            ("4-settings-13-language", ["settings.language"]),
            ("4-settings-14-appearance", ["settings.appearance"]),
            ("4-settings-15-privacy", ["settings.privacyScreen"]),
            ("4-settings-16-what-leaves-this-iphone", ["settings.privacyScreen", "label:What leaves this iPhone"]),
            ("4-settings-17-advanced", ["settings.advanced"]),
            ("4-settings-18-try-a-plan-card", ["settings.advanced", "settings.planPractice"]),
        ]
        for (name, path) in pages { visit(name) { app in self.settings(app, path) } }
        visit("4-settings-19-back-tap-steps") { app in
            self.settings(app, ["settings.voice", "settings.ways", "settings.backTap"]) && self.tap(app.buttons["ways.backTap"], app)
                && self.see(app.buttons["setup.startTest"])
        }
        visit("4-settings-20-backup-file") { app in
            self.settings(app, ["settings.memory", "settings.memories", "settings.makeBackup"])
        }
        visit("4-settings-21-import-notes") { app in
            self.settings(app, ["settings.memory", "settings.memories", "settings.importNotes"])
        }
    }

    // MARK: 5. Connections and notifications

    @MainActor
    func test5aConnections() {
        let pages: [(String, [String])] = [
            ("5-connect-01-connections", ["settings.connectionsHub"]),
            ("5-connect-02-calendar-reminders-contacts", ["settings.connectionsHub", "settings.connections"]),
            ("5-connect-03-online-accounts", ["settings.connectionsHub", "settings.onlineAccounts"]),
            ("5-connect-04-parcels", ["settings.connectionsHub", "settings.parcels"]),
            ("5-connect-05-invoices", ["settings.connectionsHub", "settings.invoices"]),
            ("5-connect-06-doddy-on-the-web", ["settings.connectionsHub", "settings.web"]),
            ("5-connect-07-ask-doddy", ["settings.connectionsHub", "settings.askDoddy"]),
            ("5-connect-08-apple-health", ["settings.connectionsHub", "connections.appleHealth"]),
            ("5-connect-09-training-plan", ["settings.connectionsHub", "connections.trainingPlan"]),
            ("5-connect-10-training-log", ["settings.connectionsHub", "connections.trainingLog"]),
        ]
        for (name, path) in pages { visit(name) { app in self.settings(app, path) } }
        visit("5-connect-11-connections-paused", extra: ["-connections.pauseAll", "YES"]) { app in
            self.settings(app, ["settings.connectionsHub"])
        }
        visit("5-connect-12-new-training-plan") { app in
            self.settings(app, ["settings.connectionsHub", "connections.trainingPlan"]) && self.tap(app.buttons["plan.make"], app)
        }
    }

    /// Split from 5a, for the 10-minute limit (see 4b).
    @MainActor
    func test5bNotifications() {
        let pages: [(String, [String])] = [
            ("5-notify-01-notifications", ["settings.notifications"]),
            ("5-notify-02-notifications-and-texts", ["settings.notifications", "settings.updates"]),
            ("5-notify-03-check-ins-and-reminders", ["settings.notifications", "settings.routines"]),
            ("5-notify-04-alarms", ["settings.notifications", "settings.alarms"]),
            ("5-notify-05-birthdays", ["settings.notifications", "settings.birthdays"]),
            ("5-notify-06-daily-news", ["settings.notifications", "settings.news"]),
            ("5-notify-07-phone-calls", ["settings.notifications", "settings.calls"]),
            ("5-notify-08-morning-check-in", ["settings.notifications", "settings.routines", "settings.checkinOpen"]),
            ("5-notify-09-evening-wrap-up", ["settings.notifications", "settings.routines", "settings.wrapUpOpen"]),
            ("5-notify-10-weekly-plan", ["settings.notifications", "settings.routines", "settings.weeklyPlanOpen"]),
            ("5-notify-11-weekly-look-back", ["settings.notifications", "settings.routines", "settings.lookBackOpen"]),
            ("5-notify-12-tidy-up", ["settings.notifications", "settings.routines", "label:Open the tidy-up now"]),
        ]
        for (name, path) in pages { visit(name) { app in self.settings(app, path) } }
    }

    // MARK: 6. The same app in dark, in Polish and at the largest text

    @MainActor
    func test6Looks() {
        visit("6-look-01-home-dark", appearance: "dark") { app in self.see(app.buttons["home.talk"], 10) }
        visit("6-look-02-settings-dark", appearance: "dark") { app in self.settings(app, []) }
        visit("6-look-03-home-polish", language: .polish) { app in self.see(app.buttons["home.talk"], 10) }
        visit("6-look-04-settings-polish", language: .polish) { app in self.settings(app, []) }
        visit("6-look-05-home-largest-text", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]) { app in
            self.see(app.buttons["home.talk"], 10)
        }
    }

    // MARK: Visiting and keeping

    /// One screen: a fresh launch, the steps to it, a moment to settle, then the picture.
    @MainActor
    private func visit(
        _ name: String, store: UITestLaunch.Store = .inMemory, onboardingDone: Bool = true, appearance: String = "light",
        language: UITestLaunch.Language = .english, welcome: Bool = false, legalAccepted: Bool = true,
        firstVisit: Bool = false, extra: [String] = [], _ steps: @MainActor (XCUIApplication) -> Bool
    ) {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(
            store: store, onboardingDone: onboardingDone, appearance: appearance, language: language, welcome: welcome,
            legalAccepted: legalAccepted)
        // As LaunchSmokeTests: someone who has talked to Doddy before, unless the visit is a first one.
        app.launchArguments += ["-quickStartOffered", "NO", "-hadFirstConversation", firstVisit ? "NO" : "YES",
                                "-firstLaunchIntroSeen", firstVisit ? "NO" : "YES"]
        // A key in `extra` replaces the same key set above (UITestLaunch's -memoriesShowsLists NO).
        var arguments = app.launchArguments
        for key in extra where key.hasPrefix("-") {
            if let at = arguments.firstIndex(of: key), at + 1 < arguments.count { arguments.removeSubrange(at...(at + 1)) }
        }
        app.launchArguments = arguments + extra
        app.launch()
        let reached = steps(app)
        settle(1.2)
        keep(name, reached: reached)
        app.terminate()
    }

    /// The whole simulator screen (status bar and island included), attached to the result and
    /// written to build/screen-atlas/, with a line in index.tsv.
    @MainActor
    private func keep(_ name: String, reached: Bool) {
        let shot = XCUIScreen.main.screenshot()
        let file = (reached ? "" : "missed-") + name
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: Self.folder.appendingPathComponent(file + ".png"))
            let line = Data("\(name)\t\(reached ? "reached" : "missed")\n".utf8)
            let index = Self.folder.appendingPathComponent("index.tsv")
            if let handle = try? FileHandle(forWritingTo: index) {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: index)
            }
        } catch {
            // The attachment is still in the .xcresult, and ci_screens.sh exports those too.
            add(XCTAttachment(string: "Couldn't write \(file).png: \(error)"))
        }
    }

    // MARK: Getting there

    @MainActor
    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    private func see(_ element: XCUIElement, _ timeout: TimeInterval = 6) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        if !element.isHittable { _ = app.reveal(element, maxSteps: 12) }
    }

    /// Taps an element once it exists and can be tapped; false instead of a failure when it can't.
    @MainActor
    private func tap(_ element: XCUIElement, _ app: XCUIApplication, _ timeout: TimeInterval = 6) -> Bool {
        guard see(element, timeout) else { return false }
        reveal(element, app)
        guard element.isHittable else { return false }
        element.tap()
        settle(0.6)
        return true
    }

    /// Home's ••• menu, then each item in turn ("home.timers" opens Focus and stopwatch).
    @MainActor
    private func menu(_ app: XCUIApplication, _ path: [String]) -> Bool {
        let more = app.buttons["home.more"]
        guard see(more, 10) else { return false }
        more.tap()
        for id in path {
            let item = app.buttons[id]
            guard see(item, 5) else { return false }
            item.tap()
            settle(0.6)
        }
        return true
    }

    /// Settings, then each row in turn: an identifier, or "label:…" where a section's identifier
    /// hides its rows' own (Privacy, see UITestLaunch's `button(labelled:)`).
    @MainActor
    private func settings(_ app: XCUIApplication, _ path: [String]) -> Bool {
        guard app.waitForTab("settings", timeout: 10) else { return false }
        app.goToTab("settings")
        guard see(app.buttons["settings.voice"], 6) else { return false }
        for step in path {
            let row = step.hasPrefix("label:") ? app.button(labelled: String(step.dropFirst(6))) : app.buttons[step]
            guard see(row, 3) || app.reveal(row, maxSteps: 16) else { return false }
            guard tap(row, app, 3) else { return false }
        }
        return true
    }

    @MainActor
    private func saveNote(_ app: XCUIApplication, _ text: String) -> Bool {
        guard tap(app.buttons["home.save"], app, 10) else { return false }
        let editor = app.textViews.firstMatch
        guard see(editor) else { return false }
        editor.tapAndType(text)
        if app.buttons["capture.keyboardDone"].exists { app.buttons["capture.keyboardDone"].tap() }
        guard tap(app.buttons["capture.save"], app) else { return false }
        return see(app.staticTexts["capture.saved"], 8)
    }

    @MainActor
    private func openFirstNote(_ app: XCUIApplication) -> Bool {
        guard settings(app, ["settings.memory", "settings.memory.notes"]) else { return false }
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch
        return tap(card, app) && see(app.staticTexts["detail.currentText"])
    }

    @MainActor
    private func openLists(_ app: XCUIApplication) -> Bool {
        guard settings(app, ["settings.memory", "settings.memory.notes"]) else { return false }
        let picker = app.segmentedControls["memories.notesOrLists"]
        guard see(picker) else { return false }
        picker.buttons["Lists"].tap()
        settle(0.6)
        return true
    }
}
