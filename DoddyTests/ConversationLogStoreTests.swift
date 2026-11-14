import DoddyCore
import Foundation
import XCTest
@testable import Doddy

final class ConversationLogStoreTests: XCTestCase {
    private func log(_ index: Int = 0) -> ConversationLog {
        let at = Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
        return ConversationLog(startedAt: at, endedAt: at, lines: [.init(fromUser: true, text: "Synthetic conversation \(index)")])
    }

    @MainActor
    func testAppendSurvivesReopenAndKeepsOnlyTen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recent.json")
        let old = UserDefaults.standard.object(forKey: PreferenceKey.rememberConversations)
        UserDefaults.standard.set(true, forKey: PreferenceKey.rememberConversations)
        defer { UserDefaults.standard.set(old, forKey: PreferenceKey.rememberConversations) }
        let store = ConversationLogStore(fileURL: url)
        XCTAssertNil(store.problem, "A missing file is normal on first use")
        for index in 0..<12 { XCTAssertTrue(store.append(log(index))) }
        XCTAssertEqual(store.logs.count, 10)
        XCTAssertEqual(ConversationLogStore(fileURL: url).logs, store.logs)
        XCTAssertTrue(store.remove(store.logs[0].id))
        XCTAssertEqual(ConversationLogStore(fileURL: url).logs.count, 9)
        XCTAssertTrue(store.clear())
        XCTAssertTrue(ConversationLogStore(fileURL: url).logs.isEmpty)
    }

    @MainActor
    func testFailedAppendDoesNotPublishOrEvictCommittedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recent.json")
        let original = (0..<10).map(log)
        try JSONEncoder().encode(original).write(to: url)
        let store = ConversationLogStore(fileURL: url)
        try FileManager.default.removeItem(at: url)
        // A directory at the target path deterministically refuses a file write, even as root.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let old = UserDefaults.standard.object(forKey: PreferenceKey.rememberConversations)
        UserDefaults.standard.set(true, forKey: PreferenceKey.rememberConversations)
        defer { UserDefaults.standard.set(old, forKey: PreferenceKey.rememberConversations) }
        XCTAssertFalse(store.append(log(99)))
        XCTAssertEqual(store.logs, original, "Failure cannot evict the oldest confirmed conversation")
        XCTAssertNotNil(store.problem)
        XCTAssertFalse(store.clear())
        XCTAssertEqual(store.logs, original)
    }

    @MainActor
    func testCorruptHistoryReportsFailureWithoutChangingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("broken synthetic JSON".utf8)
        try bytes.write(to: url)
        let store = ConversationLogStore(fileURL: url)
        XCTAssertNotNil(store.problem)
        XCTAssertTrue(store.logs.isEmpty)
        XCTAssertFalse(store.append(log()), "A corrupt archive is not silently overwritten")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(store.clear(), "Explicit deletion remains possible")
        XCTAssertNil(store.problem)
    }

    @MainActor
    func testUnavailableProductionPathCannotPretendToClearOrKeepHistory() {
        let old = UserDefaults.standard.object(forKey: PreferenceKey.rememberConversations)
        UserDefaults.standard.set(true, forKey: PreferenceKey.rememberConversations)
        defer { UserDefaults.standard.set(old, forKey: PreferenceKey.rememberConversations) }
        let store = ConversationLogStore(fileURL: nil, storageUnavailable: true)
        XCTAssertNotNil(store.problem)
        XCTAssertFalse(store.clear(), "An inaccessible archive cannot be reported forgotten")
        XCTAssertNotNil(store.problem)
        XCTAssertFalse(store.append(log()), "Clear failure must not enable volatile writes")
        XCTAssertTrue(store.logs.isEmpty)
        let volatile = ConversationLogStore(fileURL: nil)
        XCTAssertTrue(volatile.append(log()), "Explicit test stores still work")
        XCTAssertTrue(volatile.clear())
    }

    @MainActor
    func testFailedReadBackReportsUnknownAndPreventsAStaleOverwrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let old = UserDefaults.standard.object(forKey: PreferenceKey.rememberConversations)
        UserDefaults.standard.set(true, forKey: PreferenceKey.rememberConversations)
        defer { UserDefaults.standard.set(old, forKey: PreferenceKey.rememberConversations) }
        let original = log(1)
        try JSONEncoder().encode([original]).write(to: url)
        var reads = 0
        let store = ConversationLogStore(fileURL: url, readFile: { url in
            reads += 1
            if reads > 1 { throw CocoaError(.fileReadNoPermission) }
            return try Data(contentsOf: url)
        })
        let newer = log(2)
        XCTAssertFalse(store.append(newer))
        XCTAssertEqual(try JSONDecoder().decode([ConversationLog].self, from: Data(contentsOf: url)), [original, newer])
        XCTAssertNotNil(store.problem)
        XCTAssertFalse(store.append(log(3)))
        XCTAssertFalse(store.remove(UUID()))
        XCTAssertEqual(try JSONDecoder().decode([ConversationLog].self, from: Data(contentsOf: url)), [original, newer])
    }
}
