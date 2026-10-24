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

    /// How much slower than real time the opening plays when a test turns it on.
    static let openingTimeScale = 6

    /// The screens' language for a test. The app's default is Polish (ADR-573), so every test
    /// says which language it reads; the argument wins over anything a launch stored before.
    enum Language: String {
        case english = "en", polish = "pl"
        var locale: String { self == .english ? "en_US" : "pl_PL" }
    }

    static func arguments(
        store: Store, onboardingDone: Bool = true, appearance: String = "system", backTapSetup: String = "deferred",
        opening: Bool = false, listen: Bool = false, language: Language = .english, welcome: Bool = false,
        legalAccepted: Bool = true
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
        arguments += ["-openingScene", opening ? "YES" : "NO", "-listenOnOpen", listen ? "YES" : "NO"]
        // The first-launch welcome (ADR-598) would cover every fresh-install test; a test that is
        // about it asks for it (`welcome: true`).
        arguments += ["-welcome", welcome ? "YES" : "NO"]
        // The opening's whole timeline is 2.4 s, and on CI the launch and the first idle wait can
        // take longer than that, so a test sometimes looked only after it had ended. Played 6×
        // slower (14.4 s) it is still on screen when the test first looks, and still ends by itself.
        if opening { arguments += ["-openingTimeScale", String(openingTimeScale)] }
        // Memories remembers Notes or Lists in UserDefaults, which outlive the in-memory store: a
        // test that opened Lists would leave every later test looking at Lists, not the notes.
        arguments += ["-memoriesShowsLists", "NO"]
        // "Before we start" (ADR-581) would cover every first screen; Debug builds skip it with
        // this. `LegalAcceptanceUITests` turns it off to test the step itself.
        if legalAccepted { arguments += ["-legalAcceptanceSkippedForUITests", "YES"] }
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
    /// open from Settings › Doddy's memory › Notes (ADR-614).
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
        // Settings keeps the page it was on: Doddy's memory, when notes were opened from it (ADR-614).
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

    /// Settings (ADR-580): scrolls to a group's row and opens its page.
    @MainActor
    func openSettingsPage(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = buttons[identifier]
        XCTAssertTrue(reveal(row), "Settings row \(identifier)", file: file, line: line)
        row.tap()
    }

    /// A row on one of Settings' short pages (ADR-614): opens the page `group` first ("settings.voice",
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
