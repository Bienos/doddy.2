import XCTest

/// The screens the offline simulator can't reach on its own, photographed with sample data
/// (ADR-821): conversation cards, "Cheapest this week" with an answer, the basket, a finished
/// shopping task with its three picks, Home's shopping cards and the report's pages. Each visit
/// launches a Debug build with `-screenFixture <name>` (DoddyApp/Features/Voice/ScreenFixtures.swift),
/// waits for the screen and keeps a picture of the whole simulator screen, as ScreenAtlasTests does,
/// in the same folder and index. The shops, prices and dates in the shopping screens are the
/// repository's contract fixtures: made up.
///
/// Runs only in the screens run (DODDY_SCREEN_ATLAS=1, `scripts/ci_screens.sh`); every other run skips
/// each test at once. NOT RUN in the authoring environment (Linux, no Xcode).
final class ScreenFixtureTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DODDY_SCREEN_ATLAS"] == "1",
                          "Only in the screens run (scripts/ci_screens.sh, ADR-821)")
    }

    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/screen-atlas", isDirectory: true)

    // MARK: Conversation cards

    private static let firstCards = ["memory", "event", "reminder", "timer", "alarm", "message", "blik", "email", "presentation", "plan"]
    private static let otherCards = ["ingredients", "parking", "changeEvent", "deleteEvent", "map", "shortcut", "camera", "createList", "askYes", "askTap"]

    @MainActor
    func test7aCards() {
        for (index, id) in Self.firstCards.enumerated() { card(id, number: index + 1) }
    }

    @MainActor
    func test7bCards() {
        for (index, id) in Self.otherCards.enumerated() { card(id, number: Self.firstCards.count + index + 1) }
    }

    @MainActor
    private func card(_ id: String, number: Int) {
        let numbered = number < 10 ? "0\(number)" : "\(number)"
        // The consent answer is a launch argument (held in memory, never saved): without it the sheet
        // stops at "Before Doddy listens" (the first run's pictures, 2 Nov). The stand-in link sends nothing.
        visit("7-card-\(numbered)-\(id)", fixture: "card:\(id)",
              extra: ["-voice.providerConsent.elevenlabs.v1", "YES"]) { app in
            // The card comes up by itself, half height, 3 s after launch (a conversation waiting
            // for the user's tap); drag the sheet up so the whole card shows.
            guard self.see(app.buttons["voice.confirm"], 30) else { return false }
            self.settle(0.8)
            let title = app.navigationBars["Talk to Doddy"]
            if title.exists {
                title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)))
                self.settle(1.0)
            }
            return true
        }
    }

    // MARK: Shopping

    @MainActor
    func test7cShopping() {
        visit("7-shop-01-cheapest-results", fixture: "deals") { app in
            guard self.openDeals(app) else { return false }
            app.scrollStep(); self.settle(0.6)
            return true
        }
        visit("7-shop-02-cheapest-results-lower", fixture: "deals") { app in
            guard self.openDeals(app) else { return false }
            for _ in 0..<2 { app.scrollStep(); self.settle(0.6) }
            return true
        }
        visit("7-shop-03-cheapest-results-bottom", fixture: "deals") { app in
            guard self.openDeals(app) else { return false }
            for _ in 0..<5 { app.scrollStep(); self.settle(0.5) }
            return true
        }
        visit("7-shop-04-basket", fixture: "deals") { app in self.openBasket(app) }
        visit("7-shop-05-basket-lower", fixture: "deals") { app in
            guard self.openBasket(app) else { return false }
            for _ in 0..<2 { app.swipeUp(); self.settle(0.6) }
            return true
        }
        visit("7-shop-06-home-leaflet-offers-card", fixture: "dealsHome") { app in
            self.settle(2)
            return self.see(app.buttons["home.dealsFound"], 10)
        }
        visit("7-shop-07-home-task-done-card", fixture: "errand") { app in
            self.settle(2)
            return self.see(app.buttons["home.errandFinished"], 10)
        }
        visit("7-shop-08-tasks-list", fixture: "errand") { app in
            self.settle(2)
            return self.menu(app, ["home.tasks"]) && self.see(app.buttons["errands.row"], 10)
        }
        visit("7-shop-09-three-picks", fixture: "errand") { app in self.openPicks(app) }
        visit("7-shop-10-three-picks-lower", fixture: "errand") { app in
            guard self.openPicks(app) else { return false }
            for _ in 0..<3 { app.swipeUp(); self.settle(0.6) }
            return true
        }
        visit("7-shop-11-three-picks-bottom", fixture: "errand") { app in
            guard self.openPicks(app) else { return false }
            for _ in 0..<7 { app.swipeUp(); self.settle(0.5) }
            return true
        }
        visit("7-shop-12-report-pages", fixture: "report") { app in
            self.see(app.descendants(matching: .any)["fixture.reportPage.0"], 30)
        }
        visit("7-shop-13-report-page-two", fixture: "report") { app in
            guard self.see(app.descendants(matching: .any)["fixture.reportPage.0"], 30) else { return false }
            for _ in 0..<2 { app.swipeUp(); self.settle(0.6) }
            return true
        }
    }

    @MainActor
    private func openDeals(_ app: XCUIApplication) -> Bool {
        settle(2)
        guard menu(app, ["home.deals"]), see(app.descendants(matching: .any)["deals.items"], 15) else { return false }
        // The answer sits below the form's long list of shops, which isn't built until it scrolls in
        // (the first run's picture, 2 Nov, showed only the form).
        return app.reveal(app.buttons["deals.basket"], maxSteps: 14)
    }

    @MainActor
    private func openBasket(_ app: XCUIApplication) -> Bool {
        guard openDeals(app) else { return false }
        let basket = app.buttons["deals.basket"]
        if !basket.isHittable { _ = app.reveal(basket, maxSteps: 12) }
        guard basket.isHittable else { return false }
        basket.tap()
        // The Basket screen itself (the 2 Nov picture was the real Basket, but this waited for a button
        // lower down, in a section a Form doesn't build until it scrolls in).
        return see(app.navigationBars["Basket"], 10)
    }

    @MainActor
    private func openPicks(_ app: XCUIApplication) -> Bool {
        settle(2)
        guard menu(app, ["home.tasks"]), see(app.buttons["errands.row"], 10) else { return false }
        app.buttons["errands.row"].firstMatch.tap()
        return see(app.descendants(matching: .any)["shopping.summary"], 10)
    }

    // MARK: The real iOS island and Lock Screen

    private static let firstIslands = ["connecting", "listening", "thinking", "speaking", "muted"]
    private static let otherIslands = ["confirm", "text", "transfer", "document", "translator"]

    @MainActor
    func test8aNativeIsland() {
        for (index, id) in Self.firstIslands.enumerated() { native(id, number: index + 1) }
    }

    @MainActor
    func test8bNativeIsland() {
        for (index, id) in Self.otherIslands.enumerated() { native(id, number: Self.firstIslands.count + index + 1) }
    }

    /// The app's real voice Live Activity in one state, drawn by iOS: the compact island on the Home
    /// Screen, the expanded island (a long press), then the Lock Screen with its card. Three whole-screen
    /// pictures; the page crops the island out. A fixture with no conversation behind it.
    @MainActor
    private func native(_ id: String, number: Int) {
        let numbered = number < 10 ? "0\(number)" : "\(number)"
        let name = "8-native-\(numbered)-\(id)"
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light", language: .english)
        app.launchArguments += ["-quickStartOffered", "NO", "-hadFirstConversation", "YES", "-firstLaunchIntroSeen", "YES"]
        app.launchArguments += ["-screenFixture", "island:\(id)"]
        app.launch()
        var started = see(app.buttons["home.more"], 12)
        // The fixture asks for the activity 2 s after launch and writes what iOS answered on screen.
        let answer = app.staticTexts["fixture.island.report"]
        let said = see(answer, 10) ? answer.label : "no answer from the fixture"
        add(XCTAttachment(string: "\(name): \(said)"))
        if !said.contains("started") {
            // Nothing to draw: keep the app's own screen, with the answer on it, as the evidence.
            keep("\(name)-0-app", reached: false, note: said)
            started = false
        }
        settle(3)
        XCUIDevice.shared.press(.home)
        // The widget extension can take a long time to draw its first card on a hosted Mac (the
        // 1 Nov island test allowed 30 s); later states find it warm.
        settle(number == 1 ? 30 : 12)
        keep("\(name)-a-compact", reached: started, note: said)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).press(forDuration: 1.2)
        settle(4)
        keep("\(name)-b-expanded", reached: started, note: said)
        // Lock, wake, and look at the Lock Screen; then swipe up to leave it (no passcode).
        _ = XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        settle(2)
        _ = XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        settle(5)
        keep("\(name)-c-lock", reached: started, note: said)
        springboard.swipeUp()
        settle(1)
        app.terminate()
    }

    // MARK: Visiting and keeping (as ScreenAtlasTests)

    @MainActor
    private func visit(_ name: String, fixture: String, extra: [String] = [], _ steps: @MainActor (XCUIApplication) -> Bool) {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light", language: .english)
        app.launchArguments += ["-quickStartOffered", "NO", "-hadFirstConversation", "YES", "-firstLaunchIntroSeen", "YES"]
        app.launchArguments += extra
        app.launchArguments += ["-screenFixture", fixture]
        app.launch()
        let reached = steps(app)
        settle(1.2)
        keep(name, reached: reached)
        app.terminate()
    }

    @MainActor
    private func keep(_ name: String, reached: Bool, note: String = "") {
        let shot = XCUIScreen.main.screenshot()
        let file = (reached ? "" : "missed-") + name
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: Self.folder.appendingPathComponent(file + ".png"))
            let tail = note.isEmpty ? "" : "\t" + note.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let line = Data("\(name)\t\(reached ? "reached" : "missed")\(tail)\n".utf8)
            let index = Self.folder.appendingPathComponent("index.tsv")
            if let handle = try? FileHandle(forWritingTo: index) {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: index)
            }
        } catch {
            add(XCTAttachment(string: "Couldn't write \(file).png: \(error)"))
        }
    }

    @MainActor
    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    private func see(_ element: XCUIElement, _ timeout: TimeInterval = 6) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func menu(_ app: XCUIApplication, _ path: [String]) -> Bool {
        let more = app.buttons["home.more"]
        guard see(more, 10) else { return false }
        more.tap()
        for id in path {
            let item = app.buttons[id]
            guard see(item, 5) else { return false }
            item.tap()
            settle(0.6)
        }
        return true
    }
}
