import XCTest
@testable import DoddyCore

/// Private notes and the Face ID lock (ADR-310).
final class PrivateNotesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, capturedAt: now)
    }

    func testStoredSetReadsBackTheSame() {
        let a = UUID(), b = UUID()
        var notes = PrivateNotes()
        notes.set(a, isPrivate: true)
        notes.set(b, isPrivate: true)
        XCTAssertEqual(PrivateNotes(stored: notes.stored), notes)
        notes.set(a, isPrivate: false)
        XCTAssertEqual(PrivateNotes(stored: notes.stored).ids, [b])
        XCTAssertEqual(PrivateNotes(stored: "nonsense, \(b.uuidString)").ids, [b], "anything else is ignored")
    }

    func testPrivateNotesNeverLeave() throws {
        let pin = try note("Bank PIN 4417"), keys = try note("Keys in the blue tin")
        let notes = PrivateNotes(ids: [pin.id])
        XCTAssertEqual(notes.shareable([pin, keys]).map(\.id), [keys.id])
        let found = RecallOutcome.matches([MemoryCandidate(record: pin, matchedTerms: ["pin"]), MemoryCandidate(record: keys, matchedTerms: ["blue"])])
        XCTAssertEqual(notes.shareable(found), .matches([MemoryCandidate(record: keys, matchedTerms: ["blue"])]))
        XCTAssertEqual(notes.shareable(.matches([MemoryCandidate(record: pin, matchedTerms: ["pin"])])), .noMatch,
                       "only a private note matched: the voice agent hears nothing was found, not that it's hidden")
    }

    func testSearchOutsideTheAppSkipsPrivateNotes() async throws {
        let pin = try note("Bank PIN 4417")
        struct Fixed: RecallService {
            let outcome: RecallOutcome
            func recall(_ question: String, limit: Int) async throws -> RecallOutcome { outcome }
        }
        let service = ShareableRecallService(base: Fixed(outcome: .matches([MemoryCandidate(record: pin, matchedTerms: ["pin"])])),
                                             privateIDs: { [pin.id] })
        let outcome = try await service.recall("pin", limit: 5)
        XCTAssertEqual(outcome, .noMatch)
    }

    func testWhenTheAppAsksAgain() {
        XCTAssertFalse(PrivateNotes.needsUnlock(lockOn: false, unlockedAt: nil, backgroundSince: nil, now: now))
        XCTAssertTrue(PrivateNotes.needsUnlock(lockOn: true, unlockedAt: nil, backgroundSince: nil, now: now))
        XCTAssertFalse(PrivateNotes.needsUnlock(lockOn: true, unlockedAt: now, backgroundSince: now.addingTimeInterval(30), now: now.addingTimeInterval(59)))
        XCTAssertTrue(PrivateNotes.needsUnlock(lockOn: true, unlockedAt: now, backgroundSince: now, now: now.addingTimeInterval(61)))
    }

    private final class Scope: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Set<UUID> = []
        func read() -> Set<UUID> { lock.withLock { value } }
        func hide(_ id: UUID) { lock.withLock { _ = value.insert(id) } }
    }

    func testPrivacyIsReadAgainAfterAnAwaitedSearch() async throws {
        let record = try note("Synthetic private result")
        let scope = Scope()
        struct ChangingRecall: RecallService {
            let record: MemoryRecord
            let scope: Scope
            func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
                await Task.yield()
                scope.hide(record.id)
                return .matches([MemoryCandidate(record: record, matchedTerms: ["result"])])
            }
        }
        let service = ShareableRecallService(base: ChangingRecall(record: record, scope: scope), privateIDs: { scope.read() })
        let outcome = try await service.recall("result", limit: 5)
        XCTAssertEqual(outcome, .noMatch, "A note made private during the read cannot leave the phone")
    }

    func testNestedRecallScopeKeepsCallerExclusions() async throws {
        let record = try note("Synthetic caller exclusion")
        struct Fixed: RecallService {
            let record: MemoryRecord
            func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
                .matches([MemoryCandidate(record: record, matchedTerms: ["exclusion"])])
            }
        }
        let service = ShareableRecallService(base: Fixed(record: record), privateIDs: { [] })
        let outcome = try await service.recall("exclusion", limit: 5, excluding: [record.id])
        XCTAssertEqual(outcome, .noMatch)
    }
}
