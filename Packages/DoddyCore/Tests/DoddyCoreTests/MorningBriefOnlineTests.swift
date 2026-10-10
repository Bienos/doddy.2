@testable import DoddyCore
import Foundation
import XCTest

/// ADR-213: choosing what's in the brief, and Daily news, Todoist and Gmail sections.
final class MorningBriefOnlineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(_ hour: Int, dayOffset: Int = 0) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + dayOffset))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func brief(_ source: BriefSource, sections: MorningBriefSections = .standard,
                       online: BriefOnline = .none, notes: [BriefNoteReminder] = []) -> [String] {
        MorningBrief.compose(
            source: source, noteReminders: notes, name: nil, now: at(7), calendar: calendar,
            timeText: { _ in "10:00" }, sections: sections, online: online
        ).lines.map(\.text)
    }

    private let emptyDay = BriefSource.agenda(
        TodayAgenda(events: [], reminders: [], now: Date(timeIntervalSince1970: 0), calendar: .current),
        calendarRead: true, remindersRead: true)

    private func task(_ title: String, urgent: Bool = false) -> ResultItem {
        ResultItem(kind: .task, title: title, from: nil, when: "today", urgent: urgent)
    }

    private func email(_ subject: String, from: String?) -> ResultItem {
        ResultItem(kind: .email, title: subject, from: from, when: "2026-10-12 06:40", urgent: false)
    }

    // MARK: Choosing what's in it

    func testDefaultsAreWhatsOnTheIPhoneAndNothingFromAServer() {
        let sections = MorningBriefSections.standard
        XCTAssertTrue(sections.events && sections.reminders && sections.noteReminders)
        XCTAssertFalse(sections.news || sections.todoist || sections.gmail, "server reads are chosen, never assumed")
        XCTAssertFalse(sections.readsServer)
    }

    func testLeftOutSectionsLeaveNoLineAndNoNotice() {
        var sections = MorningBriefSections.standard
        sections.events = false
        sections.noteReminders = false
        let lines = brief(.agenda(TodayAgenda(events: [], reminders: [], now: at(7), calendar: calendar), calendarRead: false, remindersRead: true),
                          sections: sections, notes: [BriefNoteReminder(fireAt: at(14), noteText: "Bring the key")])
        XCTAssertEqual(lines, ["Good morning.", "No reminders due today."], "no events line, no 'Calendar is off', no note reminder")

        sections.reminders = false
        XCTAssertEqual(brief(.notConnected, sections: sections), ["Good morning."], "nothing read, nothing said about Connections")
    }

    // MARK: Todoist

    func testTodoistTasks() {
        let loaded = BriefOnline(todoist: .loaded(BriefOnlineList(
            items: [task("Buy milk"), task("Call the bank", urgent: true)], truncated: false, isDemo: false)))
        XCTAssertEqual(brief(emptyDay, online: loaded).last, "2 Todoist tasks for today: Buy milk and Call the bank (priority 1).")

        let many = BriefOnline(todoist: .loaded(BriefOnlineList(items: (1...5).map { task("Task \($0)") }, truncated: true, isDemo: false)))
        XCTAssertEqual(brief(emptyDay, online: many).last, "5 Todoist tasks for today: Task 1, Task 2 and Task 3, and more in Todoist.")

        let none = BriefOnline(todoist: .loaded(BriefOnlineList(items: [], truncated: false, isDemo: false)))
        XCTAssertEqual(brief(emptyDay, online: none).last, "No Todoist tasks due today.")
    }

    // MARK: Gmail

    func testGmailSendersAndSubjectsOnly() {
        let loaded = BriefOnline(gmail: .loaded(BriefOnlineList(items: [
            email("Lunch on Friday?", from: "Anna Demo <anna@demo.example>"),
            email("Invoice 42", from: "billing@shop.example"),
        ], truncated: false, isDemo: false)))
        XCTAssertEqual(brief(emptyDay, online: loaded).last,
                       "2 unread emails from the last day: “Lunch on Friday?” from Anna Demo and “Invoice 42” from billing@shop.example.")
        XCTAssertEqual(MorningBrief.senderName("\"Bank, Ltd\" <no@bank.example>"), "Bank, Ltd")
        XCTAssertEqual(MorningBrief.senderName("<only@address.example>"), "only@address.example")
        XCTAssertEqual(MorningBrief.senderName(nil), "an unknown sender")
    }

    func testDemoDataIsNeverPresentedAsTheUsers() {
        let demo = BriefOnline(gmail: .loaded(BriefOnlineList(items: [email("Hi", from: "A <a@x.example>")], truncated: false, isDemo: true)))
        XCTAssertEqual(brief(emptyDay, online: demo).last?.hasPrefix("Demo data, not your account: "), true)
    }

    func testUnavailableAndFailedSayWhyAndInventNothing() {
        let online = BriefOnline(
            todoist: .unavailable("Todoist isn't connected. Check Settings, Online accounts."),
            gmail: .failed("Doddy's server couldn't be reached. Check your connection and try again."))
        let lines = brief(emptyDay, online: online)
        XCTAssertTrue(lines.contains("Todoist isn't in this brief: Todoist isn't connected. Check Settings, Online accounts."))
        XCTAssertTrue(lines.contains("Couldn't check Gmail just now. Doddy's server couldn't be reached. Check your connection and try again."))
    }

    // MARK: News

    func testNewsStoriesWithLinks() throws {
        let items = try (1...4).map { n in
            try JSONDecoder().decode(NewsDigest.Item.self, from: Data(#"{"line":"Story \#(n) happened.","url":"https://news.example/\#(n)","source":"Example"}"#.utf8))
        }
        let result = MorningBrief.compose(
            source: emptyDay, noteReminders: [], name: nil, now: at(7), calendar: calendar, timeText: { _ in "" },
            sections: MorningBriefSections(news: true), online: BriefOnline(news: .loaded(items)))
        let news = result.lines.filter { $0.kind == .news || $0.kind == .newsItem }
        XCTAssertEqual(news.map(\.text), ["From your daily news:", "Story 1 happened. (Example)", "Story 2 happened. (Example)", "Story 3 happened. (Example)"])
        XCTAssertEqual(news[1].url, "https://news.example/1")
        XCTAssertEqual(brief(emptyDay, online: BriefOnline(news: .loaded([]))).last, "No daily news digest yet today.")
    }

    func testNewsPicksTodaysNewestDigestWithStories() async throws {
        func digest(_ id: Int, _ created: String, items: Int) throws -> NewsDigest {
            let stories = (0..<items).map { #"{"line":"D\#(id) story \#($0)","url":"https://n.example","source":"S"}"# }.joined(separator: ",")
            return try JSONDecoder().decode(NewsDigest.self, from: Data("""
                {"id":"00000000-0000-0000-0000-00000000000\(id)","status":"ready","aiWritten":true,"errorCode":null,"createdAt":"\(created)","items":[\(stories)]}
                """.utf8))
        }
        let all = try [
            digest(1, "2026-10-11T06:00:00.000Z", items: 3),
            digest(2, "2026-10-12T04:00:00.000Z", items: 2),
            digest(3, "2026-10-12T05:00:00.000Z", items: 0),
        ]
        let result = await MorningBriefFetcher.news({ all }, now: at(8), calendar: calendar)
        XCTAssertEqual(result, .loaded(all[1].items), "today's newest with stories; yesterday's is never shown as today's")
        struct Down: Error {}
        let failed = await MorningBriefFetcher.news({ throw Down() }, now: at(8), calendar: calendar)
        XCTAssertEqual(failed, .failed("Doddy's server couldn't be reached."))
    }

    // MARK: Fetching through the online-accounts client

    func testGmailAndTodoistAskForExactlyTheReadsChosen() async throws {
        let client = ScriptedOnline(.success(try fixtureRun("run-result-email")))
        let gmail = await MorningBriefFetcher.gmail(client, importantOnly: true, timeZone: "Europe/Warsaw")
        guard case .loaded(let list) = gmail else { return XCTFail("loaded expected") }
        XCTAssertEqual(list.items.map(\.title), ["Lunch on Friday?", "Your statement is ready"])
        XCTAssertTrue(list.isDemo, "the fixture is the mock server's")
        _ = await MorningBriefFetcher.todoist(client, timeZone: "Europe/Warsaw")

        let calls = await client.calls
        XCTAssertEqual(calls.map(\.call.name), ["check_email", "list_todoist_tasks"])
        XCTAssertEqual(calls[0].call.arguments["query"], .string("in:inbox is:unread is:important newer_than:1d"))
        XCTAssertEqual(calls[0].call.arguments["max"], .number(5))
        XCTAssertEqual(calls[1].call.arguments, ["when": .string("today")])
        XCTAssertTrue(calls.allSatisfy { $0.approvalID == nil && $0.timeZone == "Europe/Warsaw" }, "reads only, no approvals")
        XCTAssertEqual(MorningBriefFetcher.gmailQuery(importantOnly: false), "in:inbox is:unread newer_than:1d")
    }

    func testFetchProblemsBecomeUnavailableOrFailed() async throws {
        let none = await MorningBriefFetcher.todoist(nil, timeZone: "UTC")
        XCTAssertEqual(none, .unavailable("Doddy's server for online accounts isn't set up in Settings."))

        let off = ScriptedOnline(.failure(.server(code: "capability_disabled", message: "List my tasks is switched off.", retryAfterSeconds: nil, receipt: nil)))
        let offResult = await MorningBriefFetcher.todoist(off, timeZone: "UTC")
        XCTAssertEqual(offResult, .unavailable("List my tasks is switched off. Check Settings, Online accounts."))

        let down = ScriptedOnline(.failure(.transport("offline")))
        guard case .failed = await MorningBriefFetcher.gmail(down, importantOnly: false, timeZone: "UTC") else { return XCTFail() }

        let old = ScriptedOnline(.success(try fixtureRun("run-result-draft")))
        let oldResult = await MorningBriefFetcher.gmail(old, importantOnly: false, timeZone: "UTC")
        XCTAssertEqual(oldResult, .failed("Doddy's server is an older version that can't list them here."),
                       "no items: nothing is parsed out of the agent's text")
    }

    private func fixtureRun(_ name: String) throws -> RunResult {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(RunResult.self, from: Data(contentsOf: root.appendingPathComponent("contracts/online-accounts/\(name).json")))
    }
}

/// Answers every run with the same result and records what was asked.
private actor ScriptedOnline: OnlineAccountsClient {
    struct Call { let call: CloudToolCall; let timeZone: String; let approvalID: UUID? }
    private let answer: Result<RunResult, OnlineAccountsError>
    private(set) var calls: [Call] = []

    init(_ answer: Result<RunResult, OnlineAccountsError>) { self.answer = answer }

    func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult {
        calls.append(Call(call: call, timeZone: timeZone, approvalID: approvalId))
        return try answer.get()
    }

    func catalog() async throws(OnlineAccountsError) -> ToolsCatalog { throw .notConfigured }
    func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse { throw .notConfigured }
    func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult { throw .notConfigured }
    func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] { throw .notConfigured }
}
