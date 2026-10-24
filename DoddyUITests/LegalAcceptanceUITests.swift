import XCTest

/// "Before we start" (ADR-581): first use shows the Terms step before anything else; its box
/// starts unticked, Continue waits for it, both documents are reachable, and once accepted it
/// doesn't come back. NOT RUN where this was written (no Xcode); hosted CI runs it.
final class LegalAcceptanceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(store: UITestLaunch.Store, fresh: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: store, legalAccepted: false)
        // UserDefaults outlive a test: start without an acceptance an earlier test stored.
        if fresh { app.launchArguments += ["-resetLegalAcceptanceForUITests"] }
        app.launch()
        return app
    }

    @MainActor
    func testTheTermsStepComesFirstAndNeedsAnExplicitTick() {
        let app = launch(store: .inMemory)
        XCTAssertTrue(app.staticTexts["legal.title"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.links["legal.terms"].exists || app.buttons["legal.terms"].exists, "the Terms open from here")
        XCTAssertTrue(app.links["legal.privacy"].exists || app.buttons["legal.privacy"].exists, "the Privacy Policy opens from here")

        let agree = app.switches["legal.agree"].exists ? app.switches["legal.agree"] : app.buttons["legal.agree"]
        XCTAssertTrue(agree.exists)
        XCTAssertNotEqual(agree.value as? String, "Ticked", "never ticked in advance")
        let proceed = app.buttons["legal.continue"]
        XCTAssertTrue(proceed.exists)
        XCTAssertFalse(proceed.isEnabled, "Continue waits for the tick")
        let talk = app.buttons["home.talk"]
        XCTAssertFalse(talk.exists && talk.isHittable, "Home is behind the step")

        agree.tap()
        XCTAssertTrue(proceed.isEnabled)
        proceed.tap()
        XCTAssertTrue(app.staticTexts["legal.title"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnceAcceptedItStaysAcceptedAndSettingsShowsIt() {
        let id = UUID()
        var app = launch(store: .persistent(id))
        XCTAssertTrue(app.staticTexts["legal.title"].waitForExistence(timeout: 10))
        let agree = app.switches["legal.agree"].exists ? app.switches["legal.agree"] : app.buttons["legal.agree"]
        agree.tap()
        app.buttons["legal.continue"].tap()
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 5))
        app.terminate()

        app = launch(store: .persistent(id), fresh: false)
        XCTAssertTrue(app.buttons["home.talk"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["legal.title"].exists, "accepted once is enough until the terms change")
        app.goToTab("settings")
        XCTAssertTrue(app.reveal(app.descendants(matching: .any)["settings.terms"].firstMatch), "the Terms stay one tap away")
        XCTAssertTrue(app.reveal(app.descendants(matching: .any)["settings.privacyPolicy"].firstMatch))
        // When they were accepted is in Settings › Advanced (ADR-633).
        app.openSettingsPage("settings.advanced")
        XCTAssertTrue(app.reveal(app.descendants(matching: .any)["settings.termsAccepted"].firstMatch))
    }
}
