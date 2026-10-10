import XCTest
import DoddyCore
@testable import Doddy

/// The approval demo screen's model. It runs only what `ActionLedger` allows.
@MainActor
final class ActionDemoModelTests: XCTestCase {
    func testSampleIsADraftAwaitingApprovalAndLabelledSimulation() async {
        let model = ActionDemoModel()
        await model.draftSample()
        XCTAssertEqual(model.record?.status, .needsApproval)
        XCTAssertEqual(model.record?.isSimulation, true)
        XCTAssertNil(model.record?.approval)
        XCTAssertEqual(model.recipient, "Sam (sample contact)")
        XCTAssertNil(model.problem)
    }

    func testApproveSendsTheShownDraftAndShowsAConfirmedSimulatedReceipt() async {
        let model = ActionDemoModel()
        await model.draftSample()
        await model.approveAndSend()
        XCTAssertEqual(model.record?.status, .confirmed)
        XCTAssertNotNil(model.record?.providerReference)
        XCTAssertTrue(ActionStatusCopy.summary(model.record!).contains("Nothing actually left this iPhone"))
    }

    func testUnsavedEditsBlockApproval() async {
        let model = ActionDemoModel()
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
        let model = ActionDemoModel()
        await model.draftSample()
        model.text = "   "
        await model.saveEdits()
        XCTAssertEqual(model.record?.status, .needsApproval)
        XCTAssertEqual(model.problem, "The message can't be empty. Nothing was sent.")
    }

    func testNoAnswerShowsCouldntConfirmThenCheckStatusResolvesIt() async {
        let model = ActionDemoModel()
        await model.draftSample()
        model.outcome = .noAnswerThenDelivered
        await model.approveAndSend()
        XCTAssertEqual(model.record?.status, .unknown)
        XCTAssertEqual(ActionStatusCopy.label(model.record!.status), "Couldn't confirm")
        await model.checkStatus()
        XCTAssertEqual(model.record?.status, .confirmed)
    }

    func testCancelAndStartOver() async {
        let model = ActionDemoModel()
        await model.draftSample()
        await model.cancel()
        XCTAssertEqual(model.record?.status, .cancelled)
        model.startOver()
        XCTAssertNil(model.record)
        XCTAssertNil(model.problem)
    }
}
