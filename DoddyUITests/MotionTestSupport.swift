import XCTest

/// Motion v2: what a failing motion UI test says about the screen. The annotated mode
/// (`-doddyMotionDebug YES`) puts its counts, the newest DEBUG finding and the engine's last
/// decisions in accessibility texts; the tree report is the accessibility tree as the test sees it.
extension XCUIApplication {
    /// The element a marker names, found by identifier or by label. The markers carry both (the
    /// same name), because a container's `accessibilityIdentifier` (`memories.empty`,
    /// `lists.empty`) replaces the identifier of everything inside it, his markers included: hosted
    /// probe run 39304818522 read `identifier: 'lists.empty', label: 'doddy.pose.crosslegged'`.
    func marker(_ name: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", name, name)).firstMatch
    }

    /// Goes to a tab. Home has no tab bar (ADR-545), so Memories and Settings are reached from
    /// its ••• menu there; coming back to Home is always from a screen that has the bar.
    @MainActor
    func openTab(_ name: String) {
        if name == "home" {
            buttons["tab.home"].tap()
        } else {
            goToTab(name)
        }
    }

    /// Every marker whose name starts with one of `prefixes`, by identifier or label.
    func markers(startingWith prefixes: [String]) -> XCUIElementQuery {
        let format = prefixes.map { _ in "(identifier BEGINSWITH %@ OR label BEGINSWITH %@)" }.joined(separator: " OR ")
        return descendants(matching: .any)
            .matching(NSPredicate(format: format, argumentArray: prefixes.flatMap { [$0, $0] }))
    }
}

extension XCTestCase {
    /// What the annotated mode says (its counts, the newest finding, the engine's last decisions
    /// and where each drawing of him is), or "-" for each text that isn't there.
    @MainActor
    func motionDebugReport(in app: XCUIApplication) -> String {
        ["doddy.debug", "doddy.debug.last", "doddy.debug.trail"].map { id in
            let text = app.staticTexts[id]
            return text.exists ? text.label : "-"
        }.joined(separator: " | ")
    }

    /// The accessibility tree trimmed to the lines that name something, on one line (`¶` between
    /// elements), for a failure's message.
    @MainActor
    func motionTreeReport(of app: XCUIApplication, limit: Int = 70) -> String {
        let lines = app.debugDescription.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let named = lines.filter { $0.contains("identifier:") || $0.contains("label:") }
        return named.prefix(limit).map { String($0.prefix(150)) }.joined(separator: " ¶ ")
    }
}
