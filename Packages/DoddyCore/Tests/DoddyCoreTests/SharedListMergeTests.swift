import DoddyCore
import XCTest

/// Shared lists (ADR-263): the three-way merge of this iPhone, iCloud and the last sync.
final class SharedListMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let milk = UUID(), eggs = UUID(), bread = UUID(), tea = UUID()

    private func item(_ id: UUID, _ text: String, done: Bool = false, at position: Int) -> SharedListItem {
        SharedListItem(id: id, text: text, doneAt: done ? t0.addingTimeInterval(60) : nil, position: position, addedAt: t0)
    }
    private var base: SharedListState {
        SharedListState(name: "Shopping", items: [item(milk, "milk", at: 0), item(eggs, "eggs", at: 1), item(bread, "bread", at: 2)])
    }

    func testChangesOnEitherSideAreBothKept() {
        let local = SharedListState(name: "Shopping", items: [item(milk, "milk", done: true, at: 0), item(eggs, "eggs", at: 1), item(bread, "bread", at: 2)])
        let remote = SharedListState(name: "Shopping", items: [item(milk, "milk", at: 0), item(eggs, "6 eggs", at: 1), item(bread, "bread", at: 2), item(tea, "tea", at: 3)])
        let result = SharedListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.merged.items.map(\.text), ["milk", "6 eggs", "bread", "tea"])
        XCTAssertNotNil(result.merged.items[0].doneAt, "ticked here")
        XCTAssertTrue(result.localChanged)
        XCTAssertTrue(result.remoteChanged)
        XCTAssertEqual(result.conflicts, 0)
    }

    func testTheSameFieldChangedOnBothSidesKeepsICloudsVersion() {
        let local = SharedListState(name: "Food", items: base.items)
        let remote = SharedListState(name: "Groceries", items: base.items)
        let result = SharedListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.merged.name, "Groceries")
        XCTAssertEqual(result.conflicts, 1)
        XCTAssertFalse(result.remoteChanged)
    }

    func testAnEditBeatsADeleteAndAnUnchangedItemCanBeDeleted() {
        // Deleted here; changed in iCloud: kept. Deleted in iCloud; only moved here: gone.
        let local = SharedListState(name: "Shopping", items: [item(eggs, "eggs", at: 1), item(bread, "bread", at: 0)])
        let remote = SharedListState(name: "Shopping", items: [item(milk, "oat milk", at: 0), item(eggs, "eggs", at: 1)])
        let result = SharedListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.merged.items.map(\.text), ["oat milk", "eggs"])
        XCTAssertEqual(result.merged.items.map(\.position), [0, 1], "renumbered the same way on every device")
    }

    func testNothingChangedMeansNothingToWrite() {
        let result = SharedListMerge.merge(base: base, local: base, remote: base)
        XCTAssertFalse(result.localChanged)
        XCTAssertFalse(result.remoteChanged)
        XCTAssertEqual(result.merged, base)
    }

    func testTheFirstSyncOfAJoinedListTakesICloud() {
        let empty = SharedListState(name: "Shopping", items: [])
        let result = SharedListMerge.merge(base: nil, local: empty, remote: base)
        XCTAssertEqual(result.merged, base)
        XCTAssertFalse(result.remoteChanged)
    }

    func testWhatComesFromICloudIsCheckedLikeAnythingTyped() {
        let checked = SharedListState.validated(name: "  Shopping ", items: [
            item(milk, "  milk ", at: 0), item(milk, "milk again", at: 1),
            item(eggs, "   ", at: 2), item(bread, String(repeating: "x", count: 201), at: 3), item(tea, "tea", at: -4),
        ])
        XCTAssertEqual(checked?.name, "Shopping")
        XCTAssertEqual(Set(checked?.items.map(\.text) ?? []), ["milk", "tea"])
        XCTAssertEqual(checked?.items.first { $0.text == "tea" }?.position, 0, "a negative position is read as 0")
        XCTAssertNil(SharedListState.validated(name: "   ", items: []))
    }

    func testTheStateSurvivesJSONToTheMillisecond() throws {
        let odd = SharedListState(name: "Shopping", items: [SharedListItem(id: milk, text: "milk", doneAt: Date(timeIntervalSince1970: 1_800_000_000.123456), position: 0, addedAt: t0)])
        XCTAssertEqual(SharedListState.decoded(try odd.encoded()), odd)
    }
}

/// What leaves this iPhone (ADR-263): the iCloud row is on only while a list is shared.
final class SharedListDataFlowTests: XCTestCase {
    func testTheICloudRowFollowsSharedLists() {
        func row(_ shared: Int) -> DataFlowRow? {
            DataFlow.rows(DataFlowState(
                rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false, connectionsOn: [],
                pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: false, sharedLists: shared))
                .first { $0.id == "iCloudSharing" }
        }
        XCTAssertEqual(row(0)?.isActive, false)
        XCTAssertEqual(row(2)?.isActive, true)
    }
}
