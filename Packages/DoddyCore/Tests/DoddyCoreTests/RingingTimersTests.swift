import XCTest
@testable import DoddyCore

/// ADR-611: timers ring through AlarmKit on iOS 26, everything the user set for a moment is Time
/// Sensitive, and the agent hears how a timer will ring. AlarmKit and UserNotifications
/// themselves only run on an iPhone.
final class RingingTimersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)
    private let eggs = TimerDraft(seconds: 600, label: "Eggs")

    // MARK: The id AlarmKit gets

    func testTheAlarmKitIdIsTheUUIDInTheTimerIdentifier() {
        let id = UUID()
        let identifier = TimerIdempotency.identifier(key: TimerIdempotency.key(eggs), id: id)
        XCTAssertEqual(TimerIdempotency.alarmID(fromIdentifier: identifier), id)
        // Timers from before ADR-320 had no key, only the UUID.
        XCTAssertEqual(TimerIdempotency.alarmID(fromIdentifier: "doddy.timer.\(id.uuidString)"), id)
        XCTAssertNil(TimerIdempotency.alarmID(fromIdentifier: "doddy.focus.\(id.uuidString)"))
        XCTAssertNil(TimerIdempotency.alarmID(fromIdentifier: "doddy.timer.t1-abc.not-a-uuid"))
    }

    // MARK: The book of AlarmKit timers

    private func note(_ id: UUID = UUID(), firesIn: TimeInterval = 600, notedAgo: TimeInterval = 0) -> RingingTimer {
        RingingTimer(
            alarmID: id, identifier: TimerIdempotency.identifier(key: TimerIdempotency.key(eggs), id: id),
            firesAt: now + firesIn, label: "Eggs", noted: now - notedAgo)
    }

    func testOnlyTimersAlarmKitListsArePending() {
        let running = note(firesIn: 300), alsoRunning = note(firesIn: 60), gone = note()
        let pending = RingingTimerBook.pending([running, gone, alsoRunning], listed: [running.alarmID, alsoRunning.alarmID])
        XCTAssertEqual(pending.map(\.identifier), [alsoRunning.identifier, running.identifier], "soonest first")
        XCTAssertEqual(pending.map(\.ring), [.alarm, .alarm])
        XCTAssertEqual(pending.first?.firesAt, now + 60)
    }

    func testAJustNotedTimerIsKeptUntilAlarmKitListsItButAnOldOneIsDropped() {
        let listed = note(notedAgo: 3_600), justNoted = note(notedAgo: 5), stale = note(notedAgo: RingingTimerBook.grace + 1)
        let kept = RingingTimerBook.kept([listed, justNoted, stale], listed: [listed.alarmID], now: now)
        XCTAssertEqual(kept, [listed, justNoted])
        // Kept is not running: only a listed timer counts.
        XCTAssertEqual(RingingTimerBook.pending(kept, listed: [listed.alarmID]).count, 1)
    }

    func testTheBookSurvivesBeingWrittenAndReadBack() throws {
        let notes = [note(), note(firesIn: 90)]
        let data = try JSONEncoder().encode(notes)
        XCTAssertEqual(try JSONDecoder().decode([RingingTimer].self, from: data), notes)
    }

    // MARK: What the agent hears

    func testTheAgentHearsHowTheTimerRings() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let draft = TimerDraft(seconds: 600, label: nil)
        let alarm = VoiceToolReply.timer(.started(PendingTimer(identifier: "doddy.timer.x", firesAt: now, ring: .alarm)), draft: draft, calendar: calendar)
        XCTAssertTrue(alarm.hasPrefix("added: timer 10 minutes, rings at "), alarm)
        XCTAssertTrue(alarm.contains("even in Silent mode or a Focus"), alarm)
        let notification = VoiceToolReply.timer(
            .started(PendingTimer(identifier: "doddy.timer.x", firesAt: now, ring: .notification)), draft: draft, calendar: calendar)
        XCTAssertTrue(notification.contains("in Silent mode it only vibrates"), notification)
        XCTAssertFalse(notification.contains("even in Silent mode"), "a notification never promises a ring through Silent mode")
        // A writer that doesn't say keeps the old line, word for word.
        XCTAssertEqual(
            VoiceToolReply.timer(.started(PendingTimer(identifier: "doddy.timer.x", firesAt: now)), draft: draft, calendar: calendar),
            VoiceToolReply.timerAdded(draft, endsAt: now, calendar: calendar))
    }

    func testTheLabelStillFollowsAsDataAfterTheRingLine() {
        let calendar = Calendar(identifier: .gregorian)
        let reply = VoiceToolReply.timerAdded(eggs, endsAt: now, calendar: calendar, ring: .alarm)
        let ring = reply.range(of: "Silent mode")!, label = reply.range(of: "<<<DATA")!
        XCTAssertLessThan(ring.lowerBound, label.lowerBound)
        XCTAssertTrue(reply.contains("Label: \"Eggs\""))
    }

    // MARK: How loudly

    func testOnlyWhatTheUserSetForAMomentIsTimeSensitive() {
        let urgent = DoddyNotificationKind.allCases.filter { $0.urgency == .timeSensitive }
        XCTAssertEqual(Set(urgent), [.timer, .focusDone, .noteReminder, .leaveBy, .eventNudge])
        // Doddy's own routines never push through a Focus.
        for routine in [DoddyNotificationKind.morningCheckIn, .eveningWrapUp, .weeklyLookBack, .tidyUp, .birthday, .openWays] {
            XCTAssertEqual(routine.urgency, .active, "\(routine)")
        }
    }

    func testEverythingTimeSensitivePlaysASoundAndTheQuietRoutinesStayQuiet() {
        for kind in DoddyNotificationKind.allCases where kind.urgency == .timeSensitive {
            XCTAssertTrue(kind.playsSound, "\(kind)")
        }
        XCTAssertFalse(DoddyNotificationKind.eveningWrapUp.playsSound)
        XCTAssertFalse(DoddyNotificationKind.weeklyLookBack.playsSound)
        XCTAssertFalse(DoddyNotificationKind.tidyUp.playsSound)
        XCTAssertTrue(DoddyNotificationKind.morningCheckIn.playsSound)
    }

    // MARK: Reminders that alert

    func testATimedReminderAlertsAtItsDueAndAWholeDayOneDoesNot() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let timed = ReminderDue(year: 2026, month: 10, day: 26, hour: 15, minute: 30, timeZoneID: "Europe/Warsaw")
        let write = ReminderWrite(ReminderDraft(title: "Zadzwonić do mamy", due: timed, notes: nil))
        XCTAssertEqual(write.alertDate(local: local), local.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15, minute: 30)))
        // A repeating reminder alerts at its first due too; Reminders moves it on each completion.
        let weekly = ReminderWrite(ReminderDraft(title: "Śmieci", due: timed, notes: nil, repeats: .init(frequency: .weekly)))
        XCTAssertNotNil(weekly.alertDate(local: local))
        let wholeDay = ReminderDue(year: 2026, month: 10, day: 26, timeZoneID: nil)
        XCTAssertNil(ReminderWrite(ReminderDraft(title: "Paczka", due: wholeDay, notes: nil)).alertDate(local: local))
        XCTAssertNil(ReminderWrite(ReminderDraft(title: "Kiedyś", due: nil, notes: nil)).alertDate(local: local))
    }

    func testAMovedReminderWithoutAnAlarmGetsOneButAnAlarmOfItsOwnIsLeftToMove() {
        let local = Calendar(identifier: .gregorian)
        let timed = ReminderDue(year: 2026, month: 10, day: 27, hour: 9, minute: 0, timeZoneID: "UTC")
        XCTAssertNotNil(ReminderAlert.addOnMove(hasAlarms: false, newDue: timed, local: local))
        XCTAssertNil(ReminderAlert.addOnMove(hasAlarms: true, newDue: timed, local: local), "its own alarm moves instead")
        XCTAssertNil(ReminderAlert.addOnMove(hasAlarms: false, newDue: ReminderDue(year: 2026, month: 10, day: 27, timeZoneID: nil), local: local))
        XCTAssertNil(ReminderAlert.addOnMove(hasAlarms: false, newDue: nil, local: local))
    }

    // MARK: Words

    func testTimerWordsInPolishAndEnglish() {
        XCTAssertEqual(TimerCopy.title(label: nil, .polish), "Minutnik")
        XCTAssertEqual(TimerCopy.title(label: "  ", .english), "Timer")
        XCTAssertEqual(TimerCopy.title(label: "Makaron", .polish), "Makaron")
        XCTAssertEqual(TimerCopy.notificationTitle(.polish), "Czas minął")
        XCTAssertEqual(TimerCopy.notificationBody(label: nil, seconds: 600, .polish), "Minutnik na 10 min skończył odliczanie.")
        XCTAssertEqual(TimerCopy.notificationBody(label: "Makaron", seconds: 90, .polish), "Makaron · minutnik na 1 min 30 s")
        XCTAssertEqual(TimerCopy.notificationBody(label: nil, seconds: 45, .english), "Your 45 s timer is done.")
        XCTAssertEqual(TimerCopy.button(.stop, .polish), "Zatrzymaj")
        XCTAssertEqual(TimerCopy.button(.repeatTimer, .polish), "Powtórz")
        XCTAssertEqual(TimerCopy.button(.resume, .english), "Resume")
        XCTAssertEqual(TimerCopy.focusBody(label: nil, minutes: 25, .polish), "Minęło 25 min skupienia.")
        XCTAssertEqual(TimerCopy.focusBody(label: "Raport", minutes: 25, .english), "Raport")
    }

    func testShortDurations() {
        XCTAssertEqual(TimerCopy.shortDuration(0, .english), "0 s")
        XCTAssertEqual(TimerCopy.shortDuration(60, .polish), "1 min")
        XCTAssertEqual(TimerCopy.shortDuration(3_600, .polish), "1 h")
        XCTAssertEqual(TimerCopy.shortDuration(5_405, .english), "1 h 30 min 5 s")
    }
}
