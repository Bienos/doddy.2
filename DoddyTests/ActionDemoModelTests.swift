import XCTest
import DoddyCore
@testable import Doddy

/// The approval demo screen's model. It runs only what `ActionLedger` allows.
@MainActor
final class ActionDemoModelTests: XCTestCase {
    private func makeModel(store: any ActionStore = InMemoryActionStore(), adapter: SimulatedActionAdapter = SimulatedActionAdapter()) -> ActionDemoModel {
        ActionDemoModel(ledger: ActionLedger(adapters: [adapter], store: store), adapter: adapter)
    }

    func testUnfinishedDraftIsResumedAfterRestart() async {
        let store = InMemoryActionStore()
        let first = makeModel(store: store)
        await first.draftSample()
        let id = first.record?.id

        let relaunched = makeModel(store: store)
        await relaunched.load()
        XCTAssertEqual(relaunched.record?.id, id)
        XCTAssertEqual(relaunched.record?.status, .needsApproval)
        XCTAssertNil(relaunched.record?.approval)
        XCTAssertEqual(relaunched.recipient, "Sam (sample contact)")
        XCTAssertTrue(relaunched.hasLoaded)
    }

    func testUnknownActionIsCheckedOnOpenWithoutResending() async {
        let store = InMemoryActionStore()
        let adapter = SimulatedActionAdapter()
        let first = makeModel(store: store, adapter: adapter)
        await first.draftSample()
        first.outcome = .noAnswerThenDelivered
        await first.approveAndSend()
        XCTAssertEqual(first.record?.status, .unknown)

        let relaunched = makeModel(store: store, adapter: adapter)
        await relaunched.load()
        XCTAssertEqual(relaunched.recent.first?.status, .confirmed, "checked on open, now finished")
        XCTAssertNil(relaunched.record)
        let sends = await adapter.executeCount
        XCTAssertEqual(sends, 1)
    }

    func testFinishedActionsAppearInRecentAndCanBeDeleted() async {
        let store = InMemoryActionStore()
        let model = makeModel(store: store)
        await model.draftSample()
        await model.approveAndSend()
        await model.startOver()
        XCTAssertEqual(model.recent.map(\.status), [.confirmed])

        await model.deleteHistory()
        XCTAssertEqual(model.recent, [])
        XCTAssertNil(model.record)
        XCTAssertEqual(try store.loadAll(), [])
    }

    func testSampleIsADraftAwaitingApprovalAndLabelledSimulation() async {
        let model = makeModel()
        await model.draftSample()
        XCTAssertEqual(model.record?.status, .needsApproval)
        XCTAssertEqual(model.record?.isSimulation, true)
        XCTAssertNil(model.record?.approval)
        XCTAssertEqual(model.recipient, "Sam (sample contact)")
        XCTAssertNil(model.problem)
    }

    func testApproveSendsTheShownDraftAndShowsAConfirmedSimulatedReceipt() async {
        let model = makeModel()
        await model.draftSample()
        await model.approveAndSend()
        XCTAssertEqual(model.record?.status, .confirmed)
        XCTAssertNotNil(model.record?.providerReference)
        XCTAssertTrue(ActionStatusCopy.summary(model.record!).contains("Nothing actually left this iPhone"))
    }

    func testUnsavedEditsBlockApproval() async {
        let model = makeModel()
        await model.draftSample()
        model.recipient = "Someone else"
        XCTAssertTrue(model.hasUnsavedEdits)
        await model.approveAndSend()
        XCTAssertEqual(model.record?.status, .needsApproval, "nothing runs while the screen differs from the draft")

        await model.saveEdits()
        XCTAssertFalse(model.hasUnsavedEdits)
        XCTAssertEqual(model.record?.payload.target, "Someone else")
        XCTAssertEqual(model.record?.history.last?.status, .needsApproval)
        await model.approveAndSend()
        XCTAssertEqual(model.record?.status, .confirmed)
    }

    func testBlankEditIsRefusedWithoutSending() async {
        let model = makeModel()
        await model.draftSample()
        model.text = "   "
        await model.saveEdits()
        XCTAssertEqual(model.record?.status, .needsApproval)
        XCTAssertEqual(model.problem, "The message can't be empty. Nothing was sent.")
    }

    func testNoAnswerShowsCouldntConfirmThenCheckStatusResolvesIt() async {
        let model = makeModel()
        await model.draftSample()
        model.outcome = .noAnswerThenDelivered
        await model.approveAndSend()
        XCTAssertEqual(model.record?.status, .unknown)
        XCTAssertEqual(ActionStatusCopy.label(model.record!.status), "Couldn't confirm")
        await model.checkStatus()
        XCTAssertEqual(model.record?.status, .confirmed)
    }

    func testCancelAndStartOver() async {
        let model = makeModel()
        await model.draftSample()
        await model.cancel()
        XCTAssertEqual(model.record?.status, .cancelled)
        await model.startOver()
        XCTAssertNil(model.record)
        XCTAssertNil(model.problem)
    }
}
