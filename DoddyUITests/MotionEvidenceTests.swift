import XCTest

/// Motion v2, MV6 evidence (docs/design/MOTION_V2_PLAN.md section 6): the accessibility rules on
/// the simulator. Reduce Motion (fades, never a flight), "Hide Doddy's pictures" (no Doddy and no
/// gap where he was), VoiceOver (nothing of him in the accessibility tree; Home's "Talk to Doddy"
/// stays the way to talk) and accessibility text sizes (1.0× on Home, Q12). A test can't turn on
/// the system's Reduce Motion or VoiceOver: the first uses the DEBUG switch `-doddyReduceMotion`,
/// the second checks the tree VoiceOver reads. Both with the real settings are device checks
/// (docs/design/MOTION_V2_DEVICE_CHECKLIST.md). In-memory store.
final class MotionEvidenceTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(markers: Bool = true, debug: Bool? = nil, hideArt: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light")
            + ["-hideCharacterArt", hideArt ? "YES" : "NO"] + extra
        if markers { app.launchArguments += ["-doddyArtMarkers", "YES", "-doddyQuietIdle", "YES"] }
        // The annotated mode's texts are named `doddy.debug…`: on with the markers, unless a test says no.
        if debug ?? markers { app.launchArguments += ["-doddyMotionDebug", "YES"] }
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    private func everythingOfHim(in app: XCUIApplication) -> XCUIElementQuery {
        app.markers(startingWith: ["doddy."])
    }

    private func debugValue(_ name: String, in app: XCUIApplication) -> Int? {
        let label = app.staticTexts["doddy.debug"].label
        guard let range = label.range(of: "\(name) ") else { return nil }
        return Int(label[range.upperBound...].prefix { $0.isNumber })
    }

    /// Reduce Motion: every move is a fade, never a flight; he still ends on each screen's spot.
    @MainActor
    func testWithReduceMotionHeFadesAndNeverFlies() {
        let app = launch(extra: ["-doddyReduceMotion", "YES"])
        XCTAssertTrue(app.staticTexts["doddy.debug"].waitForExistence(timeout: 5))
        for tab in ["settings", "memories", "home", "settings", "home"] {
            app.buttons["tab.\(tab)"].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let stage = app.marker("doddy.surface.stage")
        let him = app.marker("doddy.motion.idle")
        XCTAssertTrue(him.waitForExistence(timeout: 5))
        XCTAssertEqual(him.frame.maxY, stage.frame.minY, accuracy: 2)
        XCTAssertEqual(debugValue("flights", in: app), 0, motionDebugReport(in: app))
        XCTAssertEqual(debugValue("checks", in: app), 0, motionDebugReport(in: app))
    }

    /// "Hide Doddy's pictures": no Doddy, and no room kept for him where he would stand.
    @MainActor
    func testHiddenPicturesLeaveNoGap() {
        // Without the annotated mode: its texts are named `doddy.debug…` too.
        let app = launch(debug: false, hideArt: true)
        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(everythingOfHim(in: app).count, 0)
        // Settings: the privacy line starts at the row's edge, not after a 73 pt box.
        app.buttons["tab.settings"].tap()
        let privacy = app.staticTexts["You choose each saved memory. See the original, edit it or remove it."]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        XCTAssertLessThan(privacy.frame.minX, 60)
        // Memories: the empty notebook's heading follows the picker, not a 150 pt box.
        app.buttons["tab.memories"].tap()
        let heading = app.staticTexts["No memories yet"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        let picker = app.segmentedControls["memories.notesOrLists"]
        XCTAssertLessThan(heading.frame.minY - picker.frame.maxY, 90)
        XCTAssertEqual(everythingOfHim(in: app).count, 0)
    }

    /// VoiceOver: he is decorative. Nothing of him is in the accessibility tree (no drawing, no
    /// touch area), on any tab, and Home's "Talk to Doddy" is the way to talk.
    @MainActor
    func testVoiceOverReadsNothingOfHim() {
        let app = launch(markers: false)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(everythingOfHim(in: app).count, 0)
        for tab in ["memories", "settings", "home"] {
            app.buttons["tab.\(tab)"].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            XCTAssertEqual(everythingOfHim(in: app).count, 0, "on \(tab)")
        }
    }

    /// Accessibility text sizes (Q12): on Home he stays 1.0×, standing on his stage.
    @MainActor
    func testAtAccessibilityTextSizesHeIsOneTimesOnHome() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let him = app.marker("doddy.motion.idle")
        XCTAssertTrue(him.waitForExistence(timeout: 8))
        let stage = app.marker("doddy.surface.stage")
        XCTAssertEqual(him.frame.maxY, stage.frame.minY, accuracy: 2)
        XCTAssertEqual(him.frame.height, 96 / 0.72 * 0.94, accuracy: 3, "1.0×, not 1.4×")
    }
}
