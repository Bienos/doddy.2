import Foundation

/// The trusted owner of action state. Every transition is checked here, so a model, a view or
/// a tool result cannot approve, execute, retry or mark anything confirmed on its own.
///
/// Lifecycle (docs/trust/04_ENFORCEMENT_ARCHITECTURE.md):
/// proposed → drafted → needsApproval → executing → confirmed | failed | unknown;
/// unknown → (reconcile) → confirmed | failed; cancel from proposed, drafted or needsApproval.
///
/// In memory only: records are lost when the app quits. Persisting pending state before an
/// external call is required before any real adapter is added (see ACTION_APPROVAL_SIMULATION.md).
public actor ActionLedger {
    public static let defaultApprovalLifetime: TimeInterval = 5 * 60

    private let adapters: [any ActionAdapter]
    private let now: @Sendable () -> Date
    private let approvalLifetime: TimeInterval
    private var records: [UUID: ActionRecord] = [:]
    private var reconciling: Set<UUID> = []

    public init(
        adapters: [any ActionAdapter],
        approvalLifetime: TimeInterval = ActionLedger.defaultApprovalLifetime,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.adapters = adapters
        self.approvalLifetime = approvalLifetime
        self.now = now
    }

    public func record(_ id: UUID) throws -> ActionRecord {
        guard let record = records[id] else { throw ActionPolicyError.notFound(id) }
        return record
    }

    /// Records a suggestion and drafts it. Unsupported types are refused before any record exists.
    public func propose(_ proposal: ActionProposal) throws -> ActionRecord {
        let adapter = try adapter(for: proposal.payload.type)
        let at = now()
        let record = ActionRecord(
            id: UUID(), payload: proposal.payload, status: .drafted, approval: nil,
            idempotencyKey: nil, providerReference: nil, failureReason: nil,
            connectorID: adapter.connectorID, isSimulation: adapter.isSimulation,
            history: [ActionEvent(status: .proposed, at: at, note: nil), ActionEvent(status: .drafted, at: at, note: nil)])
        records[record.id] = record
        return record
    }

    /// The draft is on screen for review.
    public func requestApproval(_ id: UUID) throws -> ActionRecord {
        var record = try self.record(id)
        try require(record, in: [.drafted], to: .needsApproval)
        transition(&record, to: .needsApproval)
        return store(record)
    }

    /// Any edit voids an existing approval and sends the action back to draft.
    public func edit(_ id: UUID, payload: ActionPayload) throws -> ActionRecord {
        var record = try self.record(id)
        try require(record, in: [.drafted, .needsApproval], to: .drafted)
        guard payload.type == record.payload.type else { throw ActionPolicyError.unsupportedAction(payload.type) }
        guard payload != record.payload else { return record }
        record.payload = payload
        record.approval = nil
        transition(&record, to: .drafted, note: "Edited; approval cleared")
        return store(record)
    }

    /// Call only from an explicit user control. `reviewedPayload` is what the screen showed;
    /// it must equal the current payload, so a stale screen can't approve changed content.
    public func approve(_ id: UUID, reviewedPayload: ActionPayload) throws -> ActionRecord {
        var record = try self.record(id)
        guard record.status == .needsApproval else {
            throw ActionPolicyError.invalidTransition(from: record.status, to: .needsApproval)
        }
        guard reviewedPayload == record.payload else { throw ActionPolicyError.payloadChanged }
        let at = now()
        record.approval = ActionApproval(approvedPayload: record.payload, approvedAt: at, expiresAt: at + approvalLifetime)
        record.history.append(ActionEvent(status: .needsApproval, at: at, note: "Approved by you"))
        return store(record)
    }

    public func cancel(_ id: UUID) throws -> ActionRecord {
        var record = try self.record(id)
        try require(record, in: [.proposed, .drafted, .needsApproval], to: .cancelled)
        record.approval = nil
        transition(&record, to: .cancelled)
        return store(record)
    }

    /// Runs an approved action once. The approval is used up whatever the outcome.
    public func execute(_ id: UUID) async throws -> ActionRecord {
        var record = try self.record(id)
        switch record.status {
        case .needsApproval: break
        case .executing: throw ActionPolicyError.alreadyExecuting
        case .unknown: throw ActionPolicyError.reconcileFirst
        case .confirmed, .failed, .cancelled: throw ActionPolicyError.alreadyFinished(record.status)
        case .proposed, .drafted: throw ActionPolicyError.notApproved
        }
        guard let approval = record.approval else { throw ActionPolicyError.notApproved }
        guard approval.approvedPayload == record.payload else { throw ActionPolicyError.payloadChanged }
        guard now() <= approval.expiresAt else {
            record.approval = nil
            record.history.append(ActionEvent(status: .needsApproval, at: now(), note: "Approval expired"))
            store(record)
            throw ActionPolicyError.approvalExpired
        }
        let adapter = try adapter(for: record.type)

        // Committed before the await: a second call sees `executing` and is refused.
        let key = UUID()
        record.idempotencyKey = key
        record.approval = nil
        transition(&record, to: .executing)
        store(record)

        let result: ActionProviderResult
        do {
            result = try await adapter.execute(ActionExecutionRequest(actionID: id, payload: record.payload, idempotencyKey: key))
        } catch {
            result = .unknown(reason: "No usable answer from \(adapter.connectorID)")
        }
        record = try self.record(id)
        apply(result, to: &record)
        return store(record)
    }

    /// Asks the provider what happened to an `unknown` action. Never re-sends it.
    public func reconcile(_ id: UUID) async throws -> ActionRecord {
        var record = try self.record(id)
        guard record.status == .unknown, let key = record.idempotencyKey else {
            throw ActionPolicyError.invalidTransition(from: record.status, to: .unknown)
        }
        guard !reconciling.contains(id) else { return record }
        reconciling.insert(id)
        defer { reconciling.remove(id) }
        let adapter = try adapter(for: record.type)

        let result: ActionProviderResult
        do {
            result = try await adapter.status(idempotencyKey: key)
        } catch {
            result = .unknown(reason: "Status check failed")
        }
        record = try self.record(id)
        apply(result, to: &record)
        return store(record)
    }

    // MARK: - Private

    private func adapter(for type: ActionType) throws -> any ActionAdapter {
        guard let adapter = adapters.first(where: { $0.supports(type) }) else {
            throw ActionPolicyError.unsupportedAction(type)
        }
        return adapter
    }

    private func require(_ record: ActionRecord, in allowed: Set<ActionStatus>, to target: ActionStatus) throws {
        guard allowed.contains(record.status) else {
            throw ActionPolicyError.invalidTransition(from: record.status, to: target)
        }
    }

    /// `confirmed` needs a non-empty provider reference; anything less stays `unknown`.
    private func apply(_ result: ActionProviderResult, to record: inout ActionRecord) {
        switch result {
        case .confirmed(let reference) where !reference.allSatisfy(\.isWhitespace):
            record.providerReference = reference
            record.failureReason = nil
            transition(&record, to: .confirmed)
        case .confirmed:
            transition(&record, to: .unknown, note: "Provider reported success without a reference")
        case .failed(let reason):
            record.failureReason = reason
            transition(&record, to: .failed, note: reason)
        case .unknown(let reason):
            if record.status == .unknown {
                record.history.append(ActionEvent(status: .unknown, at: now(), note: reason))
            } else {
                transition(&record, to: .unknown, note: reason)
            }
        }
    }

    private func transition(_ record: inout ActionRecord, to status: ActionStatus, note: String? = nil) {
        record.status = status
        record.history.append(ActionEvent(status: status, at: now(), note: note))
    }

    @discardableResult
    private func store(_ record: ActionRecord) -> ActionRecord {
        records[record.id] = record
        return record
    }
}

/// Parses a model's tool call into a proposal. Unknown tools and extra fields (for example
/// `"approved": true`) are ignored or refused; nothing here can approve or execute.
public enum ActionProposalParser {
    public enum Rejection: Error, Equatable, Sendable {
        case unsupportedTool(String)
        case invalid(String)
    }

    public static func parse(toolName: String, parametersJSON: Data) throws -> ActionProposal {
        guard let type = ActionType(rawValue: toolName) else { throw Rejection.unsupportedTool(toolName) }
        let parameters = (try? JSONSerialization.jsonObject(with: parametersJSON)) as? [String: Any] ?? [:]
        switch type {
        case .sendMessage:
            do {
                return ActionProposal(payload: try .message(
                    to: parameters["recipient"] as? String ?? "",
                    text: parameters["text"] as? String ?? ""))
            } catch let error as ActionPayloadError {
                throw Rejection.invalid(String(describing: error))
            }
        case .createReminder:
            throw Rejection.unsupportedTool(toolName)
        }
    }
}
