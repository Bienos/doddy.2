import XCTest
@testable import DoddyCore

final class VoiceContextTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    private let t0 = Date(timeIntervalSince1970: 1_791_504_306) // 2026-10-09 02:05:06 +02:00

    private func record(_ text: String, at: Date?) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, capturedAt: at)
    }

    func testSavedNotesNewestFirstWithLocalTimestamps() throws {
        let older = try record("Kod do paczkomatu: 5678.", at: t0.addingTimeInterval(-3600))
        let newer = try record("Moje urodziny są jutro.", at: t0)
        let rendered = VoiceContext.savedNotes([older, newer], timeZone: warsaw)
        XCTAssertEqual(rendered.text, "- [2026-10-09 02:05] Moje urodziny są jutro.\n- [2026-10-09 01:05] Kod do paczkomatu: 5678.")
        XCTAssertEqual(rendered.includedCount, 2)
        XCTAssertFalse(rendered.truncated)
    }

    func testSavedNotesRespectsBudgetAndReportsTheCut() throws {
        let records = try (0..<20).map { try record("Note number \($0) with some filler text", at: t0.addingTimeInterval(Double($0))) }
        let rendered = VoiceContext.savedNotes(records, maxCharacters: 200, timeZone: warsaw)
        XCTAssertTrue(rendered.truncated)
        XCTAssertLessThanOrEqual(rendered.text.count, 200)
        XCTAssertGreaterThan(rendered.includedCount, 0)
        XCTAssertLessThan(rendered.includedCount, 20)
        XCTAssertTrue(rendered.text.hasPrefix("- [2026-10-09 02:05] Note number 19"), "newest kept first")
    }

    func testEmptyNotesAndUnknownDates() throws {
        XCTAssertEqual(VoiceContext.savedNotes([], timeZone: warsaw), VoiceContext.Rendered(text: "(no saved notes)", includedCount: 0, truncated: false))
        let legacy = try MemoryRecord(id: UUID(), rawText: "Old import", source: .importedLegacyUnknown, capturedAt: nil)
        let dated = try record("Dated", at: t0)
        let rendered = VoiceContext.savedNotes([legacy, dated], timeZone: warsaw)
        XCTAssertEqual(rendered.text, "- [2026-10-09 02:05] Dated\n- [date unknown] Old import")
    }

    func testLongLinesAreClippedAndNewlinesFlattened() throws {
        let long = String(repeating: "a", count: 1000) + "\nsecond line"
        let rendered = VoiceContext.savedNotes([try record(long, at: t0)], timeZone: warsaw)
        XCTAssertFalse(rendered.text.contains("\n"))
        XCTAssertTrue(rendered.text.hasSuffix("…"))
        XCTAssertLessThan(rendered.text.count, 450)
    }

    func testRecentConversationsKeepNewestAndReadOldestToNewest() {
        func log(_ offset: TimeInterval, _ text: String) -> ConversationLog {
            ConversationLog(startedAt: t0.addingTimeInterval(offset), endedAt: t0.addingTimeInterval(offset + 60),
                            lines: [.init(fromUser: true, text: text), .init(fromUser: false, text: "Reply to \(text)")])
        }
        let logs = [log(0, "first"), log(7200, "third"), log(3600, "second")]
        let rendered = VoiceContext.recentConversations(logs, timeZone: warsaw)
        XCTAssertEqual(rendered.includedCount, 3)
        let firstIndex = rendered.text.range(of: "User: first")!.lowerBound
        let thirdIndex = rendered.text.range(of: "User: third")!.lowerBound
        XCTAssertLessThan(firstIndex, thirdIndex, "chronological order in the output")
        XCTAssertTrue(rendered.text.hasPrefix("Conversation on 2026-10-09 02:05:\nUser: first\nDoddy: Reply to first"))

        let small = VoiceContext.recentConversations(logs, maxCharacters: 120, timeZone: warsaw)
        XCTAssertTrue(small.truncated)
        XCTAssertEqual(small.includedCount, 1)
        XCTAssertTrue(small.text.contains("User: third"), "the newest conversation survives a cut")
        XCTAssertFalse(small.text.contains("User: first"))
    }

    func testEmptyConversationsAreSkipped() {
        let empty = ConversationLog(startedAt: t0, endedAt: t0, lines: [])
        let rendered = VoiceContext.recentConversations([empty], timeZone: warsaw)
        XCTAssertEqual(rendered.text, "(no earlier conversations)")
        XCTAssertEqual(rendered.includedCount, 0)
        XCTAssertFalse(rendered.truncated)
    }

    func testConversationLogRoundTripsThroughJSON() throws {
        let log = ConversationLog(startedAt: t0, endedAt: t0.addingTimeInterval(30), lines: [.init(fromUser: true, text: "Cześć"), .init(fromUser: false, text: "Hej")])
        let data = try JSONEncoder().encode([log])
        XCTAssertEqual(try JSONDecoder().decode([ConversationLog].self, from: data), [log])
    }

    func testPrivateConversationsAreNeverKept() {
        XCTAssertTrue(ConversationRetention.shouldKeep(rememberRecent: true, isPrivate: false, lineCount: 3))
        XCTAssertFalse(ConversationRetention.shouldKeep(rememberRecent: true, isPrivate: true, lineCount: 3))
        XCTAssertFalse(ConversationRetention.shouldKeep(rememberRecent: false, isPrivate: false, lineCount: 3))
        XCTAssertFalse(ConversationRetention.shouldKeep(rememberRecent: true, isPrivate: false, lineCount: 0))
    }

    func testSettingsShowsExactlyTheConversationsSentNextTime() {
        func log(_ offset: TimeInterval, _ text: String) -> ConversationLog {
            ConversationLog(startedAt: t0.addingTimeInterval(offset), endedAt: t0.addingTimeInterval(offset + 60),
                            lines: [.init(fromUser: true, text: text), .init(fromUser: false, text: "Reply to \(text)")])
        }
        let first = log(0, "first"), second = log(3600, "second"), third = log(7200, "third")
        let logs = [first, third, second]
        XCTAssertEqual(VoiceContext.conversationsSentNextTime(logs, timeZone: warsaw), [first.id, second.id, third.id])

        let sent = VoiceContext.conversationsSentNextTime(logs, maxCharacters: 120, timeZone: warsaw)
        XCTAssertEqual(sent, [third.id])
        XCTAssertEqual(sent.count, VoiceContext.recentConversations(logs, maxCharacters: 120, timeZone: warsaw).includedCount)
        XCTAssertTrue(VoiceContext.conversationsSentNextTime([], timeZone: warsaw).isEmpty)
    }

    func testConversationExportIsOldestFirstAndUnclipped() {
        let long = String(repeating: "a", count: VoiceContext.maxLineLength + 50)
        let later = ConversationLog(startedAt: t0.addingTimeInterval(3600), endedAt: t0.addingTimeInterval(3700),
                                    lines: [.init(fromUser: true, text: "Second chat")])
        let earlier = ConversationLog(startedAt: t0, endedAt: t0.addingTimeInterval(90),
                                      lines: [.init(fromUser: true, text: long), .init(fromUser: false, text: "Okay.")])
        let text = ConversationLogExport.plainText([later, earlier], exportedAt: t0.addingTimeInterval(7200), timeZone: warsaw)
        XCTAssertTrue(text.hasPrefix("DODDY remembered conversations — exported 2026-10-09T02:05:06Z\n2 conversations."))
        XCTAssertTrue(text.contains("## 2026-10-09 02:05 – 2026-10-09 02:06\nYou: \(long)\nDoddy: Okay."), "full text, not clipped")
        XCTAssertLessThan(text.range(of: "Okay.")!.lowerBound, text.range(of: "Second chat")!.lowerBound)
        XCTAssertTrue(ConversationLogExport.plainText([], exportedAt: t0).contains("0 conversations."))
    }
}
