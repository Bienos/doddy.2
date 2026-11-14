import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// Deleting a remembered conversation with, or without, the recap note made from it. App-target test:
/// hosted Mac job only; written without Xcode at hand, so not yet run.
final class ConversationDeletionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var oldRemember: Any?

    override func setUp() {
        suite = "ConversationDeletionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        oldRemember = UserDefaults.standard.object(forKey: PreferenceKey.rememberConversations)
        UserDefaults.standard.set(true, forKey: PreferenceKey.rememberConversations)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        UserDefaults.standard.set(oldRemember, forKey: PreferenceKey.rememberConversations)
    }

    private func log() -> ConversationLog {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        return ConversationLog(startedAt: at, endedAt: at, lines: [.init(fromUser: true, text: "Synthetic conversation")])
    }

    @MainActor
    private func conversationWithRecap() async throws -> (ConversationLog, ConversationLogStore, MemoryStore, UUID) {
        let logs = ConversationLogStore(fileURL: nil)
        let memories = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let conversation = log()
        XCTAssertTrue(logs.append(conversation))
        let recap = try await memories.save(text: "Recap", category: .other, source: .conversationRecap)
        RecapKeeper.updateLinks(defaults) { $0.linking(conversation: conversation.id, memory: recap.id) }
        return (conversation, logs, memories, recap.id)
    }

    @MainActor
    func testDeletingWithTheRecapRemovesBothAndLeavesOtherNotes() async throws {
        let (conversation, logs, memories, recapID) = try await conversationWithRecap()
        let other = try await memories.save(text: "Unrelated note", category: .other)
        let outcome = await ConversationDeletion.delete(conversation, alsoRecap: true, logs: logs, memories: memories,
                                                        defaults: defaults)
        XCTAssertEqual(outcome, .deletedWithRecap)
        XCTAssertTrue(logs.logs.isEmpty)
        XCTAssertNil(memories.record(id: recapID))
        XCTAssertNotNil(memories.record(id: other.id))
        XCTAssertTrue(RecapKeeper.links(defaults).isDeleted(conversation.id))
    }

    @MainActor
    func testDeletingWithoutTheRecapKeepsTheNoteButNotTheLink() async throws {
        let (conversation, logs, memories, recapID) = try await conversationWithRecap()
        let outcome = await ConversationDeletion.delete(conversation, alsoRecap: false, logs: logs, memories: memories,
                                                        defaults: defaults)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertNotNil(memories.record(id: recapID))
        XCTAssertNil(RecapKeeper.links(defaults).memoryID(for: conversation.id))
    }

    @MainActor
    func testAnOldNoteWithoutALinkIsNeverDeleted() async throws {
        let logs = ConversationLogStore(fileURL: nil)
        let memories = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let conversation = log()
        XCTAssertTrue(logs.append(conversation))
        let old = try await memories.save(text: "Recap-looking note", category: .other, source: .conversationRecap,
                                          capturedAt: conversation.endedAt)
        XCTAssertNil(ConversationDeletion.linkedRecapID(for: conversation, store: memories, defaults: defaults))
        let outcome = await ConversationDeletion.delete(conversation, alsoRecap: true, logs: logs, memories: memories,
                                                        defaults: defaults)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertNotNil(memories.record(id: old.id))
    }

    @MainActor
    func testForgettingAllTombstonesEveryKeptConversation() throws {
        let logs = ConversationLogStore(fileURL: nil)
        let first = log()
        XCTAssertTrue(logs.append(first))
        XCTAssertTrue(ConversationDeletion.clearAll(logs: logs, defaults: defaults))
        XCTAssertTrue(logs.logs.isEmpty)
        XCTAssertTrue(RecapKeeper.links(defaults).isDeleted(first.id))
    }
}
