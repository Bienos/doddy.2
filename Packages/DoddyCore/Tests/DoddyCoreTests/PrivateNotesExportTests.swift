import Foundation
import XCTest
@testable import DoddyCore

/// Private notes in exports, backups and restores (ADR-310): the mark travels with the notes, putting a private
/// note into a file needs the Face ID check first, and a restore brings the mark back before the note shows up.
final class PrivateNotesExportTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func note(_ text: String, at offset: TimeInterval = 0) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, capturedAt: t0.addingTimeInterval(offset))
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The file carries the mark

    func testTheJSONExportNamesThePrivateNotesAmongTheExportedOnes() throws {
        let pin = try note("Bank PIN 4417"), keys = try note("Keys in the blue tin")
        let elsewhere = UUID()
        let data = try MemoryExport.json([pin, keys], privateIDs: [pin.id, elsewhere], exportedAt: t0)
        XCTAssertEqual(try object(data)["privateNoteIds"] as? [String], [pin.id.uuidString],
                       "only a note that is in the file is named; the mark of a note that isn't is not written")
        XCTAssertEqual(try MemoryRestore.privateIDs(data), [pin.id])
    }

    func testAnExportWithNoPrivateNotesIsTheSameAsBefore() throws {
        let keys = try note("Keys in the blue tin")
        let plain = try MemoryExport.json([keys], exportedAt: t0)
        XCTAssertNil(try object(plain)["privateNoteIds"], "the key is left out, so older files and older readers see no change")
        XCTAssertEqual(plain, try MemoryExport.json([keys], privateIDs: [], exportedAt: t0))
        XCTAssertEqual(plain, try MemoryExport.json([keys], privateIDs: [UUID()], exportedAt: t0))
        XCTAssertEqual(try MemoryRestore.privateIDs(plain), [])
    }

    func testAPrivateListIsNamedToo() throws {
        let list = try MemoryRecord(id: UUID(), rawText: "Gift ideas", source: .explicitText, category: .list, capturedAt: t0)
        let data = try MemoryExport.json([list], privateIDs: [list.id], exportedAt: t0)
        XCTAssertEqual(try MemoryRestore.privateIDs(data), [list.id])
    }

    func testTheNotesStillReadBackWithTheMarkInTheFile() throws {
        let pin = try note("Bank PIN 4417"), keys = try note("Keys", at: 5)
        let data = try MemoryExport.json([pin, keys], privateIDs: [pin.id], exportedAt: t0)
        XCTAssertEqual(try MemoryRestore.read(data).records, [pin, keys])
    }

    func testAMarkThatCannotBeReadRefusesTheFileInsteadOfRestoringThePrivateNoteAsOrdinary() throws {
        let pin = try note("Bank PIN 4417")
        var file = try object(try MemoryExport.json([pin], privateIDs: [pin.id], exportedAt: t0))
        file["privateNoteIds"] = ["not-an-id"]
        XCTAssertThrowsError(try MemoryRestore.privateIDs(try JSONSerialization.data(withJSONObject: file))) {
            XCTAssertEqual($0 as? MemoryRestoreError, .unreadablePrivateMarks)
        }
        file["privateNoteIds"] = "yes"
        XCTAssertThrowsError(try MemoryRestore.privateIDs(try JSONSerialization.data(withJSONObject: file))) {
            XCTAssertEqual($0 as? MemoryRestoreError, .unreadablePrivateMarks)
        }
        XCTAssertThrowsError(try MemoryRestore.privateIDs(Data("nope".utf8))) {
            XCTAssertEqual($0 as? MemoryRestoreError, .notADoddyExport)
        }
        XCTAssertThrowsError(try MemoryRestore.privateIDs(try MemoryExport.json([pin], exportedAt: t0), maxBytes: 10)) {
            guard case .tooLarge? = $0 as? MemoryRestoreError else { return XCTFail("\($0)") }
        }
    }

    func testTextAndMarkdownExportsSayWhichNotesArePrivate() throws {
        let pin = try note("Bank PIN 4417"), keys = try note("Keys", at: 5)
        let text = MemoryExport.plainText([pin, keys], privateIDs: [pin.id], exportedAt: t0)
        let pinBlock = try XCTUnwrap(text.components(separatedBy: "\n\n").first { $0.contains("Bank PIN 4417") })
        let keysBlock = try XCTUnwrap(text.components(separatedBy: "\n\n").first { $0.contains("## Keys") })
        XCTAssertTrue(pinBlock.contains("Private: yes"))
        XCTAssertFalse(keysBlock.contains("Private"))
        XCTAssertFalse(MemoryExport.plainText([pin], exportedAt: t0).contains("Private"), "unchanged when nothing is passed")

        let markdown = MarkdownExport.markdown([pin, keys], privateIDs: [pin.id], exportedAt: t0)
        XCTAssertEqual(markdown.components(separatedBy: "Private: yes").count - 1, 1)
        XCTAssertFalse(MarkdownExport.markdown([pin], exportedAt: t0).contains("Private"))

        let list = DoddyList(record: try MemoryRecord(id: UUID(), rawText: "Gifts", source: .explicitText, category: .list, capturedAt: t0), items: [])
        XCTAssertTrue(MemoryExport.plainText([], lists: [list], privateIDs: [list.id], exportedAt: t0).contains("Private: yes"))
        XCTAssertTrue(MarkdownExport.markdown([], lists: [list], privateIDs: [list.id], exportedAt: t0).contains("Private: yes"))
    }

    // MARK: The backup carries it and the restore plan names what comes back private

    func testABackupRestorePlanNamesThePrivateNotesItAddsAndNoOthers() throws {
        let pin = try note("Bank PIN 4417"), keys = try note("Keys", at: 5), here = try note("Already here", at: 9)
        let export = try MemoryExport.json([pin, keys, here], privateIDs: [pin.id, here.id], exportedAt: t0)
        let contents = BackupContents(createdAt: t0, memoriesExport: export, reminders: [], profile: [:], photos: [])
        let plan = try BackupRestorePlan.make(contents, existing: [here], profileIsEmpty: true, now: t0)
        XCTAssertEqual(Set(plan.notes.toAdd.map(\.id)), [pin.id, keys.id])
        XCTAssertEqual(plan.privateIDs, [pin.id], "a note already on this iPhone keeps its own state")
    }

    func testABackupWithNoMarksRestoresNothingAsPrivate() throws {
        let keys = try note("Keys")
        let contents = BackupContents(createdAt: t0, memoriesExport: try MemoryExport.json([keys], exportedAt: t0),
                                      reminders: [], profile: [:], photos: [])
        XCTAssertEqual(try BackupRestorePlan.make(contents, existing: [], profileIsEmpty: true, now: t0).privateIDs, [])
    }

    func testABackupWhoseMarksAreDamagedIsNotRestored() throws {
        let pin = try note("Bank PIN 4417")
        var file = try object(try MemoryExport.json([pin], privateIDs: [pin.id], exportedAt: t0))
        file["privateNoteIds"] = [42]
        let contents = BackupContents(createdAt: t0, memoriesExport: try JSONSerialization.data(withJSONObject: file),
                                      reminders: [], profile: [:], photos: [])
        XCTAssertThrowsError(try BackupRestorePlan.make(contents, existing: [], profileIsEmpty: true, now: t0)) {
            XCTAssertEqual($0 as? MemoryRestoreError, .unreadablePrivateMarks)
        }
    }

    // MARK: The mark is set before the note is added

    func testRestoreMarksTheIncomingNotesFirstAndKeepsWhatWasMarked() {
        let old = UUID(), incoming = UUID(), already = UUID()
        let stored = PrivateNotes(ids: [old, already]).stored
        let step = PrivateNotes.markingBeforeRestore(stored: stored, incoming: [incoming, already])
        XCTAssertEqual(PrivateNotes(stored: step.stored).ids, [old, already, incoming])
        XCTAssertEqual(step.newlyMarked, [incoming], "a note that was private before is not new")
    }

    func testRestoreMarksFromNothingStored() {
        let incoming = UUID()
        let step = PrivateNotes.markingBeforeRestore(stored: nil, incoming: [incoming])
        XCTAssertEqual(PrivateNotes(stored: step.stored).ids, [incoming])
        XCTAssertEqual(PrivateNotes.markingBeforeRestore(stored: nil, incoming: []).stored, "")
    }

    func testAMarkWhoseNoteWasNotAddedIsTakenBackButOldMarksStay() {
        let old = UUID(), added = UUID(), notAdded = UUID()
        let stored = PrivateNotes(ids: [old, added, notAdded]).stored
        let settled = PrivateNotes.settlingAfterRestore(stored: stored, newlyMarked: [added, notAdded], added: [added])
        XCTAssertEqual(PrivateNotes(stored: settled).ids, [old, added])
    }

    // MARK: Face ID before a private note goes into a file

    func testNothingIsAskedWhenNoNoteInTheFileIsPrivate() throws {
        let keys = try note("Keys")
        let check = PrivateNotesExport.check(records: [keys], privateNotes: PrivateNotes(ids: [UUID()]))
        XCTAssertEqual(check.privateIDs, [])
        XCTAssertFalse(check.needsFaceID)
        XCTAssertEqual(PrivateNotesExport.outcome(for: check, faceIDConfirmed: false), .go(marked: []))
    }

    func testAFileWithAPrivateNoteNeedsFaceIDAndNamesTheNotes() throws {
        let pin = try note("Bank PIN 4417"), keys = try note("Keys")
        let check = PrivateNotesExport.check(records: [pin, keys], privateNotes: PrivateNotes(ids: [pin.id, UUID()]))
        XCTAssertEqual(check.privateIDs, [pin.id])
        XCTAssertTrue(check.needsFaceID)
        XCTAssertEqual(PrivateNotesExport.outcome(for: check, faceIDConfirmed: true), .go(marked: [pin.id]))
        XCTAssertEqual(PrivateNotesExport.outcome(for: check, faceIDConfirmed: false), .stop,
                       "no file is made, and the private note is not quietly left out of a backup that says it is complete")
    }

    func testAPrivateListCountsToo() throws {
        let list = try MemoryRecord(id: UUID(), rawText: "Gifts", source: .explicitText, category: .list, capturedAt: t0)
        XCTAssertTrue(PrivateNotesExport.check(records: [list], privateNotes: PrivateNotes(ids: [list.id])).needsFaceID)
    }
}
