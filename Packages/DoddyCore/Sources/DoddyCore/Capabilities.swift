import Foundation

/// Everything the product may eventually do. The UI derives its claims from the catalog,
/// so nothing is shown as working unless it is recorded here as available.
public enum Capability: String, CaseIterable, Sendable {
    case memoryStorage
    case memoryRecall
    case cloudAssistant
    case voiceInput
    case voiceOutput
    case reminders
    case connectedAccounts
    case cloudSync
    /// Approval and receipt flow driven by a simulated adapter. Nothing is sent anywhere.
    case actionSimulation
}

public enum CapabilityStatus: Equatable, Sendable {
    case notImplemented(plannedMilestone: String)
    case available
}

public struct CapabilityCatalog: Sendable {
    public let statuses: [Capability: CapabilityStatus]

    public init(statuses: [Capability: CapabilityStatus]) {
        self.statuses = statuses
    }

    public func status(of capability: Capability) -> CapabilityStatus {
        statuses[capability] ?? .notImplemented(plannedMilestone: "unscheduled")
    }

    public func isAvailable(_ capability: Capability) -> Bool { status(of: capability) == .available }

    /// M0: nothing is implemented. Update an entry only together with executed tests.
    public static let m0 = CapabilityCatalog(statuses: [
        .memoryStorage: .notImplemented(plannedMilestone: "M1"),
        .memoryRecall: .notImplemented(plannedMilestone: "M1"),
        .cloudAssistant: .notImplemented(plannedMilestone: "M2"),
        .voiceInput: .notImplemented(plannedMilestone: "M3"),
        .voiceOutput: .notImplemented(plannedMilestone: "M3"),
        .reminders: .notImplemented(plannedMilestone: "M4"),
        .connectedAccounts: .notImplemented(plannedMilestone: "unscheduled"),
        .cloudSync: .notImplemented(plannedMilestone: "unscheduled"),
        .actionSimulation: .notImplemented(plannedMilestone: "V1"),
    ])

    /// M1: local text memory (save, list, correct, delete, export, lexical recall).
    public static let m1 = CapabilityCatalog(statuses: m0.statuses.merging([
        .memoryStorage: .available,
        .memoryRecall: .available,
    ]) { _, new in new })

    /// V1: local memory plus voice conversation (ElevenLabs agent, foreground only).
    public static let v1Voice = CapabilityCatalog(statuses: m1.statuses.merging([
        .cloudAssistant: .available,
        .voiceInput: .available,
        .voiceOutput: .available,
    ]) { _, new in new })

    /// V1 plus the simulated approval/receipt flow (docs/implementation/ACTION_APPROVAL_SIMULATION.md).
    /// Real actions (`reminders`, `connectedAccounts`) stay not built.
    public static let v1Trust = CapabilityCatalog(statuses: v1Voice.statuses.merging([
        .actionSimulation: .available,
    ]) { _, new in new })
}

public enum DoddyError: Error, Equatable, Sendable {
    case capabilityUnavailable(Capability)
}

public struct UnavailableMemoryRepository: MemoryRepository {
    public init() {}
    public func save(_ draft: NewMemory) async throws -> MemoryRecord { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func list(limit: Int?) async throws -> [MemoryRecord] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func query(_ query: String, limit: Int) async throws -> [MemoryCandidate] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func update(id: UUID, currentText: String) async throws -> MemoryRecord { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func delete(id: UUID) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}

public struct UnavailableRecallService: RecallService {
    public init() {}
    public func recall(_ question: String, limit: Int) async throws -> RecallOutcome { throw DoddyError.capabilityUnavailable(.memoryRecall) }
}

public struct UnavailableAssistantClient: AssistantClient {
    public init() {}
    public func respond(_ request: AssistantRequest) async throws -> AssistantReply { throw DoddyError.capabilityUnavailable(.cloudAssistant) }
}

/// Supports no action, so a ledger using it refuses every proposal before anything runs.
public struct UnavailableActionAdapter: ActionAdapter {
    public init() {}
    public var connectorID: String { "unavailable" }
    public var isSimulation: Bool { false }
    public func supports(_ type: ActionType) -> Bool { false }
    public func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult {
        throw DoddyError.capabilityUnavailable(.reminders)
    }
    public func status(idempotencyKey: UUID) async throws -> ActionProviderResult {
        throw DoddyError.capabilityUnavailable(.reminders)
    }
}
