import XCTest
@testable import DoddyCore

/// "What Doddy did": entries say only what the app's own reply to the agent said.
final class ActivityLogTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))! }

    private let reminder = ReminderDraft(title: "Buy milk", due: nil, dueHasTime: false, notes: nil)

    private func entry(_ request: VoiceToolRequest, reply: String) -> ActivityEntry {
        ActivityEntry(request: ActivityRequest.describe(request, calendar: calendar)!, reply: reply, at: now)
    }

    func testOutcomesComeFromTheVerifiedReply() {
        let add = VoiceToolRequest.createReminder(reminder)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.reminderAdded(reminder, calendar: calendar)).outcome, .done)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.reminderAlreadyThere(reminder, calendar: calendar)).outcome, .alreadyThere)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.addUnconfirmed).outcome, .notSure)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.declinedReminder).outcome, .declined)

        let failed = entry(add, reply: VoiceToolReply.notAdded("Reminders isn't connected."))
        XCTAssertEqual(failed.outcome, .notDone)
        XCTAssertEqual(failed.note, "Reminders isn't connected.")

        let off = entry(add, reply: VoiceToolReply.notConnected(.reminders))
        XCTAssertEqual(off.outcome, .notDone)
        XCTAssertEqual(off.note, "Reminders isn't connected.")

        XCTAssertEqual(entry(.openMap(place: "Hala Koszyki"), reply: VoiceToolReply.mapOpened("Hala Koszyki")).outcome, .opened)
        // A reply the app never phrased as a result is not shown as done.
        XCTAssertEqual(entry(add, reply: "something else").outcome, .notSure)
    }

    func testLookupsAreLoggedButFailuresStillShow() {
        let search = VoiceToolRequest.searchMemories(query: "klucze")
        XCTAssertEqual(entry(search, reply: VoiceToolReply.search(.noMatch)).outcome, .lookedUp)
        XCTAssertEqual(entry(search, reply: VoiceToolReply.failed("The store is locked.")).outcome, .notDone)
        XCTAssertNil(ActivityRequest.describe(.unsupported(name: "send_sms"), calendar: calendar))
    }

    func testOnlineAccountWritesAreReadFromTheServerResult() {
        let draft = VoiceToolRequest.cloudTool(CloudToolCall(name: CloudToolName.draftEmail, arguments: [:]))
        XCTAssertEqual(entry(draft, reply: "drafted: Gmail draft to a@b.pl with subject \"Hi\" was created.").outcome, .done)
        let demo = entry(draft, reply: "DEMO DATA from a test server, not the user's real account. Tell the user it is demo data. drafted: Gmail draft was created.")
        XCTAssertEqual(demo.outcome, .done)
        XCTAssertEqual(demo.note, "Demo data from a test server, not your account.")
        XCTAssertEqual(entry(draft, reply: VoiceToolReply.cloudDeclined(CloudToolName.draftEmail)).outcome, .declined)
    }

    func testOnlineAccountEntriesKeepNoContent() {
        let request = ActivityRequest.describe(.cloudTool(CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])), calendar: calendar)
        XCTAssertEqual(request?.app, .gmail)
        XCTAssertNil(request?.detail)
    }

    func testCheckIsOfferedOnlyForUnsureRemindersAndSettlesIt() {
        let unsure = entry(.createReminder(reminder), reply: VoiceToolReply.addUnconfirmed)
        XCTAssertTrue(unsure.canCheckInReminders)
        XCTAssertEqual(unsure.reminderKey, ReminderKey.key(for: reminder, calendar: calendar))
        XCTAssertFalse(entry(.openMap(place: "x"), reply: VoiceToolReply.addUnconfirmed).canCheckInReminders)

        let found = ActivityLog.checked(unsure, found: true, at: now)
        XCTAssertEqual(found.outcome, .done)
        XCTAssertFalse(found.canCheckInReminders)
        XCTAssertEqual(ActivityLog.checked(unsure, found: false, at: now).outcome, .notDone)
    }

    func testLogIsNewestFirstAndBounded() {
        let old = ActivityEntry(at: now.addingTimeInterval(-31 * 86_400), app: .maps, title: "Old", detail: nil, outcome: .opened)
        var log = [old]
        for minute in 0..<(ActivityLog.maxEntries + 5) {
            let item = ActivityEntry(at: now.addingTimeInterval(Double(minute) * 60), app: .maps, title: "\(minute)", detail: nil, outcome: .opened)
            log = ActivityLog.appending(item, to: log, now: now)
        }
        XCTAssertEqual(log.count, ActivityLog.maxEntries)
        XCTAssertFalse(log.contains(old), "entries older than 30 days are dropped")
        XCTAssertEqual(log.first?.title, "\(ActivityLog.maxEntries + 4)")
    }
}

final class ConnectionPauseTests: XCTestCase {
    func testPauseStopsEveryAppButLeavesNotes() {
        let draft = ReminderDraft(title: "Buy milk", due: nil, dueHasTime: false, notes: nil)
        let paused: [VoiceToolRequest] = [
            .readCalendar(VoiceTimeRange(start: Date(), end: Date().addingTimeInterval(3600))),
            .createReminder(draft), .lookupContact(name: "Marta"), .openMap(place: "Koszyki"),
            .runShortcut(name: "Home"), .setTimer(TimerDraft(seconds: 60, label: nil)),
            .draftMessage(MessageDraft(recipientName: "Marta", channel: .text, body: "Hi")),
            .cloudTool(CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])),
        ]
        for request in paused { XCTAssertTrue(ConnectionPause.applies(to: request), "\(request)") }
        XCTAssertFalse(ConnectionPause.applies(to: .searchMemories(query: "klucze")))
        XCTAssertFalse(ConnectionPause.applies(to: .saveMemory(text: "x")))
    }

    func testPausedRequestsShowAsNotDoneInWhatDoddyDid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let draft = ReminderDraft(title: "Buy milk", due: nil, dueHasTime: false, notes: nil)
        for request in [VoiceToolRequest.createReminder(draft), .lookupContact(name: "Marta")] {
            let entry = ActivityEntry(
                request: ActivityRequest.describe(request, calendar: calendar)!, reply: ConnectionPause.reply, at: Date())
            XCTAssertEqual(entry.outcome, .notDone)
            XCTAssertEqual(entry.note, "Connections were paused.")
        }
    }
}
