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

        MorningCheckInSettings(isOn: true, hour: 25, minute: -3, weekdaysOnly: true).store(defaults)
        XCTAssertEqual(MorningCheckInSettings.stored(defaults), MorningCheckInSettings(isOn: true, hour: 23, minute: 0, weekdaysOnly: true))
    }

    func testTheNotificationSaysNothingPersonal() {
        XCTAssertEqual(MorningCheckIn.body(.english), "A quick look at your day?")
        XCTAssertEqual(MorningCheckIn.body(.polish), "Szybki rzut oka na Twój dzień?")
        XCTAssertFalse(MorningCheckIn.isCheckIn(notificationID: "doddy.note-reminder.x"))
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
            now: now, memories: [dentist, bins, later], lists: [packing, shopping], reminders: reminders, calendar: calendar)
        XCTAssertEqual(briefing.reminders.map(\.text), ["Dentist at Mokotów", "Put the bins out"], "today, ahead, in time order")
        XCTAssertEqual(briefing.lists.map(\.name), ["Shopping"], "only lists with something left")
        XCTAssertEqual(briefing.lists.first?.openCount, 2)

        let text = MorningCheckInPrompt.render(briefing, timeZone: calendar.timeZone)
        XCTAssertTrue(text.contains("Friday 9 October"))
        XCTAssertTrue(text.contains("09:30 Dentist at Mokotów; 19:00 Put the bins out."))
        XCTAssertTrue(text.contains("Shopping (2)"))
        XCTAssertFalse(text.contains("passport"))
        XCTAssertEqual(MorningCheckInPrompt.render(nil), "none")

        let empty = MorningBriefing.make(now: now, memories: [], lists: [], reminders: [], calendar: calendar)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(MorningCheckInPrompt.render(empty).contains("Doddy reminders today: none."))
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
