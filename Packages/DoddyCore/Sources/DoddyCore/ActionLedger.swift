import Foundation

/// The trusted owner of action state. Every transition is checked here, so a model, a view or
/// a tool result cannot approve, execute, retry or mark anything confirmed on its own.
///
/// Lifecycle (docs/trust/04_ENFORCEMENT_ARCHITECTURE.md):
/// proposed → drafted → needsApproval → executing → confirmed | failed | unknown;
/// unknown → (reconcile) → confirmed | failed; cancel from proposed, drafted or needsApproval.
///
/// Persistence: every change is written to the `ActionStore` before it is returned or
/// before the provider is called, so `executing` is on disk while a send is in flight.
/// On first use after launch the ledger loads the store and recovers:
/// - `executing` (the app stopped mid-send) becomes `unknown`, to be reconciled, never re-sent;
/// - approvals are not stored, so nothing approved before a restart can run without a new tap;
/// - finished records (confirmed, failed, cancelled) older than `retention` are deleted.
public actor ActionLedger {
    public static let defaultApprovalLifetime: TimeInterval = 5 * 60
    public static let defaultRetention: TimeInterval = 30 * 24 * 60 * 60

    private enum LoadState { case notLoaded, loaded, failed }

    private let adapters: [any ActionAdapter]
    private let store: any ActionStore
    private let now: @Sendable () -> Date
    private let approvalLifetime: TimeInterval
    private let retention: TimeInterval?
    private var records: [UUID: ActionRecord] = [:]
    private var reconciling: Set<UUID> = []
    private var loadState = LoadState.notLoaded

    public init(
        adapters: [any ActionAdapter],
        store: any ActionStore = InMemoryActionStore(),
        approvalLifetime: TimeInterval = ActionLedger.defaultApprovalLifetime,
        retention: TimeInterval? = ActionLedger.defaultRetention,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.adapters = adapters
        self.store = store
        self.approvalLifetime = approvalLifetime
        self.retention = retention
        self.now = now
    }

    public func record(_ id: UUID) throws -> ActionRecord {
        try ensureLoaded()
        guard let record = records[id] else { throw ActionPolicyError.notFound(id) }
        return record
    }

    /// Newest first.
    public func history(limit: Int? = nil) throws -> [ActionRecord] {
        try ensureLoaded()
        let sorted = records.values.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
        return limit.map { Array(sorted.prefix(max(0, $0))) } ?? sorted
    }

    /// Records a suggestion and drafts it. Unsupported types are refused before any record exists.
    public func propose(_ proposal: ActionProposal) throws -> ActionRecord {
        try ensureLoaded()
        let adapter = try adapter(for: proposal.payload.type)
        let at = now()
        let record = ActionRecord(
            id: UUID(), payload: proposal.payload, status: .drafted, approval: nil,
            idempotencyKey: nil, providerReference: nil, failureReason: nil,
            connectorID: adapter.connectorID, isSimulation: adapter.isSimulation,
            history: [ActionEvent(status: .proposed, at: at, note: nil), ActionEvent(status: .drafted, at: at, note: nil)])
        return try commit(record)
    }

    /// The draft is on screen for review.
    public func requestApproval(_ id: UUID) throws -> ActionRecord {
        var record = try self.record(id)
        try require(record, in: [.drafted], to: .needsApproval)
        transition(&record, to: .needsApproval)
        return try commit(record)
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
        return try commit(record)
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
        return try commit(record)
    }

    public func cancel(_ id: UUID) throws -> ActionRecord {
        var record = try self.record(id)
        try require(record, in: [.proposed, .drafted, .needsApproval], to: .cancelled)
        record.approval = nil
        transition(&record, to: .cancelled)
        return try commit(record)
    }

    /// Runs an approved action once. The approval is used up whatever the outcome.
    /// The adapter's readiness (for example OS permission) is checked first; if it isn't ready,
    /// nothing changes and the approval still stands.
    public func execute(_ id: UUID) async throws -> ActionRecord {
        var record = try executable(try self.record(id))
        let adapter = try adapter(for: record.type)

        if case .notReady(let reason) = await adapter.readiness(for: record.type) {
            throw ActionPolicyError.notReady(reason)
        }
        // The await above let other calls run (a second execute, a cancel, an edit): check
        // everything again on the current record. Only one caller can get past `commit` below.
        record = try executable(try self.record(id))

        // Stored before the await: a second call sees `executing` and is refused, and if the
        // app stops during the call the next launch knows a send may have happened.
        let key = UUID()
        record.idempotencyKey = key
        record.approval = nil
        transition(&record, to: .executing)
        try commit(record)

        let result: ActionProviderResult
        do {
            result = try await adapter.execute(ActionExecutionRequest(actionID: id, payload: record.payload, idempotencyKey: key))
        } catch {
            result = .unknown(reason: "No usable answer from \(adapter.connectorID)")
        }
        record = try self.record(id)
        apply(result, to: &record)
        return try commitResult(record)
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
        return try commitResult(record)
    }

    /// Checks every `unknown` action once (for example after launch). A check that fails
    /// leaves the action `unknown`, which is still the truthful status, so errors are not rethrown.
    public func reconcileAllUnknown() async -> [ActionRecord] {
        guard let unknown = try? history().filter({ $0.status == .unknown }) else { return [] }
        var results: [ActionRecord] = []
        for record in unknown {
            _ = try? await reconcile(record.id)
            if let latest = records[record.id] { results.append(latest) }
        }
        return results
    }

    /// Deletes every stored action, including unresolved ones. Refused while a send is in flight,
    /// because that record holds the only key for checking what happened.
    public func deleteHistory() throws {
        try ensureLoaded()
        guard !records.values.contains(where: { $0.status == .executing }) else {
            throw ActionPolicyError.actionInProgress
        }
        do {
            try store.delete(ids: Array(records.keys))
        } catch {
            throw ActionPolicyError.storageFailed
        }
        records = [:]
    }

    // MARK: - Private

    private func ensureLoaded() throws {
        switch loadState {
        case .loaded: return
        case .failed: throw ActionPolicyError.storageUnavailable
        case .notLoaded: break
        }
        do {
            var loaded = Dictionary(uniqueKeysWithValues: try store.loadAll().map { ($0.id, $0.storable) })
            for var record in loaded.values where record.status == .executing {
                transition(&record, to: .unknown, note: "The app stopped before the provider answered")
                try store.save(record)
                loaded[record.id] = record
            }
            if let retention {
                let cutoff = now() - retention
                let expired = loaded.values.filter { $0.status.isTerminal && $0.updatedAt < cutoff }.map(\.id)
                if !expired.isEmpty {
                    try store.delete(ids: expired)
                    for id in expired { loaded[id] = nil }
                }
            }
            records = loaded
            loadState = .loaded
        } catch {
            loadState = .failed
            throw ActionPolicyError.storageUnavailable
        }
    }

    /// Stores the record, then updates memory. On failure nothing changes.
    @discardableResult
    private func commit(_ record: ActionRecord) throws -> ActionRecord {
        do {
            try store.save(record)
        } catch {
            throw ActionPolicyError.storageFailed
        }
        records[record.id] = record
        return record
    }

    /// After a provider call the result is real whether or not it can be stored: memory keeps it
    /// and the caller is told. The stored copy still says `executing` / `unknown`, which becomes
    /// `unknown` after a restart and is reconciled.
    private func commitResult(_ record: ActionRecord) throws -> ActionRecord {
        records[record.id] = record
        do {
            try store.save(record)
        } catch {
            throw ActionPolicyError.resultNotSaved(record.status)
        }
        return record
    }

    /// Status and approval checks shared by both passes of `execute`.
    private func executable(_ record: ActionRecord) throws -> ActionRecord {
        var record = record
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
            try commit(record)
            throw ActionPolicyError.approvalExpired
        }
        return record
    }

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
