import XCTest

/// Sport mode step 4 (ADR-625): Settings › Connections › Sport and health › Training plan. A "yes" to a safety question
/// gets no plan and says who to ask; all "no" gets a plan that is kept on the iPhone, shown, and
/// deleted. Every launch uses an in-memory store, so the plan file is new each time.
final class TrainingPlanUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSafetyQuestionsThenKeepAndDeleteAPlan() {
        let app = XCUIApplication()
        app.launchArguments += UITestLaunch.arguments(store: .inMemory)
        app.launchArguments += ["-hadFirstConversation", "YES", "-firstLaunchIntroSeen", "YES"]
        app.launch()
        XCTAssertTrue(app.waitForTab("home", timeout: 5))
        app.goToTab("settings")
        // Settings › Connections › Sport and health › Training plan (ADR-633's hub).
        app.openSettingsPage("connections.trainingPlan", under: "settings.connectionsHub")

        let make = app.buttons["plan.make"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        XCTAssertTrue(app.reveal(make))
        make.tap()

        // The default goal is a first 5 km, 3 days, 45 minutes. One "yes" first.
        answer(app, yesTo: ["symptoms"])
        let age = app.textFields["plan.age"]
        XCTAssertTrue(show(age, in: app))
        age.tapAndType("30")
        // The number pad covers the bottom of the sheet and has no return key; its Done closes it.
        let done = app.buttons["plan.age.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the number pad's Done")
        done.tap()
        let makePlan = app.buttons["plan.questions.make"]
        XCTAssertTrue(show(makePlan, in: app))
        XCTAssertTrue(makePlan.isEnabled, "every question answered")
        makePlan.tap()
        let refusal = app.staticTexts["plan.refusal"]
        XCTAssertTrue(refusal.waitForExistence(timeout: 5))
        XCTAssertEqual(refusal.label, "Talk to a doctor first")
        XCTAssertFalse(app.buttons["plan.keep"].exists, "no plan to keep after a yes")

        // Back, the same question now "no": a plan. The form is scrolled down, so look upwards.
        app.navigationBars["Your plan"].buttons.element(boundBy: 0).tap()
        let symptoms = app.segmentedControls["plan.question.symptoms"]
        XCTAssertTrue(show(symptoms, in: app, upwards: true))
        symptoms.buttons["No"].tap()
        XCTAssertTrue(show(makePlan, in: app))
        makePlan.tap()
        let keep = app.buttons["plan.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()

        // Kept, read back, and shown on the plan screen.
        let position = app.staticTexts["plan.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(position.label.hasPrefix("Week 1 of 12") || position.label.hasPrefix("Starts on Monday"), position.label)

        let delete = app.buttons["plan.delete"]
        XCTAssertTrue(app.reveal(delete))
        delete.tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["plan.make"].waitForExistence(timeout: 5), "nothing kept after delete")
        XCTAssertFalse(app.staticTexts["plan.position"].exists)
    }

    /// Answers the five safety questions: "yes" to the keys given, "no" to the rest.
    @MainActor
    private func answer(_ app: XCUIApplication, yesTo keys: Set<String>) {
        for key in ["condition", "symptoms", "doctor", "pregnancy", "injury"] {
            let control = app.segmentedControls["plan.question.\(key)"]
            XCTAssertTrue(show(control, in: app), "question \(key)")
            control.buttons[keys.contains(key) ? "Yes" : "No"].tap()
        }
    }

    /// Scrolls the questions sheet until `element` can be tapped. Doddy's tab bar is under the
    /// sheet, so `reveal`'s tab-bar check doesn't apply here.
    @MainActor
    private func show(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = false) -> Bool {
        for _ in 0..<15 {
            if element.exists && element.isHittable { return true }
            // A drag that starts on the keyboard doesn't scroll the form: start above it.
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists && app.frame.height > 0 ? min(0.75, keyboard.frame.minY / app.frame.height - 0.05) : 0.75
            let (start, end) = upwards ? (0.25, bottom) : (bottom, 0.2)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: start))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: end))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.2)
        }
        return element.exists && element.isHittable
    }
}
