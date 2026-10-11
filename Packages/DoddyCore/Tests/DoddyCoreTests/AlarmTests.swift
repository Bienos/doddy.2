import DoddyCore
import XCTest

/// Alarms by voice (ADR-260): the arguments, the rules and what the agent is told.
final class AlarmTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 22))! }
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.setAlarm, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testAOneTimeAlarmIsADayAndATimeLaterThanNow() {
        guard case .setAlarm(let draft) = parse(#"{"time":"2026-10-12T07:00","label":"gym"}"#) else { return XCTFail() }
        XCTAssertEqual(draft.clock, "07:00")
        XCTAssertNil(draft.repeats)
        XCTAssertEqual(draft.label, "gym")
        XCTAssertEqual(draft.first.date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7)))
        XCTAssertEqual(VoiceToolReply.alarmSet(draft), "added: alarm \"gym\" at 07:00 on 2026-10-12. It rings even in Silent mode or a Focus. Checked.")

        guard case .needsClarification = parse(#"{"time":"2026-10-11T07:00"}"#) else {
            return XCTFail("a time that has passed is asked about, not set")
        }
        guard case .invalid = parse(#"{"time":"2026-10-12"}"#) else { return XCTFail("an alarm needs a time of day") }
        guard case .invalid = parse(#"{}"#) else { return XCTFail("an alarm needs a time") }
    }

    func testRepeatsAreOneOfThreeAndNamedPlainly() {
        guard case .setAlarm(let draft) = parse(#"{"time":"2026-10-12T06:30","repeat":"weekdays"}"#) else { return XCTFail() }
        XCTAssertEqual(draft.repeats, .weekdays)
        XCTAssertEqual(draft.repeats?.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(draft.summary, "06:30 on weekdays")
        guard case .invalid = parse(#"{"time":"2026-10-12T06:30","repeat":"mondays"}"#) else {
            return XCTFail("only every_day, weekdays and weekends")
        }
    }

    func testAlarmsAreServedByTimersPausedAndLogged() {
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.setAlarm), .timers)
        guard case .setAlarm(let draft) = parse(#"{"time":"2026-10-12T07:00"}"#) else { return XCTFail() }
        XCTAssertTrue(ConnectionPause.applies(to: .setAlarm(draft)))
        let logged = ActivityRequest.describe(.setAlarm(draft), calendar: calendar)
        XCTAssertEqual(logged?.title, "Set alarm")
        XCTAssertEqual(logged?.detail, "07:00 on 2026-10-12")
    }
}
