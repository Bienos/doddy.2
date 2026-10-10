import Foundation

/// Everything the product may eventually do. The UI derives its claims from the catalog,
/// so nothing is shown as working unless it is recorded here as available.
public enum Capability: String, CaseIterable, Sendable {
    case memoryStorage
    case memoryRecall
    case cloudAssistant
    case textAssistant
    case voiceInput
    case voiceOutput
    case reminders
    case connectedAccounts
    case cloudSync
    /// "Talk to Doddy" App Shortcut (Siri, Shortcuts, Action Button) and the guided Back Tap setup.
    case systemShortcut
}

public enum CapabilityStatus: Equatable, Sendable {
    case notImplemented(plannedMilestone: String)
    /// Built, but narrower than the name suggests or not yet verified live. The note says how.
    case limited(String)
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
        .textAssistant: .notImplemented(plannedMilestone: "M2"),
        .voiceInput: .notImplemented(plannedMilestone: "M3"),
        .voiceOutput: .notImplemented(plannedMilestone: "M3"),
        .reminders: .notImplemented(plannedMilestone: "M4"),
        .connectedAccounts: .notImplemented(plannedMilestone: "unscheduled"),
        .cloudSync: .notImplemented(plannedMilestone: "unscheduled"),
        .systemShortcut: .notImplemented(plannedMilestone: "V2"),
    ])

    /// M1: local text memory (save, list, correct, delete, export, lexical recall).
    public static let m1 = CapabilityCatalog(statuses: m0.statuses.merging([
        .memoryStorage: .available,
        .memoryRecall: .available,
    ]) { _, new in new })

    /// V1: local memory plus voice conversation (ElevenLabs agent, foreground only), with
    /// reminders added through the voice tools after the user taps Add (off until Settings turns them on).
    public static let v1Voice = CapabilityCatalog(statuses: m1.statuses.merging([
        .cloudAssistant: .available,
        .voiceInput: .available,
        .voiceOutput: .available,
        .reminders: .available,
    ]) { _, new in new })

    /// V2: V1 plus the Talk to Doddy App Shortcut and the guided (user-reported) Back Tap setup.
    public static let v2Shortcut = CapabilityCatalog(statuses: v1Voice.statuses.merging([
        .systemShortcut: .available,
    ]) { _, new in new })

    /// Connected Apps foundation: Google Calendar read-only through a Doddy server. Demo data unless
    /// a server in live mode is configured; live provider behaviour is unverified (see docs/integrations).
    public static let v1ConnectedApps = CapabilityCatalog(statuses: v1Voice.statuses.merging([
        .connectedAccounts: .limited("Google Calendar read-only; Gmail, Drive, Notion, Todoist tools you switch on; needs a Doddy server"),
    ]) { _, new in new })

    /// V2 (voice, shortcut, Back Tap guide) plus the Connected Apps foundation.
    public static let v2WithConnectedApps = CapabilityCatalog(statuses: v2Shortcut.statuses.merging([
        .connectedAccounts: .limited("Google Calendar read-only; Gmail, Drive, Notion, Todoist tools you switch on; needs a Doddy server"),
    ]) { _, new in new })

    /// M2: typed questions to a real model through the gateway, with checked citations.
    /// "Available" means the code exists and its tests ran. Whether a given install can use it also
    /// depends on a gateway address, an invite code and the user's consent (see `AssistantAvailability`).
    public static let m2 = CapabilityCatalog(statuses: v1Voice.statuses.merging([
        .textAssistant: .available,
    ]) { _, new in new })

    /// What this build ships: V2 with Connected Apps plus M2's typed questions (ADR-121).
    public static let v2WithAssistant = CapabilityCatalog(statuses: v2WithConnectedApps.statuses.merging([
        .textAssistant: .available,
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

public struct UnavailableToolExecutor: ToolExecutor {
    public init() {}
    public func execute(_ confirmation: ToolConfirmation) async throws -> ActionReceipt { throw DoddyError.capabilityUnavailable(.reminders) }
}
