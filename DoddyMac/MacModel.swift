import DoddyCore
import DoddyPersistence
import Foundation
import Observation

/// What "Find in my memories" shows. Only stored notes, or an honest "no match" (never a guess).
enum MacFindState {
    case idle
    case matches([MemoryCandidate])
    case noMatch
    case failed(String)
}

/// The Mac app's own memory (ADR-450): one SQLite file in this app's container, opened with the
/// same `DoddyDatabase` the iPhone uses. It is NOT synced with the iPhone: there is no account or
/// cloud sync in this version, so a note typed here exists only on this Mac.
@MainActor
@Observable
final class MacModel {
    private(set) var memories: [MemoryRecord] = []
    /// Set when the memory file could not be opened. Nothing is reset or deleted in that case.
    private(set) var storageProblem: String?
    private(set) var loadError: String?
    let databaseURL: URL?
    private let repository: (any MemoryRepository)?

    var menu: MenuBarMenu { MenuBarMenu(memoryIsOpen: repository != nil) }

    init() {
        var opened: (url: URL, repository: SQLiteMemoryRepository)?
        var problem: String?
        do {
            let url = try Self.storeURL()
            let database = try DoddyDatabase(path: url.path)
            opened = (url, SQLiteMemoryRepository(database: database))
        } catch {
            if error as? DoddyDatabaseError == .newerSchema {
                problem = "These memories were saved by a newer version of Doddy, so this version can't open them. Nothing was deleted or reset."
            } else {
                problem = "Doddy couldn't open its memory store on this Mac, so saving is switched off. Nothing was deleted or reset. (\(error.localizedDescription))"
            }
        }
        databaseURL = opened?.url
        repository = opened?.repository
        storageProblem = problem
    }

    /// Application Support/Doddy Mac/Memories/memories.sqlite inside the app's sandbox container.
    private static func storeURL() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Doddy Mac", isDirectory: true)
            .appendingPathComponent("Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("memories.sqlite")
    }

    func reload() async {
        guard let repository else { return }
        do {
            // Newest first, as the repository returns them. Lists (iPhone feature) are not shown.
            memories = try await repository.list(limit: nil).filter { $0.category != .list }
            loadError = nil
        } catch {
            // Keep the last good copy; never show an empty store for a failed read.
            loadError = "Doddy couldn't read its notes just now. (\(error.localizedDescription))"
        }
    }

    func save(_ text: String) async -> MenuBarSaveResult {
        guard let repository else {
            return .notSaved(message: "Doddy's memory store isn't open on this Mac. Nothing was marked as saved.")
        }
        let result = await MenuBarCapture.save(text, to: repository)
        if case .saved = result { await reload() }
        return result
    }

    func find(_ question: String) async -> MacFindState {
        guard let repository else { return .failed("Doddy's memory store isn't open on this Mac.") }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .idle }
        do {
            switch try await RepositoryRecallService(repository: repository).recall(trimmed, limit: 5) {
            case .matches(let found): return .matches(found)
            case .noMatch: return .noMatch
            }
        } catch {
            return .failed("Doddy couldn't search just now. (\(error.localizedDescription))")
        }
    }
}
