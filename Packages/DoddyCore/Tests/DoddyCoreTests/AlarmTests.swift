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

/// Asking about and turning off Doddy's alarms by voice (ADR-283).
final class AlarmVoiceTests: XCTestCase {
    private let gym = AlarmEntry(id: UUID(), clock: "07:00", label: "gym", summary: "07:00 on weekdays")
    private let flight = AlarmEntry(id: UUID(), clock: "07:00", label: "flight", summary: "07:00 on 2026-10-14")
    private let early = AlarmEntry(id: UUID(), clock: "05:30", label: nil, summary: "05:30 on 2026-10-12")

    func testTurningOffMatchesByTimeAndOnlyThenByLabel() {
        guard case .cancelAlarm(let clock, let label) = VoiceToolRequest.parse(
            name: VoiceToolName.cancelAlarm, parametersJSON: Data(#"{"time":"7:00"}"#.utf8), now: Date(), calendar: .current)
        else { return XCTFail() }
        XCTAssertEqual(clock, "07:00")
        XCTAssertNil(label)
        guard case .several = AlarmMatch.match(clock: "07:00", label: nil, in: [gym, flight, early]) else { return XCTFail("two at 07:00: ask") }
        XCTAssertEqual(AlarmMatch.match(clock: "07:00", label: "Gym", in: [gym, flight, early]), .one(gym))
        XCTAssertEqual(AlarmMatch.match(clock: "05:30", label: nil, in: [gym, flight, early]), .one(early))
        guard case .none = AlarmMatch.match(clock: "08:00", label: nil, in: [gym]) else { return XCTFail() }
        guard case .invalid = VoiceToolRequest.parse(name: VoiceToolName.cancelAlarm, parametersJSON: Data(#"{"time":"25:00"}"#.utf8),
                                                     now: Date(), calendar: .current) else { return XCTFail() }
    }

    func testTheListSaysOnlyDoddysAlarmsAreVisible() {
        XCTAssertTrue(VoiceToolReply.alarms([]).contains("Clock app"))
        let reply = VoiceToolReply.alarms([gym])
        XCTAssertTrue(reply.contains("07:00 on weekdays (\"gym\")"))
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.cancelAlarm), .timers)
        XCTAssertTrue(ConnectionPause.applies(to: .listAlarms))
        XCTAssertEqual(ActivityRequest.describe(.listAlarms, calendar: .current)?.isLookup, true)
    }

    /// Review F5: an unreadable AlarmKit list is "unknown", never "none set".
    func testAnUnreadableListIsUnknownNotNone() {
        XCTAssertTrue(VoiceToolReply.alarmsUnreadable.hasPrefix("unknown:"))
        XCTAssertFalse(VoiceToolReply.alarmsUnreadable.contains("none"))
    }
}
