import DoddyCore
import Foundation
import Observation

/// SIMULATION. Drives the approval and receipt flow against `SimulatedActionAdapter`.
/// All state and every rule live in `ActionLedger`; this model only forwards taps and
/// shows what the ledger returns.
@MainActor
@Observable
final class ActionDemoModel {
    private let adapter = SimulatedActionAdapter()
    private let ledger: ActionLedger

    private(set) var record: ActionRecord?
    private(set) var isWorking = false
    private(set) var problem: String?
    /// Edit buffers for the draft. Changes reach the ledger only through `saveEdits()`.
    var recipient = ""
    var text = ""
    var outcome: SimulatedActionAdapter.Outcome = .delivers

    init() {
        ledger = ActionLedger(adapters: [adapter])
    }

    var hasUnsavedEdits: Bool {
        guard let record else { return false }
        return recipient != record.payload.target || text != (record.payload.value(for: "text") ?? "")
    }

    var isAwaitingApproval: Bool { record?.status == .needsApproval }

    /// Goes through the same parser a model's tool call would, so the sample gets no shortcut.
    func draftSample() async {
        let json = Data(#"{"recipient":"Sam (sample contact)","text":"Running 10 minutes late, see you soon."}"#.utf8)
        await run {
            let proposal = try ActionProposalParser.parse(toolName: ActionType.sendMessage.rawValue, parametersJSON: json)
            let drafted = try await self.ledger.propose(proposal)
            return try await self.ledger.requestApproval(drafted.id)
        }
    }

    /// Saving an edit clears any approval; the new draft goes back for review.
    func saveEdits() async {
        guard let id = record?.id else { return }
        await run {
            let payload = try ActionPayload.message(to: self.recipient, text: self.text)
            _ = try await self.ledger.edit(id, payload: payload)
            return try await self.ledger.requestApproval(id)
        }
    }

    /// The tap is the approval of exactly the payload on screen (`record.payload`).
    func approveAndSend() async {
        guard let shown = record, !hasUnsavedEdits else { return }
        await adapter.setOutcome(outcome)
        await run {
            _ = try await self.ledger.approve(shown.id, reviewedPayload: shown.payload)
            return try await self.ledger.execute(shown.id)
        }
    }

    func checkStatus() async {
        guard let id = record?.id else { return }
        await run { try await self.ledger.reconcile(id) }
    }

    func cancel() async {
        guard let id = record?.id else { return }
        await run { try await self.ledger.cancel(id) }
    }

    func startOver() {
        record = nil
        problem = nil
        recipient = ""
        text = ""
    }

    private func run(_ step: @escaping () async throws -> ActionRecord) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await step()
            show(updated)
            problem = nil
        } catch {
            problem = ActionStatusCopy.problem(for: error)
            if let id = record?.id, let latest = try? await ledger.record(id) { show(latest) }
        }
    }

    private func show(_ updated: ActionRecord) {
        record = updated
        recipient = updated.payload.target
        text = updated.payload.value(for: "text") ?? ""
    }
}

extension SimulatedActionAdapter.Outcome {
    var displayName: String {
        switch self {
        case .delivers: "Delivered"
        case .fails: "Rejected"
        case .noAnswerThenDelivered: "No answer (later found delivered)"
        case .noAnswerThenNotDelivered: "No answer (later found not delivered)"
        case .noAnswerStaysUnknown: "No answer (stays unknown)"
        case .okWithoutReference: "Says OK, gives no reference"
        }
    }
}
