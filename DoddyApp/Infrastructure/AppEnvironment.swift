import DoddyCore
import DoddyPersistence
import Foundation
import SwiftUI

/// Composition root. Local memory uses SQLite; voice uses the ElevenLabs agent (VoiceView);
/// actions go through one persistent `ActionLedger` whose only adapter is the simulation
/// (no real external action exists yet).
struct AppEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let recallService: any RecallService
    let assistantClient: any AssistantClient
    /// The one action ledger (SQLite-backed). Until a real adapter exists it holds only the simulation.
    let actionLedger: ActionLedger
    /// The simulated provider behind the approval demo; nil when actions are unavailable.
    let simulatedActions: SimulatedActionAdapter?
    let capabilities: CapabilityCatalog
    let privacy: PrivacyDefaults
    /// Set when the memory store could not be opened. Nothing is reset or deleted in that case.
    let storageProblem: String?

    static let unavailable = AppEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        recallService: UnavailableRecallService(),
        assistantClient: UnavailableAssistantClient(),
        actionLedger: ActionLedger(adapters: [UnavailableActionAdapter()]),
        simulatedActions: nil,
        capabilities: .m0,
        privacy: .m0,
        storageProblem: nil)

    /// `-inMemoryStore` (UI tests) keeps everything in memory and writes nothing to disk.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        do {
            let repository = arguments.contains("-inMemoryStore")
                ? try SQLiteMemoryRepository.inMemory()
                : try SQLiteMemoryRepository(path: try databaseURL().path)
            let actions = makeActions(arguments: arguments)
            return AppEnvironment(
                memoryRepository: repository,
                recallService: RepositoryRecallService(repository: repository),
                assistantClient: UnavailableAssistantClient(),
                actionLedger: actions.ledger,
                simulatedActions: actions.simulation,
                // Without a working action store the approval demo is switched off.
                capabilities: actions.simulation == nil ? .v1Voice : .v1Trust,
                privacy: .v1Voice,
                storageProblem: nil)
        } catch {
            return AppEnvironment(
                memoryRepository: UnavailableMemoryRepository(),
                recallService: UnavailableRecallService(),
                assistantClient: UnavailableAssistantClient(),
                actionLedger: ActionLedger(adapters: [UnavailableActionAdapter()]),
                simulatedActions: nil,
                capabilities: .m0,
                privacy: .m0,
                storageProblem: "Doddy couldn't open its memory store, so saving is switched off. Nothing was deleted or reset. Try closing and reopening the app. (\(error.localizedDescription))")
        }
    }

    /// Separate SQLite file (ADR-045). If it can't open, actions are off and nothing is reset.
    private static func makeActions(arguments: [String]) -> (ledger: ActionLedger, simulation: SimulatedActionAdapter?) {
        do {
            let store: any ActionStore = arguments.contains("-inMemoryStore")
                ? InMemoryActionStore()
                : try SQLiteActionStore(path: try databaseURL(directory: "Actions", file: "actions.sqlite").path)
            let simulation = SimulatedActionAdapter()
            return (ActionLedger(adapters: [simulation], store: store), simulation)
        } catch {
            return (ActionLedger(adapters: [UnavailableActionAdapter()]), nil)
        }
    }

    /// Application Support/<directory>/<file>, readable after first unlock only.
    private static func databaseURL(directory name: String = "Memories", file: String = "memories.sqlite") throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory.appendingPathComponent(file)
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.unavailable
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
