import DoddyCore
import Foundation
import XCTest

final class NewestNotesFallbackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_255_000)

    private func note(_ text: String, minutesAgo: Double, source: MemorySource = .explicitText,
                      category: MemoryCategory = .other) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, category: category,
                         capturedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testNoMatchListsTheNewestNotesLabelledAsNotAMatch() throws {
        let old = try note("Kod do paczkomatu 4821", minutesAgo: 600)
        let justSaved = try note("Paragon z Biedronki", minutesAgo: 1)
        let newest = NewestNotes.pick([old, justSaved], excluding: [], withPhoto: [justSaved.id])

        let reply = VoiceToolReply.search(.noMatch, question: "zdjęcie notatka photo note", newest: newest)

        XCTAssertTrue(reply.hasPrefix("No saved note contains the words of this search."))
        XCTAssertTrue(reply.contains("did not match the search"))
        XCTAssertTrue(reply.contains("Do not guess."))
        let first = try XCTUnwrap(reply.range(of: "Paragon z Biedronki"))
        let second = try XCTUnwrap(reply.range(of: "Kod do paczkomatu 4821"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound, "Newest first")
        XCTAssertTrue(reply.contains("\"Paragon z Biedronki\" (saved") && reply.contains("(has a photo)"))
        XCTAssertTrue(reply.contains("you can't see it"))
        XCTAssertFalse(reply.contains("Found "), "The newest notes are never presented as matches")
    }

    func testPrivateNotesListsAndSamplesNeverReachVoiceAndTheLimitHolds() throws {
        let secret = try note("Private PIN 1234", minutesAgo: 0)
        let list = try note("Zakupy", minutesAgo: 0.5, category: .list)
        let sample = try note("Sample fixture", minutesAgo: 0.2, source: .sampleFixture)
        let shareable = try (1...5).map { try note("Note \($0)", minutesAgo: Double($0)) }
        let newest = NewestNotes.pick([secret, list, sample] + shareable, excluding: [secret.id], withPhoto: [secret.id])

        XCTAssertEqual(newest.notes.map(\.currentText), ["Note 1", "Note 2", "Note 3"])
        XCTAssertTrue(newest.withPhoto.isEmpty, "A photo flag of a note that was left out is dropped too")
        let reply = VoiceToolReply.search(.noMatch, newest: newest)
        XCTAssertFalse(reply.contains("Private PIN"))
        XCTAssertFalse(reply.contains("Zakupy"))
        XCTAssertFalse(reply.contains("Sample fixture"))
        XCTAssertFalse(reply.contains("Note 4"))
    }

    func testWithNoNotesOrWithAMatchTheReplyIsUnchanged() throws {
        XCTAssertEqual(VoiceToolReply.search(.noMatch, question: "kod", newest: .none),
                       VoiceToolReply.search(.noMatch, question: "kod"))
        let record = try note("Kod do bramy 1234", minutesAgo: 5)
        let match = RecallOutcome.matches([MemoryCandidate(record: record, matchedTerms: ["kod"])])
        let other = NewestNotes.pick([try note("Something else", minutesAgo: 1)], excluding: [])
        XCTAssertEqual(VoiceToolReply.search(match, question: "kod", newest: other),
                       VoiceToolReply.search(match, question: "kod"))
    }

    func testCameraReplyPointsToTheSearchAfterSaving() {
        XCTAssertTrue(VoiceToolReply.cameraOpened.contains("call search_memories"))
        XCTAssertTrue(VoiceToolReply.cameraOpened.contains("Never say a photo was taken or saved"))
    }
}
