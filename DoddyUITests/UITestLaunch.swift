import XCTest

/// The launch arguments every UI test starts from, in one place (app tests review, finding 5).
/// Default-on features would otherwise cover the screen in every test: the opening (ADR-225),
/// listening on open, the Back Tap card and a real voice agent. A new default-on feature gets
/// its switch here once.
enum UITestLaunch {
    enum Store {
        /// A fresh in-memory store: every launch is a fresh install.
        case inMemory
        /// A real store on disk for this test only, so a restart finds what was saved.
        case persistent(UUID)
    }

    /// The screens' language for a test. The app's default is Polish (ADR-573), so every test
    /// says which language it reads; the argument wins over anything a launch stored before.
    enum Language: String {
        case english = "en", polish = "pl"
        var locale: String { self == .english ? "en_US" : "pl_PL" }
    }

    static func arguments(
        store: Store, onboardingDone: Bool = true, appearance: String = "system", backTapSetup: String = "deferred",
        listen: Bool = false, language: Language = .english, welcome: Bool = false,
        legalAccepted: Bool = true, firstRunAccess: Bool = false
    ) -> [String] {
        var arguments: [String]
        switch store {
        case .inMemory: arguments = ["-inMemoryStore", "YES"]
        case .persistent(let id): arguments = ["-memoryTestID", id.uuidString]
        }
        arguments += ["-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale]
        if onboardingDone { arguments += ["-onboardingDone", "YES"] }
        arguments += ["-appearance", appearance, "-backTapSetupStatus", backTapSetup]
        // No agent ID: a conversation stops at "Couldn't connect" before the microphone or ElevenLabs.
        arguments += ["-voiceAgentID", ""]
        arguments += ["-listenOnOpen", listen ? "YES" : "NO"]
        // The first-launch welcome (ADR-598) would cover every fresh-install test; a test that is
        // about it asks for it (`welcome: true`).
        arguments += ["-welcome", welcome ? "YES" : "NO"]
        // The first-run "Allow access" step (ADR-814) would sit between the Terms and the introduction in
        // every fresh-install test, and a real iOS question would block them. `FirstRunAccessUITests` asks for it.
        arguments += ["-firstRunAccess", firstRunAccess ? "YES" : "NO"]
        // Memories remembers Notes or Lists in UserDefaults, which outlive the in-memory store: a
        // test that opened Lists would leave every later test looking at Lists, not the notes.
        arguments += ["-memoriesShowsLists", "NO"]
        // "Before we start" (ADR-581) would cover every first screen; Debug builds skip it with
        // this. `LegalAcceptanceUITests` turns it off to test the step itself.
        if legalAccepted { arguments += ["-legalAcceptanceSkippedForUITests", "YES"] }
        // Every feature is shown in every build since 10 Nov 2026 (decision 2026-11-10-no-beta-scope); this key is
        // kept so the UI tests keep asking for everything explicitly (a Debug build honours it). The UI test
        // target doesn't link DoddyCore, so this is `ReleaseScope.previewEverythingKey` spelled out;
        // `ReleaseScopeTests.testPreviewKeyIsTheOneTheUITestsPass` keeps the two the same.
        arguments += ["-releaseScope.previewEverything", "YES"]
        return arguments
    }
}

extension XCUIElement {
    /// Taps a text field or text view and types once it really has the keyboard focus. A tap while
    /// its sheet is still sliding in can land before the view accepts focus, and `typeText` then
    /// fails with "Neither element nor any descendant has keyboard focus" (PR #119's second Mac
    /// run, in MotionRideTests' note saves). Taps again, up to `tries` times, before typing.
    @MainActor
    func tapAndType(_ text: String, tries: Int = 3) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<tries {
            tap()
            let wait = XCTNSPredicateExpectation(predicate: focused, object: self)
            if XCTWaiter.wait(for: [wait], timeout: 2) == .completed { break }
        }
        typeText(text)
    }
}

extension XCUIApplication {
    /// Scrolls, about half a screen at a time, until `element` is on screen, tappable and clear
    /// of Doddy's tab bar. Settings, Home and the notes list have grown past the fixed swipe
    /// counts the tests used to have, and Settings and the notes list build their rows lazily.
    /// A swipe flings a long list past the row between checks, so each step is a drag that holds
    /// at the end (no momentum). Returns whether it got there.
    @MainActor @discardableResult
    func reveal(_ element: XCUIElement, maxSteps: Int = 40) -> Bool {
        for _ in 0..<maxSteps {
            if isReachable(element) { return true }
            scrollStep()
        }
        return isReachable(element)
    }

    /// Scrolls up just over half the screen with no momentum: less than the visible height, so no
    /// row is stepped over. It starts in the left margin, clear of switches and text fields (a
    /// drag that starts on a text field doesn't scroll).
    @MainActor
    func scrollStep() {
        let from = coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.75))
        let to = coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.2))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.2)
    }

    @MainActor
    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let bar = buttons["tab.home"]
        return !bar.exists || element.frame.maxY <= bar.frame.minY
    }

    /// Waits until the app can go to tab `name`: its tab bar button, or, on Home, which has no tab
    /// bar (ADR-545), the ••• menu.
    @MainActor
    func waitForTab(_ name: String, timeout: TimeInterval) -> Bool {
        descendants(matching: .button)
            .matching(NSPredicate(format: "identifier IN %@", ["tab.\(name)", "home.more"]))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Goes to tab `name` ("memories", "settings"): the tab bar (or iPad's sidebar) where there is
    /// one, else Home's ••• menu (ADR-545). Notes and lists have no tab on iPhone any more: they
    /// open from Settings › Doddy's memory › Notes (ADR-633).
    @MainActor
    func goToTab(_ name: String) {
        if name == "memories" {
            let sidebar = descendants(matching: .any)["tab.memories"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); return }
            goToTab("settings")
            openSettingsPage("settings.memory.notes", under: "settings.memory")
            return
        }
        _ = waitForTab(name, timeout: 5)
        let tab = buttons["tab.\(name)"]
        if tab.exists && tab.isHittable {
            tab.tap()
        } else {
            tapHomeMenuItem("home.menu.\(name)")
        }
        // Settings keeps the page it was on: Doddy's memory, when notes were opened from it (ADR-633).
        // Back to its first page (Voice is its first row), where the tests start.
        if name == "settings" {
            _ = buttons["settings.voice"].waitForExistence(timeout: 2)
            for _ in 0..<3 where !buttons["settings.voice"].exists {
                let back = navigationBars.buttons.element(boundBy: 0)
                guard back.exists else { break }
                back.tap()
                _ = buttons["settings.voice"].waitForExistence(timeout: 2)
            }
        }
    }

    /// Opens Home's ••• menu and taps the item with this identifier (ADR-545).
    @MainActor
    func tapHomeMenuItem(_ identifier: String) {
        let more = buttons["home.more"]
        _ = more.waitForExistence(timeout: 5)
        more.tap()
        let item = buttons[identifier]
        _ = item.waitForExistence(timeout: 5)
        item.tap()
    }

    /// Find (search saved notes): on the notes screen, reached from Settings › Doddy's memory. It left Home's
    /// ••• menu on 10 Nov 2026 (owner: the menu row wasn't clear). Returns whether the search field showed.
    @MainActor
    @discardableResult
    func openFind() -> Bool {
        goToTab("memories")
        let find = buttons["memories.find"]
        guard find.waitForExistence(timeout: 5) else { return false }
        find.tap()
        return textFields["memories.query"].waitForExistence(timeout: 5)
    }

    /// Home's + is a menu since 5 Nov 2026 (Take a photo, Choose a photo, New note): opens the new-note screen.
    @MainActor
    func openNewNote() {
        let plus = buttons["home.save"]
        _ = plus.waitForExistence(timeout: 5)
        plus.tap()
        let note = buttons["home.save.note"]
        _ = note.waitForExistence(timeout: 5)
        note.tap()
    }

    /// Settings (ADR-580): scrolls to a group's row and opens its page.
    @MainActor
    func openSettingsPage(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = buttons[identifier]
        XCTAssertTrue(reveal(row), "Settings row \(identifier)", file: file, line: line)
        row.tap()
    }

    /// A row on one of Settings' short pages (ADR-633): opens the page `group` first ("settings.voice",
    /// "settings.memory", "settings.connectionsHub", "settings.advanced"), unless it is open already.
    @MainActor
    func openSettingsPage(_ identifier: String, under group: String, file: StaticString = #filePath, line: UInt = #line) {
        if !buttons[identifier].exists { openSettingsPage(group, file: file, line: line) }
        openSettingsPage(identifier, file: file, line: line)
    }

    /// A button found by what it says. A Section's accessibility identifier (Settings' Privacy
    /// section has `settings.privacy`) replaces its rows' own, so `buttons["settings.dataFlow"]`
    /// never matches there.
    @MainActor
    func button(labelled label: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A text found by what it says, whatever accessibility identifier a container gave it.
    @MainActor
    func text(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
