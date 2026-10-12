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
        return arguments
    }
}

extension XCUIApplication {
    /// Scrolls, one slow swipe at a time, until `element` is on screen, tappable and clear of
    /// Doddy's tab bar. Settings, Home and the notes list have grown past the fixed swipe counts
    /// the tests used to have, and Settings and the notes list build their rows lazily.
    /// Returns whether the element got there.
    @MainActor @discardableResult
    func reveal(_ element: XCUIElement, maxSwipes: Int = 30) -> Bool {
        for _ in 0..<maxSwipes {
            if isReachable(element) { return true }
            swipeUp(velocity: .slow)
        }
        return isReachable(element)
    }

    @MainActor
    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let bar = buttons["tab.home"]
        return !bar.exists || element.frame.maxY <= bar.frame.minY
    }

    /// A text found by what it says. A container's accessibility identifier replaces its texts'
    /// own, so `staticTexts["No memories yet"]` stops matching once the empty state has an ID.
    @MainActor
    func text(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
