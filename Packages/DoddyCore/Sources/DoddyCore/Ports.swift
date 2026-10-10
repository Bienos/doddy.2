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

/// Durable local storage. A returned record means the write is committed and read back.
public protocol MemoryRepository: Sendable {
    func save(_ draft: NewMemory) async throws -> MemoryRecord
    /// Newest first. `nil` limit returns everything.
    func list(limit: Int?) async throws -> [MemoryRecord]
    func query(_ query: String, limit: Int) async throws -> [MemoryCandidate]
    func update(id: UUID, currentText: String) async throws -> MemoryRecord
    /// Changes only the note's type. Read back before success; the words, dates and "edited"
    /// state stay as they are.
    func setCategory(id: UUID, to category: MemoryCategory) async throws -> MemoryRecord
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func export() async throws -> Data
    /// Adds exported records exactly as they were (id, both texts, source, category, dates).
    /// A record whose id is already stored is left untouched. One transaction: every added
    /// record is read back before success, otherwise nothing is added. Returns what was added.
    func restore(_ records: [MemoryRecord]) async throws -> [MemoryRecord]
    /// The same, also adding each added note's corrections when they are its whole history
    /// (ADR-214). Notes already here keep their own.
    func restore(_ records: [MemoryRecord], corrections: [MemoryCorrection]) async throws -> [MemoryRecord]
    /// Every correction of one note, oldest first (ADR-214). The original is the note's `rawText`.
    func corrections(of id: UUID) async throws -> [MemoryCorrection]
    /// Every stored correction, for exports.
    func allCorrections() async throws -> [MemoryCorrection]
}

extension MemoryRepository {
    public func restore(_ records: [MemoryRecord], corrections: [MemoryCorrection]) async throws -> [MemoryRecord] {
        throw DoddyError.capabilityUnavailable(.memoryStorage)
    }

    public func corrections(of id: UUID) async throws -> [MemoryCorrection] {
        throw DoddyError.capabilityUnavailable(.memoryStorage)
    }

    public func allCorrections() async throws -> [MemoryCorrection] {
        throw DoddyError.capabilityUnavailable(.memoryStorage)
    }

    public func restore(_ records: [MemoryRecord]) async throws -> [MemoryRecord] {
        throw DoddyError.capabilityUnavailable(.memoryStorage)
    }

    public func setCategory(id: UUID, to category: MemoryCategory) async throws -> MemoryRecord {
        throw DoddyError.capabilityUnavailable(.memoryStorage)
    }
}

public enum MemoryStoreError: Error, Equatable, Sendable {
    case notFound(UUID)
    /// The write reported success but reading it back did not match. Treated as a failed save.
    case verificationFailed
    /// A stored row no longer satisfies the domain rules.
    case corruptRecord(String)
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

/// One earlier turn of the current chat. Chats live in memory only and are never saved as notes.
public struct ConversationTurn: Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AssistantRequest: Equatable, Sendable {
    public let requestID: UUID
    public let sessionID: UUID
    public let userText: String
    /// The only stored memories the assistant may cite.
    public let groundingMemories: [MemoryCandidate]
    public let recentTurns: [ConversationTurn]
    /// BCP 47 language code of the app, e.g. "en" or "pl".
    public let locale: String

    public init(
        sessionID: UUID,
        userText: String,
        groundingMemories: [MemoryCandidate] = [],
        recentTurns: [ConversationTurn] = [],
        locale: String = "en",
        requestID: UUID = UUID()
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.userText = userText
        self.groundingMemories = groundingMemories
        self.recentTurns = recentTurns
        self.locale = locale
    }
}

public struct AssistantReply: Equatable, Sendable {
    public let text: String
    /// Must be a subset of the request's grounding memory IDs. `CitationVerifier` enforces this.
    public let citedMemoryIDs: [UUID]

    public init(text: String, citedMemoryIDs: [UUID] = []) {
        self.text = text
        self.citedMemoryIDs = citedMemoryIDs
    }
}

/// Provider-neutral AI boundary. The only real implementation is `GatewayAssistantClient` (M2).
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
