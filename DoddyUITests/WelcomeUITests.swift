import XCTest

/// The first-launch welcome (ADR-595). NOT RUN in the authoring environment (no Xcode): the hosted
/// Mac CI is the first run. The sign-in is UI only, so these tests check what the buttons say and
/// that "Try Doddy without an account" is the only way on.
final class WelcomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(extra: [String] = [], welcome: Bool = true, onboardingDone: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(
            store: .inMemory, onboardingDone: onboardingDone, welcome: welcome) + ["-quickStartOffered", "NO"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func swipeToNextChapter(_ app: XCUIApplication) {
        let pager = app.scrollViews["welcome.pager"]
        pager.swipeLeft()
    }

    @MainActor
    func testFiveChaptersSwipeRightToLeftAndSkipJumpsToTheLast() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["welcome.chapter.0"].waitForExistence(timeout: 8), "the welcome shows on a new installation")
        XCTAssertTrue(app.buttons["welcome.getIn"].exists)
        for chapter in 1...4 {
            swipeToNextChapter(app)
            XCTAssertTrue(app.descendants(matching: .any)["welcome.chapter.\(chapter)"].waitForExistence(timeout: 5), "chapter \(chapter)")
        }
        XCTAssertFalse(app.buttons["welcome.skip"].exists, "Skip is gone on the last chapter")
    }

    @MainActor
    func testSkipGoesToTheLastChapter() {
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.skip"].waitForExistence(timeout: 8))
        app.buttons["welcome.skip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["welcome.chapter.4"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSignInOptionsSaySoAndOnlyTheNoAccountButtonMovesOn() {
        let app = launch()
        XCTAssertTrue(app.buttons["welcome.getIn"].waitForExistence(timeout: 8))
        app.buttons["welcome.getIn"].tap()
        XCTAssertTrue(app.buttons["welcome.faceID"].waitForExistence(timeout: 5))
        // Apple's system button, first, the same size as the others. Not tapped: it opens Apple's sheet.
        XCTAssertTrue(app.buttons["welcome.apple"].exists)
        XCTAssertEqual(app.buttons["welcome.apple"].frame.height, app.buttons["welcome.google"].frame.height, accuracy: 1,
                       "Apple's button is no smaller than the others")
        XCTAssertTrue(app.buttons["welcome.google"].exists)
        XCTAssertTrue(app.buttons["welcome.email"].exists)

        app.buttons["welcome.google"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["welcome.notConnected"].waitForExistence(timeout: 5),
                      "an unconnected sign-in says so and never looks like success")
        XCTAssertTrue(app.buttons["welcome.withoutAccount"].exists, "the sheet stays open")
        XCTAssertTrue(app.descendants(matching: .any)["welcome.root"].exists, "still on the welcome")

        app.buttons["welcome.withoutAccount"].tap()
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 8), "Home is next")
        XCTAssertFalse(app.descendants(matching: .any)["welcome.root"].exists)
    }

    @MainActor
    func testItDoesNotShowWhenSkippedByTheLaunchArgument() {
        let app = launch(welcome: false)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["welcome.root"].exists)
    }

    @MainActor
    func testReduceMotionStillShowsEveryChapterAndTheSheet() {
        let app = launch(extra: ["-UIAccessibilityReduceMotionEnabled", "YES"])
        XCTAssertTrue(app.descendants(matching: .any)["welcome.chapter.0"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["welcome.getIn"].exists)
    }

    @MainActor
    func testLargestTextStillReachesTheSheetAndTheTitle() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.descendants(matching: .any)["welcome.chapter.0"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["welcome.getIn"].exists)
    }
}
