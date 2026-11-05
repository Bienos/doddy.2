import XCTest

/// Motion v2, MV5 (docs/design/MOTION_V2_PLAN.md section 6): the behaviours the pack can draw and
/// the app's real state can drive, checked through the UI-test markers (`-doddyArtMarkers YES`).
/// Timing, the breaths, the welcome, thinking and the listening pose are checked frame by frame in
/// DoddyCore (MotionBehaviourTests); these check what the simulator shows. Haptics and how a
/// touch feels are device checks (NOT RUN here). In-memory store.
final class MotionBehaviourUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light")
            + ["-doddyArtMarkers", "YES", "-hideCharacterArt", "NO", "-doddyMotionDebug", "YES"]
        app.launch()
        XCTAssertTrue(app.waitForTab("home", timeout: 10))
        return app
    }

    private func drawings(in app: XCUIApplication) -> XCUIElementQuery {
        app.markers(startingWith: ["doddy.motion.", "doddy.pose."])
    }

    /// A tap on him on Home talks, as Home's Talk button does (Q2). With no voice account in the
    /// simulator the conversation can't start on Home (ADR-595), so the transcript sheet opens on
    /// its sign-in gate, full height, and hides him (it keeps its own Doddy).
    @MainActor
    func testATapOnHimOpensTheVoiceScreen() {
        let app = launch()
        let him = app.marker("doddy.motion.idle")
        XCTAssertTrue(him.waitForExistence(timeout: 8))
        let soles = CGPoint(x: him.frame.midX, y: him.frame.maxY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: soles.x, dy: soles.y - 60)).tap()
        let end = Date().addingTimeInterval(5)
        while Date() < end, app.buttons["home.talk"].isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(app.buttons["home.talk"].isHittable, "the voice screen is over Home")
        XCTAssertFalse(app.marker("doddy.motion.idle").exists, "and hides him")
    }

    /// Left alone on Home he sits down cross-legged on his stage (brief: at 15 s idle), and he is
    /// the only Doddy there.
    @MainActor
    func testLeftAloneOnHomeHeSitsCrossLeggedOnTheStage() {
        let app = launch()
        let stage = app.marker("doddy.surface.stage")
        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        let sitting = app.marker("doddy.pose.crosslegged")
        XCTAssertTrue(sitting.waitForExistence(timeout: 30))
        XCTAssertEqual(sitting.frame.maxY, stage.frame.minY, accuracy: 2)
        XCTAssertEqual(drawings(in: app).count, 1)
        let label = app.staticTexts["doddy.debug"].label
        XCTAssertTrue(label.hasSuffix("checks 0"), label)
    }
}
