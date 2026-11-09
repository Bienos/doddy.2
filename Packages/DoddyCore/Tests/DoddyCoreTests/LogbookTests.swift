import Foundation
import XCTest
@testable import DoddyCore

/// Logbook, the iPhone's half (ADR-602, decision 2026-11-09-usage-counts-on-by-default): counts only,
/// in the shape the server's allow-list takes (`backend/src/web/logbook.ts`).

private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/web/\(name).json"))
}

private final class Transport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    var replies: [(Int, Data)]
    var fails = false

    init(_ replies: [(Int, Data)] = []) { self.replies = replies }
    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let (failing, reply) = lock.withLock { () -> (Bool, (Int, Data)) in
            recorded.append(request)
            return (fails, replies.isEmpty ? (200, Data()) : replies.removeFirst())
        }
        if failing { throw URLError(.notConnectedToInternet) }
        return reply
    }
}

/// Warsaw, so local days and hours differ from UTC.
private var warsaw: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return calendar
}

/// A moment in Warsaw (UTC+1) in November 2026, on the 9th unless `day` says otherwise.
private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 9) -> Date {
    warsaw.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
}

private func note(_ n: Int, _ text: String, source: MemorySource = .explicitVoice, category: MemoryCategory = .fact,
                  captured: Date, edited: Date? = nil) throws -> MemoryRecord {
    let record = try MemoryRecord(
        id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!, rawText: text, source: source,
        category: category, capturedAt: captured)
    return try edited.map { try record.correcting(to: text + " (changed)", at: $0) } ?? record
}

private func entry(_ tool: String?, _ outcome: ActivityOutcome, at date: Date, undone: Bool = false) -> ActivityEntry {
    ActivityEntry(at: date, app: .reminders, title: "Add reminder", detail: "“Call Ana about the flat”", outcome: outcome,
                  undoState: undone ? .undone(date) : nil, tool: tool)
}

private func keys(_ value: Any?) -> Set<String> {
    Set((value as? [String: Any]).map { Array($0.keys) } ?? [])
}

final class LogbookTests: XCTestCase {
    private let secret = "Call Ana about the flat"

    private func sources() throws -> LogbookSources {
        let list = UUID()
        return LogbookSources(
            conversations: [
                LogbookConversation(startedAt: at(8, 5), endedAt: at(8, 5, 40), ended: "user", language: "pl"),
                LogbookConversation(startedAt: at(8, 30), endedAt: at(8, 32), ended: "stopped", language: "pl", wayIn: .backTap),
                LogbookConversation(startedAt: at(21, 0), endedAt: at(21, 4), ended: "dropped-offline", language: "en", wayIn: .island),
                LogbookConversation(startedAt: at(22, 0), endedAt: at(22, 7), ended: "doddy", language: "not a code"),
                // The day before, and the day after: not counted on the 9th.
                LogbookConversation(startedAt: at(23, 59, day: 8), endedAt: at(0, 1, day: 9), ended: "user", language: "pl"),
                LogbookConversation(startedAt: at(0, 30, day: 10), endedAt: at(0, 31, day: 10), ended: "user", language: "pl"),
            ],
            activity: [
                entry("create_reminder", .done, at: at(9)),
                entry("create_reminder", .done, at: at(9, 1), undone: true),
                entry("create_reminder", .declined, at: at(9, 2)),
                entry("create_reminder", .notSure, at: at(9, 3)),
                entry("create_reminder", .notDone, at: at(9, 4)),
                entry("get_weather", .lookedUp, at: at(9, 5)),
                entry("made_up_tool", .done, at: at(9, 6)),
                entry(nil, .done, at: at(9, 7)),
                entry("get_weather", .lookedUp, at: at(9, day: 8)),
            ],
            notes: [
                try note(1, secret, source: .explicitVoice, category: .commitment, captured: at(9)),
                try note(2, "Ana's door code is 4512", source: .explicitText, category: .fact, captured: at(10)),
                try note(3, "A link someone shared", source: .sharedContent, category: .place, captured: at(11), edited: at(12)),
                try note(4, "Private: the doctor said", source: .explicitText, category: .fact, captured: at(13)),
                try note(5, "Groceries", source: .explicitVoice, category: .list, captured: at(14)),
                try note(6, "Yesterday's note", source: .explicitVoice, category: .fact, captured: at(9, day: 8), edited: at(15)),
            ],
            privateNoteIDs: [UUID(uuidString: "00000000-0000-4000-8000-000000000004")!],
            listItems: [
                ListItem(id: UUID(), listID: list, text: "milk", source: .voice, addedAt: at(9), doneAt: at(18), position: 0),
                ListItem(id: UUID(), listID: list, text: "bread", source: .typed, addedAt: at(9, 30), doneAt: nil, position: 1),
                ListItem(id: UUID(), listID: list, text: "eggs", source: .voice, addedAt: at(9, day: 8), doneAt: at(10, day: 10), position: 2),
            ],
            errands: [
                LogbookErrand(createdAt: at(9), finishedAt: at(9, 12), state: .done),
                LogbookErrand(createdAt: at(10), finishedAt: nil, state: .running),
                LogbookErrand(createdAt: at(23), finishedAt: at(1, day: 10), state: .failed),
                LogbookErrand(createdAt: at(9, day: 8), finishedAt: at(11), state: .done),
            ])
    }

    func testADayIsAddedUpFromTheIPhonesOwnRecords() throws {
        let day = LogbookBuilder.day("2026-11-09", from: try sources(), calendar: warsaw)
        XCTAssertEqual(day.schema, "doddy.logbook.day.v1")

        let c = day.conversations
        XCTAssertEqual(c.count, 4, "only the four that started on the 9th, in Warsaw")
        XCTAssertEqual(c.seconds, 40 + 120 + 240 + 420)
        XCTAssertEqual(c.byHour[8], 2)
        XCTAssertEqual(c.byHour[21], 1)
        XCTAssertEqual(c.byHour[22], 1)
        XCTAssertEqual([c.lengths.under1, c.lengths.from1To3, c.lengths.from3To5, c.lengths.from5To10], [1, 1, 1, 1])
        XCTAssertEqual([c.ended.you, c.ended.doddy, c.ended.quiet, c.ended.dropped], [2, 1, 0, 1], "Stop listening is the person ending it")
        XCTAssertEqual(c.languages, ["pl": 2, "en": 1], "a language that isn't a code is left out, not sent")
        XCTAssertEqual(c.waysIn.backTap, 1)
        XCTAssertEqual(c.waysIn.island, 1)

        XCTAssertEqual(day.tools.keys.sorted(), ["create_reminder", "get_weather"], "unknown and unnamed tools aren't counted")
        let reminder = try XCTUnwrap(day.tools["create_reminder"])
        XCTAssertEqual([reminder.done, reminder.declined, reminder.unsure, reminder.failed, reminder.undone], [2, 1, 1, 1, 1])
        XCTAssertEqual(day.tools["get_weather"]?.done, 1)

        XCTAssertEqual(day.notes.bySource.voice, 1)
        XCTAssertEqual(day.notes.bySource.typed, 1, "the private note isn't counted at all")
        XCTAssertEqual(day.notes.bySource.shared, 1)
        XCTAssertEqual(day.notes.byKind, ["commitment": 1, "fact": 1, "place": 1], "lists are counted under lists, not notes")
        XCTAssertEqual(day.notes.edited, 2, "edits are counted on the day they were made")

        XCTAssertEqual([day.lists.addedVoice, day.lists.addedTyped, day.lists.ticked], [1, 1, 1])

        XCTAssertEqual(day.errands.handedOver, 3)
        XCTAssertEqual(day.errands.finished, 1)
        XCTAssertEqual(day.errands.stopped, 1, "ended the next day, still counted on the day it was handed over")
        XCTAssertEqual(day.errands.minutes, 12 + 120)

        XCTAssertEqual(day.problems(toolNames: LogbookBuilder.toolNames), [])
    }

    func testNothingButCountsLeavesTheIPhone() throws {
        let day = LogbookBuilder.day("2026-11-09", from: try sources(), calendar: warsaw)
        let body = String(decoding: try day.encoded(), as: UTF8.self)
        for words in [secret, "Ana", "4512", "doctor", "Groceries", "milk", "bread", "Add reminder"] {
            XCTAssertFalse(body.contains(words), "\(words) must never be sent")
        }
    }

    func testTheKeysAreExactlyTheServersAllowList() throws {
        let day = LogbookBuilder.day("2026-11-09", from: try sources(), calendar: warsaw)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try day.encoded()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schema", "day", "conversations", "tools", "notes", "lists", "errands", "translator"])
        let c = try XCTUnwrap(json["conversations"] as? [String: Any])
        XCTAssertEqual(Set(c.keys), ["count", "seconds", "by_hour", "lengths", "ended", "languages", "ways_in"])
        XCTAssertEqual(keys(c["lengths"]), ["under_1", "1_3", "3_5", "5_10"])
        XCTAssertEqual(keys(c["ended"]), ["you", "doddy", "quiet", "dropped"])
        XCTAssertEqual(keys(c["ways_in"]), ["app", "back_tap", "action_button", "widget", "siri", "island"])
        let notes = try XCTUnwrap(json["notes"] as? [String: Any])
        XCTAssertEqual(Set(notes.keys), ["by_source", "by_kind", "edited"])
        XCTAssertEqual(keys(notes["by_source"]), ["voice", "typed", "shared", "imported"])
        XCTAssertEqual(keys(json["lists"]), ["added_voice", "added_typed", "ticked"])
        XCTAssertEqual(keys(json["errands"]), ["handed_over", "finished", "stopped", "minutes", "searches", "pages"])
        XCTAssertEqual(keys(json["translator"]), ["sessions", "minutes"])
        let reminder = try XCTUnwrap((json["tools"] as? [String: Any])?["create_reminder"] as? [String: Any])
        XCTAssertEqual(Set(reminder.keys), ["done", "declined", "unsure", "failed", "undone"])
    }

    /// The days the server itself wrote (`npm run fixtures:web`) read as LogbookDay and pass its checks here.
    func testTheServersOwnDaysReadAndPass() throws {
        struct View: Decodable { let days: [LogbookDay] }
        let view = try JSONDecoder().decode(View.self, from: try fixture("logbook-view"))
        XCTAssertFalse(view.days.isEmpty)
        for day in view.days {
            XCTAssertEqual(day.problems(toolNames: LogbookBuilder.toolNames), [], day.day)
        }
    }

    func testEveryServerRuleIsCheckedBeforeSending() {
        var day = LogbookDay(day: "2026-11-09")
        XCTAssertEqual(day.problems(toolNames: []), [])
        day.conversations.count = 1
        XCTAssertTrue(day.problems(toolNames: []).contains("conversations: hours must add up to the count"))
        day.conversations.byHour[9] = 1
        day.conversations.lengths.under1 = 1
        day.conversations.ended.you = 1
        XCTAssertEqual(day.problems(toolNames: []), [])
        day.conversations.languages = ["pl": 2]
        XCTAssertTrue(day.problems(toolNames: []).contains("conversations: languages can't exceed the count"))
        day.conversations.languages = [:]
        day.tools["send_email"] = LogbookDay.Outcomes()
        XCTAssertTrue(day.problems(toolNames: ["get_weather"]).contains("tools: a tool Doddy doesn't have"))
        day.tools = [:]
        day.notes.byKind["list"] = 1
        XCTAssertTrue(day.problems(toolNames: []).contains("notes: a type the server doesn't know"))
        day.notes.byKind = [:]
        day.errands.handedOver = 1
        day.errands.finished = 1
        day.errands.stopped = 1
        XCTAssertTrue(day.problems(toolNames: []).contains("errands: finished and stopped can't exceed handed over"))
        XCTAssertEqual(LogbookDay(day: "2026-02-30").problems(toolNames: []), ["day"])
    }

    func testDayKeysFollowThePhonesTimeZone() {
        // 23:30 UTC on the 8th is 00:30 on the 9th in Warsaw.
        let late = Date(timeIntervalSince1970: 1_794_180_600)
        XCTAssertEqual(LogbookCalendar.dayKey(late, calendar: warsaw), "2026-11-09")
        XCTAssertEqual(LogbookCalendar.dayKey(at(12), daysBefore: 1, calendar: warsaw), "2026-11-08")
        XCTAssertEqual(LogbookCalendar.dayKey(at(12, day: 1), daysBefore: 1, calendar: warsaw), "2026-10-31")
        XCTAssertTrue(LogbookCalendar.isCalendarDay("2028-02-29"))
        XCTAssertFalse(LogbookCalendar.isCalendarDay("2026-02-29"))
        XCTAssertTrue(LogbookCalendar.isLanguageCode("pt-BR"))
        XCTAssertFalse(LogbookCalendar.isLanguageCode("Polish"))
    }

    func testTheScheduleSendsMissedDaysOnceAndTodayAtMostHourly() {
        var state = LogbookSendState()
        let first = LogbookSchedule.daysToSend(now: at(10), state: state, calendar: warsaw)
        XCTAssertEqual(first.first, "2026-11-02")
        XCTAssertEqual(first.last, "2026-11-09")
        XCTAssertEqual(first.count, 8, "the last week, then today")
        for day in first { LogbookSchedule.recordSent(day, at: at(10), state: &state, calendar: warsaw) }

        XCTAssertEqual(LogbookSchedule.daysToSend(now: at(10, 30), state: state, calendar: warsaw), [], "today again only after an hour")
        XCTAssertEqual(LogbookSchedule.daysToSend(now: at(11, 1), state: state, calendar: warsaw), ["2026-11-09"])

        // The next morning: yesterday is sent once more, now that it's over, then today.
        let next = LogbookSchedule.daysToSend(now: at(8, day: 10), state: state, calendar: warsaw)
        XCTAssertEqual(next, ["2026-11-09", "2026-11-10"])
        for day in next { LogbookSchedule.recordSent(day, at: at(8, day: 10), state: &state, calendar: warsaw) }
        XCTAssertEqual(LogbookSchedule.daysToSend(now: at(9, 1, day: 10), state: state, calendar: warsaw), ["2026-11-10"])
    }

    func testTheClientSpeaksTheServersRoutes() async throws {
        let transport = Transport([(200, try fixture("logbook-state-on")), (200, try fixture("logbook-stored")), (200, try fixture("logbook-deleted"))])
        let client = try XCTUnwrap(BackendLogbookClient(baseURL: URL(string: "https://doddy.example")!, sessionToken: { "token-1" }, transport: transport))

        let deleted = try await client.setEnabled(true)
        XCTAssertEqual(deleted, 0)
        try await client.putDay(LogbookDay(day: "2026-10-20"))
        let gone = try await client.deleteAll()
        XCTAssertEqual(gone, 3)

        let requests = transport.requests
        XCTAssertEqual(requests.map(\.method), ["PUT", "PUT", "DELETE"])
        XCTAssertEqual(requests.map(\.url.path), ["/v1/web/logbook/state", "/v1/web/logbook/days/2026-10-20", "/v1/web/logbook"])
        XCTAssertEqual(requests[0].headers["authorization"], "Bearer token-1")
        XCTAssertEqual(String(decoding: requests[0].body ?? Data(), as: UTF8.self), #"{"enabled":true}"#)
        let sent = try JSONDecoder().decode(LogbookDay.self, from: try XCTUnwrap(requests[1].body))
        XCTAssertEqual(sent, LogbookDay(day: "2026-10-20"))
        XCTAssertNil(requests[2].body)
    }

    func testTheServersRefusalsAreNamed() async throws {
        let off = Transport([(403, try fixture("error-logbook-off"))])
        let offClient = try XCTUnwrap(BackendLogbookClient(baseURL: URL(string: "https://doddy.example")!, sessionToken: { "t" }, transport: off))
        do { try await offClient.putDay(LogbookDay(day: "2026-10-20")); XCTFail() } catch { XCTAssertEqual(error, .off) }

        let invalid = Transport([(400, try fixture("error-logbook-invalid"))])
        let invalidClient = try XCTUnwrap(BackendLogbookClient(baseURL: URL(string: "https://doddy.example")!, sessionToken: { "t" }, transport: invalid))
        do { try await invalidClient.putDay(LogbookDay(day: "2026-10-20")); XCTFail() } catch {
            XCTAssertEqual(error, .refused("The Logbook summary wasn't valid (the summary as a whole). Nothing was stored."))
        }

        let signedOut = Transport([(401, Data())])
        let signedOutClient = try XCTUnwrap(BackendLogbookClient(baseURL: URL(string: "https://doddy.example")!, sessionToken: { "t" }, transport: signedOut))
        do { _ = try await signedOutClient.setEnabled(true); XCTFail() } catch { XCTAssertEqual(error, .unauthenticated) }

        let noToken = try XCTUnwrap(BackendLogbookClient(baseURL: URL(string: "https://doddy.example")!, sessionToken: { nil }, transport: Transport()))
        do { _ = try await noToken.deleteAll(); XCTFail() } catch { XCTAssertEqual(error, .notConfigured) }

        XCTAssertNil(BackendLogbookClient(baseURL: URL(string: "http://doddy.example")!, sessionToken: { "t" }, transport: Transport()), "never over plain http")
    }

    func testAnUploadStopsAtTheFirstFailureAndSendsThatDayAgainLater() async throws {
        let transport = Transport([(200, Data(#"{"stored":true,"day":"2026-11-02"}"#.utf8)), (503, Data())])
        let client = try XCTUnwrap(BackendLogbookClient(baseURL: URL(string: "https://doddy.example")!, sessionToken: { "t" }, transport: transport))
        var state = LogbookSendState()
        let result = await LogbookUpload.run(client: client, sources: try sources(), state: &state, now: at(10), calendar: warsaw)
        XCTAssertEqual(result.sent, ["2026-11-02"])
        XCTAssertEqual(result.failure, .unreadable)
        XCTAssertEqual(state.finishedDays, ["2026-11-02"], "only the day the server confirmed counts as sent")
        XCTAssertEqual(LogbookSchedule.daysToSend(now: at(10), state: state, calendar: warsaw).first, "2026-11-03")
    }
}

