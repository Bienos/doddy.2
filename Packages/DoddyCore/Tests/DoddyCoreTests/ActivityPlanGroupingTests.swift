import XCTest
@testable import DoddyCore

/// "What Doddy did" shows each plan card as one item with its steps in order (ADR-208).
final class ActivityPlanGroupingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ title: String, at seconds: Double, outcome: ActivityOutcome = .done, plan: (UUID, Int, Int)? = nil) -> ActivityEntry {
        ActivityEntry(
            at: base.addingTimeInterval(seconds), app: .reminders, title: title, detail: nil, outcome: outcome,
            plan: plan.map { ActivityPlanRef(id: $0.0, step: $0.1, count: $0.2) })
    }

    func testAPlanIsOneItemWithItsStepsInOrderWhereItsNewestStepFalls() {
        let plan = UUID()
        let entries = [
            entry("before", at: 0),
            entry("step 2", at: 11, plan: (plan, 2, 3)),
            entry("between", at: 12),
            entry("step 1", at: 10, plan: (plan, 1, 3)),
            entry("step 3", at: 13, outcome: .notSure, plan: (plan, 3, 3)),
            entry("after", at: 20),
        ]
        let items = ActivityItem.items(entries)
        XCTAssertEqual(items.count, 4)
        guard case .single(let newest) = items[0], case .plan(let id, let steps) = items[1],
              case .single(let between) = items[2], case .single(let oldest) = items[3] else { return XCTFail("\(items)") }
        XCTAssertEqual(newest.title, "after")
        XCTAssertEqual(id, plan)
        XCTAssertEqual(steps.map(\.title), ["step 1", "step 2", "step 3"])
        XCTAssertEqual(items[1].at, base.addingTimeInterval(13))
        XCTAssertEqual(between.title, "between")
        XCTAssertEqual(oldest.title, "before")
    }

    func testTwoPlansStaySeparate() {
        let first = UUID(), second = UUID()
        let items = ActivityItem.items([
            entry("a1", at: 0, plan: (first, 1, 2)), entry("a2", at: 1, plan: (first, 2, 2)),
            entry("b1", at: 5, plan: (second, 1, 1)),
        ])
        XCTAssertEqual(items.map(\.id), [second, first])
    }

    func testSummaryCountsOnlyWhatEachStepSays() {
        let plan = UUID()
        let steps = [
            entry("1", at: 0, outcome: .done, plan: (plan, 1, 4)),
            entry("2", at: 0, outcome: .alreadyThere, plan: (plan, 2, 4)),
            entry("3", at: 0, outcome: .notSure, plan: (plan, 3, 4)),
            entry("4", at: 0, outcome: .declined, plan: (plan, 4, 4)),
        ]
        XCTAssertEqual(ActivityPlanSummary.title(steps), "Plan · 4 steps")
        XCTAssertEqual(ActivityPlanSummary.outcomes(steps), "2 done · 1 not sure · 1 you said no")
        XCTAssertEqual(ActivityPlanSummary.title(Array(steps.prefix(3))), "Plan · 4 steps (1 no longer listed)")
    }
}
