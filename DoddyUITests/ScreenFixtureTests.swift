import XCTest

/// The screens the offline simulator can't reach on its own, photographed with sample data
/// (ADR-694): conversation cards, "Cheapest this week" with an answer, the basket, a finished
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
                          "Only in the screens run (scripts/ci_screens.sh, ADR-694)")
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
        visit("7-card-\(numbered)-\(id)", fixture: "card:\(id)") { app in
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
        visit("7-shop-01-cheapest-results", fixture: "deals") { app in self.openDeals(app) }
        visit("7-shop-02-cheapest-results-lower", fixture: "deals") { app in
            guard self.openDeals(app) else { return false }
            for _ in 0..<2 { app.swipeUp(); self.settle(0.6) }
            return true
        }
        visit("7-shop-03-cheapest-results-bottom", fixture: "deals") { app in
            guard self.openDeals(app) else { return false }
            for _ in 0..<5 { app.swipeUp(); self.settle(0.5) }
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
        guard menu(app, ["home.deals"]) else { return false }
        return see(app.buttons["deals.basket"], 15)
    }

    @MainActor
    private func openBasket(_ app: XCUIApplication) -> Bool {
        guard openDeals(app) else { return false }
        let basket = app.buttons["deals.basket"]
        if !basket.isHittable { _ = app.reveal(basket, maxSteps: 12) }
        guard basket.isHittable else { return false }
        basket.tap()
        return see(app.descendants(matching: .any)["basket.share"], 10)
    }

    @MainActor
    private func openPicks(_ app: XCUIApplication) -> Bool {
        settle(2)
        guard menu(app, ["home.tasks"]), see(app.buttons["errands.row"], 10) else { return false }
        app.buttons["errands.row"].firstMatch.tap()
        return see(app.descendants(matching: .any)["shopping.summary"], 10)
    }

    // MARK: Visiting and keeping (as ScreenAtlasTests)

    @MainActor
    private func visit(_ name: String, fixture: String, _ steps: @MainActor (XCUIApplication) -> Bool) {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.arguments(store: .inMemory, appearance: "light", language: .english)
        app.launchArguments += ["-quickStartOffered", "NO", "-hadFirstConversation", "YES", "-firstLaunchIntroSeen", "YES"]
        app.launchArguments += ["-screenFixture", fixture]
        app.launch()
        let reached = steps(app)
        settle(1.2)
        keep(name, reached: reached)
        app.terminate()
    }

    @MainActor
    private func keep(_ name: String, reached: Bool) {
        let shot = XCUIScreen.main.screenshot()
        let file = (reached ? "" : "missed-") + name
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: Self.folder.appendingPathComponent(file + ".png"))
            let line = Data("\(name)\t\(reached ? "reached" : "missed")\n".utf8)
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
