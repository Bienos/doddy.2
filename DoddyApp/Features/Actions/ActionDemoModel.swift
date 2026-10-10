import DoddyCore
import Foundation
import Observation

/// SIMULATION. Drives the approval and receipt flow against `SimulatedActionAdapter`.
/// All state and every rule live in `ActionLedger` (stored on this iPhone); this model only
/// forwards taps and shows what the ledger returns.
@MainActor
@Observable
final class ActionDemoModel {
    private let adapter: SimulatedActionAdapter
    private let ledger: ActionLedger

    private(set) var record: ActionRecord?
    /// Earlier actions from the ledger, newest first (excluding `record`).
    private(set) var recent: [ActionRecord] = []
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    private(set) var problem: String?
    /// Edit buffers for the draft. Changes reach the ledger only through `saveEdits()`.
    var recipient = ""
    var text = ""
    var outcome: SimulatedActionAdapter.Outcome = .delivers

    init(ledger: ActionLedger, adapter: SimulatedActionAdapter) {
        self.ledger = ledger
        self.adapter = adapter
    }

    static let recentLimit = 5

    /// On open: checks any action whose outcome is unknown (status only, never a re-send),
    /// then resumes the newest unfinished action, if there is one.
    func load() async {
        _ = await ledger.reconcileAllUnknown()
        do {
            let history = try await ledger.history()
            if let open = history.first(where: { !$0.status.isTerminal }) {
                show(open)
            }
            await refreshRecent(from: history)
            problem = nil
        } catch {
            problem = ActionStatusCopy.problem(for: error)
        }
        hasLoaded = true
    }

    /// Deletes every stored action. The view asks for confirmation first.
    func deleteHistory() async {
        do {
            try await ledger.deleteHistory()
            await startOver()
        } catch {
            problem = ActionStatusCopy.problem(for: error)
        }
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

    func startOver() async {
        record = nil
        problem = nil
        recipient = ""
        text = ""
        await refreshRecent()
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
        await refreshRecent()
    }

    private func refreshRecent(from history: [ActionRecord]? = nil) async {
        let all: [ActionRecord]
        if let history { all = history } else { all = (try? await ledger.history()) ?? recent }
        recent = Array(all.filter { $0.id != record?.id }.prefix(Self.recentLimit))
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
