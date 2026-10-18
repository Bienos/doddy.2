import Foundation
import XCTest
@testable import DoddyCore

/// Texts the user sends to Doddy's number (ADR-490 unit U3, ADR-494).
final class TextsToDoddyTests: XCTestCase {
    /// GET /v1/texts/settings as server/messaging/src/routes/textSettings.ts writes it.
    private let serverJSON = #"""
    {"available":{"notes":true,"replies":true},"doddyNumber":"+48221234567","phoneVerified":true,"textsFromDoddy":true,
     "optedOut":false,"inboundEnabled":true,"repliesEnabled":false,"repliesUseMemories":false,"memoryCopy":false,
     "language":"pl","consentTextVersion":"texts-in-v1"}
    """#

    func testTheServersSettingsDecode() throws {
        let s = try JSONDecoder().decode(TextSettings.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(s.available, .init(notes: true, replies: true))
        XCTAssertEqual(s.doddyNumber, "+48221234567")
        XCTAssertTrue(s.inboundEnabled)
        XCTAssertFalse(s.repliesEnabled)
        XCTAssertEqual(s.language, "pl")
        XCTAssertEqual(s.consentTextVersion, TextsToDoddyConsent.textVersion)
    }

    func testEachSwitchSaysWhatItWaitsFor() {
        func settings(
            notes: Bool = true, replies: Bool = true, phone: Bool = true, fromDoddy: Bool = true,
            inbound: Bool = true, repliesOn: Bool = true, copy: Bool = true
        ) -> TextSettings {
            TextSettings(
                available: .init(notes: notes, replies: replies), doddyNumber: nil, phoneVerified: phone, textsFromDoddy: fromDoddy,
                optedOut: !fromDoddy, inboundEnabled: inbound, repliesEnabled: repliesOn, repliesUseMemories: false, memoryCopy: copy,
                language: "en", consentTextVersion: nil)
        }
        XCTAssertEqual(settings(notes: false).inboundBlocker, .notSetUp)
        XCTAssertEqual(settings(phone: false).inboundBlocker, .noVerifiedPhone)
        XCTAssertNil(settings().inboundBlocker)
        XCTAssertEqual(settings(replies: false).repliesBlocker, .repliesNotSetUp)
        XCTAssertEqual(settings(inbound: false).repliesBlocker, .textsToDoddyOff)
        XCTAssertEqual(settings(fromDoddy: false).repliesBlocker, .textsFromDoddyOff)
        XCTAssertNil(settings().repliesBlocker)
        XCTAssertEqual(settings(repliesOn: false).memoriesBlocker, .repliesOff)
        XCTAssertEqual(settings(copy: false).memoriesBlocker, .memoryCopyOff)
        XCTAssertNil(settings().memoriesBlocker)
        // The first problem wins: an unverified number before anything about replies.
        XCTAssertEqual(settings(phone: false, fromDoddy: false, inbound: false).memoriesBlocker, .noVerifiedPhone)
        XCTAssertEqual(TextSettings.off.inboundBlocker, .notSetUp)
    }

    func testSwitchesThatAreOnButCantWorkSaySo() {
        func settings(notes: Bool = true, replies: Bool = true, fromDoddy: Bool = true, repliesOn: Bool = true,
                      memories: Bool = true, copy: Bool = true) -> TextSettings {
            TextSettings(
                available: .init(notes: notes, replies: replies), doddyNumber: nil, phoneVerified: true, textsFromDoddy: fromDoddy,
                optedOut: !fromDoddy, inboundEnabled: true, repliesEnabled: repliesOn, repliesUseMemories: memories, memoryCopy: copy,
                language: "en", consentTextVersion: "texts-in-v1")
        }
        XCTAssertEqual(settings().pauses, [])
        XCTAssertEqual(settings(notes: false).pauses, [.notReceiving])
        XCTAssertEqual(settings(fromDoddy: false).pauses, [.repliesCantText], "after STOP the switch stays on but replies stop")
        XCTAssertEqual(settings(replies: false).pauses, [.repliesNotSetUp])
        XCTAssertEqual(settings(copy: false).pauses, [.memoriesWithoutCopy])
        XCTAssertEqual(settings(fromDoddy: false, repliesOn: false, memories: false).pauses, [], "nothing on, nothing paused")
        XCTAssertEqual(TextSettings.off.pauses, [])
    }

    func testTheConsentWordingSaysWhereTextsGoAndWhatStopDoes() {
        let text = TextsToDoddyConsent.text
        for part in ["Doddy's server", "Twilio", "notes", "an AI", "Anthropic", "STOP"] {
            XCTAssertTrue(text.contains(part), part)
        }
        XCTAssertEqual(TextsToDoddyConsent.textVersion, "texts-in-v1", "a new wording needs a new version on the server too")
    }

    func testTheServerKnowsThisConsentVersion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let server = try String(contentsOf: root.appendingPathComponent("server/messaging/src/textReplies.ts"), encoding: .utf8)
        XCTAssertTrue(server.contains("TEXTS_IN_CONSENT_VERSIONS = new Set([\"\(TextsToDoddyConsent.textVersion)\"])"))
    }

    // MARK: Requests

    private struct Body: Decodable, Equatable {
        var inboundEnabled: Bool?
        var repliesEnabled: Bool?
        var repliesUseMemories: Bool?
        var language: String?
        var consentTextVersion: String?
    }

    private func bodies(_ transport: StepTransport) async throws -> [Body] {
        try await transport.sent.compactMap { try $0.body.map { try JSONDecoder().decode(Body.self, from: $0) } }
    }

    func testSwitchesSendOnlyWhatChangesAndConsentOnlyWhenTurningOn() async throws {
        let ok = Result<ServerResponse, any Error>.success(ServerResponse(status: 204))
        let transport = StepTransport([ok, ok, ok, ok])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        try await client.setTextsToDoddy(true, language: .polish)
        try await client.setTextReplies(true, language: .english)
        try await client.setTextRepliesUseMemories(true)
        try await client.setTextsToDoddy(false, language: .english)
        let sent = await transport.sent
        XCTAssertEqual(Set(sent.map(\.path)), ["/v1/texts/settings"])
        XCTAssertEqual(Set(sent.map(\.method)), [.put])
        let sentBodies = try await bodies(transport)
        XCTAssertEqual(sentBodies, [
            Body(inboundEnabled: true, language: "pl", consentTextVersion: "texts-in-v1"),
            Body(repliesEnabled: true, language: "en"),
            Body(repliesUseMemories: true),
            Body(inboundEnabled: false, language: "en"),
        ])
    }

    func testRefusalsComeBackAsTheServersReason() async {
        let transport = StepTransport([.success(ServerResponse(status: 409, body: Data(#"{"error":"sms_not_enabled"}"#.utf8)))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        do {
            try await client.setTextReplies(true, language: .english)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ServerError, .notEnabled("sms_not_enabled"))
        }
    }

    func testTheHistoryExportIsTheServersJSONAsItCame() async throws {
        let json = Data(#"{"exportedAt":"2026-10-18T10:00:00.000Z","calls":[],"notesWaiting":[]}"#.utf8)
        let transport = StepTransport([.success(ServerResponse(status: 200, body: json)), .success(ServerResponse(status: 200, body: Data("<html>".utf8)))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let exported = try await client.phoneHistory()
        XCTAssertEqual(exported, json)
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/v1/phone/history")
        do {
            _ = try await client.phoneHistory()
            XCTFail("a reply that isn't a JSON object is not an export")
        } catch {}
    }

    func testNotesSayWhetherTheyCameFromATextOrACall() throws {
        let inbox = try JSONDecoder().decode(CallInbox.self, from: Data(#"""
        {"notes":[{"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a10","text":"Kupić mleko","createdAt":"2026-10-18T10:00:00.000Z","source":"text"},
                  {"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a11","text":"Call the dentist","createdAt":"2026-10-18T10:00:00.000Z","source":"call"},
                  {"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a12","text":"From an older server","createdAt":"2026-10-18T10:00:00.000Z"},
                  {"id":"6f1c2c1e-3b6c-4c55-9a39-0d6a1e9f1a13","text":"Ask about the gate","createdAt":"2026-10-18T10:00:00.000Z","source":"doddy"}],
         "unreadable":[]}
        """#.utf8))
        XCTAssertEqual(inbox.notes.map(\.fromText), [true, false, false, false])
        XCTAssertEqual(inbox.notes.map(\.writtenByDoddy), [false, false, false, true], "Doddy's words are never shown as the user's text")
    }

    func testTheLanguageCodes() {
        XCTAssertEqual(NotificationLanguage.polish.serverCode, "pl")
        XCTAssertEqual(NotificationLanguage.english.serverCode, "en")
    }
}
