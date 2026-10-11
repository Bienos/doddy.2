@testable import DoddyCore
import XCTest

/// ADR-253 (OP-014): the user's own words for when, against the date the agent wrote out.
/// Now is Saturday 10 October 2026, 13:02 in Warsaw: Friday is the 16th, then the 23rd.
final class SaidTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_630_120)
    private let zone = "Europe/Warsaw"

    private func due(_ day: Int, _ hour: Int? = nil, _ minute: Int? = nil) -> ReminderDue {
        ReminderDue(year: 2026, month: 10, day: day, hour: hour, minute: minute, timeZoneID: zone)
    }

    private func kind(_ said: String, _ due: ReminderDue, timeRequired: Bool = false) -> ReminderClarification.Kind? {
        SaidTime.check(said, due: due, now: now, timeRequired: timeRequired)?.kind
    }

    func testNextWeekdayAsksWhichOfTheTwo() throws {
        let question = try XCTUnwrap(SaidTime.check("next Friday", due: due(16), now: now, timeRequired: false))
        XCTAssertEqual(question.kind, .ambiguousDay)
        XCTAssertEqual(question.problem, "\"next Friday\" can mean Friday 16 October or Friday 23 October")
        XCTAssertEqual(kind("next Friday", due(23)), .ambiguousDay)
        XCTAssertEqual(kind("w przyszły piątek", due(23)), .ambiguousDay)
        XCTAssertEqual(kind("w następną sobotę", due(17)), .ambiguousDay)
        // The answer, written out, settles it.
        XCTAssertNil(kind("Friday 16 October", due(16)))
        XCTAssertNil(kind("next Friday the 16th", due(16)))
        XCTAssertNil(kind("piątek 23 października", due(23)))
        XCTAssertNil(kind("this Friday", due(16)))
        XCTAssertNil(kind("w piątek", due(16)))
    }

    func testWordsThatContradictTheDateAreCaught() {
        XCTAssertEqual(kind("Friday", due(15)), .saidDifferently, "the 15th is a Thursday")
        XCTAssertEqual(kind("w piątek", due(15)), .saidDifferently)
        XCTAssertEqual(kind("tomorrow", due(12)), .saidDifferently)
        XCTAssertNil(kind("jutro", due(11)))
        XCTAssertNil(kind("pojutrze", due(12)))
        XCTAssertEqual(kind("the day after tomorrow", due(11)), .saidDifferently)
        XCTAssertNil(kind("today", due(10)))
        XCTAssertEqual(kind("dzisiaj", due(11)), .saidDifferently)
        XCTAssertEqual(kind("October 16", due(17)), .saidDifferently)
        XCTAssertNil(kind("16 października", due(16)))
        XCTAssertEqual(kind("16 listopada", due(16)), .saidDifferently, "November, not October")
    }

    func testWeekendAndNextWeekAskWhichDay() throws {
        let weekend = try XCTUnwrap(SaidTime.check("this weekend", due: due(10), now: now, timeRequired: false))
        XCTAssertEqual(weekend.kind, .ambiguousDay)
        XCTAssertEqual(weekend.problem, "\"this weekend\" can mean Saturday 10 October or Sunday 11 October")
        XCTAssertEqual(kind("w weekend", due(11)), .ambiguousDay)
        XCTAssertNil(kind("Sunday this weekend", due(11)))
        XCTAssertEqual(kind("next week", due(14)), .ambiguousDay)
        XCTAssertEqual(kind("w przyszłym tygodniu", due(14)), .ambiguousDay)
        XCTAssertNil(kind("w przyszłym tygodniu w środę", due(14)))
    }

    func testAnHourWithoutMorningOrEveningAsks() throws {
        let question = try XCTUnwrap(SaidTime.check("tomorrow at 7", due: due(11, 7), now: now, timeRequired: true))
        XCTAssertEqual(question.kind, .ambiguousTime)
        XCTAssertEqual(question.question, "whether they mean 07:00 or 19:00")
        XCTAssertEqual(kind("Friday at 9", due(16, 21), timeRequired: true), .ambiguousTime)
        XCTAssertNil(kind("tomorrow at 7pm", due(11, 19)))
        XCTAssertEqual(kind("tomorrow at 7pm", due(11, 7)), .saidDifferently)
        XCTAssertNil(kind("tomorrow at 7 in the morning", due(11, 7)))
        XCTAssertNil(kind("jutro o 19", due(11, 19)))
        XCTAssertNil(kind("jutro o 9:30", due(11, 9, 30)), "hours and minutes are the 24-hour clock")
        XCTAssertNil(kind("jutro o siódmej rano", due(11, 7)))
        XCTAssertEqual(kind("jutro o siódmej wieczorem", due(11, 7)), .saidDifferently)
        XCTAssertNil(kind("jutro o dwudziestej pierwszej", due(11, 21)))
        XCTAssertNil(kind("at noon tomorrow", due(11, 12)))
        XCTAssertEqual(kind("tomorrow at 9", due(11, 10)), .saidDifferently, "9, not 10")
        XCTAssertEqual(kind("tomorrow at 9", due(11, 9, 30)), .saidDifferently, "9:00, not 9:30")
        // Later today only one of the two is still ahead: 7 said at 13:02 is 19:00.
        XCTAssertNil(kind("today at 7", due(10, 19)))
        XCTAssertEqual(kind("today at 7", due(10, 7)), .saidDifferently)
    }

    func testATimeTheUserNeverSaidIsNotAdded() throws {
        let morning = try XCTUnwrap(SaidTime.check("tomorrow morning", due: due(11, 9), now: now, timeRequired: false))
        XCTAssertEqual(morning.kind, .noTimeSaid)
        XCTAssertEqual(morning.question, "what time they want, or whether a reminder for the day without a time is fine")
        XCTAssertEqual(SaidTime.check("jutro rano", due: due(11, 9), now: now, timeRequired: true)?.question, "what time they mean")
        XCTAssertEqual(kind("tomorrow", due(11, 9)), .noTimeSaid)
        XCTAssertNil(kind("tomorrow", due(11)), "a day without a time is what was said")
        XCTAssertEqual(kind("tomorrow at 9", due(11)), .saidDifferently, "a time was said but none was sent")
    }

    func testRelativeTimesAndWordsItDoesNotRead() {
        XCTAssertNil(kind("in 2 hours", due(10, 15, 2)))
        XCTAssertNil(kind("za 30 minut", due(10, 13, 32)))
        XCTAssertNil(kind("in half an hour", due(10, 13, 30)))
        XCTAssertEqual(kind("in 2 hours", due(10, 16)), .saidDifferently)
        // Clock words these rules don't read are not second-guessed.
        XCTAssertNil(kind("tomorrow at half past seven", due(11, 19, 30)))
        XCTAssertNil(kind("jutro wpół do ósmej", due(11, 7, 30)))
        // "piątej" is five o'clock, not Friday ("piątek").
        XCTAssertNil(kind("jutro o piątej po południu", due(11, 17)))
        // "od 16 października" is a day, not 16:00.
        XCTAssertNil(kind("od 16 października", due(16)))
    }

    // MARK: Through the tool parser

    func testToolCallsWithTheUsersWordsAreChecked() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        func parse(_ name: String, _ json: String) -> VoiceToolRequest {
            VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
        }
        guard case .needsClarification("create_reminder", let reminder) =
                parse("create_reminder", #"{"title":"Call mum","due":"2026-10-16","said_time":"next Friday"}"#) else {
            return XCTFail("expected a question")
        }
        XCTAssertEqual(reminder.kind, .ambiguousDay)
        // Without the words the date is used as before.
        guard case .createReminder = parse("create_reminder", #"{"title":"Call mum","due":"2026-10-16"}"#) else {
            return XCTFail("expected a reminder")
        }
        guard case .needsClarification("create_calendar_event", let event) = parse(
            "create_calendar_event", #"{"title":"Dentist","start":"2026-10-11T07:00","said_time":"jutro o 7"}"#) else {
            return XCTFail("expected a question")
        }
        XCTAssertEqual(event.kind, .ambiguousTime)
        guard case .createCalendarEvent = parse(
            "create_calendar_event", #"{"title":"Trip","start":"2026-10-16","all_day":true,"said_time":"Friday 16 October"}"#) else {
            return XCTFail("expected an event")
        }
        guard case .needsClarification(_, let note) = parse(
            "remind_me_about_note", #"{"note":"Parcel code 7731","due":"2026-10-11T09:00","said_time":"tomorrow morning"}"#) else {
            return XCTFail("expected a question")
        }
        XCTAssertEqual(note.kind, .noTimeSaid)
        guard case .needsClarification = parse(
            "create_reminder", #"{"title":"Pay rent","said_time":"tomorrow"}"#) else {
            return XCTFail("words about a day but no due")
        }
    }

    func testAPlanStepWithAnUnclearDayStopsThePlan() {
        let steps = #"[{"tool":"create_reminder","title":"Call mum","due":"2026-10-16","said_time":"next Friday"},{"tool":"save_memory","text":"Mum's number"}]"#
        let json = try! JSONSerialization.data(withJSONObject: ["steps": steps])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        guard case .refused(let reply) = PlanProposal.parse(parametersJSON: json, now: now, calendar: calendar) else {
            return XCTFail("expected the plan to wait for an answer")
        }
        XCTAssertTrue(reply.contains("Friday 16 October or Friday 23 October"), reply)
        XCTAssertTrue(reply.hasPrefix("failed: not added yet: step 1"))
    }
}
