import XCTest
@testable import DoddyCore

/// The practice plan card (ADR-206): real parsing, sample data, nothing claimed as done.
final class PlanPracticeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testFourStepsOnTheNextSaturdayFromAnyDay() {
        // 2026-10-10 is a Saturday: the sample moves to the 17th, never today.
        for (today, saturday) in [(10, 17), (11, 17), (16, 17), (17, 24)] {
            let steps = PlanPractice.steps(now: day(today, 23), calendar: calendar)
            XCTAssertEqual(steps.map(\.toolName), [VoiceToolName.saveMemory, VoiceToolName.createReminder, VoiceToolName.createCalendarEvent, VoiceToolName.setTimer], "today \(today)")
            guard case .createReminder(let reminder) = steps[1].request else { return XCTFail() }
            XCTAssertEqual(reminder.due?.day, saturday, "today \(today)")
            guard case .createCalendarEvent(let event) = steps[2].request else { return XCTFail() }
            XCTAssertEqual(event.start, day(saturday, 14))
            XCTAssertEqual(event.end, day(saturday, 16))
        }
    }

    func testStepsAreDatedCorrectlyOnABuddhistOrJapaneseCalendar() {
        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            var local = Calendar(identifier: identifier)
            local.timeZone = calendar.timeZone
            let steps = PlanPractice.steps(now: day(11), calendar: local)
            XCTAssertEqual(steps.count, 4, "\(identifier)")
            guard steps.count == 4, case .createCalendarEvent(let event) = steps[2].request else { return XCTFail("\(identifier)") }
            XCTAssertEqual(event.start, day(17, 14), "\(identifier)")
        }
    }

    func testResultsNeverSayDone() {
        for step in PlanPractice.steps(now: day(10), calendar: calendar) {
            let ticked = PlanPractice.result(for: step, ticked: true, calendar: calendar)
            XCTAssertTrue(ticked.hasPrefix("Practice only."), ticked)
            XCTAssertTrue(ticked.hasSuffix("Nothing was done."), ticked)
            XCTAssertEqual(PlanPractice.result(for: step, ticked: false, calendar: calendar), "Unticked: this would be skipped.")
        }
    }

    func testPracticeStepsCanBeChangedLikeRealOnes() throws {
        let steps = PlanPractice.steps(now: day(10), calendar: calendar)
        var form = PlanStepForm(steps[3], now: day(10), calendar: calendar)
        form.minutes = 12
        guard case .step(let changed) = form.apply(to: steps[3], now: day(10), calendar: calendar),
              case .setTimer(let timer) = changed.request else { return XCTFail() }
        XCTAssertEqual(timer.seconds, 720)
    }
}
