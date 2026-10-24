import XCTest
@testable import DoddyCore

/// ADR-612: a note reminder marked "Ring like an alarm" also gets an AlarmKit alarm, kept in step
/// with the database reminder. AlarmKit itself only runs on an iPhone.
final class RingingRemindersTests: XCTestCase {
    private let zone = "Europe/Warsaw"
    private var calendar: Calendar { ReminderSchedule.calendar(zone) }
    /// Sat 24 Oct 2026, 12:00 in Warsaw.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))! }
    private let memory = UUID()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func reminder(_ fireAt: Date, repeats: ReminderRepeat? = nil, memoryID: UUID? = nil) -> MemoryReminder {
        MemoryReminder(
            id: UUID(), memoryID: memoryID ?? memory, trigger: .time(fireAt: fireAt, timeZoneID: zone),
            createdAt: now, repeats: repeats)
    }

    private func place(memoryID: UUID? = nil) -> MemoryReminder {
        MemoryReminder(
            id: UUID(), memoryID: memoryID ?? memory,
            trigger: .place(try! ReminderPlace(name: "Biedronka", latitude: 52.2, longitude: 21.0, radiusMeters: 150, onArrival: true)),
            createdAt: now)
    }

    // MARK: What can ring, and when

    func testAOneOffRingsOnceAtItsMomentAndNotOnceItHasPassed() {
        XCTAssertEqual(ReminderRing.plan(for: reminder(at(25, 8)), now: now), .once(at(25, 8)))
        XCTAssertNil(ReminderRing.plan(for: reminder(at(24, 9)), now: now))
    }

    func testRepeatsRingOnTheirWeekdaysAtTheirClockTime() {
        // 26 Oct 2026 is a Monday (weekday 2).
        XCTAssertEqual(ReminderRing.plan(for: reminder(at(26, 8, 15), repeats: .daily), now: now),
                       .weekly(hour: 8, minute: 15, weekdays: [1, 2, 3, 4, 5, 6, 7]))
        XCTAssertEqual(ReminderRing.plan(for: reminder(at(26, 7), repeats: .weekdays), now: now),
                       .weekly(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6]))
        XCTAssertEqual(ReminderRing.plan(for: reminder(at(29, 19), repeats: .weekly), now: now),
                       .weekly(hour: 19, minute: 0, weekdays: [5]), "Thursday")
        // A repeat whose first time has passed still rings on its days.
        XCTAssertNotNil(ReminderRing.plan(for: reminder(at(20, 8), repeats: .daily), now: now))
    }

    func testPlacesAndMonthlyRemindersCantRingAndSaySo() {
        XCTAssertEqual(ReminderRing.support(place()), .place)
        XCTAssertNil(ReminderRing.plan(for: place(), now: now))
        XCTAssertEqual(ReminderRing.support(repeats: .monthly, isPlace: false), .monthly)
        XCTAssertNil(ReminderRing.plan(for: reminder(at(26, 9), repeats: .monthly), now: now))
        XCTAssertEqual(ReminderRing.unsupportedReason(.monthly, .polish), "Przypomnienie co miesiąc nie może dzwonić jak budzik.")
        XCTAssertNil(ReminderRing.unsupportedReason(.supported, .english))
    }

    // MARK: The ringing screen's words

    func testTheRingingScreenShowsTheNoteOnlyWhenTheUserAllowsIt() {
        XCTAssertEqual(ReminderRing.title(noteText: "Leki\nmagnez i witamina D", showNoteText: true, language: .polish), "Leki")
        XCTAssertEqual(ReminderRing.title(noteText: "Leki", showNoteText: false, language: .polish), "Przypomnienie")
        XCTAssertEqual(ReminderRing.title(noteText: "  ", showNoteText: true, language: .english), "Reminder")
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(ReminderRing.title(noteText: long, showNoteText: true, language: .english).count, ReminderRing.maxTitleLength)
        XCTAssertEqual(ReminderRing.snoozeButton(.polish), "Za 10 min")
    }

    // MARK: Keeping AlarmKit in step

    func testANewWishIsScheduled() {
        let entry = RingingReminderEntry(memoryID: memory)
        let steps = RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(25, 8))], listed: [], now: now)
        XCTAssertEqual(steps, [.schedule(memoryID: memory, plan: .once(at(25, 8)))])
    }

    func testAnAlarmAlreadyOnThePlanIsLeftAlone() {
        let alarm = UUID()
        let plan = ReminderRingPlan.once(at(25, 8))
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [alarm], signature: plan.signature)
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(25, 8))], listed: [alarm], now: now), [])
        XCTAssertTrue(RingingReminderSync.isRinging(entry, reminder: reminder(at(25, 8)), listed: [alarm], now: now))
    }

    func testANewTimeMovesTheAlarm() {
        // "In 1 hour" or a new date: the note's reminder is replaced, so its alarm is too.
        let alarm = UUID()
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [alarm], signature: ReminderRingPlan.once(at(25, 8)).signature)
        let steps = RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(25, 9))], listed: [alarm], now: now)
        XCTAssertEqual(steps, [.cancel([alarm]), .schedule(memoryID: memory, plan: .once(at(25, 9)))])
        XCTAssertFalse(RingingReminderSync.isRinging(entry, reminder: reminder(at(25, 9)), listed: [alarm], now: now))
    }

    func testAMissingAlarmIsSetAgain() {
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [UUID()], signature: ReminderRingPlan.once(at(25, 8)).signature)
        let steps = RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(25, 8))], listed: [], now: now)
        XCTAssertEqual(steps, [.schedule(memoryID: memory, plan: .once(at(25, 8)))])
    }

    func testDoneOrDeletedTurnsTheAlarmOffAndForgetsTheWish() {
        let alarm = UUID()
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [alarm], signature: "x")
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [], listed: [alarm], now: now),
                       [.cancel([alarm]), .forget(memoryID: memory)])
        // An alarm AlarmKit no longer lists isn't cancelled again.
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [], listed: [], now: now), [.forget(memoryID: memory)])
    }

    func testAReminderChangedToAPlaceOrMonthlyStopsRinging() {
        let alarm = UUID()
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [alarm], signature: "x")
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [place()], listed: [alarm], now: now),
                       [.cancel([alarm]), .forget(memoryID: memory)])
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(26, 9), repeats: .monthly)], listed: [alarm], now: now),
                       [.cancel([alarm]), .forget(memoryID: memory)])
    }

    func testAPassedOneOffIsLeftAloneSoASnoozedAlarmKeepsRinging() {
        let alarm = UUID()
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [alarm], signature: ReminderRingPlan.once(at(24, 11)).signature)
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(24, 11))], listed: [alarm], now: now), [])
    }

    func testAnUnreadableAlarmListTouchesNothing() {
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [UUID()], signature: "x")
        XCTAssertEqual(RingingReminderSync.steps(entries: [entry], reminders: [], listed: nil, now: now), [])
        XCTAssertFalse(RingingReminderSync.isRinging(entry, reminder: reminder(at(25, 8)), listed: nil, now: now))
    }

    func testNewWordsOnTheRingingScreenSetTheAlarmAgain() {
        let alarm = UUID()
        let plan = ReminderRingPlan.once(at(25, 8))
        let entry = RingingReminderEntry(memoryID: memory, alarmIDs: [alarm], signature: RingingReminderSync.signature(plan, title: "Leki"))
        let same = RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(25, 8))], listed: [alarm], now: now) { _ in "Leki" }
        XCTAssertEqual(same, [])
        // "Show note text" switched off: the screen must say "Przypomnienie" instead.
        let hidden = RingingReminderSync.steps(entries: [entry], reminders: [reminder(at(25, 8))], listed: [alarm], now: now) { _ in "Przypomnienie" }
        XCTAssertEqual(hidden, [.cancel([alarm]), .schedule(memoryID: memory, plan: plan)])
        XCTAssertTrue(RingingReminderSync.isRinging(entry, reminder: reminder(at(25, 8)), listed: [alarm], now: now, title: "Leki"))
    }

    func testOnlyNotesThatAskedToRingAreTouched() {
        let other = reminder(at(25, 8), memoryID: UUID())
        XCTAssertEqual(RingingReminderSync.steps(entries: [], reminders: [other], listed: [], now: now), [])
    }

    // MARK: By voice

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: "remind_me_about_note", parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testTheAgentCanAskForARingButOnlyAsAProposal() {
        guard case .remindAboutNote(let ringing) = parse(#"{"note":"Leki","due":"2026-10-25T08:00","repeat":"daily","ring":true}"#) else {
            return XCTFail("expected a reminder")
        }
        XCTAssertTrue(ringing.rings)
        XCTAssertEqual(ringing.repeats, .daily)
        guard case .remindAboutNote(let plain) = parse(#"{"note":"Leki","due":"2026-10-25T08:00"}"#) else {
            return XCTFail("expected a reminder")
        }
        XCTAssertFalse(plain.rings, "without ring it is a notification, as before")
    }

    func testTheReplySaysRingingOnlyWhenTheAlarmIsConfirmed() {
        XCTAssertTrue(VoiceToolReply.noteReminderRingLine(confirmed: true).contains("even in Silent mode"))
        let unconfirmed = VoiceToolReply.noteReminderRingLine(confirmed: false)
        XCTAssertTrue(unconfirmed.contains("didn't confirm"))
        XCTAssertFalse(unconfirmed.contains("It also rings"))
    }

    func testEntriesSurviveBeingWrittenAndReadBack() throws {
        let entries = [RingingReminderEntry(memoryID: memory, alarmIDs: [UUID()], signature: "weekly:8:0:2,3")]
        XCTAssertEqual(try JSONDecoder().decode([RingingReminderEntry].self, from: JSONEncoder().encode(entries)), entries)
    }
}
