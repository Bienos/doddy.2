import XCTest

/// ADR-609: the real Dynamic Island in Polish, the app's default language. The offline fixture
/// (no microphone, no provider) runs with the app in Polish; the island's words and buttons
/// come from the app's Polish table, sent with each update ("Stop" stays "Stop"). Screenshots are attached to the
/// result, as `MemoryBaselineTests` does in English.
final class IslandPolishTests: XCTestCase {
    @MainActor
    func testTheNativeIslandSpeaksPolish() throws {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, language: .polish) + ["-islandBaseline"]
        app.launch()
        XCTAssertTrue(app.buttons["island.fixture.start"].waitForExistence(timeout: 8))
        let enabled = app.staticTexts["island.fixture.activitiesEnabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        if enabled.label != "Live Activities on" {
            throw XCTSkip("Live Activities are off on this simulator; no Dynamic Island proof claimed.")
        }
        app.buttons["island.fixture.start"].tap()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The compact island says what Doddy is doing in Polish ("Test activity" is "Test wyspy").
        let compact = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Test wyspy'")).firstMatch
        XCTAssertTrue(compact.waitForExistence(timeout: 30), "The island's words follow the app's Polish.")
        attach(springboard, name: "Native compact Island in Polish - offline labelled fixture")
        compact.press(forDuration: 1.2)
        // The owner kept "Stop" on the island in Polish too: "Zatrzymaj" didn't fit.
        let stop = springboard.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "Stop stays Stop")
        XCTAssertTrue(springboard.buttons["Wycisz"].exists, "Mute is Wycisz")
        attach(springboard, name: "Native expanded Island in Polish - offline labelled fixture")
        stop.tap()
        app.activate()
        XCTAssertTrue(app.buttons["island.fixture.start"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
