import DoddyCore
import XCTest

final class OpenLoopsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    /// Thursday 5 November 2026 is "today"; `now` is noon.
    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5 + dayOffset))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private var now: Date { at(12) }

    private func build(_ input: OpenLoopsInput, limit: Int = OpenLoopsAgenda.defaultLimit) -> OpenLoopsAgenda {
        OpenLoopsBuilder.build(input, now: now, calendar: calendar, limitPerSection: limit)
    }

    private func titles(_ agenda: OpenLoopsAgenda, _ section: OpenLoopSection) -> [String] {
        agenda.items(in: section).map { item in
            if case .text(let text) = item.title { return text }
            return "(hidden)"
        }
    }

    private func item(_ agenda: OpenLoopsAgenda, _ title: String) -> OpenLoopItem? {
        agenda.allItems.first { $0.title == .text(title) }
    }

    // MARK: Reminders on notes

    func testAOneOffNoteReminderIsOverdueDueTodayOrLater() {
        let past = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: at(10), timeZoneID: "Europe/Warsaw", createdAt: at(8, dayOffset: -3))
        let evening = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: at(18), timeZoneID: "Europe/Warsaw", createdAt: at(8, dayOffset: -3))
        let tomorrow = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: at(9, dayOffset: 1), timeZoneID: "Europe/Warsaw", createdAt: at(8, dayOffset: -3))
        let agenda = build(OpenLoopsInput(noteReminders: [
            OpenLoopNoteReminder(reminder: tomorrow, title: .text("Tomorrow note")),
            OpenLoopNoteReminder(reminder: evening, title: .text("Evening note")),
            OpenLoopNoteReminder(reminder: past, title: .text("Past note")),
        ]))
        XCTAssertEqual(titles(agenda, .today), ["Past note", "Evening note"], "earliest first")
        XCTAssertEqual(item(agenda, "Past note")?.status, .overdue)
        XCTAssertEqual(item(agenda, "Evening note")?.status, .dueToday(hasTime: true))
        XCTAssertEqual(titles(agenda, .later), ["Tomorrow note"])
        XCTAssertEqual(item(agenda, "Tomorrow note")?.status, .scheduled)
    }

    func testAPrivateNoteKeepsItsWordsHidden() {
        let reminder = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: at(18), timeZoneID: "Europe/Warsaw", createdAt: at(8, dayOffset: -1))
        let agenda = build(OpenLoopsInput(noteReminders: [OpenLoopNoteReminder(reminder: reminder, title: .hidden)]))
        XCTAssertEqual(agenda.items(in: .today).first?.title, .hidden)
        XCTAssertEqual(agenda.items(in: .today).first?.source, .noteReminder)
    }

    func testAPlaceReminderIsListedLaterWithoutAnyTime() throws {
        let place = try ReminderPlace(name: "Post office", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true)
        let reminder = MemoryReminder(id: UUID(), memoryID: UUID(), trigger: .place(place), createdAt: at(8, dayOffset: -1))
        let agenda = build(OpenLoopsInput(noteReminders: [OpenLoopNoteReminder(reminder: reminder, title: .text("Parcel slip"))]))
        XCTAssertEqual(item(agenda, "Parcel slip")?.section, .later)
        XCTAssertEqual(item(agenda, "Parcel slip")?.status, .atPlace("Post office"))
        XCTAssertNil(item(agenda, "Parcel slip")?.when)
    }

    func testARepeatingReminderIsDueUntilDoneThenShowsItsNextTime() {
        let anchor = at(8, dayOffset: -4)
        func daily(lastDone: Date?) -> MemoryReminder {
            MemoryReminder(id: UUID(), memoryID: UUID(), trigger: .time(fireAt: anchor, timeZoneID: "Europe/Warsaw"), createdAt: anchor,
                           repeats: .daily, lastDoneAt: lastDone)
        }
        // 08:00 has passed today and wasn't marked done.
        XCTAssertEqual(build(OpenLoopsInput(noteReminders: [OpenLoopNoteReminder(reminder: daily(lastDone: nil), title: .text("Vitamins"))]))
            .items(in: .today).first?.status, .overdue)
        XCTAssertEqual(build(OpenLoopsInput(noteReminders: [OpenLoopNoteReminder(reminder: daily(lastDone: nil), title: .text("Vitamins"))]))
            .items(in: .today).first?.when, at(8), "ordered by the occurrence that is waiting, not the first one ever set")
        // Done this morning: the next one is tomorrow 08:00, so it is later.
        let done = build(OpenLoopsInput(noteReminders: [OpenLoopNoteReminder(reminder: daily(lastDone: at(8, 30)), title: .text("Vitamins"))]))
        XCTAssertEqual(done.items(in: .later).first?.status, .repeating(.daily))
        XCTAssertEqual(done.items(in: .later).first?.when, at(8, dayOffset: 1))
        // An evening repeat still to come today stays in Today.
        let evening = MemoryReminder(id: UUID(), memoryID: UUID(), trigger: .time(fireAt: at(18, dayOffset: -4), timeZoneID: "Europe/Warsaw"),
                                     createdAt: anchor, repeats: .daily, lastDoneAt: at(18, 5, dayOffset: -1))
        let later = build(OpenLoopsInput(noteReminders: [OpenLoopNoteReminder(reminder: evening, title: .text("Pills"))]))
        XCTAssertEqual(later.items(in: .today).first?.status, .repeating(.daily))
        XCTAssertEqual(later.items(in: .today).first?.when, at(18))
    }

    // MARK: Apple Reminders and the calendar

    func testAppleRemindersAreOverdueDueTodayLaterOrWithoutADate() {
        let agenda = build(OpenLoopsInput(appleReminders: [
            ReminderSummary(id: "r1", title: "Pay rent", due: at(0, dayOffset: -1), dueHasTime: false),
            ReminderSummary(id: "r2", title: "Call mum", due: at(18), dueHasTime: true),
            ReminderSummary(id: "r3", title: "Someday", due: nil, dueHasTime: false),
            ReminderSummary(id: "r4", title: "Next week", due: at(9, dayOffset: 7), dueHasTime: true),
            ReminderSummary(id: "r5", title: "Today, no time", due: at(0), dueHasTime: false),
        ]))
        XCTAssertEqual(item(agenda, "Pay rent")?.status, .overdue)
        XCTAssertEqual(item(agenda, "Call mum")?.status, .dueToday(hasTime: true))
        XCTAssertEqual(item(agenda, "Today, no time")?.status, .dueToday(hasTime: false), "a day-only reminder isn't overdue during its day")
        XCTAssertEqual(item(agenda, "Someday")?.status, .noDate)
        XCTAssertEqual(titles(agenda, .later), ["Next week", "Someday"], "a row with no moment goes last")
    }

    func testEventsAreListedForTodayAndLaterOnlyWhenANudgeHoldsThem() {
        func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEventSummary {
            CalendarEventSummary(id: "ev-\(title)", title: title, start: start, end: end, allDay: allDay)
        }
        let trip = event("Trip", at(9, dayOffset: 1), at(10, dayOffset: 1))
        let moved = event("Dentist", at(10, dayOffset: 2), at(11, dayOffset: 2))
        let events = [
            event("Standup", at(9), at(9, 15)),
            event("Lunch", at(11, 30), at(12, 30)),
            event("Holiday", at(0), at(0, dayOffset: 1), allDay: true),
            trip, moved,
            event("Tomorrow, no nudge", at(14, dayOffset: 1), at(15, dayOffset: 1)),
        ]
        let nudges = [
            ScheduledNudge(id: EventNudgePlan.identifier(eventID: "ev-Trip", leadMinutes: 30), fireAt: at(8, 30, dayOffset: 1)),
            // Set for the old time: the event now starts an hour later than when this nudge was made.
            ScheduledNudge(id: EventNudgePlan.identifier(eventID: "ev-Dentist", leadMinutes: 10), fireAt: at(8, 50, dayOffset: 2)),
        ]
        let agenda = build(OpenLoopsInput(events: events, nudges: nudges))
        XCTAssertEqual(titles(agenda, .today), ["Holiday", "Lunch"], "the ended one is gone; the all-day one starts at midnight")
        XCTAssertEqual(item(agenda, "Lunch")?.status, .scheduled, "in progress still counts as today")
        XCTAssertEqual(titles(agenda, .later), ["Trip", "Dentist"])
        XCTAssertEqual(item(agenda, "Trip")?.status, .nudgeSet(leadMinutes: 30))
        XCTAssertEqual(item(agenda, "Dentist")?.status, .nudgeAtOldTime)
        XCTAssertNil(item(agenda, "Tomorrow, no nudge"), "Doddy holds nothing for it")
    }

    // MARK: Tasks, watches, parcels

    private func errand(_ title: String, _ state: ErrandState, updated: Date) -> StoredErrand {
        var record = StoredErrand(id: UUID(), createdAt: updated, state: state,
                                  draft: ErrandDraft(words: title, brief: title, title: title))
        record.updatedAt = updated
        return record
    }

    func testTasksRunningWaitFinishedOnesCountForAWeekAndUnknownIsNeverSuccess() {
        let agenda = build(OpenLoopsInput(errands: [
            errand("Queued", .queued, updated: at(11)),
            errand("Running", .running, updated: at(11)),
            errand("Done", .done, updated: at(9, dayOffset: -2)),
            errand("Old done", .done, updated: at(9, dayOffset: -8)),
            errand("Failed", .failed, updated: at(9, dayOffset: -1)),
            errand("Cancelled", .cancelled, updated: at(9)),
            errand("Draft", .draft, updated: at(9)),
            errand("Lost answer", .unknown, updated: at(9)),
        ]))
        XCTAssertEqual(titles(agenda, .waiting), ["Lost answer", "Queued", "Running"])
        XCTAssertEqual(item(agenda, "Queued")?.status, .queued)
        XCTAssertEqual(item(agenda, "Running")?.status, .running)
        XCTAssertEqual(item(agenda, "Lost answer")?.status, .cannotConfirm)
        XCTAssertEqual(titles(agenda, .today), ["Done", "Failed"], "oldest answer first")
        XCTAssertEqual(item(agenda, "Done")?.status, .finished)
        XCTAssertEqual(item(agenda, "Failed")?.status, .failed)
        for hidden in ["Old done", "Cancelled", "Draft"] { XCTAssertNil(item(agenda, hidden), hidden) }
    }

    func testWatchesActiveOnesAreWatchedAndOnlyAConfirmedPriceIsReached() {
        func watch(_ title: String, _ state: WatchState, triggeredAt: Date? = nil, triggeredPrice: Int? = nil, lastPrice: Int? = nil,
                   checked: Date? = nil) -> WatchSummary {
            WatchSummary(id: UUID(), state: state, title: title, shop: "Shop", url: "https://example.com/p", thresholdMinor: 30_000,
                         createdAt: at(9, dayOffset: -10), endsAt: at(9, dayOffset: 20), lastCheckedAt: checked,
                         lastPriceMinor: lastPrice, triggeredAt: triggeredAt, triggeredPriceMinor: triggeredPrice)
        }
        let agenda = build(OpenLoopsInput(watches: [
            watch("Shoes", .active, lastPrice: 34_900),
            watch("Phone", .triggered, triggeredAt: at(7), triggeredPrice: 28_900),
            watch("Old trigger", .triggered, triggeredAt: at(7, dayOffset: -9), triggeredPrice: 100),
            watch("Unreadable", .failed, checked: at(7, dayOffset: -2)),
            watch("Stopped", .stopped), watch("Expired", .expired), watch("Draft", .draft),
            watch("Newer server", .unknown),
        ]))
        XCTAssertEqual(item(agenda, "Shoes")?.status, .watching(lastPrice: Money(minor: 34_900), threshold: Money(minor: 30_000)))
        XCTAssertEqual(item(agenda, "Shoes")?.section, .watching)
        XCTAssertEqual(item(agenda, "Phone")?.status, .priceReached(Money(minor: 28_900)))
        XCTAssertEqual(item(agenda, "Phone")?.section, .today)
        XCTAssertEqual(item(agenda, "Unreadable")?.status, .failed)
        XCTAssertEqual(item(agenda, "Newer server")?.status, .cannotConfirm, "never shown as active")
        XCTAssertEqual(item(agenda, "Newer server")?.section, .watching)
        for hidden in ["Old trigger", "Stopped", "Expired", "Draft"] { XCTAssertNil(item(agenda, hidden), hidden) }
    }

    private func parcel(_ digits: String, label: String?, status: String?) -> ParcelEntry {
        var book = ParcelBook(isOn: true)
        guard case .added = book.add(ParcelNumber(digits)!, label: label, now: at(8, dayOffset: -2), id: UUID()) else {
            XCTFail("the parcel wasn't added")
            return ParcelEntry.placeholder
        }
        if let status {
            let json = #"{"number":"\#(digits)","status":"\#(status)","events":[]}"#
            // swiftlint:disable:next force_try
            let tracking = try! JSONDecoder().decode(ParcelTracking.self, from: Data(json.utf8))
            book.record(tracking, now: at(9))
        }
        return book.entries[0]
    }

    func testParcelsReadyOrInTroubleNeedThePersonOthersWaitAndDeliveredIsClosedByTheCarrier() {
        let agenda = build(OpenLoopsInput(parcels: [
            parcel("123456789012345678901234", label: "Shoes", status: "ready_to_pickup"),
            parcel("223456789012345678901234", label: "Book", status: "out_for_delivery"),
            parcel("323456789012345678901234", label: "Done", status: "delivered"),
            parcel("423456789012345678901234", label: "Sent back", status: "returned_to_sender"),
            parcel("523456789012345678901234", label: nil, status: nil),
            parcel("623456789012345678901234", label: "Odd", status: "something_new"),
            parcel("723456789012345678901234", label: "Late", status: "pickup_time_expired"),
        ]))
        XCTAssertEqual(Set(titles(agenda, .today)), ["Shoes", "Late"])
        XCTAssertEqual(item(agenda, "Shoes")?.status, .parcel(.readyForPickup))
        XCTAssertEqual(item(agenda, "Late")?.status, .parcel(.problem))
        XCTAssertEqual(Set(titles(agenda, .waiting)), ["Book", "Odd", "(hidden)"])
        XCTAssertEqual(item(agenda, "Odd")?.status, .parcel(.unknown), "a status the app doesn't know is not turned into a sentence")
        XCTAssertEqual(agenda.items(in: .waiting).first { $0.title == .hidden }?.status, .parcel(.unknown), "never looked up")
        XCTAssertNil(item(agenda, "Done"))
        XCTAssertNil(item(agenda, "Sent back"))
    }

    // MARK: A source that could not be read

    func testAnUnreadableSourceIsNamedNotShownAsEmptyAndItsRowsAreNotShown() {
        let reminder = ReminderSummary(id: "r1", title: "Pay rent", due: at(15), dueHasTime: true)
        let event = CalendarEventSummary(id: "e1", title: "Dentist", start: at(15), end: at(16), allDay: false)
        let agenda = build(OpenLoopsInput(appleReminders: [reminder], events: [event], unavailable: [.appleReminder, .parcel]))
        XCTAssertEqual(agenda.unavailable, [.appleReminder, .parcel])
        XCTAssertNil(item(agenda, "Pay rent"), "stale rows aren't presented as current")
        XCTAssertNotNil(item(agenda, "Dentist"))
        XCTAssertFalse(agenda.isEmpty)
        let nothing = build(OpenLoopsInput(unavailable: [.calendarEvent]))
        XCTAssertTrue(nothing.allItems.isEmpty)
        XCTAssertFalse(nothing.isEmpty, "unreadable is not the same as nothing there")
        XCTAssertTrue(build(OpenLoopsInput()).isEmpty)
    }

    // MARK: Order, limits, repeats

    func testTheLimitCutsEachSectionAndCountsWhatIsLeft() {
        let reminders = (0..<5).map { ReminderSummary(id: "r\($0)", title: "Task \($0)", due: at(13 + $0), dueHasTime: true) }
        let agenda = build(OpenLoopsInput(appleReminders: reminders), limit: 3)
        XCTAssertEqual(titles(agenda, .today), ["Task 0", "Task 1", "Task 2"])
        XCTAssertEqual(agenda.more[.today], 2)
        XCTAssertEqual(agenda.more[.later], 0)
        XCTAssertEqual(build(OpenLoopsInput(appleReminders: reminders), limit: 0).items(in: .today), [])
    }

    func testTheSameInputInAnyOrderGivesTheSameList() {
        let reminders = [
            ReminderSummary(id: "b", title: "Same time", due: at(15), dueHasTime: true),
            ReminderSummary(id: "a", title: "Same time", due: at(15), dueHasTime: true),
            ReminderSummary(id: "c", title: "Earlier", due: at(14), dueHasTime: true),
            ReminderSummary(id: "d", title: "No date", due: nil, dueHasTime: false),
        ]
        let events = [CalendarEventSummary(id: "e", title: "Meeting", start: at(15), end: at(16), allDay: false)]
        let forward = build(OpenLoopsInput(appleReminders: reminders, events: events))
        let backward = build(OpenLoopsInput(appleReminders: Array(reminders.reversed()), events: events))
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward.items(in: .today).map(\.id), ["appleReminder:c", "appleReminder:a", "appleReminder:b", "calendarEvent:e"])
    }

    func testTwoRecordsWithTheSameIDAreOneRow() {
        let one = ReminderSummary(id: "r1", title: "Pay rent", due: at(15), dueHasTime: true)
        XCTAssertEqual(build(OpenLoopsInput(appleReminders: [one, one])).allItems.count, 1)
    }

    func testRowIDsAreStableAndNameTheirSource() {
        let reminder = ReminderSummary(id: "r1", title: "Pay rent", due: at(15), dueHasTime: true)
        XCTAssertEqual(build(OpenLoopsInput(appleReminders: [reminder])).allItems.first?.id, "appleReminder:r1")
    }
}

private extension ParcelEntry {
    /// Only for a failed test to return something; never used when the helper works.
    static var placeholder: ParcelEntry {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(ParcelEntry.self, from: Data(
            #"{"id":"00000000-0000-0000-0000-000000000000","number":"000000000000000000000000","addedAt":0}"#.utf8))
    }
}
