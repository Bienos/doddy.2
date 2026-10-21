import DoddyCore
import DoddyPersistence
import Foundation
import SwiftUI

/// What the typed assistant (M2) needs from the app: where credentials live and how HTTP is sent.
/// The gateway address comes from Settings at question time, so changing it needs no restart.
struct AssistantWiring: Sendable {
    let credentials: any DeviceCredentialStore
    let transport: any GatewayTransport

    func service(gatewayAddress: String, recall: any RecallService) -> AssistantService {
        let client = GatewayAssistantClient(
            configuration: GatewayConfiguration(string: gatewayAddress),
            transport: transport,
            credentials: credentials)
        return AssistantService(recall: recall, client: client)
    }
}

/// Composition root. Local memory and the reviewed profile use one SQLite file; voice uses the
/// ElevenLabs agent (VoiceView); typed questions go through the Doddy gateway (AskView); the Talk to
/// Doddy shortcut and Back Tap guide live in `ShortcutRouter`; Connected Apps talks to a Doddy server
/// (ConnectedAppsScreen); other actions stay explicit `Unavailable*` adapters.
struct AppEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let profileRepository: any ProfileRepository
    let recallService: any RecallService
    /// `nil` when the typed assistant is not wired (M0 fallback after a storage failure, previews).
    let assistant: AssistantWiring?
    let toolExecutor: any ToolExecutor
    /// Reminders on notes (M4a). `nil` when the memory store is not open.
    let noteReminders: NoteReminderCoordinator?
    let capabilities: CapabilityCatalog
    let privacy: PrivacyDefaults
    /// Set when the memory store could not be opened. Nothing is reset or deleted in that case.
    let storageProblem: String?
    /// Lists (ADR-216), in the same SQLite file as the notes.
    var listRepository: any ListRepository = UnavailableListRepository()
    /// Which lists are shared through iCloud (ADR-263), and their last sync.
    var listShareRepository: any ListShareRepository = UnavailableListShareRepository()
    /// Which note carries which photo (ADR-218), and the folder of photo files next to the database.
    var photoRepository: any PhotoRepository = UnavailablePhotoRepository()
    var photoFiles: PhotoFiles = .unavailable
    /// Which note carries which recording (ADR-230), and the folder of recordings next to the database.
    var audioRepository: any AudioRepository = UnavailableAudioRepository()
    var audioFiles: AudioFiles = .unavailable
    /// The learning loop (ADR-440): learned facts, procedures and outcome events, in the same file.
    /// `nil` when the memory store is not open.
    var learningService: LearningService?
    /// Calls Doddy places for the user (ADR-500): brief, card, answer with transcript, cost and
    /// the server's deletion receipts, in the same file.
    var callCaseRepository: any CallCaseRepository = UnavailableCallCaseRepository()
    /// Tasks handed to Doddy's background worker (ADR-570): the user's words, the state, and the
    /// result once it is saved here (then the server deletes its copy), in the same file.
    var errandRepository: any ErrandRepository = UnavailableErrandRepository()

    static let unavailable = AppEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        profileRepository: UnavailableProfileRepository(),
        recallService: UnavailableRecallService(),
        assistant: nil,
        toolExecutor: UnavailableToolExecutor(),
        noteReminders: nil,
        capabilities: .m0,
        privacy: .m0,
        storageProblem: nil)

    /// The one environment of this process, so the app and Siri (ADR-248) share one database
    /// connection whichever starts first.
    static let shared = AppEnvironment.live()

    /// `-inMemoryStore` (UI tests) keeps everything in memory and writes nothing to disk.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        do {
            let isUITest = arguments.contains("-inMemoryStore")
            let databaseFile = isUITest ? nil : try databaseURL(arguments: arguments)
            let database = try databaseFile.map { try DoddyDatabase(path: $0.path) } ?? DoddyDatabase.inMemory()
            let repository = SQLiteMemoryRepository(database: database)
            let credentials: any DeviceCredentialStore = isUITest ? InMemoryCredentialStore() : KeychainCredentialStore()
            // UI-test launches never touch iOS notifications: reminders stay inside Doddy.
            let notifications: any NoteNotificationScheduling = isUITest ? DisabledNoteNotifications() : SystemNoteNotifications()
            let noteReminders = NoteReminderCoordinator(
                repository: SQLiteNoteReminderRepository(database: database), center: notifications,
                showNoteText: { UserDefaults.standard.bool(forKey: PreferenceKey.showNoteTextInNotifications) },
                language: { .current })
            return AppEnvironment(
                memoryRepository: repository,
                profileRepository: SQLiteProfileRepository(database: database),
                recallService: RepositoryRecallService(repository: repository),
                assistant: AssistantWiring(credentials: credentials, transport: AppHTTPTransport()),
                toolExecutor: UnavailableToolExecutor(),
                noteReminders: noteReminders,
                // Notifications, texts, calls and news say "needs setup" until a messaging server is set.
                capabilities: .shipping(serverConfigured: ServerConfig.baseURL() != nil),
                privacy: .v1Voice,
                storageProblem: nil,
                listRepository: SQLiteListRepository(database: database),
                listShareRepository: SQLiteListShareRepository(database: database),
                photoRepository: SQLitePhotoRepository(database: database),
                photoFiles: databaseFile.map(PhotoFiles.beside(database:)) ?? .temporary(),
                audioRepository: SQLiteAudioRepository(database: database),
                audioFiles: databaseFile.map(AudioFiles.beside(database:)) ?? .temporary(),
                learningService: LearningService(
                    facts: SQLiteLearnedFactRepository(database: database),
                    procedures: SQLiteProcedureRepository(database: database),
                    outcomes: SQLiteOutcomeEventRepository(database: database)),
                callCaseRepository: SQLiteCallCaseRepository(database: database),
                errandRepository: SQLiteErrandRepository(database: database))
        } catch {
            return AppEnvironment(
                memoryRepository: UnavailableMemoryRepository(),
                profileRepository: UnavailableProfileRepository(),
                recallService: UnavailableRecallService(),
                assistant: nil,
                toolExecutor: UnavailableToolExecutor(),
                noteReminders: nil,
                capabilities: .m0,
                privacy: .m0,
                storageProblem: storageProblem(for: error))
        }
    }

    private static func storageProblem(for error: any Error) -> String {
        if error as? DoddyDatabaseError == .newerSchema {
            return NSLocalizedString("Your memories were saved by a newer version of Doddy, so this version can't open them. Nothing was deleted or reset. Install the latest version of Doddy.", comment: "")
        }
        return "Doddy couldn't open its memory store, so saving is switched off. Nothing was deleted or reset. Try closing and reopening the app. (\(error.localizedDescription))"
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
