import XCTest
@testable import DoddyCore

final class BackTapSetupTests: XCTestCase {
    func testLinksOpenTheExactPlaces() {
        XCTAssertEqual(BackTapSetup.Link.newShortcut.candidates.first?.absoluteString, "shortcuts://create-shortcut")
        XCTAssertEqual(BackTapSetup.Link.editShortcut.candidates.first?.absoluteString, "shortcuts://open-shortcut?name=Open%20Doddy")
        XCTAssertEqual(BackTapSetup.Link.runShortcut.candidates.map(\.absoluteString), ["shortcuts://run-shortcut?name=Open%20Doddy"])
        let settings = BackTapSetup.Link.backTapSettings.candidates.map(\.absoluteString)
        XCTAssertEqual(settings.first, "App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/Back%20Tap")
        XCTAssertEqual(settings.last, "App-prefs:", "last resort opens Settings itself")
        XCTAssertEqual(BackTapSetup.settingsPath, ["Settings", "Accessibility", "Touch", "Back Tap"])
    }

    func testTapTestNeedsAShortcutOpenAfterTheStart() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(TapTestState.evaluate(testStartedAt: nil, lastShortcutOpenAt: start, now: start), .notStarted)
        XCTAssertEqual(
            TapTestState.evaluate(testStartedAt: start, lastShortcutOpenAt: start.addingTimeInterval(-5), now: start.addingTimeInterval(30)),
            .waiting(since: start), "an open from before the test does not count")
        XCTAssertEqual(
            TapTestState.evaluate(testStartedAt: start, lastShortcutOpenAt: start.addingTimeInterval(20), now: start.addingTimeInterval(30)),
            .openedByShortcut(at: start.addingTimeInterval(20)))
        XCTAssertEqual(
            TapTestState.evaluate(testStartedAt: start, lastShortcutOpenAt: nil, now: start.addingTimeInterval(BackTapSetup.tapTestWindow + 1)),
            .timedOut)
        XCTAssertEqual(
            TapTestState.evaluate(
                testStartedAt: start, lastShortcutOpenAt: start.addingTimeInterval(BackTapSetup.tapTestWindow + 1),
                now: start.addingTimeInterval(BackTapSetup.tapTestWindow + 2)),
            .timedOut, "an open after the window does not count")
    }
}
