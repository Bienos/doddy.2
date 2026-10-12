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

    static func arguments(
        store: Store, onboardingDone: Bool = true, appearance: String = "system", backTapSetup: String = "deferred",
        opening: Bool = false, listen: Bool = false
    ) -> [String] {
        var arguments: [String]
        switch store {
        case .inMemory: arguments = ["-inMemoryStore", "YES"]
        case .persistent(let id): arguments = ["-memoryTestID", id.uuidString]
        }
        if onboardingDone { arguments += ["-onboardingDone", "YES"] }
        arguments += ["-appearance", appearance, "-backTapSetupStatus", backTapSetup]
        // No agent ID: a conversation stops at "Couldn't connect" before the microphone or ElevenLabs.
        arguments += ["-voiceAgentID", ""]
        arguments += ["-openingScene", opening ? "YES" : "NO", "-listenOnOpen", listen ? "YES" : "NO"]
        // Memories remembers Notes or Lists in UserDefaults, which outlive the in-memory store: a
        // test that opened Lists would leave every later test looking at Lists, not the notes.
        arguments += ["-memoriesShowsLists", "NO"]
        return arguments
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
