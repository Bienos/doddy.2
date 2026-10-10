import DoddyCore
import Foundation
import XCTest

final class DeletedNoteTests: XCTestCase {
    func testUndoIsOfferedOnlyInsideTheWindow() throws {
        let at = Date(timeIntervalSince1970: 1_760_000_000)
        let deleted = DeletedNote(
            record: try MemoryRecord(id: UUID(), rawText: "Gate code 4821", source: .explicitText, capturedAt: at),
            deletedAt: at)
        XCTAssertTrue(deleted.canUndo(at: at))
        XCTAssertTrue(deleted.canUndo(at: at.addingTimeInterval(9.9)))
        XCTAssertFalse(deleted.canUndo(at: at.addingTimeInterval(DeletedNote.undoWindow)))
        XCTAssertFalse(deleted.canUndo(at: at.addingTimeInterval(-1)), "a clock that went backwards doesn't reopen it")
    }
}
