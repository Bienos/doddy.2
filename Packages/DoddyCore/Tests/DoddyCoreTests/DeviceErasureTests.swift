import Foundation
import XCTest
@testable import DoddyCore

/// "Erase everything on this iPhone": the plan runs one step per store, each with an erase and a read-back, and
/// says "erased" only when every store was read back as empty (DOD-08). Platforms: iPhone (the Watch and Mac apps
/// are paused). The stores here are in-memory fakes; the real ones are in the app (`EraseThisIPhone.swift`).
final class DeviceErasureTests: XCTestCase {
    /// A fake store: holds items, erases on request, and can be made to fail or to lie.
    private final class FakeStore: @unchecked Sendable {
        private let lock = NSLock()
        private var items: Int
        private(set) var eraseCalls = 0
        private(set) var verifyCalls = 0
        var failErase = false
        /// Erase "works" but leaves this many items (a store that didn't really empty).
        var leftOver = 0
        var failVerify = false

        init(items: Int) { self.items = items }

        var count: Int { lock.withLock { items } }

        func erase() throws {
            try lock.withLock {
                eraseCalls += 1
                if failErase { throw FakeError.eraseRefused }
                items = leftOver
            }
        }

        func verifyEmpty() throws -> Bool {
            try lock.withLock {
                verifyCalls += 1
                if failVerify { throw FakeError.readRefused }
                return items == 0
            }
        }
    }

    private enum FakeError: Error { case eraseRefused, readRefused }

    private func step(_ id: DeviceStoreID, _ store: FakeStore) -> DeviceErasureStep {
        DeviceErasureStep(store: id, erase: { try store.erase() }, verifyEmpty: { try store.verifyEmpty() })
    }

    /// Fakes for every store, so a test can change one.
    private func everyStore(items: Int = 3) -> [DeviceStoreID: FakeStore] {
        Dictionary(uniqueKeysWithValues: DeviceStoreID.allCases.map { ($0, FakeStore(items: items)) })
    }

    private func steps(_ stores: [DeviceStoreID: FakeStore]) -> [DeviceErasureStep] {
        DeviceStoreID.allCases.compactMap { id in stores[id].map { step(id, $0) } }
    }

    // MARK: Erased only when read back

    func testEveryStoreErasedAndReadBackIsErased() async {
        let stores = everyStore()
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(report.result, .erased)
        XCTAssertTrue(report.isErased)
        XCTAssertEqual(report.notConfirmed, [])
        for (id, store) in stores {
            XCTAssertEqual(store.count, 0, "\(id) still holds items")
            XCTAssertEqual(store.verifyCalls, 1, "\(id) must be read back once")
        }
    }

    func testAStoreThatSaysItErasedButIsNotEmptyIsNotConfirmed() async {
        let stores = everyStore()
        stores[.conversationTranscripts]!.leftOver = 2
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(report.result, .notConfirmed([.conversationTranscripts]))
        XCTAssertEqual(report.outcomes[.conversationTranscripts], .notConfirmed(.notEmpty))
        XCTAssertFalse(report.isErased)
    }

    func testAnEraseThatFailsAndIsStillFullIsNotConfirmedWithItsReason() async {
        let stores = everyStore()
        stores[.messagesThread]!.failErase = true
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(report.notConfirmed, [.messagesThread])
        guard case .notConfirmed(.eraseFailed(let reason)) = report.outcomes[.messagesThread] else {
            return XCTFail("expected an erase failure, got \(String(describing: report.outcomes[.messagesThread]))")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testAnEraseThatThrowsButLeavesTheStoreEmptyCountsAsErased() async {
        // The read-back is what counts: a store already empty is empty, whatever the erase said.
        let stores = everyStore(items: 0)
        stores[.trips]!.failErase = true
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(report.result, .erased)
    }

    func testAReadBackThatCannotBeDoneIsNotConfirmed() async {
        let stores = everyStore()
        stores[.spotlight]!.failVerify = true
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(report.notConfirmed, [.spotlight])
        guard case .notConfirmed(.couldNotVerify) = report.outcomes[.spotlight] else {
            return XCTFail("expected couldNotVerify")
        }
    }

    // MARK: Partial failure

    func testOneFailureDoesNotStopTheRest() async {
        let stores = everyStore()
        stores[.notesAndLists]!.failErase = true
        stores[.keychainPersonalKeys]!.failErase = true
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(Set(report.notConfirmed), [.notesAndLists, .keychainPersonalKeys])
        for (id, store) in stores where id != .notesAndLists && id != .keychainPersonalKeys {
            XCTAssertEqual(store.count, 0, "\(id) must still be erased after another store failed")
        }
        // Every store was tried, the failing ones too.
        for (_, store) in stores { XCTAssertEqual(store.eraseCalls, 1) }
    }

    func testNotConfirmedStoresAreListedInTheOrderOfTheInventory() async {
        let stores = everyStore()
        stores[.spotlight]!.leftOver = 1
        stores[.notesAndLists]!.leftOver = 1
        stores[.preferences]!.leftOver = 1
        let report = await DeviceErasure.run(steps: steps(stores).reversed())
        XCTAssertEqual(report.notConfirmed, DeviceStoreID.allCases.filter { [.spotlight, .notesAndLists, .preferences].contains($0) })
    }

    // MARK: A store the plan forgot

    func testAStoreWithNoStepIsNeverReportedErased() async {
        var stores = everyStore()
        stores[.activityList] = nil
        let report = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(report.result, .notConfirmed([.activityList]))
        XCTAssertEqual(report.outcomes[.activityList], .notConfirmed(.notInPlan))
    }

    func testAnEmptyPlanConfirmsNothing() async {
        let report = await DeviceErasure.run(steps: [])
        XCTAssertEqual(report.notConfirmed, DeviceStoreID.allCases)
    }

    // MARK: Twice

    func testRunningItTwiceIsHarmless() async {
        let stores = everyStore()
        let first = await DeviceErasure.run(steps: steps(stores))
        let second = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(first.result, .erased)
        XCTAssertEqual(second.result, .erased)
        for (_, store) in stores { XCTAssertEqual(store.count, 0) }
    }

    func testARetryAfterAFailureConfirmsWhatFailed() async {
        let stores = everyStore()
        stores[.errands]!.failErase = true
        let first = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(first.notConfirmed, [.errands])
        stores[.errands]!.failErase = false
        let second = await DeviceErasure.run(steps: steps(stores))
        XCTAssertEqual(second.result, .erased)
    }

    // MARK: Order and scope

    func testStepsRunInTheOrderGiven() async {
        actor Log { var ids: [DeviceStoreID] = []; func add(_ id: DeviceStoreID) { ids.append(id) } }
        let log = Log()
        let given: [DeviceStoreID] = [.sharedListsInICloud, .notesAndLists, .spotlight]
        let planned = given.map { id in
            DeviceErasureStep(store: id, erase: { await log.add(id) }, verifyEmpty: { true })
        }
        _ = await DeviceErasure.run(steps: planned, required: Set(given))
        let ran = await log.ids
        XCTAssertEqual(ran, given)
    }

    func testOnlyTheRequiredStoresMustHaveASteps() async {
        let report = await DeviceErasure.run(
            steps: [DeviceErasureStep(store: .spotlight, erase: {}, verifyEmpty: { true })], required: [.spotlight])
        XCTAssertEqual(report.result, .erased)
    }

    func testTwoStepsForOneStoreNeedBothToBeConfirmed() async {
        let ok = DeviceErasureStep(store: .preferences, erase: {}, verifyEmpty: { true })
        let notOk = DeviceErasureStep(store: .preferences, erase: {}, verifyEmpty: { false })
        let report = await DeviceErasure.run(steps: [ok, notOk], required: [.preferences])
        XCTAssertEqual(report.notConfirmed, [.preferences])
        let reversed = await DeviceErasure.run(steps: [notOk, ok], required: [.preferences])
        XCTAssertEqual(reversed.notConfirmed, [.preferences])
    }

    // MARK: The order the app runs the plan in

    func testTheOrderListsEveryStoreOnceAndRespectsWhatDependsOnWhat() {
        let order = DeviceStoreID.erasureOrder
        XCTAssertEqual(order.count, DeviceStoreID.allCases.count)
        XCTAssertEqual(Set(order), Set(DeviceStoreID.allCases))
        func place(_ id: DeviceStoreID) -> Int { order.firstIndex(of: id)! }
        // Sharing is stopped while the lists and the links to their shares still exist.
        XCTAssertLessThan(place(.sharedListsInICloud), place(.notesAndLists))
        // The server copy is emptied while the switch that says it exists, and the sign-in it needs, are still there.
        XCTAssertLessThan(place(.memoryCopyOnServer), place(.preferences))
        XCTAssertLessThan(place(.memoryCopyOnServer), place(.keychainServerHandles))
        // Preferences go last: other steps read them (private note ids, switches, markers they write).
        XCTAssertEqual(order.last, .preferences)
        // Models first, then the folders they wrote to are swept.
        XCTAssertLessThan(place(.notesAndLists), place(.notePhotoFiles))
        XCTAssertLessThan(place(.notesAndLists), place(.noteAudioFiles))
        XCTAssertLessThan(place(.recordings), place(.recordingFiles))
        XCTAssertLessThan(place(.conversationTranscripts), place(.workingFiles))
    }

    func testTheRequiredStoresFollowTheOrder() {
        let kept = DeviceStoreID.erasureOrder.filter(DeviceErasureScope.keepSignIn.requiredStores.contains)
        XCTAssertEqual(kept.count, DeviceErasureScope.keepSignIn.requiredStores.count)
        XCTAssertFalse(kept.contains(.keychainServerHandles))
    }

    // MARK: The inventory itself

    func testEveryStoreIsInAGroupAndHasABackupRule() {
        for id in DeviceStoreID.allCases {
            _ = id.group
            _ = id.backup
        }
        XCTAssertEqual(Set(DeviceStoreID.allCases.map(\.rawValue)).count, DeviceStoreID.allCases.count, "ids must be unique")
    }

    func testDeviceErasureScopeKeepsTheSignInUnlessTheAccountWasDeleted() {
        XCTAssertTrue(DeviceErasureScope.keepSignIn.keepsSignIn)
        XCTAssertFalse(DeviceErasureScope.afterAccountDeleted.keepsSignIn)
    }
}
