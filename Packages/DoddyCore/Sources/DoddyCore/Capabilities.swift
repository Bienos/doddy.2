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
    case pushUpdates
    case textUpdates
    case connectedAccounts
    case cloudSync
}

public enum CapabilityStatus: Equatable, Sendable {
    case notImplemented(plannedMilestone: String)
    /// Built, but it can't work until something outside the app exists (e.g. a deployed server).
    case needsSetup(String)
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
        .pushUpdates: .notImplemented(plannedMilestone: "S1"),
        .textUpdates: .notImplemented(plannedMilestone: "S1"),
        .connectedAccounts: .notImplemented(plannedMilestone: "unscheduled"),
        .cloudSync: .notImplemented(plannedMilestone: "unscheduled"),
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

    /// S1: voice plus push and text updates through the Doddy server. Without a server
    /// address the updates are reported as needing setup, never as available.
    public static func s1Updates(serverConfigured: Bool) -> CapabilityCatalog {
        let updates: CapabilityStatus = serverConfigured ? .available : .needsSetup("Doddy server not connected")
        return CapabilityCatalog(statuses: v1Voice.statuses.merging([
            .pushUpdates: updates,
            .textUpdates: updates,
        ]) { _, new in new })
    }
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

public struct UnavailableToolExecutor: ToolExecutor {
    public init() {}
    public func execute(_ confirmation: ToolConfirmation) async throws -> ActionReceipt { throw DoddyError.capabilityUnavailable(.reminders) }
}
