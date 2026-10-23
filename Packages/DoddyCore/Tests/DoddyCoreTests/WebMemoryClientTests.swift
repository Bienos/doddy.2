import Foundation
import XCTest
@testable import DoddyCore

/// Fixtures written by the backend from its own replies (`npm run fixtures:web`, ADR-603); the web
/// app's tests read the same files.
private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/web/\(name).json"))
}

private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let status: Int
    let body: Data
    let fails: Bool

    init(status: Int = 200, body: Data = Data(), fails: Bool = false) {
        self.status = status
        self.body = body
        self.fails = fails
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if fails { throw URLError(.notConnectedToInternet) }
        return (status, body)
    }
}

private func record(_ n: Int, _ text: String, source: MemorySource = .explicitVoice, category: MemoryCategory = .fact, captured: TimeInterval? = nil) throws -> MemoryRecord {
    try MemoryRecord(
        id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!, rawText: text, source: source, category: category,
        capturedAt: source == .importedLegacyUnknown ? nil : Date(timeIntervalSince1970: captured ?? 1_700_000_000 + Double(n)))
}

/// The error a call throws, or nil when it returned.
private func failure<T>(_ body: () async throws -> T) async -> WebMemoryError? {
    do {
        _ = try await body()
        return nil
    } catch {
        return (error as? WebMemoryError) ?? .server(message: "not a WebMemoryError: \(error)")
    }
}

final class WebMemoryClientTests: XCTestCase {
    private let server = URL(string: "https://doddy.example.com")!

    private func client(_ transport: ScriptedTransport, token: String? = "ds1.a.b") -> BackendWebMemoryClient {
        BackendWebMemoryClient(baseURL: server, sessionToken: { token }, transport: transport)!
    }

    // MARK: the calls

    func testSwitchesAreSetWithThePhonesSessionAndTheServersAnswerIsWhatCounts() async throws {
        let transport = ScriptedTransport(body: try fixture("memory-state-on"))
        let state = try await client(transport).setState(notes: true, conversations: true)
        XCTAssertEqual(state, WebMemoryState(notes: true, conversations: true))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/web/memory/state")
        XCTAssertEqual(request.headers["authorization"], "Bearer ds1.a.b")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), #"{"conversations":true,"notes":true}"#)
    }

    func testAnAnswerThatDoesntMatchWhatWasAskedIsNotBelieved() async throws {
        // The server says notes are on when the phone asked for them off: nothing is claimed.
        let transport = ScriptedTransport(body: try fixture("memory-state-on"))
        let error = await failure { try await client(transport).setState(notes: false, conversations: true) }
        XCTAssertEqual(error, .unreadable, "a mismatch must not pass")
    }

    func testNotesAreSentAsTheWholeListAndTheCountComesBackFromTheServer() async throws {
        let transport = ScriptedTransport(body: try fixture("memory-notes-stored"))
        let items = [try record(1, "Anna's birthday is 14 March"), try record(2, "Dentist on Friday at 9", category: .commitment), try record(3, "Zaproszenie od Łukasza")]
        let kept = KeptNote.from(items, excluding: PrivateNotes())
        let count = try await client(transport).replaceNotes(kept)
        XCTAssertEqual(count, 3)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.path, "/v1/web/memory/notes")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        let sent = try XCTUnwrap(body["items"] as? [[String: Any]])
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0]["id"] as? String, "00000000-0000-4000-8000-000000000001", "ids go lowercase")
        XCTAssertEqual(sent[0]["text"] as? String, "Anna's birthday is 14 March")
        XCTAssertEqual(sent[0]["source"] as? String, "explicit_voice")
        XCTAssertEqual(sent[1]["kind"] as? String, "commitment")
        XCTAssertNotNil(sent[0]["capturedAt"] as? String)
        XCTAssertEqual(Set(sent[0].keys), ["id", "text", "source", "kind", "capturedAt"], "only what the server's allow-list names")
    }

    func testACountThatIsntTheNumberSentIsNotBelieved() async throws {
        // The fixture's server answer is 3; sending 2 and being told 3 is a mismatch.
        let transport = ScriptedTransport(body: try fixture("memory-notes-stored"))
        let two = KeptNote.from([try record(1, "one"), try record(2, "two")], excluding: PrivateNotes())
        let error = await failure { try await client(transport).replaceNotes(two) }
        XCTAssertEqual(error, .unreadable, "a different count must not pass")
    }

    func testAConversationGoesToItsOwnAddressWithTheTurnsAsText() async throws {
        let transport = ScriptedTransport(body: try fixture("memory-conversation-stored"))
        let id = UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!
        let log = ConversationLog(
            id: id, startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_180),
            lines: [.init(fromUser: true, text: "Kiedy są urodziny Anny?"), .init(fromUser: false, text: "Urodziny Anny są 14 marca.")], ended: "user")
        let conversation = try XCTUnwrap(KeptConversation.from(log, language: "pl", now: Date(timeIntervalSince1970: 2_000)))
        try await client(transport).putConversation(conversation)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.path, "/v1/web/memory/conversations/00000000-0000-4000-8000-0000000000c1")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["startedAt", "endedAt", "language", "endedBy", "turns"], "the id is in the address, not the body")
        XCTAssertEqual(body["endedBy"] as? String, "you")
        XCTAssertEqual(body["language"] as? String, "pl")
        let turns = try XCTUnwrap(body["turns"] as? [[String: String]])
        XCTAssertEqual(turns, [["role": "user", "text": "Kiedy są urodziny Anny?"], ["role": "doddy", "text": "Urodziny Anny są 14 marca."]])
    }

    func testDeletingEverythingReadsTheCountsTheServerGave() async throws {
        let transport = ScriptedTransport(body: try fixture("memory-deleted"))
        let state = try await client(transport).deleteAll()
        XCTAssertEqual(state, WebMemoryState(notes: false, conversations: false, deletedNotes: 3, deletedConversations: 0))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url.path, "/v1/web/memory")
        XCTAssertNil(request.body)
    }

    // MARK: what the server can say instead

    func testTheServerSayingItIsOffIsItsOwnError() async throws {
        let transport = ScriptedTransport(status: 403, body: try fixture("error-memory-off"))
        let error = await failure { try await client(transport).replaceNotes([]) }
        XCTAssertEqual(error, .off)
    }

    func testEveryOtherAnswerIsAnErrorTheModelCanSay() async throws {
        let cases: [(Int, String, WebMemoryError)] = [
            (401, #"{"error":{"code":"unauthenticated","message":"x"}}"#, .unauthenticated),
            (413, #"{"error":{"code":"payload_too_large","message":"x"}}"#, .tooLarge),
            (503, #"{"error":{"code":"live_not_configured","message":"x","correlationId":"c1"}}"#, .notSetUp),
            (429, #"{"error":{"code":"rate_limited","message":"x","correlationId":"c1","retryAfterSeconds":30}}"#, .rateLimited(retryAfterSeconds: 30)),
            (500, #"{"error":{"code":"internal","message":"Something went wrong.","correlationId":"c1"}}"#, .server(message: "Something went wrong.")),
            (500, "<html>", .unreadable),
        ]
        for (status, body, expected) in cases {
            let transport = ScriptedTransport(status: status, body: Data(body.utf8))
            let error = await failure { try await client(transport).deleteAll() }
            XCTAssertEqual(error, expected, "status \(status)")
        }
    }

    func testNoConnectionAndNoSessionAreTheirOwnErrors() async throws {
        let offline = await failure { try await client(ScriptedTransport(fails: true)).deleteAll() }
        XCTAssertEqual(offline, .transport)
        let transport = ScriptedTransport(body: try fixture("memory-deleted"))
        let noSession = await failure { try await client(transport, token: nil).deleteAll() }
        XCTAssertEqual(noSession, .notConfigured)
        XCTAssertEqual(transport.requests.count, 0, "nothing is sent without a session")
    }

    func testOnlyHTTPSOrLoopbackServersAreUsed() {
        XCTAssertNil(BackendWebMemoryClient(baseURL: URL(string: "http://doddy.example.com")!, sessionToken: { "t" }, transport: ScriptedTransport()))
        XCTAssertNotNil(BackendWebMemoryClient(baseURL: URL(string: "http://127.0.0.1:8787")!, sessionToken: { "t" }, transport: ScriptedTransport()))
    }

    // MARK: what is sent

    func testPrivateNotesListsSamplesAndBlanksNeverLeaveTheiPhone() throws {
        let kept = try record(1, "Anna's birthday")
        let secret = try record(2, "PRIVATE the diagnosis")
        let list = try record(3, "Shopping", category: .list)
        let sample = try record(4, "A sample note", source: .sampleFixture)
        let duplicate = try record(1, "Anna's birthday")
        let items = KeptNote.from([kept, secret, list, sample, duplicate], excluding: PrivateNotes(ids: [secret.id]))
        XCTAssertEqual(items.map(\.text), ["Anna's birthday"])
        XCTAssertEqual(items.count, 1, "each note once")
        // There is no way to build upload items without saying which notes are private.
        let everything = KeptNote.from([secret], excluding: PrivateNotes(ids: [secret.id]))
        XCTAssertTrue(everything.isEmpty)
    }

    func testAnImportedNoteWithNoDateIsSentWithoutOne() throws {
        let undated = try record(1, "From an old import", source: .importedLegacyUnknown)
        let item = try XCTUnwrap(KeptNote.from([undated], excluding: PrivateNotes()).first)
        XCTAssertNil(item.capturedAt)
        XCTAssertEqual(item.source, "imported_legacy_unknown")
    }

    func testOverTheServersLimitTheNewestNotesAreSent() throws {
        let many = try (1...5_003).map { try record($0, "Note \($0)", captured: Double($0)) }
        let items = KeptNote.from(many, excluding: PrivateNotes())
        XCTAssertEqual(items.count, KeptNote.maxNotes)
        XCTAssertEqual(items.first?.text, "Note 5003")
        XCTAssertFalse(items.contains { $0.text == "Note 3" }, "the oldest three are the ones left out")
    }

    func testAConversationIsTrimmedToWhatTheServerTakes() throws {
        let long = String(repeating: "ą", count: 5_000)
        var lines: [ConversationLog.Line] = (0..<410).map { .init(fromUser: $0 % 2 == 0, text: "Turn \($0)") }
        lines.append(.init(fromUser: true, text: "   "))
        lines.append(.init(fromUser: false, text: long))
        let log = ConversationLog(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 50), lines: lines, ended: "dropped-network")
        let conversation = try XCTUnwrap(KeptConversation.from(log, language: "Polish, informal", now: Date(timeIntervalSince1970: 1_000)))
        XCTAssertEqual(conversation.turns.count, KeptConversation.maxTurns, "the last 400 turns")
        XCTAssertEqual(conversation.turns.last?.text.unicodeScalars.count, KeptConversation.maxTurnCharacters)
        XCTAssertFalse(conversation.turns.contains { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }, "blank lines are dropped")
        XCTAssertEqual(conversation.endedBy, "dropped")
        XCTAssertNil(conversation.language, "a language that isn't a code is not sent")
        XCTAssertEqual(conversation.endedAt, conversation.startedAt, "it can't end before it started")
    }

    func testHowAConversationEndedIsNamedTheWayTheServerDoes() {
        XCTAssertEqual(KeptConversation.endedBy("user"), "you")
        XCTAssertEqual(KeptConversation.endedBy("doddy"), "doddy")
        XCTAssertEqual(KeptConversation.endedBy("quiet"), "quiet")
        XCTAssertEqual(KeptConversation.endedBy("dropped-offline"), "dropped")
        XCTAssertNil(KeptConversation.endedBy("something-new"))
    }

    func testNothingSayableOrTooOldIsNotSent() {
        let blank = ConversationLog(startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_100), lines: [.init(fromUser: true, text: "  ")])
        XCTAssertNil(KeptConversation.from(blank, language: "en", now: Date(timeIntervalSince1970: 2_000)))
        let old = ConversationLog(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 100), lines: [.init(fromUser: true, text: "Hello there")])
        XCTAssertNil(KeptConversation.from(old, language: "en", now: Date(timeIntervalSince1970: 400 * 86_400)), "older than the server's year")
        XCTAssertNotNil(KeptConversation.from(old, language: "en", now: Date(timeIntervalSince1970: 300 * 86_400)))
    }

    func testAConversationMayBeSentOnlyWhenKeptOnTheServerAndNotPrivateAndNotEmpty() {
        XCTAssertTrue(KeptConversation.mayBeSent(keptOnServer: true, isPrivate: false, lineCount: 2))
        XCTAssertFalse(KeptConversation.mayBeSent(keptOnServer: false, isPrivate: false, lineCount: 2), "switched off")
        XCTAssertFalse(KeptConversation.mayBeSent(keptOnServer: true, isPrivate: true, lineCount: 2), "a private conversation never leaves")
        XCTAssertFalse(KeptConversation.mayBeSent(keptOnServer: true, isPrivate: false, lineCount: 0), "nothing was said")
    }
}
