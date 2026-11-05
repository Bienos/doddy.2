import Foundation
import XCTest
@testable import DoddyCore

/// Sport mode step 4 on the iPhone (ADR-625): the kept plan, its start and where today falls.
final class SavedPlanTests: XCTestCase {
    private func warsaw(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ text: String, _ calendar: Calendar) -> Date {
        let parts = text.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts.count > 3 ? parts[3] : 12))!
    }

    private func tenK() -> TrainingPlan {
        let request = PlanRequest(goal: .tenK, level: .some, daysPerWeek: 3, minutesPerSession: 45, screening: .clear(age: 30))
        guard case .plan(let plan) = PlanEngine.make(request) else { fatalError("the engine makes this plan") }
        return plan
    }

    // MARK: The file

    func testAKeptPlanReadsBackAsDoddysPlan() throws {
        let saved = SavedTrainingPlan(plan: tenK(), start: PlanStart(year: 2026, month: 10, day: 26),
                                      savedAt: Date(timeIntervalSince1970: 1_793_000_000.25))
        XCTAssertEqual(SavedTrainingPlan.read(try saved.encoded()), .plan(saved))
    }

    func testAChangedPlanIsNotShownAsDoddys() throws {
        let plan = tenK()
        let first = plan.weeks[0]
        let longer = PlanSession(day: first.sessions[0].day, kind: .easyRun, minutes: first.sessions[0].minutes + 30)
        let edited = TrainingPlan(request: plan.request,
                                  weeks: [PlanWeek(number: 1, sessions: [longer] + first.sessions.dropFirst())] + plan.weeks.dropFirst(),
                                  baselineRunMinutes: plan.baselineRunMinutes)
        let saved = SavedTrainingPlan(plan: edited, start: PlanStart(year: 2026, month: 10, day: 26), savedAt: .now)
        XCTAssertEqual(SavedTrainingPlan.read(try saved.encoded()), .notThisDoddysPlan)

        // Answers that wouldn't get a plan at all (a "yes" to a screening question).
        var screening = PlanScreening.clear(age: 30)
        screening.symptoms = true
        let request = PlanRequest(goal: .tenK, level: .some, daysPerWeek: 3, minutesPerSession: 45, screening: screening)
        let unscreened = SavedTrainingPlan(plan: TrainingPlan(request: request, weeks: plan.weeks, baselineRunMinutes: plan.baselineRunMinutes),
                                           start: PlanStart(year: 2026, month: 10, day: 26), savedAt: .now)
        XCTAssertEqual(SavedTrainingPlan.read(try unscreened.encoded()), .notThisDoddysPlan)
    }

    func testAnUnknownFileIsUnreadableNotOverwritten() throws {
        XCTAssertEqual(SavedTrainingPlan.read(Data("not a plan".utf8)), .unreadable)
        let saved = SavedTrainingPlan(plan: tenK(), start: PlanStart(year: 2026, month: 10, day: 26), savedAt: .now)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try saved.encoded()) as? [String: Any])
        object["version"] = SavedTrainingPlan.version + 1
        XCTAssertEqual(SavedTrainingPlan.read(try JSONSerialization.data(withJSONObject: object)), .unreadable)
    }

    // MARK: The calendar

    func testThePlanStartsOnAMonday() {
        for firstWeekday in [1, 2] {
            let calendar = warsaw(firstWeekday: firstWeekday)
            // Wednesday 21 October 2026, Sunday 25 October, Monday 19 October.
            XCTAssertEqual(PlanStart.monday(of: date("2026-10-21", calendar), calendar: calendar), PlanStart(year: 2026, month: 10, day: 19))
            XCTAssertEqual(PlanStart.monday(of: date("2026-10-25", calendar), calendar: calendar), PlanStart(year: 2026, month: 10, day: 19),
                           "Sunday belongs to the week that started on Monday, whatever the first weekday (\(firstWeekday))")
            XCTAssertEqual(PlanStart.monday(of: date("2026-10-19", calendar), calendar: calendar), PlanStart(year: 2026, month: 10, day: 19))
            XCTAssertEqual(PlanStart.monday(of: date("2026-10-21", calendar), weeksLater: 1, calendar: calendar),
                           PlanStart(year: 2026, month: 10, day: 26))
            XCTAssertEqual(PlanStart.monday(of: date("2026-12-30", calendar), weeksLater: 1, calendar: calendar),
                           PlanStart(year: 2027, month: 1, day: 4), "across the new year")
        }
    }

    func testWhereTodayFalls() {
        let calendar = warsaw()
        let plan = tenK()
        let start = PlanStart(year: 2026, month: 10, day: 19)
        XCTAssertEqual(PlanCalendar.position(of: plan, start: start, now: date("2026-10-16", calendar), calendar: calendar), .startsIn(days: 3))
        XCTAssertEqual(PlanCalendar.position(of: plan, start: start, now: date("2026-10-19-0", calendar), calendar: calendar), .inPlan(week: 1, day: 1))
        XCTAssertEqual(PlanCalendar.position(of: plan, start: start, now: date("2026-10-25-23", calendar), calendar: calendar), .inPlan(week: 1, day: 7))
        // Summer time ends on 25 October 2026 in Poland: Monday the 26th is still week 2, day 1.
        XCTAssertEqual(PlanCalendar.position(of: plan, start: start, now: date("2026-10-26-0", calendar), calendar: calendar), .inPlan(week: 2, day: 1))
        XCTAssertEqual(PlanCalendar.position(of: plan, start: start, now: date("2026-12-13", calendar), calendar: calendar), .inPlan(week: 8, day: 7))
        XCTAssertEqual(PlanCalendar.position(of: plan, start: start, now: date("2026-12-14", calendar), calendar: calendar), .finished)
    }

    func testTheStartIsADayNotAnInstant() {
        // Saved in Warsaw, read in New York: still Monday 19 October.
        let start = PlanStart.monday(of: date("2026-10-21", warsaw()), calendar: warsaw())
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let first = start.date(in: newYork)!
        XCTAssertEqual(newYork.dateComponents([.year, .month, .day], from: first), DateComponents(year: 2026, month: 10, day: 19))
        XCTAssertEqual(PlanCalendar.weekday(of: first, calendar: newYork), 1)
    }
}

/// Whether a distance plan gets the long run to the goal (ADR-625): the screen must not call a
/// shorter last run "your goal run".
final class PlanGoalReachTests: XCTestCase {
    private func plan(_ goal: PlanGoal, _ level: PlanLevel, longest: Int?) -> TrainingPlan {
        let request = PlanRequest(goal: goal, level: level, daysPerWeek: 3, minutesPerSession: 60,
                                  longestRecentRunMinutes: longest, screening: .clear(age: 30))
        guard case .plan(let plan) = PlanEngine.make(request) else { fatalError("the engine makes this plan") }
        return plan
    }

    func testAPlanFromFarBelowEndsShortAndSaysSo() {
        let short = plan(.tenK, .some, longest: nil)
        XCTAssertEqual(short.goalLongRunMinutes, 70)
        XCTAssertLessThan(short.lastLongRunMinutes ?? 0, 70)
        XCTAssertFalse(short.reachesGoal)
        let half = plan(.halfMarathon, .regular, longest: nil)
        XCTAssertEqual(half.goalLongRunMinutes, 120)
        XCTAssertFalse(half.reachesGoal)
    }

    func testAPlanFromCloseByReachesTheGoal() {
        let close = plan(.tenK, .regular, longest: 65)
        XCTAssertEqual(close.lastLongRunMinutes, 70)
        XCTAssertTrue(close.reachesGoal)
        XCTAssertTrue(plan(.firstFiveK, .beginner, longest: nil).reachesGoal, "a first 5 km has no long-run goal")
        XCTAssertNil(plan(.strengthGym, .some, longest: nil).goalLongRunMinutes)
    }
}
