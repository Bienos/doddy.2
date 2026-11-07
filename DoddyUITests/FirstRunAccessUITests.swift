import XCTest

/// "Allow access" (ADR-814): on a new installation it comes after the Terms and before the introduction,
/// lists every item ticked, and "Not now" asks iOS nothing and moves on. It never taps Allow: that would
/// raise real iOS questions. NOT RUN where this was written (no Xcode); hosted CI runs it.
final class FirstRunAccessUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, onboardingDone: false, firstRunAccess: true)
            + ["-resetFirstRunAccessForUITests"]
        app.launch()
        return app
    }

    @MainActor
    func testTheStepListsEveryItemTickedAndNotNowMovesOnWithoutAsking() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["access.title"].waitForExistence(timeout: 10), app.debugDescription)
        for item in ["microphone", "notifications", "contacts", "calendar", "reminders", "location", "motion", "photos", "camera"] {
            let row = app.switches["access.\(item)"]
            XCTAssertTrue(app.reveal(row), "\(item) is on the list")
            XCTAssertEqual(row.value as? String, "1", "\(item) starts ticked")
        }
        XCTAssertTrue(app.buttons["access.allow"].exists)
        let skip = app.buttons["access.skip"]
        XCTAssertTrue(app.reveal(skip))
        skip.tap()
        XCTAssertTrue(app.staticTexts["access.title"].waitForNonExistence(timeout: 5), "Not now closes the step")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Not now asks iOS nothing")
    }
}
