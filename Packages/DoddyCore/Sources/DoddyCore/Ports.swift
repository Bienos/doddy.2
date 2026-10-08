import Foundation

// Stable domain ports (docs/architecture/IOS_ARCHITECTURE.md). M0 ships protocols and
// explicit `Unavailable*` adapters only; no production behaviour is simulated.

/// Verified result of a recall match: always refers to a real stored record.
public struct MemoryCandidate: Equatable, Sendable {
    public let record: MemoryRecord
    public let matchedTerms: [String]

    public init(record: MemoryRecord, matchedTerms: [String]) {
        self.record = record
        self.matchedTerms = matchedTerms
    }

    public var memoryID: UUID { record.id }
}

/// Durable local storage. A returned record means the write is committed (M1 contract).
public protocol MemoryRepository: Sendable {
    func save(_ draft: NewMemory) async throws -> MemoryRecord
    func query(_ query: String, limit: Int) async throws -> [MemoryCandidate]
    func update(id: UUID, currentText: String) async throws -> MemoryRecord
    func delete(id: UUID) async throws
    func export() async throws -> Data
}

public enum RecallOutcome: Equatable, Sendable {
    case matches([MemoryCandidate])
    /// Say so plainly; never generate an answer instead.
    case noMatch
}

public enum RecallCopy {
    public static let noMatch = "I couldn't find that in your saved memories."
}

/// Deterministic, source-grounded lookup over stored memories.
public protocol RecallService: Sendable {
    func recall(_ question: String, limit: Int) async throws -> RecallOutcome
}

public struct AssistantRequest: Equatable, Sendable {
    public let sessionID: UUID
    public let userText: String
    /// The only stored memories the assistant may cite.
    public let groundingMemories: [MemoryCandidate]

    public init(sessionID: UUID, userText: String, groundingMemories: [MemoryCandidate] = []) {
        self.sessionID = sessionID
        self.userText = userText
        self.groundingMemories = groundingMemories
    }
}

public struct AssistantReply: Equatable, Sendable {
    public let text: String
    /// Must be a subset of the request's grounding memory IDs (verified in M2).
    public let citedMemoryIDs: [UUID]

    public init(text: String, citedMemoryIDs: [UUID] = []) {
        self.text = text
        self.citedMemoryIDs = citedMemoryIDs
    }
}

/// Provider-neutral AI boundary. No implementation exists before M2.
public protocol AssistantClient: Sendable {
    func respond(_ request: AssistantRequest) async throws -> AssistantReply
}

public enum ToolKind: String, Codable, Sendable {
    case createReminder = "create_reminder"
}

/// A model- or app-suggested action. A proposal alone authorises nothing.
public struct ToolProposal: Equatable, Sendable {
    public let operationID: UUID
    public let kind: ToolKind
    public let summary: String

    public init(operationID: UUID, kind: ToolKind, summary: String) {
        self.operationID = operationID
        self.kind = kind
        self.summary = summary
    }
}

/// Evidence that the user reviewed and approved one specific proposal.
public struct ToolConfirmation: Equatable, Sendable {
    public let proposal: ToolProposal
    public let confirmedAt: Date

    public init(proposal: ToolProposal, confirmedAt: Date) {
        self.proposal = proposal
        self.confirmedAt = confirmedAt
    }
}

public enum ActionOutcome: String, Codable, Sendable {
    case verified
    /// The outcome could not be confirmed; reconcile before retrying.
    case unknown
    case failed
}

public struct ActionReceipt: Equatable, Sendable {
    public let operationID: UUID
    public let outcome: ActionOutcome
    public let externalID: String?

    public init(operationID: UUID, outcome: ActionOutcome, externalID: String? = nil) {
        self.operationID = operationID
        self.outcome = outcome
        self.externalID = externalID
    }
}

/// Executes only confirmed proposals and returns an independently verified receipt (M4).
public protocol ToolExecutor: Sendable {
    func execute(_ confirmation: ToolConfirmation) async throws -> ActionReceipt
}
