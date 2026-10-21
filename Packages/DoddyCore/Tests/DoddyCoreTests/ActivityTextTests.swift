import XCTest
@testable import DoddyCore

/// "What Doddy did" in Polish (ADR-275): every row Doddy can write has a Polish title, Doddy's own
/// notes are translated, and anything else is shown exactly as kept.
final class ActivityTextTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))! }

    /// One request of every kind that gets a row.
    private var everyKind: [VoiceToolRequest] {
        let range = VoiceTimeRange(start: now, end: now.addingTimeInterval(86_400))
        let event = CalendarEventDraft(title: "Dentist", start: now, end: now.addingTimeInterval(3_600), allDay: false, location: nil, notes: nil)
        let list = ListVoiceRequest(list: "Shopping", items: ["milk"])
        var requests: [VoiceToolRequest] = [
            .searchMemories(query: "keys"), .saveMemory(text: "Keys in the tin"), .readCalendar(range),
            .createCalendarEvent(event), .createReminder(ReminderDraft(title: "Buy milk", due: nil, notes: nil)),
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "Keys", target: .time(now, timeZoneID: "Europe/Warsaw"))),
            .lookupContact(name: "Marta"), .upcomingBirthdays(days: 7), .setTimer(TimerDraft(seconds: 60, label: nil)),
            .openMap(place: "Old Town"), .runShortcut(name: "Home"),
            .draftMessage(MessageDraft(recipientName: "Marta", channel: .text, body: "Hi")),
            .draftMessage(MessageDraft(recipientName: "Marta", channel: .email, body: "Hi")),
            .addToList(list), .readList(name: "Shopping"), .checkOff(list), .removeFromList(list), .createList(list),
            .changeCalendarEvent(EventChangeDraft(title: "Dentist", currentStart: now, currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: "Doctor")),
            .changeReminder(ReminderChangeDraft(title: "Buy milk", newDue: nil, markDone: true)),
            .deleteCalendarEvent(EventChangeDraft(title: "Dentist", currentStart: now, currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: nil)),
            .deleteReminder(title: "Buy milk"),
            .setAlarm(AlarmDraft(first: ReminderDue(year: 2026, month: 10, day: 12, hour: 7, minute: 0, timeZoneID: "Europe/Warsaw"), repeats: .weekdays, label: nil)),
            .listAlarms, .cancelAlarm(clock: "07:00", label: "Gym"), .deleteCalendarEvents(range),
            .moveReminders(dueBy: ReminderDue(year: 2026, month: 10, day: 11, hour: nil, minute: nil, timeZoneID: nil),
                           to: ReminderDue(year: 2026, month: 10, day: 12, hour: nil, minute: nil, timeZoneID: nil)),
            // Kinds added on the default branch while this test was on a branch (rounds 4 and 6).
            .convertCurrency(CurrencyConversionRequest(amount: 20, from: "EUR", to: "PLN")),
            .parkingSpot(.save(note: nil)), .parkingSpot(.find), .parkingSpot(.clear),
            .addIngredients(IngredientsProposal(list: "Shopping", dish: "Pancakes", items: ["Eggs"])),
            .findFreeTime(FreeTimeRequest(firstDay: now, days: 1)),
            .leaveBy(LeaveByRequest(place: "Dentist", arriveBy: now)),
            // ADR-510.
            .draftBlikTransfer(BlikTransferDraft(recipientName: "Ania", amount: BlikAmount(grosze: 5_000)!, title: "Pizza")),
            // ADR-570.
            .handOverErrand(ErrandDraft(words: "sprawdź loty do Rzymu", brief: "Loty do Rzymu w listopadzie.", title: "Rzym")),
            .checkErrands(about: nil),
        ]
        requests += CloudToolName.all.sorted().map { .cloudTool(CloudToolCall(name: $0, arguments: [:])) }
        return requests
    }

    /// Every kind of request, so a new tool can't be left out of `everyKind` unnoticed: a new
    /// case stops this compiling until it is sorted into "gets a row" or "doesn't".
    private func getsARow(_ request: VoiceToolRequest) -> Bool {
        switch request {
        case .searchMemories, .saveMemory, .readCalendar, .createCalendarEvent, .createReminder, .remindAboutNote,
             .lookupContact, .upcomingBirthdays, .setTimer, .setAlarm, .listAlarms, .cancelAlarm, .openMap, .runShortcut,
             .draftMessage, .draftBlikTransfer, .cloudTool, .addToList, .readList, .checkOff, .removeFromList, .createList,
             .changeCalendarEvent, .changeReminder, .deleteCalendarEvent, .deleteReminder, .deleteCalendarEvents, .moveReminders,
             .convertCurrency, .parkingSpot, .addIngredients, .findFreeTime, .leaveBy, .handOverErrand, .checkErrands:
            true
        case .needsClarification, .calculate, .convertUnits, .undoLast, .startTranslator, .stopTranslator, .unsupported, .invalid,
             .noteCapabilityGap:
            // The gap tool leaves no row in What Doddy did (ADR-440).
            false
        }
    }

    func testEveryKindThatGetsARowIsInTheList() {
        XCTAssertTrue(everyKind.allSatisfy(getsARow))
        // One of each kind that gets a row (cloud tools count once each, drafts twice).
        let kinds = Set(everyKind.map { String(describing: $0).prefix { $0 != "(" } })
        XCTAssertEqual(kinds.count, 35)
        XCTAssertNil(ActivityRequest.describe(.undoLast, calendar: calendar))
        XCTAssertNil(ActivityRequest.describe(.calculate(expression: "1+1"), calendar: calendar))
    }

    func testEveryRowDoddyWritesHasAPolishTitleAndApp() {
        var seen = 0
        for request in everyKind {
            guard let row = ActivityRequest.describe(request, calendar: calendar) else { continue }
            seen += 1
            let polish = ActivityText.title(row.title, .polish)
            XCTAssertNotEqual(polish, row.title, "no Polish title for \(row.title)")
            XCTAssertEqual(ActivityText.title(row.title, .english), row.title)
            if ![ActivityApp.gmail, .drive, .notion, .todoist, .outlook].contains(row.app) {
                XCTAssertNotEqual(row.app.title(.polish), row.app.title, "no Polish name for \(row.app)")
            }
        }
        XCTAssertEqual(seen, everyKind.count)
        XCTAssertEqual(ActivityRequest.describe(.draftMessage(MessageDraft(recipientName: "M", channel: .email, body: "x")), calendar: calendar)?.title, "Draft an email")
        // Rows written before the article was fixed still read in Polish.
        XCTAssertEqual(ActivityText.title("Draft a email", .polish), "Szkic e-maila")
    }

    func testEveryResultHasPolish() {
        let all: [ActivityOutcome] = [.lookedUp, .done, .alreadyThere, .opened, .notSure, .notDone, .declined, .inProgress]
        XCTAssertEqual(Set(all.map { $0.text(.polish) }).count, all.count)
        for outcome in all { XCTAssertNotEqual(outcome.text(.polish), outcome.text) }

        let row = ActivityEntry(at: now, app: .calendar, title: "Add event", detail: "“Dentist”", outcome: .done)
        XCTAssertEqual(row.statusText(.polish), "Kalendarz · Zrobione")
        XCTAssertEqual(row.statusText(.english), "Calendar · Done")
        XCTAssertEqual(row.title(.polish), "Dodaj wydarzenie")
        var undone = row
        undone.undoState = .undone(now)
        XCTAssertEqual(undone.statusText(.polish), "Kalendarz · Cofnięte")
    }

    func testDoddysOwnNotesAreTranslatedAndEverythingElseIsKeptAsWritten() {
        let fixed = [
            "Connections were paused.", "Doddy couldn't confirm it went through.", "Demo data from a test server, not your account.",
            ActivityLog.interruptedNote, "The conversation ended before you answered.", "Reminders isn't connected.",
        ]
        for note in fixed { XCTAssertNotEqual(ActivityText.note(note, .polish), note, note) }

        // The Check and Undo notes, exactly as the log writes them.
        let reminder = ActivityEntry(at: now, app: .reminders, title: "Add reminder", detail: nil, outcome: .notSure, reminderKey: "k")
        XCTAssertEqual(ActivityLog.checked(reminder, found: true, at: now).note(.polish), "Znalezione w Przypomnieniach przy sprawdzaniu.")
        XCTAssertNotEqual(ActivityLog.checked(reminder, found: false, at: now).note(.polish), ActivityLog.checked(reminder, found: false, at: now).note)
        let event = ActivityEntry(at: now, app: .calendar, title: "Add event", detail: nil, outcome: .done)
        XCTAssertEqual(ActivityLog.undid(event, result: .undone, at: now).note(.polish), "Cofnięto. Sprawdzone w Kalendarzu.")
        XCTAssertEqual(
            ActivityLog.undid(event, result: .notSure, at: now).note(.polish),
            "Doddy nie mógł potwierdzić cofnięcia. Sprawdź Kalendarz, zanim spróbujesz ponownie.")
        XCTAssertTrue(ActivityLog.undid(event, result: .leftAlone, at: now).note(.polish)!.hasPrefix("Nie cofnięto: zmieniło się w Kalendarzu"))
        let blocked = ActivityUndo.addedEvent(eventID: "E", event: CalendarEventSummary(title: "x", start: now, end: now, allDay: false))
            .blocked(pauseAll: false, connectionOn: false)!
        XCTAssertEqual(
            ActivityLog.undid(event, result: .notDone(blocked), at: now).note(.polish),
            "Nie cofnięto: Kalendarz: wyłączone w Ustawieniach, Połączenia. Nic się nie zmieniło.")

        // A reason an app gave is not reworded: the frame is Polish, the reason stays.
        XCTAssertEqual(
            ActivityLog.undid(event, result: .notDone("EKErrorDomain 5."), at: now).note(.polish),
            "Nie cofnięto: EKErrorDomain 5. Nic się nie zmieniło.")
        XCTAssertEqual(ActivityText.note("Gmail said: quota exceeded.", .polish), "Gmail said: quota exceeded.")
        XCTAssertEqual(ActivityText.note("Connections were paused.", .english), "Connections were paused.")
    }

    func testPlanHeadingsUsePolishPluralsAndCounts() {
        XCTAssertEqual(ActivityPlanSummary.polishSteps(1), "krok")
        XCTAssertEqual(ActivityPlanSummary.polishSteps(2), "kroki")
        XCTAssertEqual(ActivityPlanSummary.polishSteps(4), "kroki")
        XCTAssertEqual(ActivityPlanSummary.polishSteps(5), "kroków")
        XCTAssertEqual(ActivityPlanSummary.polishSteps(12), "kroków")
        XCTAssertEqual(ActivityPlanSummary.polishSteps(22), "kroki")

        let id = UUID()
        let steps = [
            ActivityEntry(at: now, app: .calendar, title: "Add event", detail: nil, outcome: .done, plan: ActivityPlanRef(id: id, step: 1, count: 3)),
            ActivityEntry(at: now, app: .reminders, title: "Add reminder", detail: nil, outcome: .notSure, plan: ActivityPlanRef(id: id, step: 2, count: 3)),
        ]
        XCTAssertEqual(ActivityPlanSummary.title(steps, language: .polish), "Plan · 3 kroki (niewidoczne: 1)")
        XCTAssertEqual(ActivityPlanSummary.outcomes(steps, language: .polish), "zrobione: 1 · niepewne: 1")
        XCTAssertEqual(ActivityPlanSummary.title(steps, language: .english), ActivityPlanSummary.title(steps))
    }
}
