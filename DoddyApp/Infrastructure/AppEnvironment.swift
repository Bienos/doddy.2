import DoddyCore
import DoddyPersistence
import Foundation
import SwiftUI

/// What the typed assistant (M2) needs from the app: where credentials live and how HTTP is sent.
/// The gateway address comes from Settings at question time, so changing it needs no restart.
struct AssistantWiring: Sendable {
    let credentials: any DeviceCredentialStore
    let transport: any HTTPTransport

    func service(gatewayAddress: String, recall: any RecallService) -> AssistantService {
        let client = GatewayAssistantClient(
            configuration: GatewayConfiguration(string: gatewayAddress),
            transport: transport,
            credentials: credentials)
        return AssistantService(recall: recall, client: client)
    }
}

/// Composition root. Local memory uses SQLite; voice uses the ElevenLabs agent (VoiceView); typed
/// questions go through the Doddy gateway (AskView); reminders and other actions stay explicit
/// `Unavailable*` adapters.
struct AppEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let recallService: any RecallService
    /// `nil` when the typed assistant is not wired (M0 fallback after a storage failure, previews).
    let assistant: AssistantWiring?
    let toolExecutor: any ToolExecutor
    let capabilities: CapabilityCatalog
    let privacy: PrivacyDefaults
    /// Set when the memory store could not be opened. Nothing is reset or deleted in that case.
    let storageProblem: String?

    static let unavailable = AppEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        recallService: UnavailableRecallService(),
        assistant: nil,
        toolExecutor: UnavailableToolExecutor(),
        capabilities: .m0,
        privacy: .m0,
        storageProblem: nil)

    /// `-inMemoryStore` (UI tests) keeps everything in memory and writes nothing to disk.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        do {
            let isUITest = arguments.contains("-inMemoryStore")
            let repository = isUITest
                ? try SQLiteMemoryRepository.inMemory()
                : try SQLiteMemoryRepository(path: try databaseURL().path)
            let credentials: any DeviceCredentialStore = isUITest ? InMemoryCredentialStore() : KeychainCredentialStore()
            return AppEnvironment(
                memoryRepository: repository,
                recallService: RepositoryRecallService(repository: repository),
                assistant: AssistantWiring(credentials: credentials, transport: AppHTTPTransport()),
                toolExecutor: UnavailableToolExecutor(),
                capabilities: .m2,
                privacy: .m2,
                storageProblem: nil)
        } catch {
            return AppEnvironment(
                memoryRepository: UnavailableMemoryRepository(),
                recallService: UnavailableRecallService(),
                assistant: nil,
                toolExecutor: UnavailableToolExecutor(),
                capabilities: .m0,
                privacy: .m0,
                storageProblem: "Doddy couldn't open its memory store, so saving is switched off. Nothing was deleted or reset. Try closing and reopening the app. (\(error.localizedDescription))")
        }
    }

    /// Application Support/Memories/memories.sqlite, readable after first unlock only.
    private static func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Memories", isDirectory: true)
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory.appendingPathComponent("memories.sqlite")
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
