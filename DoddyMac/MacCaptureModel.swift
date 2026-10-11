import DoddyCore
import DoddyPersistence
import Foundation
import Observation

/// The Mac menu bar's notes (ADR-435): Doddy's own database on this Mac, in the app's sandbox
/// container (Application Support), opened with the same SQLite store as the iPhone's. Nothing
/// here reaches the iPhone and nothing from the iPhone is here; notes don't sync.
@MainActor
@Observable
final class MacCaptureModel {
    private let repository: SQLiteMemoryRepository?
    /// Set when the database can't be opened. Save is then not offered.
    let openProblem: String?
    private(set) var recent: [MemoryRecord] = []
    private(set) var recentProblem: String?

    init() {
        let opened = Self.open()
        repository = opened.repository
        openProblem = opened.problem
    }

    private static func open() -> (repository: SQLiteMemoryRepository?, problem: String?) {
        do {
            let folder = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Doddy", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (try SQLiteMemoryRepository(path: folder.appendingPathComponent("doddy-mac.sqlite").path), nil)
        } catch {
            return (nil, "Doddy's notes on this Mac can't be opened, so nothing can be saved.")
        }
    }

    var canSave: Bool { repository != nil }

    /// `nil` only when the database isn't open (nothing was tried).
    func save(_ text: String) async -> QuickCaptureOutcome? {
        guard let repository else { return nil }
        let outcome = await QuickCapture.save(text, to: repository)
        await refresh()
        return outcome
    }

    /// The last few notes on this Mac, so an unconfirmed save can be checked before trying again.
    func refresh() async {
        guard let repository else { return }
        do {
            recent = try await repository.list(limit: 5)
            recentProblem = nil
        } catch {
            recentProblem = "Recent notes can't be read right now."
        }
    }
}
