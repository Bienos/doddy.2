import XCTest

final class MemoryBaselineTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSaveRestartFindAndDeleteRealNote() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .persistent(UUID()))
        app.launch()
        XCTAssertTrue(app.buttons["home.save"].appears(timeout: 8))
        app.openNewNote()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.appears(timeout: 5))
        let text = "Synthetic amber notebook is in the green drawer."
        editor.tap()
        editor.typeText(text)
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].appears(timeout: 5))
        attach(app, name: "Native confirmed save - synthetic data")
        app.buttons["capture.done"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.waitForTab("memories", timeout: 8))
        app.goToTab("memories")
        app.buttons["memories.find"].tap()
        let search = app.textFields["memories.query"]
        XCTAssertTrue(search.appears(timeout: 5))
        search.tap()
        search.typeText("amber")
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(hit.appears(timeout: 5), "A real persisted record must survive process restart.")
        attach(app, name: "Native recall after restart - synthetic data")
        hit.tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].appears(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, text)
        let delete = app.buttons["detail.delete"]
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["memories.noMatch"].appears(timeout: 5))
        app.terminate()
        app.launch()
        app.goToTab("memories")
        XCTAssertTrue(app.text("No memories yet").appears(timeout: 5))
    }

    @MainActor
    func testNativeIslandOfflineFixtureCanStartMuteAndEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory) + ["-islandBaseline"]
        app.launch()
        XCTAssertTrue(app.buttons["island.fixture.start"].appears(timeout: 8))
        let enabled = app.staticTexts["island.fixture.activitiesEnabled"]
        XCTAssertTrue(enabled.appears(timeout: 5))
        if enabled.label != "Live Activities on" {
            throw XCTSkip("Live Activities are off on this simulator; no Dynamic Island proof claimed.")
        }
        app.buttons["island.fixture.start"].tap()
        XCTAssertEqual(app.staticTexts["island.fixture.status"].label, "Fixture active")
        let count = app.staticTexts["island.fixture.nativeCount"]
        XCTAssertTrue(count.appears(timeout: 5))
        XCTAssertTrue(count.waitForLabel("1 native activities", timeout: 5))
        app.buttons["island.fixture.mute"].tap()
        XCTAssertEqual(app.staticTexts["island.fixture.status"].label, "Fixture muted")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // SpringBoard exposes the compact surface as Other, not StaticText. Use its
        // actual accessibility frame: SpringBoard also has pixel-sized overlay windows,
        // so normalizing a coordinate against the entire application is unreliable.
        let compact = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Test muted'")).firstMatch
        XCTAssertTrue(compact.appears(timeout: 30), "The actual widget must render, not just an app fixture label. Allow a cold widget-extension launch.")
        attach(springboard, name: "Native compact Island - offline labelled fixture")
        compact.press(forDuration: 1.2)
        let unmute = springboard.buttons["Unmute"]
        XCTAssertTrue(unmute.appears(timeout: 15))
        attach(springboard, name: "Native expanded Island controls - offline labelled fixture")
        unmute.tap()
        // Let the island settle before the app comes forward, so the system's island change and the
        // app's activation don't animate at once (ADR-764). Twice on CI the simulator's drawing froze
        // at that moment (2 Nov after Unmute, 7 Nov after Stop): backboardd waited on a GPU command
        // that never finished, and the tap never reached the app. That overlap is a guess, not a
        // proven cause, so this wait asserts nothing; the checks below are unchanged.
        _ = unmute.waitUntilGone(timeout: 5)
        app.activate()
        XCTAssertTrue(app.buttons["island.fixture.end"].appears(timeout: 5))
        // The system button reaches the app's handler a few seconds later, as with Stop below
        // (20a6e031): 5 s was too short once on CI (run 39147513810, 18 Oct). The 10 s failures
        // of 1 and 2 Nov (runs 41341166440, 41368047283) were not slowness but the frozen
        // simulator above (ADR-764), which no wait fixes. 20 s, the same check.
        XCTAssertTrue(app.staticTexts["island.fixture.status"].waitForLabel("Fixture active", timeout: 20), "System Unmute must reach the app handler.")
        XCUIDevice.shared.press(.home)
        let activeCompact = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Test activity'")).firstMatch
        XCTAssertTrue(activeCompact.appears(timeout: 15))
        // Unmuted: Doddy's head on the compact island, all of him on the expanded one (ADR-615).
        attach(springboard, name: "Native compact Island, not muted - offline labelled fixture")
        activeCompact.press(forDuration: 1.2)
        // The island's end control is labelled "Stop" ("Stop listening" in Hey Doddy mode).
        let stop = springboard.buttons["Stop"]
        XCTAssertTrue(stop.appears(timeout: 8))
        attach(springboard, name: "Native expanded Island, not muted - offline labelled fixture")
        stop.tap()
        // As after Unmute: the island settles first (ADR-764).
        _ = stop.waitUntilGone(timeout: 5)
        app.activate()
        // Like Unmute above, the system button reaches the app's handler a few seconds later (20 s).
        XCTAssertTrue(app.staticTexts["island.fixture.status"].waitForLabel("Fixture ended", timeout: 20), "System Stop must reach the app handler.")
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
    /// Polled (`pollUntil`, UITestLaunch.swift) instead of an XCTNSPredicateExpectation, which looks first
    /// only after about a second. `label` is read only once the element exists: reading it on a missing
    /// element fails the test.
    @MainActor
    func waitForLabel(_ expected: String, timeout: TimeInterval) -> Bool {
        pollUntil(timeout: timeout) { exists && label == expected }
    }

    /// True once the element is gone, false if it is still there after `timeout`.
    @MainActor
    func waitUntilGone(timeout: TimeInterval) -> Bool {
        pollUntil(timeout: timeout) { !exists }
    }
}
