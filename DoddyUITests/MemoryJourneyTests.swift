import XCTest

final class MemoryJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(appearance: String = "light", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .persistent(UUID()), appearance: appearance)
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testApprovedJourneyCorrectionRetainsOriginalAfterRestart() {
        let app = launch()
        app.buttons["home.save"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let original = "Synthetic violet umbrella is in the hallway."
        editor.tap(); editor.typeText(original)
        dismissKeyboard(app)
        scrollTo(app.buttons["capture.save"], app: app)
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 6))
        screenshot(app, "Approved native save receipt")
        scrollTo(app.buttons["capture.viewNote"], app: app)
        app.buttons["capture.viewNote"].tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, original)
        app.navigationBars.buttons["Back"].tap()
        scrollTo(app.buttons["capture.done"], app: app)
        app.buttons["capture.done"].tap()
        app.buttons["tab.memories"].tap()
        let savedCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch
        // The notes are a lazy stack below the heading, scenery, Find and the picker.
        scrollTo(savedCard, app: app)
        XCTAssertTrue(savedCard.exists); savedCard.tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, original)
        app.navigationBars.buttons["Back"].tap()
        app.buttons["tab.home"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.find"].waitForExistence(timeout: 8))
        app.buttons["home.find"].tap()
        let query = app.textFields["memories.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("violet\n")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.' AND label CONTAINS %@", original)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 6))
        screenshot(app, "Approved native source-linked recall")
        result.tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, original)
        scrollTo(app.buttons["detail.edit"], app: app)
        app.buttons["detail.edit"].tap()
        let correction = app.textViews.firstMatch
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
        correction.tap()
        // TextEditor may put the caret at the start; explicitly select the native
        // text rather than assuming the tap placed it after the last character.
        correction.press(forDuration: 1.2)
        let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Select All'")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), app.debugDescription)
        selectAll.tap()
        correction.typeText(XCUIKeyboardKey.delete.rawValue + "Synthetic violet umbrella is by the door.")
        app.buttons["correction.save"].tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, "Synthetic violet umbrella is by the door.")
        scrollTo(app.buttons["Original capture"], app: app)
        app.buttons["Original capture"].tap()
        XCTAssertTrue(app.staticTexts["detail.originalText"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["detail.originalText"].label, original)
        screenshot(app, "Native correction with original provenance")
        app.terminate(); app.launch()
        app.buttons["home.find"].tap()
        let reopened = app.textFields["memories.query"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        reopened.tap(); reopened.typeText("violet\n")
        let edited = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 5)); edited.tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.currentText"].label, "Synthetic violet umbrella is by the door.")
        scrollTo(app.buttons["detail.delete"], app: app)
        app.buttons["detail.delete"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["memories.noMatch"].waitForExistence(timeout: 6))
        app.terminate(); app.launch(); app.buttons["tab.memories"].tap()
        XCTAssertTrue(app.text("No memories yet").waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptySaveShowsErrorAndKeepsEditor() {
        let app = launch()
        app.buttons["home.save"].tap()
        XCTAssertTrue(app.buttons["capture.save"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["capture.save"], app: app); app.buttons["capture.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["capture.saved"].exists)
        XCTAssertTrue(app.textViews.firstMatch.exists)
    }

    @MainActor
    func testDarkLargestTextKeepsTextRoutesUsable() {
        let app = launch(appearance: "dark", largeText: true)
        scrollTo(app.buttons["home.save"], app: app)
        XCTAssertTrue(app.buttons["home.save"].isHittable)
        screenshot(app, "Native dark accessibility text")
        app.buttons["home.save"].tap()
        XCTAssertTrue(app.buttons["capture.save"].waitForExistence(timeout: 5), app.debugDescription)
        scrollTo(app.buttons["capture.save"], app: app)
        XCTAssertTrue(app.buttons["capture.save"].isHittable)
        screenshot(app, "Native dark accessibility capture")
        app.buttons["Cancel"].tap()
        app.buttons["tab.memories"].tap()
        XCTAssertTrue(app.text("No memories yet").waitForExistence(timeout: 5))
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        // The keyboard's Done button comes with the on-screen keyboard, which on a busy CI
        // simulator can be a moment after typing: wait for it instead of checking once. The old
        // fallback, a swipe, then scroll drags that start low on the screen, can land on the
        // keyboard and type: three CI runs on PR #89 saved the note with a stray space that way.
        let done = app.buttons["capture.keyboardDone"]
        if done.waitForExistence(timeout: 5) { done.tap(); return }
        // A hardware keyboard covers nothing; an on-screen keyboard without Done is a real fault.
        guard app.keyboards.count > 0 else { return }
        XCTFail("The capture keyboard has no Done button. \(app.debugDescription)")
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        // Home at the largest text size is many screens tall.
        var lastMinY: CGFloat?
        for _ in 0..<40 {
            let bar = app.buttons["tab.home"]
            let bottom = bar.exists ? bar.frame.minY - 8 : app.frame.maxY - 40
            let frame: CGRect? = element.exists ? element.frame : nil
            if let frame, element.isHittable {
                if frame.maxY < bottom && frame.minY > 90 { return }
                // Tappable, and the last step didn't move it: the page can't scroll it any
                // further (a pinned button, or the end of the page). Without this the loop ran
                // all 40 steps, about 2 minutes each time on CI (ADR-499), and then the tap
                // worked anyway.
                if let lastMinY, abs(frame.minY - lastMinY) < 1 { return }
            }
            lastMinY = frame?.minY
            app.scrollStep()
        }
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
