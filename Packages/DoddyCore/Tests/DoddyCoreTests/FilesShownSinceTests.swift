import XCTest

@testable import DoddyCore

/// Decision 2026-11-12-deleted-files-stay-gone: files made before the conversation was deleted, or before this
/// install, are not shown again on this iPhone.
final class FilesShownSinceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func id(_ n: Int) -> String { String(repeating: "b", count: 23) + String(n % 10) }

    private func document(_ n: Int, age: TimeInterval) -> MadeDocument {
        MadeDocument(
            id: id(n), name: "File \(n)", kind: .doc, status: .ready, createdAt: now.addingTimeInterval(-age),
            deleteAfter: now.addingTimeInterval(7 * 24 * 3600), sizeBytes: 10)
    }

    func testTheStartIsTheLaterOfInstallAndDeletion() {
        let installed = now.addingTimeInterval(-3_600)
        let deleted = now.addingTimeInterval(-60)
        XCTAssertEqual(FilesShownSince.start(installedAt: installed, conversationDeletedAt: deleted), deleted)
        XCTAssertEqual(FilesShownSince.start(installedAt: deleted, conversationDeletedAt: installed), deleted)
        XCTAssertEqual(FilesShownSince.start(installedAt: installed, conversationDeletedAt: nil), installed)
        XCTAssertEqual(FilesShownSince.start(installedAt: nil, conversationDeletedAt: deleted), deleted)
        XCTAssertNil(FilesShownSince.start(installedAt: nil, conversationDeletedAt: nil))
    }

    func testFilesMadeBeforeTheStartAreNotShownAgain() {
        // The owner's report, 12 Nov 2026: after a sign-out, deleting the app and installing it again, Messages
        // showed two documents and a deck from before. Made before the install, they stay hidden.
        let installedAt = now.addingTimeInterval(-600)
        let list = MadeDocumentList(
            documents: [document(1, age: 3 * 24 * 3600), document(2, age: 2 * 24 * 3600), document(3, age: 60)],
            keptDays: 7)
        let shown = FilesShownSince.visible(list, since: installedAt)
        XCTAssertEqual(shown.documents.map(\.id), [id(3)])
        XCTAssertEqual(shown.keptDays, 7)
    }

    func testAFileMadeAtTheStartIsShown() {
        let start = now.addingTimeInterval(-60)
        let list = MadeDocumentList(documents: [document(1, age: 60)], keptDays: 7)
        XCTAssertEqual(FilesShownSince.visible(list, since: start).documents.map(\.id), [id(1)])
    }

    func testWithNoStartEverythingTheServerKeepsIsShown() {
        let list = MadeDocumentList(documents: [document(1, age: 6 * 24 * 3600), document(2, age: 60)], keptDays: 7)
        XCTAssertEqual(FilesShownSince.visible(list, since: nil), list)
    }

    func testFilesMadeOnThisIPhoneFollowTheSameStart() {
        let deletedAt = now.addingTimeInterval(-300)
        let old = LocalMadeFile(name: "Old.pptx", title: "Old", kind: "deck", createdAt: now.addingTimeInterval(-900))
        let new = LocalMadeFile(name: "New.pptx", title: "New", kind: "deck", createdAt: now.addingTimeInterval(-30))
        XCTAssertEqual(FilesShownSince.visible([old, new], since: deletedAt).map(\.name), ["New.pptx"])
        XCTAssertEqual(FilesShownSince.visible([old, new], since: nil).map(\.name), ["Old.pptx", "New.pptx"])
    }

    func testTheThreadCardsFollowTheVisibleList() {
        // Messages builds its cards from the visible list, so a hidden file is not a card either.
        let installedAt = now.addingTimeInterval(-600)
        let list = MadeDocumentList(documents: [document(1, age: 3_600), document(2, age: 120)], keptDays: 7)
        let cards = ThreadAttachments.shown(
            documents: FilesShownSince.visible(list, since: installedAt).documents, thread: [], now: now)
        XCTAssertEqual(cards.map(\.id), [id(2)])
    }
}
