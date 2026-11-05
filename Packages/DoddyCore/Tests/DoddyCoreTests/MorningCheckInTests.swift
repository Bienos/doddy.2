import DoddyCore
import XCTest

/// Morning check-in (ADR-220): when it rings, what it says, and what the agent is given.
final class MorningCheckInTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testOffByDefaultAndRequestsMatchTheChoice() {
        let defaults = UserDefaults(suiteName: "MorningCheckInTests-\(UUID().uuidString)")!
        let stored = MorningCheckInSettings.stored(defaults)
        XCTAssertFalse(stored.isOn)
        XCTAssertEqual(stored.hour, 8)
        XCTAssertTrue(MorningCheckIn.requests(stored).isEmpty, "nothing is scheduled until it is turned on")

        let daily = MorningCheckIn.requests(MorningCheckInSettings(isOn: true, hour: 7, minute: 30))
        XCTAssertEqual(daily.count, 1)
        XCTAssertNil(daily[0].weekday)
        XCTAssertEqual([daily[0].hour, daily[0].minute], [7, 30])

        let weekdays = MorningCheckIn.requests(MorningCheckInSettings(isOn: true, weekdaysOnly: true))
        XCTAssertEqual(weekdays.compactMap(\.weekday), [2, 3, 4, 5, 6])
        XCTAssertTrue(weekdays.allSatisfy { MorningCheckIn.isCheckIn(notificationID: $0.id) })
        XCTAssertEqual(Set(weekdays.map(\.id)).count, 5)
        XCTAssertEqual(weekdays.map(\.id), (2...6).map { "doddy.morning-checkin.weekday\($0)" },
                       "the id carries the weekday number, not \"Optional(2)\"")

        MorningCheckInSettings(isOn: true, hour: 25, minute: -3, weekdaysOnly: true).store(defaults)
        XCTAssertEqual(MorningCheckInSettings.stored(defaults), MorningCheckInSettings(isOn: true, hour: 23, minute: 0, weekdaysOnly: true))
    }

    func testTheNotificationSaysNothingPersonal() {
        XCTAssertEqual(MorningCheckIn.body(.english), "A quick look at your day?")
        XCTAssertEqual(MorningCheckIn.body(.polish), "Szybki rzut oka na Twój dzień?")
        XCTAssertFalse(MorningCheckIn.isCheckIn(notificationID: "doddy.note-reminder.x"))
    }

    func testTodayEndsAtMidnightOnClockChangeDays() throws {
        let note = try MemoryRecord(id: UUID(), rawText: "Late call", source: .explicitText, category: .other, capturedAt: date(8))
        func briefing(now: Date, fireAt: Date) -> MorningBriefing {
            let reminder = MemoryReminder(id: UUID(), memoryID: note.id, fireAt: fireAt, timeZoneID: "Europe/Warsaw", createdAt: now)
            return MorningBriefing.make(now: now, memories: [note], lists: [], reminders: [reminder], privateNotes: PrivateNotes(), calendar: calendar)
        }
        func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        // 25 October 2026 has 25 hours in Warsaw: 23:30 is still today.
        XCTAssertEqual(briefing(now: at(10, 25, 8), fireAt: at(10, 25, 23, 30)).reminders.count, 1)
        // 29 March 2026 has 23 hours: 00:30 the next day is not today.
        XCTAssertEqual(briefing(now: at(3, 29, 8), fireAt: at(3, 30, 0, 30)).reminders.count, 0)
    }

    func testBriefingHasTodaysRemindersAndOpenListsOnly() throws {
        let now = date(8)
        let dentist = try MemoryRecord(id: UUID(), rawText: "Dentist at Mokotów", source: .explicitText, category: .other, capturedAt: now)
        let bins = try MemoryRecord(id: UUID(), rawText: "Put the bins out", source: .explicitText, category: .other, capturedAt: now)
        let later = try MemoryRecord(id: UUID(), rawText: "Renew passport", source: .explicitText, category: .other, capturedAt: now)
        let reminders = [
            MemoryReminder(id: UUID(), memoryID: bins.id, fireAt: date(19), timeZoneID: "Europe/Warsaw", createdAt: now),
            MemoryReminder(id: UUID(), memoryID: dentist.id, fireAt: date(9, 30), timeZoneID: "Europe/Warsaw", createdAt: now),
            MemoryReminder(id: UUID(), memoryID: later.id, fireAt: date(9, day: 10), timeZoneID: "Europe/Warsaw", createdAt: now),
            MemoryReminder(id: UUID(), memoryID: bins.id, fireAt: date(7), timeZoneID: "Europe/Warsaw", createdAt: now),
        ]
        let shoppingRecord = try MemoryRecord(id: UUID(), rawText: "Shopping", source: .explicitVoice, category: .list, capturedAt: now)
        let doneRecord = try MemoryRecord(id: UUID(), rawText: "Packing", source: .explicitVoice, category: .list, capturedAt: now)
        let shopping = DoddyList(record: shoppingRecord, items: [
            ListItem(id: UUID(), listID: shoppingRecord.id, text: "eggs", source: .voice, addedAt: now, doneAt: nil, position: 0),
            ListItem(id: UUID(), listID: shoppingRecord.id, text: "milk", source: .voice, addedAt: now, doneAt: nil, position: 1),
        ])
        let packing = DoddyList(record: doneRecord, items: [
            ListItem(id: UUID(), listID: doneRecord.id, text: "socks", source: .voice, addedAt: now, doneAt: now, position: 0),
        ])

        let briefing = MorningBriefing.make(
            now: now, memories: [dentist, bins, later], lists: [packing, shopping], reminders: reminders, privateNotes: PrivateNotes(),
            calendar: calendar)
        XCTAssertEqual(briefing.reminders.map(\.text), ["Dentist at Mokotów", "Put the bins out"], "today, ahead, in time order")
        XCTAssertEqual(briefing.lists.map(\.name), ["Shopping"], "only lists with something left")
        XCTAssertEqual(briefing.lists.first?.openCount, 2)

        let text = MorningCheckInPrompt.render(briefing, timeZone: calendar.timeZone)
        XCTAssertTrue(text.contains("Friday 9 October"))
        XCTAssertTrue(text.contains("09:30 Dentist at Mokotów; 19:00 Put the bins out."))
        XCTAssertTrue(text.contains("Shopping (2)"))
        XCTAssertFalse(text.contains("passport"))
        XCTAssertEqual(MorningCheckInPrompt.render(nil), "none")

        let empty = MorningBriefing.make(now: now, memories: [], lists: [], reminders: [], privateNotes: PrivateNotes(), calendar: calendar)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(MorningCheckInPrompt.render(empty).contains("Doddy reminders today: none."))
    }

    /// ADR-722: the check-in used to be built from every note, so the words of a Private note with a reminder today
    /// went to the voice agent. Now they never enter the briefing, and the prompt leaves the reminder out altogether.
    func testAPrivateNotesWordsNeverReachTheBriefingOrThePrompt() throws {
        let now = date(8)
        let secret = try MemoryRecord(id: UUID(), rawText: "Bank PIN 4417 for the safe", source: .explicitText, category: .other, capturedAt: now)
        let plain = try MemoryRecord(id: UUID(), rawText: "Dentist at Mokotów", source: .explicitText, category: .other, capturedAt: now)
        let reminders = [
            MemoryReminder(id: UUID(), memoryID: secret.id, fireAt: date(9), timeZoneID: "Europe/Warsaw", createdAt: now),
            MemoryReminder(id: UUID(), memoryID: plain.id, fireAt: date(10), timeZoneID: "Europe/Warsaw", createdAt: now),
        ]
        let briefing = MorningBriefing.make(
            now: now, memories: [secret, plain], lists: [], reminders: reminders,
            privateNotes: PrivateNotes(ids: [secret.id]), calendar: calendar)

        // The screen still lists it, as "Private note": "None set for today" would be untrue.
        XCTAssertEqual(briefing.reminders.map(\.text), [PrivateNotes.hiddenText, "Dentist at Mokotów"])
        XCTAssertEqual(briefing.reminders.map(\.isPrivate), [true, false])
        XCTAssertFalse(String(describing: briefing).contains("4417"), "the words are not in the briefing at all")
        XCTAssertFalse(String(describing: briefing).contains("PIN"))

        let prompt = MorningCheckInPrompt.render(briefing, timeZone: calendar.timeZone)
        XCTAssertFalse(prompt.contains("4417"))
        XCTAssertFalse(prompt.contains("PIN"))
        XCTAssertFalse(prompt.contains(PrivateNotes.hiddenText), "the agent is not even told a private reminder exists")
        XCTAssertTrue(prompt.contains("10:00 Dentist at Mokotów."), "the other reminder is given as before")
        XCTAssertFalse(prompt.contains("09:00"))
    }

    func testOnlyPrivateRemindersTodayReadAsNoneForTheAgentButNotForTheScreen() throws {
        let now = date(8)
        let secret = try MemoryRecord(id: UUID(), rawText: "Call the clinic about the results", source: .explicitText, category: .other, capturedAt: now)
        let reminder = MemoryReminder(id: UUID(), memoryID: secret.id, fireAt: date(15), timeZoneID: "Europe/Warsaw", createdAt: now)
        let briefing = MorningBriefing.make(
            now: now, memories: [secret], lists: [], reminders: [reminder],
            privateNotes: PrivateNotes(ids: [secret.id]), calendar: calendar)
        XCTAssertEqual(briefing.reminders.count, 1)
        XCTAssertFalse(briefing.isEmpty, "the screen has a line to show")
        XCTAssertTrue(MorningCheckInPrompt.render(briefing, timeZone: calendar.timeZone).contains("Doddy reminders today: none."))

        // The same note, not private: its words are in the prompt, so the filter above is what hides it.
        let open = MorningBriefing.make(
            now: now, memories: [secret], lists: [], reminders: [reminder], privateNotes: PrivateNotes(), calendar: calendar)
        XCTAssertTrue(MorningCheckInPrompt.render(open, timeZone: calendar.timeZone).contains("15:00 Call the clinic about the results"))
    }

    func testWhatLeavesThisIPhoneSaysSoOnlyWhenOn() {
        func voiceRow(_ on: Bool) -> String {
            let state = DataFlowState(
                rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false, connectionsOn: [],
                pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: false, morningCheckInOn: on)
            return DataFlow.rows(state).first { $0.id == "elevenlabs" }?.what ?? ""
        }
        XCTAssertTrue(voiceRow(true).contains("morning check-in"))
        XCTAssertFalse(voiceRow(false).contains("morning check-in"))
    }
}
