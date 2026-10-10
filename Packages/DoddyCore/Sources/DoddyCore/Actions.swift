import Foundation

// Action types for the approval and receipt flow (DOD-07, DOD-08, DOD-09; UX-02, UX-03).
// docs/trust/04_ENFORCEMENT_ARCHITECTURE.md is the spec. A model may only produce an
// `ActionProposal`; approval and status live in `ActionLedger`, never in model text.

public enum ActionType: String, Codable, Sendable, CaseIterable {
    case sendMessage = "send_message"
    case createReminder = "create_reminder"

    /// Design policy tiers from the constitution, not regulatory categories.
    public var riskTier: ActionRiskTier {
        switch self {
        case .sendMessage, .createReminder: .externalWrite
        }
    }
}

public enum ActionRiskTier: Int, Codable, Sendable, Comparable {
    case publicLookup = 0
    case privateRead = 1
    case localDraft = 2
    /// Needs approval of the exact payload in the MVP.
    case externalWrite = 3
    /// Irreversible, destructive, expensive or regulated: not supported.
    case irreversible = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Trusted status, owned by `ActionLedger`. Wording for people is in `ActionStatusCopy`.
public enum ActionStatus: String, Codable, Sendable, CaseIterable {
    case proposed
    case drafted
    case needsApproval = "needs_approval"
    case executing
    case confirmed
    case failed
    /// The provider did not give a usable answer. Never shown as success; reconcile before anything else.
    case unknown
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .confirmed, .failed, .cancelled: true
        case .proposed, .drafted, .needsApproval, .executing, .unknown: false
        }
    }
}

public enum ActionPayloadError: Error, Equatable, Sendable {
    case missingField(String)
    case fieldTooLong(String, limit: Int)
}

/// The exact content the user approves. Approval is bound to the whole value: any change to
/// the type, target or any field (even whitespace) is a different payload.
public struct ActionPayload: Equatable, Hashable, Codable, Sendable {
    public struct Field: Equatable, Hashable, Codable, Sendable {
        public let key: String
        public let label: String
        public let value: String
    }

    public let type: ActionType
    /// Who or what the action is for (recipient, list). Shown first on the approval screen.
    public let target: String
    public let fields: [Field]

    public static let maxTargetLength = 200
    public static let maxMessageLength = 2_000

    public static func message(to recipient: String, text: String) throws -> ActionPayload {
        try ActionPayload(
            type: .sendMessage,
            target: validated(recipient, key: "recipient", limit: maxTargetLength),
            fields: [Field(key: "text", label: "Message", value: validated(text, key: "text", limit: maxMessageLength))])
    }

    public func value(for key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    private init(type: ActionType, target: String, fields: [Field]) {
        self.type = type
        self.target = target
        self.fields = fields
    }

    /// Values are kept exactly as given (shown and executed unchanged); blank values are rejected.
    private static func validated(_ value: String, key: String, limit: Int) throws -> String {
        guard !value.allSatisfy(\.isWhitespace) else { throw ActionPayloadError.missingField(key) }
        guard value.unicodeScalars.count <= limit else { throw ActionPayloadError.fieldTooLong(key, limit: limit) }
        return value
    }
}

/// A suggested action. It authorises nothing, whatever its fields say.
public struct ActionProposal: Equatable, Sendable {
    public let payload: ActionPayload
    public init(payload: ActionPayload) { self.payload = payload }
}

/// Evidence that the user approved one exact payload. Only `ActionLedger.approve` creates it.
public struct ActionApproval: Equatable, Sendable {
    public let approvedPayload: ActionPayload
    public let approvedAt: Date
    public let expiresAt: Date

    init(approvedPayload: ActionPayload, approvedAt: Date, expiresAt: Date) {
        self.approvedPayload = approvedPayload
        self.approvedAt = approvedAt
        self.expiresAt = expiresAt
    }
}

public struct ActionEvent: Equatable, Codable, Sendable {
    public let status: ActionStatus
    public let at: Date
    public let note: String?
}

/// The ledger's record of one action; also the receipt the user sees.
public struct ActionRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public internal(set) var payload: ActionPayload
    public internal(set) var status: ActionStatus
    public internal(set) var approval: ActionApproval?
    /// Set when execution starts; sent to the provider so it can deduplicate and reconcile.
    public internal(set) var idempotencyKey: UUID?
    /// Present only when the provider confirmed the action.
    public internal(set) var providerReference: String?
    public internal(set) var failureReason: String?
    public let connectorID: String
    /// True when the adapter is a simulation: nothing left the device.
    public let isSimulation: Bool
    public internal(set) var history: [ActionEvent]

    public var type: ActionType { payload.type }
    public var riskTier: ActionRiskTier { payload.type.riskTier }
    public var createdAt: Date { history.first?.at ?? .distantPast }
    public var updatedAt: Date { history.last?.at ?? .distantPast }

    /// What `ActionStore` keeps: everything except the approval. Approvals are never stored,
    /// so a stored or restored record can never authorise a send.
    public var storable: ActionRecord {
        var copy = self
        copy.approval = nil
        return copy
    }

    /// Rebuilds a stored record. Throws if the row breaks a lifecycle rule (for example
    /// `confirmed` without a provider reference), so a damaged store is reported, not trusted.
    public static func restore(
        id: UUID, payload: ActionPayload, status: ActionStatus, idempotencyKey: UUID?,
        providerReference: String?, failureReason: String?, connectorID: String,
        isSimulation: Bool, history: [ActionEvent]
    ) throws -> ActionRecord {
        let ranProvider: Set<ActionStatus> = [.executing, .confirmed, .failed, .unknown]
        guard !history.isEmpty, history.last?.status == status else { throw ActionStoreError.corruptRecord(id.uuidString) }
        guard !ranProvider.contains(status) || idempotencyKey != nil else { throw ActionStoreError.corruptRecord(id.uuidString) }
        if status == .confirmed {
            guard let providerReference, !providerReference.allSatisfy(\.isWhitespace) else {
                throw ActionStoreError.corruptRecord(id.uuidString)
            }
        } else if providerReference != nil {
            throw ActionStoreError.corruptRecord(id.uuidString)
        }
        return ActionRecord(
            id: id, payload: payload, status: status, approval: nil, idempotencyKey: idempotencyKey,
            providerReference: providerReference, failureReason: failureReason, connectorID: connectorID,
            isSimulation: isSimulation, history: history)
    }
}

public enum ActionStoreError: Error, Equatable, Sendable {
    case corruptRecord(String)
    /// The write reported success but reading it back did not match.
    case verificationFailed
}

/// Durable home of action records (DOD-08). Synchronous on purpose: `ActionLedger` calls it
/// inside the actor, so writes happen in order and nothing interleaves with them. A call that
/// returns has committed and read back the record. Approvals are not stored (`storable`).
public protocol ActionStore: Sendable {
    /// Every stored record, in no particular order.
    func loadAll() throws -> [ActionRecord]
    func save(_ record: ActionRecord) throws
    func delete(ids: [UUID]) throws
}

/// Keeps records in memory only: for tests, previews and UI-test launches.
public final class InMemoryActionStore: ActionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [UUID: ActionRecord] = [:]

    public init() {}

    public func loadAll() throws -> [ActionRecord] {
        lock.withLock { Array(records.values) }
    }

    public func save(_ record: ActionRecord) throws {
        lock.withLock { records[record.id] = record.storable }
    }

    public func delete(ids: [UUID]) throws {
        lock.withLock { for id in ids { records[id] = nil } }
    }
}

public struct ActionExecutionRequest: Equatable, Sendable {
    public let actionID: UUID
    public let payload: ActionPayload
    public let idempotencyKey: UUID
}

/// What a provider reported. `confirmed` must carry the provider's own reference.
public enum ActionProviderResult: Equatable, Sendable {
    case confirmed(providerReference: String)
    case failed(reason: String)
    case unknown(reason: String)
}

/// Executes approved payloads for one connector. Only `ActionLedger` calls it.
public protocol ActionAdapter: Sendable {
    var connectorID: String { get }
    var isSimulation: Bool { get }
    func supports(_ type: ActionType) -> Bool
    /// A thrown error is treated as `unknown`: the request may or may not have reached the provider.
    func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult
    /// Provider-side status for an earlier request, used to reconcile `unknown`.
    func status(idempotencyKey: UUID) async throws -> ActionProviderResult
}

public enum ActionPolicyError: Error, Equatable, Sendable {
    case unsupportedAction(ActionType)
    case notFound(UUID)
    case invalidTransition(from: ActionStatus, to: ActionStatus)
    case notApproved
    /// What the user reviewed is not the current payload.
    case payloadChanged
    case approvalExpired
    case alreadyExecuting
    /// The last attempt's outcome is unknown; reconcile before anything else.
    case reconcileFirst
    case alreadyFinished(ActionStatus)
    /// The store refused the write; nothing changed.
    case storageFailed
    /// The provider answered but the result couldn't be stored. The receipt shows it for now;
    /// after a restart the action reads "Couldn't confirm" and is checked again.
    case resultNotSaved(ActionStatus)
    /// Stored actions couldn't be loaded, so no action can run.
    case storageUnavailable
    /// An action is being sent right now.
    case actionInProgress
}

/// User-facing wording (UX-02). "Confirmed" only ever appears for provider-confirmed records.
public enum ActionStatusCopy {
    public static func label(_ status: ActionStatus) -> String {
        switch status {
        case .proposed: "Suggested"
        case .drafted: "Draft"
        case .needsApproval: "Needs approval"
        case .executing: "In progress"
        case .confirmed: "Confirmed"
        case .failed: "Failed"
        case .unknown: "Couldn't confirm"
        case .cancelled: "Cancelled"
        }
    }

    public static func summary(_ record: ActionRecord) -> String {
        let simulated = record.isSimulation
        switch record.status {
        case .proposed, .drafted:
            return "Drafted. Not sent."
        case .needsApproval:
            return record.approval == nil ? "Waiting for your approval. Not sent." : "Approved. Not sent yet."
        case .executing:
            return simulated ? "Simulating the send…" : "Sending…"
        case .confirmed:
            return simulated
                ? "Simulated send confirmed by the test adapter. Nothing actually left this iPhone."
                : record.type == .sendMessage ? "Sent to \(record.payload.target)." : "Added to \(record.payload.target)."
        case .failed:
            return simulated ? "Simulated failure. Nothing was sent." : "Not sent."
        case .unknown:
            return "Couldn't confirm whether it was sent. Doddy won't send it again until the status is checked."
        case .cancelled:
            return "Cancelled. Nothing was sent."
        }
    }
}

extension ActionStatusCopy {
    /// Wording for a refused step. Every message says whether anything was sent.
    public static func problem(for error: any Error) -> String {
        if let error = error as? ActionPayloadError {
            switch error {
            case .missingField(let key): return "The \(key == "recipient" ? "recipient" : "message") can't be empty. Nothing was sent."
            case .fieldTooLong(_, let limit): return "That's over the \(limit)-character limit. Nothing was sent."
            }
        }
        guard let error = error as? ActionPolicyError else { return "Something went wrong. Nothing was sent." }
        switch error {
        case .unsupportedAction: return "Doddy can't do that yet. Nothing was sent."
        case .notFound: return "That action no longer exists. Nothing was sent."
        case .invalidTransition, .alreadyFinished: return "That step isn't possible now. Check the status above."
        case .notApproved: return "It needs your approval first. Nothing was sent."
        case .payloadChanged: return "The draft changed after you reviewed it. Check it and approve again. Nothing was sent."
        case .approvalExpired: return "Your approval expired. Check the draft and approve again. Nothing was sent."
        case .alreadyExecuting: return "It's already being sent. It won't be sent twice."
        case .reconcileFirst: return "Doddy couldn't confirm the last attempt, so it won't send again. Check the status first."
        case .storageFailed: return "Doddy couldn't save this step on your iPhone, so nothing changed. Nothing was sent."
        case .resultNotSaved: return "Doddy got the result shown above but couldn't save it. After a restart it will show as unconfirmed and be checked again."
        case .storageUnavailable: return "Doddy couldn't open its saved actions, so actions are switched off. Nothing was sent or deleted."
        case .actionInProgress: return "Something is being sent right now. Try again when it finishes."
        }
    }
}
