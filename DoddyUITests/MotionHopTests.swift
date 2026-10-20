import XCTest

/// Motion v2, MV3 (docs/design/MOTION_V2_PLAN.md section 6): one Doddy, hopping between the tabs.
/// With `-doddyArtMarkers YES` his drawing is one element named for the picture it shows
/// (`doddy.motion.idle`, `doddy.motion.jump`, `doddy.pose.crosslegged`), and each surface's top
/// edge is `doddy.surface.<surface>`, so these tests check that there is one of him, where his
/// soles are, and that sheets and "Hide Doddy's pictures" hide him. The simulator runs at 60 Hz:
/// 120 Hz and the hand-off at it are device checks (NOT RUN here). In-memory store.
final class MotionHopTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(hideArt: Bool = false, debug: Bool = false, lists: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = UITestLaunch.arguments(store: .inMemory, appearance: "light")
        // `-memoriesShowsLists NO` is an argument-domain value: it wins over what the picker
        // writes, so Lists would flip straight back to Notes. A test that opens Lists drops it.
        if lists, let i = arguments.firstIndex(of: "-memoriesShowsLists") { arguments.removeSubrange(i...(i + 1)) }
        app.launchArguments = arguments + ["-doddyArtMarkers", "YES", "-doddyQuietIdle", "YES", "-hideCharacterArt", hideArt ? "YES" : "NO"]
        if debug { app.launchArguments += ["-doddyMotionDebug", "YES"] }
        app.launch()
        XCTAssertTrue(app.waitForTab("home", timeout: 10))
        return app
    }

    private func surface(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.marker("doddy.surface.\(name)")
    }

    /// Every drawing of him: the persistent Doddy and any picture of him still on screen.
    private func drawings(in app: XCUIApplication) -> XCUIElementQuery {
        app.markers(startingWith: ["doddy.motion.", "doddy.pose."])
    }

    /// There is exactly one drawing of him within `timeout` (a single frame of two or none is the
    /// DEBUG checks' business; two that stay, or none, is this test's). Says what is on screen,
    /// how the count moved while waiting, what the annotated mode said, and the tree; keeps a
    /// screenshot.
    @MainActor
    private func assertOneDoddy(in app: XCUIApplication, timeout: TimeInterval = 3,
                                file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(timeout)
        var counts: [Int] = []
        while Date() < end {
            let n = drawings(in: app).count
            counts.append(n)
            if n == 1 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let count = drawings(in: app).count
        guard count != 1 else { return }
        let all = app.markers(startingWith: ["doddy."])
        let seen = (0..<all.count).map { "\(all.element(boundBy: $0).label) \(all.element(boundBy: $0).frame)" }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        XCTFail("\(count) drawings, not 1. On screen: \(seen). Counts while waiting: \(counts). "
                + "Annotated: \(motionDebugReport(in: app)). Tree: \(motionTreeReport(of: app))", file: file, line: line)
    }

    /// Waits until he stands still on `surfaceName` (his drawing's bottom edge on its top edge,
    /// ±2 pt) showing `picture`, and returns his drawing.
    @MainActor
    @discardableResult
    private func waitUntilHeStands(on surfaceName: String, as picture: String = "doddy.motion.idle",
                                   in app: XCUIApplication, timeout: TimeInterval = 6,
                                   file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let edge = surface(surfaceName, in: app)
        let him = app.marker(picture)
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if edge.exists, him.exists, abs(him.frame.maxY - edge.frame.minY) <= 2 { return him }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("He didn't come to stand on \(surfaceName) as \(picture) (edge exists: \(edge.exists), "
                + "drawing exists: \(him.exists), drawing \(him.exists ? "\(him.frame)" : "-"), "
                + "edge \(edge.exists ? "\(edge.frame)" : "-"))", file: file, line: line)
        return him
    }

    /// Home: one Doddy, standing on the stage line, centred, drawn at 1.4×.
    @MainActor
    func testHomeHasOneDoddyStandingOnTheStage() {
        let app = launch()
        let him = waitUntilHeStands(on: "stage", in: app)
        XCTAssertEqual(him.frame.midX, surface("stage", in: app).frame.midX, accuracy: 2)
        // 1.4× of the 133 pt picture, cut at its ground (94 % of the strip): about 175 pt tall.
        XCTAssertEqual(him.frame.height, 96 / 0.72 * 1.4 * 0.94, accuracy: 3)
        assertOneDoddy(in: app)
    }

    /// The owner, 20 Oct: away from Doddy and back, he came back with a hop to about 36 pt right
    /// of the middle. Away and back twice: each time he stands in the middle of the stage. (Whether
    /// the simulator lays the app out at another size while it is away, as an iPhone can, isn't
    /// known; the rotation test below moves the stage sideways for certain.)
    @MainActor
    func testBackFromTheBackgroundHeStandsInTheMiddleOfTheStage() {
        let app = launch(debug: true)
        waitUntilHeStands(on: "stage", in: app)
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            app.activate()
            XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
            // Long enough for a hop he mustn't make to start and land.
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            let him = waitUntilHeStands(on: "stage", in: app)
            XCTAssertEqual(him.frame.midX, surface("stage", in: app).frame.midX, accuracy: 2, motionDebugReport(in: app))
        }
        assertOneDoddy(in: app)
    }

    /// Sideways and back on Home: the stage's centre moves and he goes with it (MotionHost's
    /// `surfaceMoved`). Before, his spot stayed at its old window x and the clear-zone shuffle
    /// hopped him to the end of the stage's stand range, 36 pt off the middle.
    @MainActor
    func testTurningThePhoneSidewaysAndBackKeepsHimInTheMiddle() {
        let app = launch(debug: true)
        waitUntilHeStands(on: "stage", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        // Upright again before anything can fail, so a failure never leaves the simulator sideways.
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let him = waitUntilHeStands(on: "stage", in: app)
        XCTAssertEqual(him.frame.midX, surface("stage", in: app).frame.midX, accuracy: 2, motionDebugReport(in: app))
        let trail = app.staticTexts["doddy.debug.trail"]
        if trail.exists { XCTAssertFalse(trail.label.contains("clear zone"), motionDebugReport(in: app)) }
        assertOneDoddy(in: app)
    }

    /// A tab tap takes him to the new screen's spot; he is never drawn twice on the way.
    @MainActor
    func testTabTapsTakeHimToEachScreensSpot() {
        let app = launch(debug: true)
        waitUntilHeStands(on: "stage", in: app)
        app.goToTab("settings")
        let him = waitUntilHeStands(on: "ledge.settings", in: app)
        // 1.0× off Home.
        XCTAssertEqual(him.frame.height, 96 / 0.72 * 0.94, accuracy: 3)
        assertOneDoddy(in: app)
        app.goToTab("memories")
        XCTAssertTrue(app.descendants(matching: .any)["memories.empty"].waitForExistence(timeout: 5))
        // The empty notebook: he sits cross-legged on its spot, in place of the old picture.
        waitUntilHeStands(on: "ledge.emptyMemories", as: "doddy.pose.crosslegged", in: app)
        assertOneDoddy(in: app)
        app.buttons["tab.home"].tap()
        waitUntilHeStands(on: "stage", in: app)
        assertOneDoddy(in: app)
    }

    /// A sheet hides him while it is up; he is back where he stood when it has gone.
    @MainActor
    func testASheetHidesHimAndHeIsBackAfter() {
        let app = launch()
        waitUntilHeStands(on: "stage", in: app)
        app.buttons["home.save"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.marker("doddy.motion.idle").exists, "hidden under the sheet")
        // Nothing typed: Cancel closes the sheet.
        app.navigationBars.buttons["Cancel"].tap()
        waitUntilHeStands(on: "stage", in: app)
    }

    /// "Hide Doddy's pictures": no Doddy anywhere, and no spot kept for him.
    @MainActor
    func testHidingThePicturesHidesHimEverywhere() {
        let app = launch(hideArt: true)
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(drawings(in: app).count, 0)
        app.goToTab("memories")
        XCTAssertTrue(app.descendants(matching: .any)["memories.empty"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(drawings(in: app).count, 0)
    }

    /// No lists yet: he waits cross-legged on the Lists spot (ADR-313), the only Doddy there.
    @MainActor
    func testEmptyListsHeSitsOnTheirSpot() {
        let app = launch(debug: true, lists: true)
        app.goToTab("memories")
        let picker = app.segmentedControls["memories.notesOrLists"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Lists"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lists.empty"].waitForExistence(timeout: 5))
        waitUntilHeStands(on: "ledge.emptyLists", as: "doddy.pose.crosslegged", in: app)
        assertOneDoddy(in: app)
    }

    /// Find with nothing found: he comes out and shrugs on Find's spot (Q4), the only Doddy.
    @MainActor
    func testFindWithNothingFoundHeShrugsThere() {
        let app = launch()
        app.tapHomeMenuItem("home.find")
        let query = app.textFields["memories.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("zzqx nothing like this\n")
        XCTAssertTrue(app.staticTexts["memories.noMatch"].waitForExistence(timeout: 6))
        waitUntilHeStands(on: "ledge.find", as: "doddy.pose.shrug", in: app)
        assertOneDoddy(in: app)
    }

    /// DEBUG annotated mode: across tab hops the DEBUG checks (one Doddy, soles on the surface,
    /// size only in the air, clear zones) find nothing.
    @MainActor
    func testDebugChecksFindNothingAcrossTabHops() {
        let app = launch(debug: true)
        let debug = app.staticTexts["doddy.debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 5))
        waitUntilHeStands(on: "stage", in: app)
        for tab in ["memories", "settings", "home", "settings", "memories", "home"] {
            app.openTab(tab)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        waitUntilHeStands(on: "stage", in: app)
        XCTAssertTrue(debug.label.hasSuffix("checks 0"), motionDebugReport(in: app))
    }
}
