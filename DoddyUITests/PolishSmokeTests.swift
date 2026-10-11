import XCTest

/// The app in Polish (app tests review, finding 6). Polish lines are longer than English, so this
/// checks the main routes stay reachable and tappable, and that the Polish catalog is the one in
/// use. Strings come from l10n/pl.json; if a translation changes, change it here too.
final class PolishSmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testHomeCaptureMemoriesAndSettingsWorkInPolish() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory) + ["-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        XCTAssertTrue(app.buttons["home.save"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["home.greeting"].label, "Trochę mniej do noszenia w głowie.")
        XCTAssertTrue(app.buttons["home.save"].isHittable)

        app.buttons["home.save"].tap()
        let save = app.buttons["capture.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable, "Save must be reachable with Polish text")
        attachScreenshot(app, "Polish capture")
        // "Cancel" in Polish; nothing was typed, so nothing is saved.
        app.buttons["Anuluj"].tap()

        XCTAssertTrue(app.buttons["tab.memories"].waitForExistence(timeout: 5))
        app.buttons["tab.memories"].tap()
        XCTAssertTrue(app.staticTexts["Brak wspomnień"].waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        let link = app.buttons["settings.dataFlow"]
        for _ in 0..<8 {
            if link.exists && link.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(link.isHittable)
        link.tap()
        XCTAssertTrue(app.navigationBars["Co opuszcza tego iPhone’a"].waitForExistence(timeout: 5))
        attachScreenshot(app, "Polish What leaves this iPhone")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
