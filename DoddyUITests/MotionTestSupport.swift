import XCTest

/// Motion v2: what a failing motion UI test says about the screen. The annotated mode
/// (`-doddyMotionDebug YES`) puts its counts, the newest DEBUG finding and the engine's last
/// decisions in accessibility texts; the tree report is the accessibility tree as the test sees it.
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
