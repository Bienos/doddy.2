import DoddyCore
import DoddyPersistence
import Foundation
import SwiftUI

/// Composition root. Local memory uses SQLite; voice uses the ElevenLabs agent (VoiceView); the
/// Talk to Doddy shortcut and Back Tap guide live in `ShortcutRouter`; reminders and other
/// actions stay explicit `Unavailable*` adapters.
struct AppEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let recallService: any RecallService
    let assistantClient: any AssistantClient
    let toolExecutor: any ToolExecutor
    let capabilities: CapabilityCatalog
    let privacy: PrivacyDefaults
    /// Set when the memory store could not be opened. Nothing is reset or deleted in that case.
    let storageProblem: String?

    static let unavailable = AppEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        recallService: UnavailableRecallService(),
        assistantClient: UnavailableAssistantClient(),
        toolExecutor: UnavailableToolExecutor(),
        capabilities: .m0,
        privacy: .m0,
        storageProblem: nil)

    /// `-inMemoryStore` (UI tests) keeps everything in memory and writes nothing to disk.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        do {
            let repository = arguments.contains("-inMemoryStore")
                ? try SQLiteMemoryRepository.inMemory()
                : try SQLiteMemoryRepository(path: try databaseURL(arguments: arguments).path)
            return AppEnvironment(
                memoryRepository: repository,
                recallService: RepositoryRecallService(repository: repository),
                assistantClient: UnavailableAssistantClient(),
                toolExecutor: UnavailableToolExecutor(),
                capabilities: .v2Shortcut,
                privacy: .v1Voice,
                storageProblem: nil)
        } catch {
            return AppEnvironment(
                memoryRepository: UnavailableMemoryRepository(),
                recallService: UnavailableRecallService(),
                assistantClient: UnavailableAssistantClient(),
                toolExecutor: UnavailableToolExecutor(),
                capabilities: .m0,
                privacy: .m0,
                storageProblem: "Doddy couldn't open its memory store, so saving is switched off. Nothing was deleted or reset. Try closing and reopening the app. (\(error.localizedDescription))")
        }
    }

    /// Application Support/Memories/memories.sqlite, readable after first unlock only.
    private static func databaseURL(arguments: [String]) throws -> URL {
        let fileManager = FileManager.default
        var directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Memories", isDirectory: true)
        #if DEBUG
        // A persistent UI fixture must never use the user's real memory database.
        if let index = arguments.firstIndex(of: "-memoryTestID") {
            guard arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            directory = directory.deletingLastPathComponent()
                .appendingPathComponent("TestMemories", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
        }
        #endif
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
