import XCTest
@testable import DoddyCore

/// ADR-632 / ADR-620: a weight goal is judged by pace, with no calorie number in any answer.
final class WeightGoalGuardTests: XCTestCase {
    func testTheGoalIsReadFromTheWords() throws {
        let week = try XCTUnwrap(WeightGoalRequest.parse("Chcę schudnąć 10 kg w tydzień"))
        XCTAssertEqual(week.kilograms, 10)
        XCTAssertEqual(week.weeks, 1, accuracy: 1e-9)
        let months = try XCTUnwrap(WeightGoalRequest.parse("lose 5 kg in 2 months"))
        XCTAssertEqual(months.kilograms, 5)
        XCTAssertEqual(months.weeks, 8.69, accuracy: 0.01)
        let weeks = try XCTUnwrap(WeightGoalRequest.parse("zrzucić 3 kilo w 6 tygodni"))
        XCTAssertEqual(weeks.weeks, 6, accuracy: 1e-9)
        let days = try XCTUnwrap(WeightGoalRequest.parse("2,5 kg w 10 dni"))
        XCTAssertEqual(days.kilograms, 2.5)
        XCTAssertEqual(days.weeks, 10.0 / 7.0, accuracy: 1e-9)
        let bare = try XCTUnwrap(WeightGoalRequest.parse("I want to lose 4 kg in a month"))
        XCTAssertEqual(bare.weeks, 4.345, accuracy: 1e-9)
    }

    func testNoAmountOrNoPeriodIsNotAGoal() {
        XCTAssertNil(WeightGoalRequest.parse("Trenuję 3 dni"))
        XCTAssertNil(WeightGoalRequest.parse("chcę schudnąć"))
        XCTAssertNil(WeightGoalRequest.parse("chcę schudnąć 10 kg"))
        XCTAssertNil(WeightGoalRequest(kilograms: 0, weeks: 4))
        XCTAssertNil(WeightGoalRequest(kilograms: 5, weeks: 0))
    }

    func testTenKilosInAWeekIsTooFastAndSaysHowLongItShouldTake() throws {
        let advice = WeightGoalGuard.assess(try XCTUnwrap(WeightGoalRequest(kilograms: 10, weeks: 1)))
        XCTAssertEqual(advice, .tooFast(kilogramsPerWeek: 10, saferWeeks: 20))
        let polish = WeightGoalGuard.message(advice, language: .polish)
        XCTAssertTrue(polish.contains("za szybko"), polish)
        XCTAssertTrue(polish.contains("0,5 kg"), polish)
        XCTAssertTrue(polish.contains("20 tygodni"), polish)
        let english = WeightGoalGuard.message(advice, language: .english)
        XCTAssertTrue(english.contains("too fast") && english.contains("20 weeks"), english)
    }

    func testTheLimitIsHalfAKiloAWeek() throws {
        XCTAssertEqual(WeightGoalGuard.assess(try XCTUnwrap(WeightGoalRequest(kilograms: 2, weeks: 4))), .fine(kilogramsPerWeek: 0.5))
        XCTAssertEqual(WeightGoalGuard.assess(try XCTUnwrap(WeightGoalRequest(kilograms: 1, weeks: 8))), .fine(kilogramsPerWeek: 0.125))
        guard case .tooFast = WeightGoalGuard.assess(try XCTUnwrap(WeightGoalRequest(kilograms: 2.1, weeks: 4))) else {
            return XCTFail("2.1 kg in 4 weeks is over half a kilo a week")
        }
    }

    func testNoGoalAtAllUnderTheOwnersConditions() throws {
        let request = try XCTUnwrap(WeightGoalRequest(kilograms: 2, weeks: 20))
        XCTAssertEqual(WeightGoalGuard.assess(request, bmi: 18.4), .notAdvisable(.underweight))
        XCTAssertEqual(WeightGoalGuard.assess(request, bmi: 18.5), .fine(kilogramsPerWeek: 0.1))
        XCTAssertEqual(WeightGoalGuard.assess(request, age: 17), .notAdvisable(.minor))
        XCTAssertEqual(WeightGoalGuard.assess(request, age: 18), .fine(kilogramsPerWeek: 0.1))
        XCTAssertEqual(WeightGoalGuard.assess(request, triage: TrainingTriage.assess("mam bulimię")), .notAdvisable(.sensitive))
        XCTAssertEqual(WeightGoalGuard.assess(request, triage: TrainingTriage.assess("jestem w ciąży")), .notAdvisable(.sensitive))
    }

    func testNoAnswerEverNamesACalorieNumber() throws {
        let advices: [WeightGoalAdvice] = [
            .fine(kilogramsPerWeek: 0.4), .tooFast(kilogramsPerWeek: 3, saferWeeks: 6), .notAdvisable(.underweight),
            .notAdvisable(.minor), .notAdvisable(.sensitive),
        ]
        for advice in advices {
            for language in [NotificationLanguage.polish, .english] {
                let text = WeightGoalGuard.message(advice, language: language).lowercased()
                // The word may appear ("no calorie targets"); a number of calories never does.
                XCTAssertNil(text.range(of: #"\d\s*(kcal|kalor|calor)"#, options: .regularExpression), text)
                XCTAssertFalse(text.contains("kcal"), text)
            }
        }
    }
}
