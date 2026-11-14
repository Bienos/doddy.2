@testable import DoddyCore
import XCTest

/// Which recap note came from which conversation, and the tombstones of deleted conversations.
/// Written without a Swift toolchain at hand: run `make test-core` before relying on it.
final class RecapLinksTests: XCTestCase {
    func testALinkIsFoundByItsConversationAndNothingIsGuessed() {
        let conversation = UUID(), memory = UUID()
        let links = RecapLinks().linking(conversation: conversation, memory: memory)
        XCTAssertEqual(links.memoryID(for: conversation), memory)
        XCTAssertNil(links.memoryID(for: UUID()))
    }

    func testADeletedConversationGetsNoLink() {
        let conversation = UUID()
        let links = RecapLinks().tombstoning([conversation]).linking(conversation: conversation, memory: UUID())
        XCTAssertTrue(links.isDeleted(conversation))
        XCTAssertNil(links.memoryID(for: conversation))
    }

    func testANoteThatCouldNotBeRemovedStaysLinkedEvenAfterDeletion() {
        let conversation = UUID(), memory = UUID()
        let links = RecapLinks().tombstoning([conversation])
            .linking(conversation: conversation, memory: memory, evenIfDeleted: true)
        XCTAssertEqual(links.memoryID(for: conversation), memory)
    }

    func testUnlinkingKeepsTheTombstone() {
        let conversation = UUID()
        let links = RecapLinks().linking(conversation: conversation, memory: UUID())
            .tombstoning([conversation]).unlinking(conversation: conversation)
        XCTAssertNil(links.memoryID(for: conversation))
        XCTAssertTrue(links.isDeleted(conversation))
    }

    func testLinkingTheSameConversationAgainReplacesTheOldLink() {
        let conversation = UUID(), first = UUID(), second = UUID()
        let links = RecapLinks().linking(conversation: conversation, memory: first)
            .linking(conversation: conversation, memory: second)
        XCTAssertEqual(links.links.count, 1)
        XCTAssertEqual(links.memoryID(for: conversation), second)
    }

    func testStoredFormRoundTripsAndGarbageIsEmpty() {
        let conversation = UUID(), memory = UUID(), gone = UUID()
        let links = RecapLinks().linking(conversation: conversation, memory: memory).tombstoning([gone])
        XCTAssertEqual(RecapLinks(stored: links.stored), links)
        XCTAssertEqual(RecapLinks(stored: "not json"), RecapLinks())
        XCTAssertEqual(RecapLinks(stored: nil), RecapLinks())
    }

    func testOldestEntriesAreDroppedBeyondTheLimit() {
        let ids = (0..<(RecapLinks.maxEntries + 5)).map { _ in UUID() }
        let links = RecapLinks().tombstoning(ids)
        XCTAssertEqual(links.deleted.count, RecapLinks.maxEntries)
        XCTAssertFalse(links.isDeleted(ids[0]))
        XCTAssertTrue(links.isDeleted(ids[ids.count - 1]))
    }
}
