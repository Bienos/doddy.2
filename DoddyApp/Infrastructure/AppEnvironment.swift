import DoddyCore
import DoddyPersistence
import Foundation
import SwiftUI

/// Composition root. Local memory uses SQLite; voice uses the ElevenLabs agent (VoiceView);
/// Calendar, Reminders, Contacts and local nudges use iOS frameworks (Features/Connections/System)
/// and stay unused until the user connects them.
struct AppEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let recallService: any RecallService
    let assistantClient: any AssistantClient
    let toolExecutor: any ToolExecutor
    let calendarGateway: any CalendarGateway
    let remindersGateway: any RemindersGateway
    let contactsGateway: any ContactsGateway
    let nudgeScheduler: any NudgeScheduler
    let capabilities: CapabilityCatalog
    let privacy: PrivacyDefaults
    /// Set when the memory store could not be opened. Nothing is reset or deleted in that case.
    let storageProblem: String?

    static let unavailable = AppEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        recallService: UnavailableRecallService(),
        assistantClient: UnavailableAssistantClient(),
        toolExecutor: UnavailableToolExecutor(),
        calendarGateway: UnavailableCalendarGateway(),
        remindersGateway: UnavailableRemindersGateway(),
        contactsGateway: UnavailableContactsGateway(),
        nudgeScheduler: UnavailableNudgeScheduler(),
        capabilities: .m0,
        privacy: .m0,
        storageProblem: nil)

    /// `-inMemoryStore` (UI tests) keeps everything in memory and writes nothing to disk.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let eventStore = SharedEventStore()
        do {
            let repository = arguments.contains("-inMemoryStore")
                ? try SQLiteMemoryRepository.inMemory()
                : try SQLiteMemoryRepository(path: try databaseURL().path)
            return AppEnvironment(
                memoryRepository: repository,
                recallService: RepositoryRecallService(repository: repository),
                assistantClient: UnavailableAssistantClient(),
                toolExecutor: UnavailableToolExecutor(),
                calendarGateway: EventKitCalendarGateway(shared: eventStore),
                remindersGateway: EventKitRemindersGateway(shared: eventStore),
                contactsGateway: SystemContactsGateway(),
                nudgeScheduler: LocalNudgeScheduler(),
                capabilities: .v4aConnections,
                privacy: .v1Voice,
                storageProblem: nil)
        } catch {
            return AppEnvironment(
                memoryRepository: UnavailableMemoryRepository(),
                recallService: UnavailableRecallService(),
                assistantClient: UnavailableAssistantClient(),
                toolExecutor: UnavailableToolExecutor(),
                calendarGateway: UnavailableCalendarGateway(),
                remindersGateway: UnavailableRemindersGateway(),
                contactsGateway: UnavailableContactsGateway(),
                nudgeScheduler: UnavailableNudgeScheduler(),
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
