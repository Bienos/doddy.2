import XCTest

/// Motion v2, MV4 (docs/design/MOTION_V2_PLAN.md section 6): he rides what moves. Checked through
/// the UI-test markers (`-doddyArtMarkers YES`) and the DEBUG checks' count in the annotated mode
/// (`-doddyMotionDebug YES`). The simulator runs at 60 Hz and without a ProMotion screen or a
/// real keyboard animation: 120 Hz riding and interactive keyboard dismissal are device checks
/// (NOT RUN here). In-memory store; the notes are typed in through Capture, like a person would.
final class MotionRideTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light")
            + ["-doddyArtMarkers", "YES", "-doddyQuietIdle", "YES", "-hideCharacterArt", "NO", "-doddyMotionDebug", "YES"]
        app.launch()
        XCTAssertTrue(app.waitForTab("home", timeout: 10))
        return app
    }

    private func surface(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.marker("doddy.surface.\(name)")
    }

    private func drawings(in app: XCUIApplication) -> XCUIElementQuery {
        app.markers(startingWith: ["doddy.motion.", "doddy.pose."])
    }

    private func checksCount(in app: XCUIApplication) -> String {
        app.staticTexts["doddy.debug"].label.components(separatedBy: "checks ").last ?? "?"
    }

    /// The surface whose top edge his drawing's bottom edge is on (±2 pt), if any.
    @MainActor
    private func surfaceUnderHim(in app: XCUIApplication, timeout: TimeInterval = 6) -> String? {
        let him = app.marker("doddy.motion.idle")
        let edges = app.markers(startingWith: ["doddy.surface."])
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if him.exists {
                let soles = him.frame.maxY
                for i in 0..<edges.count {
                    let edge = edges.element(boundBy: i)
                    if abs(edge.frame.minY - soles) <= 2, edge.frame.minX <= him.frame.midX, edge.frame.maxX >= him.frame.midX {
                        return edge.label.replacingOccurrences(of: "doddy.surface.", with: "")
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    @MainActor
    private func saveNote(_ text: String, in app: XCUIApplication) {
        // Home has no tab bar (ADR-545): from Home there is nothing to tap.
        if app.buttons["tab.home"].exists { app.buttons["tab.home"].tap() }
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        app.buttons["home.save"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tapAndType(text)
        if app.buttons["capture.keyboardDone"].exists { app.buttons["capture.keyboardDone"].tap() }
        tapInSheet(app.buttons["capture.save"], app: app)
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 6))
        tapInSheet(app.buttons["capture.done"], app: app)
    }

    /// Inside the capture sheet `reveal` never succeeds (the tab bar under the sheet is still in
    /// the hierarchy): scroll the sheet until the button can be tapped.
    @MainActor
    private func tapInSheet(_ button: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<6 where !button.isHittable { app.scrollStep() }
        button.tap()
    }

    /// Ask (Q2): he comes up with its cover and stands on the composer, clear of Send; closing it
    /// he is back on Home's stage. One Doddy throughout, and the DEBUG checks stay clean.
    @MainActor
    func testInAskHeStandsOnTheComposerAndIsBackOnTheStageAfter() {
        let app = launch()
        XCTAssertEqual(surfaceUnderHim(in: app), "stage")
        app.buttons["home.ask"].tap()
        let input = app.textFields["ask.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(surfaceUnderHim(in: app), "composer")
        let him = app.marker("doddy.motion.idle")
        // His 48 pt clear zone ends at least 24 pt before Send (brief rule 8).
        XCTAssertLessThanOrEqual(him.frame.midX + 24 + 24, app.buttons["ask.send"].frame.minX + 1)
        XCTAssertEqual(drawings(in: app).count, 1)
        // Typing: the composer (and the keyboard, when the simulator shows one) carry him.
        input.tap()
        input.typeText("Synthetic question")
        XCTAssertEqual(surfaceUnderHim(in: app), "composer")
        app.navigationBars.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["home.ask"].waitForExistence(timeout: 5))
        XCTAssertEqual(surfaceUnderHim(in: app), "stage")
        XCTAssertEqual(drawings(in: app).count, 1)
        XCTAssertEqual(checksCount(in: app), "0", motionDebugReport(in: app))
    }

    /// Memories: he stands on a card, a page pushed over it covers him where he stands, and Back
    /// reveals him on the same card. Scrolling the list, he rides his card or waits on the rail,
    /// and once it settles he is on a card again: one Doddy, DEBUG checks clean.
    @MainActor
    func testHeRidesTheMemoriesListAndAPageCoversHimInPlace() {
        let app = launch()
        for i in 1...6 { saveNote("Synthetic note number \(i) for the riding test.", in: app) }
        app.goToTab("memories")
        let spot = try? XCTUnwrap(surfaceUnderHim(in: app))
        XCTAssertTrue(spot?.hasPrefix("rule.") == true, "on a card: \(spot ?? "nowhere")")
        // A note's page covers him in place.
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.open.'")).firstMatch
        card.tap()
        XCTAssertTrue(app.staticTexts["detail.currentText"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(drawings(in: app).count, 0, "covered by the page, not hopping onto it")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(surfaceUnderHim(in: app), spot, "revealed where he stood")
        // Scroll down and back up.
        app.swipeUp(velocity: .slow)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let after = surfaceUnderHim(in: app)
        XCTAssertTrue(after?.hasPrefix("rule.") == true || after == "rail", "on a card or the rail: \(after ?? "nowhere")")
        app.swipeDown(velocity: .fast)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertLessThanOrEqual(drawings(in: app).count, 1)
        XCTAssertEqual(checksCount(in: app), "0", motionDebugReport(in: app))
    }

    /// Calm mode: tabs tapped faster than he could hop. He waits, then makes one hop to where you
    /// stopped; the DEBUG checks stay clean.
    @MainActor
    func testRapidTabTapsEndWithHimOnTheLastScreensSpot() {
        let app = launch()
        XCTAssertEqual(surfaceUnderHim(in: app), "stage")
        for tab in ["memories", "settings", "home", "memories", "settings"] {
            app.openTab(tab)
        }
        XCTAssertEqual(surfaceUnderHim(in: app, timeout: 8), "ledge.settings")
        XCTAssertEqual(drawings(in: app).count, 1)
        XCTAssertEqual(checksCount(in: app), "0", motionDebugReport(in: app))
    }
}
