import XCTest

/// Motion v2, MV2 (docs/design/MOTION_V2_PLAN.md section 1): the surfaces Doddy stands on. With
/// `-doddyArtMarkers YES` each surface's top edge is an accessibility element named
/// `doddy.surface.<surface>`, so these tests check that a surface is there, and where. Doddy
/// doesn't move yet (MV3). In-memory store: each test is a fresh install.
final class MotionSurfaceTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(hideArt: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light")
            + ["-doddyArtMarkers", "YES", "-hideCharacterArt", hideArt ? "YES" : "NO"]
        app.launch()
        XCTAssertTrue(app.waitForTab("home", timeout: 10))
        return app
    }

    private func surface(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["doddy.surface.\(name)"]
    }

    @MainActor
    private func tapInSheet(_ button: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<6 where !button.isHittable { app.scrollStep() }
        button.tap()
    }

    /// Home's stage is a 140 pt line, centred, and the calm Home has no tab bar, so no rail
    /// (ADR-545); the rail is the tab bar's top edge on the screens that have the bar.
    @MainActor
    func testHomeHasA140PtStageAndNoRailAndTheTabBarIsTheRailElsewhere() {
        let app = launch()
        let stage = surface("stage", in: app)
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertEqual(stage.frame.width, 140, accuracy: 1)
        XCTAssertEqual(stage.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
        XCTAssertFalse(surface("rail", in: app).exists)
        app.goToTab("memories")
        let rail = surface("rail", in: app)
        XCTAssertTrue(rail.waitForExistence(timeout: 5))
        // The capsule's top edge: 8 pt above the tab buttons (Home and Settings since ADR-607).
        XCTAssertEqual(rail.frame.minY, app.buttons["tab.settings"].frame.minY - 8, accuracy: 3)
    }

    /// Q4: an empty Memories screen and Settings each have a still spot for him.
    @MainActor
    func testEmptyMemoriesAndSettingsHaveALedge() {
        let app = launch()
        app.goToTab("memories")
        XCTAssertTrue(app.descendants(matching: .any)["memories.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(surface("ledge.emptyMemories", in: app).exists)
        app.goToTab("settings")
        XCTAssertTrue(surface("ledge.settings", in: app).waitForExistence(timeout: 5))
    }

    /// "Hide Doddy's pictures": no surfaces at all, so no room is kept for him.
    @MainActor
    func testHidingThePicturesRemovesEverySurface() {
        let app = launch(hideArt: true)
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(surface("stage", in: app).exists)
        XCTAssertFalse(surface("rail", in: app).exists)
        app.goToTab("memories")
        XCTAssertTrue(app.descendants(matching: .any)["memories.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(surface("ledge.emptyMemories", in: app).exists)
    }

    /// A saved note's card is a rule (its top edge, full width); its page has his spot on the paper
    /// card; deleting it shows the undo bar, which is "the strip".
    @MainActor
    func testNoteCardIsARuleItsPageHasASpotAndTheUndoBarIsTheStrip() {
        let app = launch()
        app.buttons["home.save"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Synthetic blue kettle is on the top shelf.")
        if app.buttons["capture.keyboardDone"].exists { app.buttons["capture.keyboardDone"].tap() }
        // Inside the capture sheet `reveal` never succeeds: the tab bar under the sheet is still
        // in the hierarchy. Scroll the sheet until the button can be tapped instead.
        tapInSheet(app.buttons["capture.save"], app: app)
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 6))
        tapInSheet(app.buttons["capture.done"], app: app)

        app.goToTab("memories")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch
        XCTAssertTrue(app.reveal(card))
        let rule = surface("rule.0", in: app)
        XCTAssertTrue(rule.exists)
        XCTAssertEqual(rule.frame.minY, card.frame.minY, accuracy: 2)
        XCTAssertEqual(rule.frame.width, card.frame.width, accuracy: 2)

        card.tap()
        let text = app.staticTexts["detail.currentText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        let detail = surface("detail", in: app)
        XCTAssertTrue(detail.exists)
        // The paper card's top edge, above its text and wider than it.
        XCTAssertLessThan(detail.frame.minY, text.frame.minY)
        XCTAssertGreaterThan(detail.frame.maxX, text.frame.maxX)

        XCTAssertTrue(app.reveal(app.buttons["detail.delete"]))
        app.buttons["detail.delete"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["undoDelete"].waitForExistence(timeout: 5))
        let strip = surface("panel", in: app)
        XCTAssertTrue(strip.exists)
        XCTAssertLessThan(strip.frame.minY, app.buttons["undoDelete"].frame.minY)
        XCTAssertLessThan(strip.frame.minY, surface("rail", in: app).frame.minY)
    }

    /// Q2: Ask's composer is "the composer", a full-width edge above the field, with Send on it.
    @MainActor
    func testAskComposerIsASurface() {
        let app = launch()
        XCTAssertTrue(app.buttons["home.ask"].waitForExistence(timeout: 5))
        app.buttons["home.ask"].tap()
        let input = app.textFields["ask.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let composer = surface("composer", in: app)
        XCTAssertTrue(composer.exists)
        XCTAssertLessThan(composer.frame.minY, input.frame.minY)
        XCTAssertLessThan(composer.frame.minY, app.buttons["ask.send"].frame.minY)
        XCTAssertGreaterThan(composer.frame.width, input.frame.width)
    }
}
