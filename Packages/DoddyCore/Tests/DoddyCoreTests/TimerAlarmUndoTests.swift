import XCTest
@testable import DoddyCore

/// Step 2c of decision `2026-11-14-spoken-yes-and-fewer-cards`: a timer Doddy started and an alarm Doddy set get
/// Undo in "What Doddy did", so they can run when asked, without a card. Undo is kept only for one the iPhone
/// listed afterwards (or the one an unconfirmed try started after all), stops a timer paused or not, ends for a one-off
/// alarm when it rings, needs the Timers switch like setting one, and its sheet says exactly what will be stopped or
/// turned off.
final class TimerAlarmUndoTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(10, 12) }

    private let identifier = "doddy.timer.t1-abc.6F1C2D9E-7A51-4C8B-9E0D-2B3A4C5D6E7F"

    private func timer(seconds: Int = 600, label: String? = "Pasta") -> (TimerDraft, PendingTimer) {
        (TimerDraft(seconds: seconds, label: label), PendingTimer(identifier: identifier, firesAt: now.addingTimeInterval(TimeInterval(seconds)), ring: .alarm))
    }

    private func alarm(day: Int = 11, hour: Int = 7, repeats: AlarmRepeat? = nil, label: String? = "Gym") -> (AlarmDraft, AlarmEntry) {
        let draft = AlarmDraft(
            first: ReminderDue(year: 2026, month: 10, day: day, hour: hour, minute: 0, timeZoneID: "Europe/Warsaw"), repeats: repeats, label: label)
        let entry = AlarmEntry(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, clock: draft.clock, label: label,
                               summary: draft.summary, key: AlarmIdempotency.key(draft))
        return (draft, entry)
    }

    private func row(_ request: VoiceToolRequest, reply: String, undo: ActivityUndo?) -> ActivityEntry {
        ActivityEntry(request: ActivityRequest.describe(request, calendar: calendar)!, reply: reply, at: now, undo: undo)
    }

    // MARK: When Undo is kept

    func testATimerTheIPhoneListedCanBeStoppedPausedOrNot() throws {
        let (draft, running) = timer()
        let undo = try XCTUnwrap(ActivityUndo.startedTimer(.started(running), draft: draft))
        XCTAssertEqual(undo, .startedTimer(identifier: identifier, firesAt: running.firesAt, seconds: 600, label: "Pasta"))
        XCTAssertNil(undo.until, "a paused timer rings later than it was set to: the iPhone's list decides at the tap")
        let done = row(.setTimer(draft), reply: VoiceToolReply.timer(.started(running), draft: draft, calendar: calendar), undo: undo)
        XCTAssertEqual(done.outcome, .done)
        XCTAssertEqual(done.undo, undo)
        XCTAssertTrue(done.canUndo(now: now.addingTimeInterval(599)))
        XCTAssertTrue(done.canUndo(now: running.firesAt.addingTimeInterval(3_600)), "paused on the Lock Screen, it may still be there")
        XCTAssertFalse(done.canUndo(now: now.addingTimeInterval(24 * 3_600)), "the day's window still ends it")
    }

    func testTheTimerAnUnconfirmedTryStartedGetsTheUndo() throws {
        // `alreadyRunning` only follows a try Doddy couldn't confirm, whose row says "Not sure" and has no Undo.
        let (draft, running) = timer()
        let undo = try XCTUnwrap(ActivityUndo.startedTimer(.alreadyRunning(running), draft: draft))
        XCTAssertEqual(undo, .startedTimer(identifier: identifier, firesAt: running.firesAt, seconds: 600, label: "Pasta"))
        let found = row(.setTimer(draft), reply: VoiceToolReply.timer(.alreadyRunning(running), draft: draft, calendar: calendar), undo: undo)
        XCTAssertEqual(found.outcome, .alreadyThere, "the row still says nothing new was started")
        XCTAssertTrue(found.canUndo(now: now))
    }

    func testOnlyATimerDoddyStartedAndSawGetsUndo() {
        let (draft, running) = timer()
        XCTAssertNil(ActivityUndo.startedTimer(.unknown, draft: draft))
        XCTAssertNil(ActivityUndo.startedTimer(.notStarted("No."), draft: draft))
        // A reply that isn't "done" drops Undo even if one was passed.
        let undo = ActivityUndo.startedTimer(.started(running), draft: draft)
        XCTAssertNil(row(.setTimer(draft), reply: VoiceToolReply.timer(.unknown, draft: draft, calendar: calendar), undo: undo).undo)
        XCTAssertNil(row(.setTimer(draft), reply: VoiceToolReply.declinedTimer, undo: undo).undo)
    }

    func testAOneOffAlarmCanBeTurnedOffUntilItRingsAndARepeatingOneForTheDay() throws {
        let (draft, set) = alarm()
        let undo = try XCTUnwrap(ActivityUndo.setAlarm(.set(set), draft: draft, calendar: calendar))
        XCTAssertEqual(undo, .setAlarm(id: set.id, clock: "07:00", repeats: nil, label: "Gym", ringsAt: date(11, 7)))
        let done = row(.setAlarm(draft), reply: VoiceToolReply.alarm(.set(set)), undo: undo)
        XCTAssertEqual(done.outcome, .done)
        XCTAssertTrue(done.canUndo(now: date(11, 6, 59)))
        XCTAssertFalse(done.canUndo(now: date(11, 7)))

        let (daily, repeating) = alarm(repeats: .weekdays)
        let every = try XCTUnwrap(ActivityUndo.setAlarm(.set(repeating), draft: daily, calendar: calendar))
        XCTAssertNil(every.until, "a repeating alarm is kept for the day's window only")
        let repeatingRow = row(.setAlarm(daily), reply: VoiceToolReply.alarm(.set(repeating)), undo: every)
        XCTAssertTrue(repeatingRow.canUndo(now: now.addingTimeInterval(23 * 3_600)))
        XCTAssertFalse(repeatingRow.canUndo(now: now.addingTimeInterval(24 * 3_600)))
    }

    func testAnAlarmThatWasAlreadySetOrNotConfirmedGetsNoUndo() {
        let (draft, set) = alarm()
        XCTAssertNil(ActivityUndo.setAlarm(.alreadySet(set), draft: draft, calendar: calendar),
                     "set by an earlier, confirmed request: that row has its own Undo")
        XCTAssertNil(ActivityUndo.setAlarm(.unknown, draft: draft, calendar: calendar, afterUnconfirmedTry: true))
        XCTAssertNil(ActivityUndo.setAlarm(.notSet("No."), draft: draft, calendar: calendar, afterUnconfirmedTry: true))
        XCTAssertNil(ActivityUndo.setAlarm(.unknown, draft: draft, calendar: calendar))
        XCTAssertNil(ActivityUndo.setAlarm(.notAllowed, draft: draft, calendar: calendar))
        XCTAssertNil(ActivityUndo.setAlarm(.needsNewerIOS, draft: draft, calendar: calendar))
        XCTAssertNil(ActivityUndo.setAlarm(.notSet("No."), draft: draft, calendar: calendar))
    }

    func testTheAlarmAnUnconfirmedTrySetGetsTheUndo() throws {
        let (draft, set) = alarm()
        let undo = try XCTUnwrap(ActivityUndo.setAlarm(.alreadySet(set), draft: draft, calendar: calendar, afterUnconfirmedTry: true))
        XCTAssertEqual(undo, .setAlarm(id: set.id, clock: "07:00", repeats: nil, label: "Gym", ringsAt: date(11, 7)))
        let found = row(.setAlarm(draft), reply: VoiceToolReply.alarm(.alreadySet(set)), undo: undo)
        XCTAssertEqual(found.outcome, .alreadyThere)
        XCTAssertTrue(found.canUndo(now: now))
    }

    func testAnAlreadyThereRowElsewhereStillHasNoUndo() {
        // Only timers and alarms found after an unconfirmed try keep it; an event already in Calendar is the user's.
        let event = CalendarEventSummary(title: "Dentist", start: date(11, 9), end: date(11, 10), allDay: false)
        let there = ActivityEntry(at: now, app: .calendar, title: "Add event", detail: nil, outcome: .alreadyThere,
                                  undo: .addedEvent(eventID: "E1", event: event))
        XCTAssertFalse(there.canUndo(now: now))
        let (draft, running) = timer()
        let notSure = ActivityEntry(at: now, app: .timers, title: "Set timer", detail: nil, outcome: .notSure,
                                    undo: ActivityUndo.startedTimer(.started(running), draft: draft))
        XCTAssertFalse(notSure.canUndo(now: now))
    }

    // MARK: Where it is checked and what stops it

    func testItsTheTimersConnectionLikeSettingOne() {
        let (draft, running) = timer()
        let (alarmDraft, set) = alarm()
        for undo in [ActivityUndo.startedTimer(.started(running), draft: draft)!, ActivityUndo.setAlarm(.set(set), draft: alarmDraft, calendar: calendar)!] {
            XCTAssertEqual(undo.app, .timers)
            XCTAssertEqual(undo.connection, .timers, "sent to the iPhone's timers, never to the notes store")
            XCTAssertNil(undo.memoryID)
            XCTAssertEqual(undo.placeName, "Timers")
            XCTAssertEqual(undo.blocked(pauseAll: true, connectionOn: true), "Connections are paused in Settings.")
            XCTAssertEqual(undo.blocked(pauseAll: false, connectionOn: false), "Timers is off in Settings, Connections.")
            XCTAssertNil(undo.blocked(pauseAll: false, connectionOn: true))
            XCTAssertFalse(undo.isSameChange(event: nil, reminderID: nil))
        }
    }

    func testUndoThatStillMeansCalendarAndRemindersOnly() {
        let (draft, running) = timer()
        let timerRow = ActivityEntry(at: now, app: .timers, title: "Set timer", detail: nil, outcome: .done,
                                     undo: ActivityUndo.startedTimer(.started(running), draft: draft))
        XCTAssertTrue(timerRow.canUndo(now: now))
        XCTAssertNil(ActivityUndo.latest(in: [timerRow], since: now.addingTimeInterval(-60), now: now),
                     "the undo_last tool and its description name Calendar and Reminders; timers are undone in What Doddy did")
        let event = CalendarEventSummary(title: "Dentist", start: date(11, 9), end: date(11, 10), allDay: false)
        let eventRow = ActivityEntry(at: now.addingTimeInterval(-30), app: .calendar, title: "Add event", detail: nil, outcome: .done,
                                     undo: .addedEvent(eventID: "E1", event: event))
        XCTAssertEqual(ActivityUndo.latest(in: [timerRow, eventRow], since: now.addingTimeInterval(-60), now: now), eventRow)
    }

    // MARK: The sheet

    func testTheSheetSaysWhatWillBeStoppedInBothLanguages() {
        let (draft, running) = timer()
        let pasta = ActivityUndo.startedTimer(.started(running), draft: draft)!
        XCTAssertEqual(pasta.question(.english), "Stop the timer “Pasta” (10 min)?")
        XCTAssertEqual(pasta.question(.polish), "Zatrzymać minutnik „Pasta” (10 min)?")
        XCTAssertEqual(pasta.buttonTitle(.english), "Stop timer")
        XCTAssertEqual(pasta.buttonTitle(.polish), "Zatrzymaj")
        XCTAssertEqual(pasta.explanation(calendar: calendar, language: .english),
                       "Doddy started this timer (set to ring at 12:10). Only this timer is stopped, and only if the iPhone still has it, paused or not.")
        XCTAssertEqual(pasta.explanation(calendar: calendar, language: .polish),
                       "Doddy uruchomił ten minutnik (miał zadzwonić o 12:10). Zatrzymany zostanie tylko ten minutnik i tylko wtedy, gdy iPhone nadal go ma, także wstrzymany.")
        let plain = ActivityUndo.startedTimer(identifier: identifier, firesAt: now, seconds: 5_400, label: nil)
        XCTAssertEqual(plain.question(.english), "Stop the 1 h 30 min timer?")
        XCTAssertEqual(plain.question(.polish), "Zatrzymać minutnik na 1 h 30 min?")
    }

    func testTheSheetSaysWhatWillBeTurnedOffInBothLanguages() {
        let (draft, set) = alarm()
        let gym = ActivityUndo.setAlarm(.set(set), draft: draft, calendar: calendar)!
        XCTAssertEqual(gym.question(.english), "Turn off the alarm “Gym” at 07:00?")
        XCTAssertEqual(gym.question(.polish), "Wyłączyć budzik „Gym” o 07:00?")
        XCTAssertEqual(gym.buttonTitle(.english), "Turn off")
        XCTAssertEqual(gym.buttonTitle(.polish), "Wyłącz")
        XCTAssertTrue(gym.explanation(calendar: calendar, language: .english).contains("and it hasn't rung"))
        let (daily, repeating) = alarm(repeats: .weekdays, label: nil)
        let weekdays = ActivityUndo.setAlarm(.set(repeating), draft: daily, calendar: calendar)!
        XCTAssertEqual(weekdays.question(.english), "Turn off the 07:00 alarm?")
        XCTAssertEqual(weekdays.question(.polish), "Wyłączyć budzik o 07:00?")
        XCTAssertEqual(weekdays.explanation(calendar: calendar, language: .english),
                       "Doddy set this alarm (on weekdays). Only this alarm is turned off, on every day, and only if the iPhone still has it.")
        XCTAssertTrue(weekdays.explanation(calendar: calendar, language: .polish).contains("(w dni robocze)"))
    }

    // MARK: After the tap

    func testTheRowAndTheAgentSayWhatHappenedInPolishToo() {
        let (draft, running) = timer()
        let undo = ActivityUndo.startedTimer(.started(running), draft: draft)!
        let timerRow = ActivityEntry(at: now, app: .timers, title: "Set timer", detail: nil, outcome: .done, undo: undo)
        XCTAssertEqual(ActivityLog.undid(timerRow, result: .undone, at: now).note(.polish), "Cofnięto. Sprawdzone w Minutnikach.")
        XCTAssertEqual(ActivityLog.undid(timerRow, result: .notSure, at: now).note(.polish),
                       "Doddy nie mógł potwierdzić cofnięcia. Sprawdź Minutniki, zanim spróbujesz ponownie.")
        // Gone (it rang or was stopped) says so, not "it changed".
        let gone = ActivityLog.undid(timerRow, result: .leftAlone, at: now)
        XCTAssertEqual(gone.note, "Not undone: the timer already rang or was stopped, so there was nothing to stop.")
        XCTAssertEqual(gone.note(.polish), "Nie cofnięto: minutnik już zadzwonił albo został zatrzymany, więc nie było czego zatrzymać.")
        XCTAssertEqual(VoiceToolReply.undo(.leftAlone, undo), "not undone: the timer already rang or was stopped. Nothing changed.")
        let off = undo.blocked(pauseAll: false, connectionOn: false)!
        XCTAssertEqual(ActivityLog.undid(timerRow, result: .notDone(off), at: now).note(.polish),
                       "Nie cofnięto: Minutniki: wyłączone w Ustawieniach, Połączenia. Nic się nie zmieniło.")
        XCTAssertEqual(ActivityLog.undid(timerRow, result: .notDone(ActivityUndo.timersUnreadable), at: now).note(.polish),
                       "Nie cofnięto: Doddy nie mógł odczytać swoich minutników i budzików. Nic się nie zmieniło.")

        // The label is the agent's words, so it follows as data.
        XCTAssertEqual(VoiceToolReply.undo(.undone, undo), "undone: the timer was stopped. Checked. Its label:\n" + ToolData.block(["Label: \"Pasta\""]))
        let (alarmDraft, set) = alarm(label: nil)
        let alarmUndo = ActivityUndo.setAlarm(.set(set), draft: alarmDraft, calendar: calendar)!
        XCTAssertEqual(VoiceToolReply.undo(.undone, alarmUndo), "undone: the alarm was turned off. Checked.")

        let alarmRow = ActivityEntry(at: now, app: .timers, title: "Set alarm", detail: nil, outcome: .done, undo: alarmUndo)
        let alarmGone = ActivityLog.undid(alarmRow, result: .leftAlone, at: now)
        XCTAssertEqual(alarmGone.note, "Not undone: the alarm already rang or was turned off, so there was nothing to turn off.")
        XCTAssertEqual(alarmGone.note(.polish), "Nie cofnięto: budzik już zadzwonił albo został wyłączony, więc nie było czego wyłączyć.")
        XCTAssertEqual(VoiceToolReply.undo(.leftAlone, alarmUndo), "not undone: the alarm already rang or was turned off. Nothing changed.")
        // iOS refused twice and still lists it: nothing changed, and the row says so.
        let refused = ActivityLog.undid(alarmRow, result: .notDone(ActivityUndo.alarmNotTurnedOff), at: now)
        XCTAssertEqual(refused.note, "Not undone: The iPhone didn't turn the alarm off. Nothing changed.")
        XCTAssertEqual(refused.note(.polish), "Nie cofnięto: iPhone nie wyłączył budzika. Nic się nie zmieniło.")
        XCTAssertTrue(refused.canUndo(now: now), "nothing changed, so Undo can be tried again")
    }

    func testOtherPlacesStillSayItChanged() {
        let event = CalendarEventSummary(title: "Dentist", start: date(11, 9), end: date(11, 10), allDay: false)
        let eventRow = ActivityEntry(at: now, app: .calendar, title: "Add event", detail: nil, outcome: .done,
                                     undo: .addedEvent(eventID: "E1", event: event))
        XCTAssertEqual(ActivityLog.undid(eventRow, result: .leftAlone, at: now).note,
                       "Not undone: it changed in Calendar since Doddy did this, so Doddy left it alone.")
        XCTAssertEqual(VoiceToolReply.undo(.leftAlone, eventRow.undo!),
                       "not undone: it changed in Calendar since Doddy did it, so Doddy left it alone. Nothing changed.")
    }

    func testRowsWithTimerAndAlarmUndoSurviveSaving() throws {
        let (draft, running) = timer()
        let (alarmDraft, set) = alarm(repeats: .everyDay)
        for undo in [ActivityUndo.startedTimer(.started(running), draft: draft)!, ActivityUndo.setAlarm(.set(set), draft: alarmDraft, calendar: calendar)!] {
            let saved = ActivityEntry(at: now, app: .timers, title: "Set", detail: nil, outcome: .done, undo: undo)
            let data = try JSONEncoder().encode([saved])
            XCTAssertEqual(try JSONDecoder().decode([ActivityEntry].self, from: data), [saved])
        }
    }
}
