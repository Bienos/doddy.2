import DoddyCore
import DoddyPersistence
import Foundation

/// What the Mac app needs from storage (ADR-351). One SQLite file in the app's own sandbox folder,
/// the same schema and repositories as the iPhone app. The Mac keeps its own notes: there is no
/// sync with an iPhone (yet), and nothing here uses the network.
struct MacEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let listRepository: any ListRepository
    let recallService: any RecallService
    /// Set when the notes file could not be opened. Nothing is reset or deleted in that case.
    let storageProblem: String?
    /// The folder holding the notes file, shown in Settings so the user can find it.
    let folder: URL?

    static let unavailable = MacEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        listRepository: UnavailableListRepository(),
        recallService: UnavailableRecallService(),
        storageProblem: nil,
        folder: nil)

    /// `-inMemoryStore` keeps everything in memory and writes nothing to disk (UI tests).
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> MacEnvironment {
        do {
            let inMemory = arguments.contains("-inMemoryStore")
            let file = inMemory ? nil : try databaseURL()
            let database = try file.map { try DoddyDatabase(path: $0.path) } ?? DoddyDatabase.inMemory()
            let repository = SQLiteMemoryRepository(database: database)
            return MacEnvironment(
                memoryRepository: repository,
                listRepository: SQLiteListRepository(database: database),
                recallService: RepositoryRecallService(repository: repository),
                storageProblem: nil,
                folder: file?.deletingLastPathComponent())
        } catch {
            return MacEnvironment(
                memoryRepository: UnavailableMemoryRepository(),
                listRepository: UnavailableListRepository(),
                recallService: UnavailableRecallService(),
                storageProblem: problem(for: error),
                folder: nil)
        }
    }

    private static func problem(for error: any Error) -> String {
        if error as? DoddyDatabaseError == .newerSchema {
            return NSLocalizedString("Your notes were saved by a newer version of Doddy, so this version can't open them. Nothing was deleted or reset. Install the latest version of Doddy.", comment: "")
        }
        return String(format: NSLocalizedString("Doddy couldn't open its notes file, so saving is switched off. Nothing was deleted or reset. Try quitting and reopening Doddy. (%@)", comment: ""), error.localizedDescription)
    }

    /// ~/Library/Containers/<app>/Data/Library/Application Support/Doddy/memories.sqlite
    private static func databaseURL() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Doddy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("memories.sqlite")
    }
}
