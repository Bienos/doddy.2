import XCTest
@testable import DoddyCore

/// A plan card's tap is worth something only while the card is fresh and only for the payload it showed
/// (DOD-07, ASK-01: one tap, one run, exactly that request). A tap on a card that ran out runs nothing: the card
/// is shown again with what is true now, and only a new tap on that card runs it. Every time below is passed in,
/// so the window's edges are tested exactly.
final class PlanApprovalTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let window = PlanApprovalGate.window
    private let card = "call_plan_1"

    private func after(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func prepared(_ line: String, id: UInt8) -> PlanCardPayload.Prepared {
        PlanCardPayload.Prepared(
            preview: ToolPreview(title: "Draft to Anna", lines: [line], confirmLabel: "Draft"),
            approvalID: UUID(uuid: (id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    /// Step 1 is a timer on this iPhone, step 2 an email draft the server prepared.
    private func payload(_ line: String = "Subject: Lunch", id: UInt8 = 1) -> PlanCardPayload {
        PlanCardPayload(tools: [1: "set_timer", 2: "draft_email"], prepared: [2: prepared(line, id: id)])
    }

    private func shown(_ payload: PlanCardPayload? = nil, preparedAt: Date? = nil, at shownAt: Date? = nil) -> PlanApprovalGate {
        var gate = PlanApprovalGate()
        gate.show(card, payload: payload ?? self.payload(), preparedAt: preparedAt ?? t0, at: shownAt ?? t0)
        return gate
    }

    // MARK: A fresh card

    func testAFreshTapRunsTheCardOnce() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(10)), .run)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(11)), .ignore, "one tap, one run")
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(300)), .ignore, "not even much later")
    }

    func testTwoTapsInTheSameMomentRunItOnce() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(5)), .run)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(5)), .ignore)
    }

    // MARK: A card that ran out

    func testATapAfterTheWindowRunsNothingAndAsksForTheCardToBeShownAgain() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(window + 1)), .refresh)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(window + 2)), .ignore,
                       "while the card is being checked again a second tap does nothing: no second refresh and no run")
    }

    func testTheShownAgainCardRunsOnANewTapOnly() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(120)), .refresh)
        // The app checked the steps again and put the card back, with a new server approval, 5 s later.
        let again = payload(id: 2)
        gate.show(card, payload: again, preparedAt: after(125), at: after(125))
        XCTAssertTrue(gate.wasShownAgain(card))
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: again, at: after(127)), .run, "the new tap on the new card")
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: again, at: after(128)), .ignore, "and once")
    }

    func testAPressThatLandsAsTheCardIsShownAgainIsNotTheNewTap() {
        var gate = shown()
        _ = gate.answer(.tapped, for: card, payload: payload(), at: after(120))
        let again = payload(id: 2)
        gate.show(card, payload: again, preparedAt: after(125), at: after(125))
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: again, at: after(125.4)), .ignore,
                       "a double tap straddling the refresh is the same press, not a look at the new card")
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: again, at: after(126.5)), .run, "a real second tap still works")
    }

    func testTheOldApprovalCannotRunTheShownAgainCard() {
        let old = payload("Subject: Lunch", id: 1)
        // The server prepared something else this time (another thread, another page).
        let changed = payload("Subject: Dinner", id: 2)
        var gate = shown(old)
        _ = gate.answer(.tapped, for: card, payload: old, at: after(120))
        gate.show(card, payload: changed, preparedAt: after(125), at: after(125))
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: old, at: after(130)), .refresh, "the approval of the old payload voids; it runs nothing")

        var other = shown(old)
        _ = other.answer(.tapped, for: card, payload: old, at: after(120))
        other.show(card, payload: changed, preparedAt: after(125), at: after(125))
        XCTAssertEqual(other.answer(.tapped, for: card, payload: changed, at: after(130)), .run, "only a tap on the card as it is now runs")
    }

    func testAPayloadThatIsNotTheOneShownIsNeverRunAndIsCheckedAgain() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload("Subject: Dinner", id: 1), at: after(5)), .refresh)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload("Subject: Lunch", id: 1), at: after(6)), .ignore,
                       "the card waits to be shown again; the first card's own payload no longer runs it")
    }

    func testANewApprovalIdForTheSameTextIsAChangedPayloadToo() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload("Subject: Lunch", id: 7), at: after(5)), .refresh,
                       "the id the tap would spend is not the one the card was shown with")
    }

    // MARK: A spoken yes

    func testAFreshCardTakesASpokenYesOnceAsTheOwnersTableSays() {
        // Plans are on the spoken-yes tier (decision 2026-11-14-spoken-yes-and-fewer-cards), and stay there after outside
        // text: Doddy asks once and the person's own yes is enough (owner, 15 Nov 2026, option 2).
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.proposePlan), .spokenYes)
        XCTAssertEqual(ConfirmationTiers.tier(for: VoiceToolName.proposePlan, outsideContentSeen: true), .spokenYes)
        var gate = shown()
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: payload(), at: after(5)), .run)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(6)), .ignore, "the yes used the card up")
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: payload(), at: after(7)), .ignore)
    }

    func testASpokenYesAfterTheWindowRunsNothingAndChangesNothing() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: payload(), at: after(window + 1)), .ignore)
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: payload(), at: after(window + 5)), .ignore)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(window + 6)), .refresh,
                       "the card still waits: a tap on it shows it again")
    }

    func testASpokenYesNeverRunsTheShownAgainCard() {
        var gate = shown()
        _ = gate.answer(.tapped, for: card, payload: payload(), at: after(120))
        let again = payload(id: 2)
        gate.show(card, payload: again, preparedAt: after(125), at: after(125))
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: again, at: after(127)), .ignore, "only a new tap runs it")
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: again, at: after(128)), .run)
    }

    func testASpokenYesForAnotherPayloadRunsNothing() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: payload("Subject: Dinner", id: 1), at: after(5)), .ignore)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(6)), .run, "the card is untouched")
    }

    func testTheCardSaysWhetherAYesMayAnswerIt() {
        var gate = shown()
        XCTAssertTrue(gate.acceptsSpokenYes(for: card, at: after(5)))
        XCTAssertTrue(gate.acceptsSpokenYes(for: card, at: after(window)))
        XCTAssertFalse(gate.acceptsSpokenYes(for: card, at: after(window + 0.5)), "ran out")
        XCTAssertFalse(gate.acceptsSpokenYes(for: "another", at: after(5)), "no such card")
        _ = gate.answer(.tapped, for: card, payload: payload(), at: after(120))
        gate.show(card, payload: payload(id: 2), preparedAt: after(125), at: after(125))
        XCTAssertFalse(gate.acceptsSpokenYes(for: card, at: after(126)), "shown again: tap only")
    }

    // MARK: The window's edges

    func testTheWindowIsNinetySecondsAndItsEdgeCountsAsFresh() {
        XCTAssertEqual(PlanApprovalGate.window, 90)
        var onTheEdge = shown()
        XCTAssertEqual(onTheEdge.answer(.tapped, for: card, payload: payload(), at: after(window)), .run)
        var justPast = shown()
        XCTAssertEqual(justPast.answer(.tapped, for: card, payload: payload(), at: after(window + 0.001)), .refresh)
        var atTheStart = shown()
        XCTAssertEqual(atTheStart.answer(.tapped, for: card, payload: payload(), at: after(0)), .run)
    }

    func testTheWindowCountsFromWhenTheServerApprovalWasPrepared() {
        // The steps were prepared 20 s before the card was put on screen (a slow server), so 70 s remain.
        var onTheEdge = shown(preparedAt: after(-20), at: t0)
        XCTAssertEqual(onTheEdge.answer(.tapped, for: card, payload: payload(), at: after(window - 20)), .run)
        var justPast = shown(preparedAt: after(-20), at: t0)
        XCTAssertEqual(justPast.answer(.tapped, for: card, payload: payload(), at: after(window - 20 + 0.001)), .refresh)
    }

    func testAClockSetBackIsNotFresh() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(-1)), .refresh, "a tap that seems to come before the card was prepared")
    }

    func testTheSettleTimeOfAShownAgainCardIsOneSecondAndItsEdgeCounts() {
        XCTAssertEqual(PlanApprovalGate.settle, 1)
        func again() -> PlanApprovalGate {
            var gate = shown()
            _ = gate.answer(.tapped, for: card, payload: payload(), at: after(120))
            gate.show(card, payload: payload(id: 2), preparedAt: after(125), at: after(125))
            return gate
        }
        var early = again()
        XCTAssertEqual(early.answer(.tapped, for: card, payload: payload(id: 2), at: after(125.999)), .ignore)
        var onTheEdge = again()
        XCTAssertEqual(onTheEdge.answer(.tapped, for: card, payload: payload(id: 2), at: after(126)), .run)
    }

    func testAFirstCardNeedsNoSettleTime() {
        var gate = shown()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(0)), .run, "the person taps a card that is already up")
    }

    func testAShownAgainCardRunsOutToo() {
        func again() -> (PlanApprovalGate, PlanCardPayload) {
            var gate = shown()
            _ = gate.answer(.tapped, for: card, payload: payload(), at: after(120))
            let next = payload(id: 2)
            gate.show(card, payload: next, preparedAt: after(125), at: after(125))
            return (gate, next)
        }
        var (onTheEdge, next) = again()
        XCTAssertEqual(onTheEdge.answer(.tapped, for: card, payload: next, at: after(125 + window)), .run)
        var (justPast, same) = again()
        XCTAssertEqual(justPast.answer(.tapped, for: card, payload: same, at: after(125 + window + 0.001)), .refresh, "the new window is 90 s too")
    }

    func testTheWindowIsInsideTheServersApprovalAndAFewStepsStillFit() {
        XCTAssertEqual(PlanApprovalGate.approvalLife, 120, "backend AskGate: a single-use approval works for two minutes")
        XCTAssertGreaterThanOrEqual(PlanApprovalGate.approvalLife - PlanApprovalGate.window, 30, "time for the steps to run one after another")
    }

    // MARK: Cards that are gone, and several cards

    func testNoCardNoRun() {
        var gate = PlanApprovalGate()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: t0), .ignore)
        gate.show(card, payload: payload(), preparedAt: t0, at: t0)
        gate.forget(card)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(1)), .ignore, "a declined or replaced card")
        gate.show(card, payload: payload(), preparedAt: t0, at: t0)
        gate.clear()
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(1)), .ignore, "the end of the conversation")
    }

    func testAForgottenCardShownAgainStartsAsAFirstCard() {
        var gate = shown()
        gate.forget(card)
        XCTAssertFalse(gate.wasShownAgain(card))
        gate.show(card, payload: payload(), preparedAt: after(50), at: after(50))
        XCTAssertFalse(gate.wasShownAgain(card))
    }

    func testOneCardsApprovalIsNotAnother() {
        var gate = shown()
        gate.show("call_plan_2", payload: payload(id: 5), preparedAt: t0, at: t0)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload(), at: after(5)), .run)
        XCTAssertEqual(gate.answer(.tapped, for: "call_plan_2", payload: payload(id: 5), at: after(5)), .run)
        XCTAssertEqual(gate.answer(.tapped, for: "call_plan_2", payload: payload(id: 1), at: after(6)), .ignore)
    }

    // MARK: What a shown again card keeps ticked

    func testAStepWhoseCardTextChangedIsUntickedAndTheOthersKeepTheirTicks() {
        let old = payload("Subject: Lunch", id: 1)
        let new = payload("Subject: Dinner", id: 2)
        XCTAssertEqual(new.changedSteps(since: old), [2])
        XCTAssertEqual(PlanApprovalGate.tickedAfterRefresh([1, 2], old: old, new: new, blocked: []), [1])
    }

    func testANewApprovalIdAloneIsNotAChange() {
        let old = payload("Subject: Lunch", id: 1)
        let new = payload("Subject: Lunch", id: 2)
        XCTAssertEqual(new.changedSteps(since: old), [])
        XCTAssertEqual(PlanApprovalGate.tickedAfterRefresh([1, 2], old: old, new: new, blocked: []), [1, 2])
    }

    func testAStepThatCannotRunAnymoreIsUntickedAndOneTheUserNeverTickedStaysUnticked() {
        let same = payload()
        XCTAssertEqual(PlanApprovalGate.tickedAfterRefresh([1, 2], old: same, new: same, blocked: [1]), [2])
        XCTAssertEqual(PlanApprovalGate.tickedAfterRefresh([2], old: same, new: same, blocked: []), [2], "step 1 was unticked by the person and stays so")
    }

    func testAStepThatAppearedOrWentIsAChange() {
        let old = payload()
        let fewer = PlanCardPayload(tools: [1: "set_timer"], prepared: [:])
        XCTAssertEqual(fewer.changedSteps(since: old), [2])
        XCTAssertEqual(old.changedSteps(since: fewer), [2])
        let otherTool = PlanCardPayload(tools: [1: "save_memory", 2: "draft_email"], prepared: old.prepared)
        XCTAssertEqual(otherTool.changedSteps(since: old), [1])
    }

    func testAPayloadIsBuiltFromThePlansSteps() {
        let data = try! JSONSerialization.data(withJSONObject: ["steps": [["tool": "set_timer", "minutes": 10, "label": "pasta"], ["tool": "save_memory", "text": "Pasta takes 10 minutes"]]])
        guard case .plan(let steps) = PlanProposal.parse(parametersJSON: data) else { return XCTFail("not a plan") }
        let payload = PlanCardPayload(steps: steps, prepared: [:])
        XCTAssertEqual(payload.tools, [1: "set_timer", 2: "save_memory"])
    }

    // MARK: A step with no approval

    func testAStepWithoutItsApprovalIsNotRunAndTheAgentHearsNothingWasDone() {
        // The app never makes an approval after the card was shown (a preview the person didn't see); the step says so.
        let text = PlanReply.stepNotApproved
        XCTAssertTrue(text.hasPrefix("failed:"), text)
        XCTAssertTrue(text.contains("Nothing was done."), text)
        XCTAssertFalse(PlanReply.donePrefixes.contains { text.hasPrefix($0) }, "never read as done")
    }
}
