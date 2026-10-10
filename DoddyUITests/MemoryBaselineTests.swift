import XCTest

final class MemoryBaselineTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSaveRestartFindAndDeleteRealNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-memoryTestID", UUID().uuidString, "-hasSeenFirstHello", "YES",
                               "-backTapSetupStatus", "deferred", "-voiceAgentID", ""]
        app.launch()
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 8))
        app.buttons["home.save"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let text = "Synthetic amber notebook is in the green drawer."
        editor.tap()
        editor.typeText(text)
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 5))
        attach(app, name: "Native confirmed save - synthetic data")
        app.buttons["capture.done"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.memories"].waitForExistence(timeout: 8))
        app.buttons["tab.memories"].tap()
        app.buttons["memories.find"].tap()
        let search = app.textFields["memories.query"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("amber")
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "A real persisted record must survive process restart.")
        attach(app, name: "Native recall after restart - synthetic data")
        hit.tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, text)
        let delete = app.buttons["detail.delete"]
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["memories.noMatch"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.buttons["tab.memories"].tap()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNativeIslandOfflineFixtureCanStartMuteAndEnd() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "YES", "-hasSeenFirstHello", "YES", "-islandBaseline"]
        app.launch()
        XCTAssertTrue(app.buttons["island.fixture.start"].waitForExistence(timeout: 8))
        app.buttons["island.fixture.start"].tap()
        XCTAssertEqual(app.staticTexts["island.fixture.status"].label, "Fixture active")
        let count = app.staticTexts["island.fixture.nativeCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.waitForLabel("1 native activities", timeout: 5))
        app.buttons["island.fixture.mute"].tap()
        XCTAssertEqual(app.staticTexts["island.fixture.status"].label, "Fixture muted")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // SpringBoard exposes the compact surface as Other, not StaticText. Use its
        // actual accessibility frame: SpringBoard also has pixel-sized overlay windows,
        // so normalizing a coordinate against the entire application is unreliable.
        let compact = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Test muted'")).firstMatch
        XCTAssertTrue(compact.waitForExistence(timeout: 30), "The actual widget must render, not just an app fixture label. Allow a cold widget-extension launch.")
        attach(springboard, name: "Native compact Island - offline labelled fixture")
        compact.press(forDuration: 1.2)
        let unmute = springboard.buttons["Unmute"]
        XCTAssertTrue(unmute.waitForExistence(timeout: 15))
        attach(springboard, name: "Native expanded Island controls - offline labelled fixture")
        unmute.tap()
        app.activate()
        XCTAssertTrue(app.buttons["island.fixture.end"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["island.fixture.status"].waitForLabel("Fixture active", timeout: 5), "System Unmute must reach the app handler.")
        XCUIDevice.shared.press(.home)
        let activeCompact = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Test activity'")).firstMatch
        XCTAssertTrue(activeCompact.waitForExistence(timeout: 15))
        activeCompact.press(forDuration: 1.2)
        XCTAssertTrue(springboard.buttons["End"].waitForExistence(timeout: 8))
        springboard.buttons["End"].tap()
        app.activate()
        XCTAssertEqual(app.staticTexts["island.fixture.status"].label, "Fixture ended")
        XCTAssertTrue(count.waitForLabel("0 native activities", timeout: 5))
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForLabel(_ expected: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: self)], timeout: timeout) == .completed
    }
}
