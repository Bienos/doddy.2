import DoddyCore
import XCTest

/// "Ask me about it" (ADR-403): which notes get it, and what the agent is told.
final class NoteQuestionTests: XCTestCase {
    private func note(_ text: String) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: .other, capturedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testPrivateNotesNeverGetTheButton() throws {
        let gate = try note("Gate code 4821")
        var privateNotes = PrivateNotes(stored: nil)
        XCTAssertTrue(NoteQuestion.canAsk(about: gate, privateNotes: privateNotes))
        privateNotes.set(gate.id, isPrivate: true)
        XCTAssertFalse(NoteQuestion.canAsk(about: gate, privateNotes: privateNotes), "a private note is never sent")
    }

    func testTheMessageQuotesTheNoteOnOneLineAndCutsItShort() throws {
        let message = NoteQuestion.appMessage(for: try note("Gate code\n4821"))
        XCTAssertTrue(message.contains("\u{201C}Gate code 4821\u{201D}"))
        XCTAssertTrue(message.hasSuffix("Do what the note question section says now."))
        let long = NoteQuestion.appMessage(for: try note(String(repeating: "a", count: 500)))
        XCTAssertTrue(long.contains(String(repeating: "a", count: NoteQuestion.maxCharacters) + "…"))
        XCTAssertFalse(long.contains(String(repeating: "a", count: NoteQuestion.maxCharacters + 1)))
    }
}
