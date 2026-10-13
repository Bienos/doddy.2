import DoddyCore
import DoddyPersistence
import Foundation
import Observation
import WidgetKit

/// The Mac menu bar's notes (ADR-435): Doddy's own database on this Mac, in the app's sandbox
/// container (Application Support), opened with the same SQLite store as the iPhone's. Nothing
/// here reaches the iPhone and nothing from the iPhone is here; notes don't sync.
@MainActor
@Observable
final class MacCaptureModel {
    private let repository: SQLiteMemoryRepository?
    /// Set when the database can't be opened. Save is then not offered.
    let openProblem: String?
    /// Every note on this Mac, newest first: the Doddy window lists them all (ADR-451).
    private(set) var notes: [MemoryRecord] = []
    /// The menu bar window shows the last five.
    var recent: [MemoryRecord] { Array(notes.prefix(5)) }
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

    /// Save as the windows show it: what to say, or `nil` when the database isn't open.
    func saveForDisplay(_ text: String) async -> MacSaveResult? {
        (await save(text)).map(MacSaveResult.init)
    }

    /// The notes on this Mac, so an unconfirmed save can be checked before trying again, and the
    /// desktop widget's count (ADR-439).
    func refresh() async {
        guard let repository else { return }
        do {
            let all = try await repository.list(limit: nil)
            notes = all
            recentProblem = nil
            shareCount(all.count)
        } catch {
            recentProblem = "Recent notes can't be read right now."
        }
    }

    /// Written to the App Group folder and read back; only then is the widget asked to reload.
    /// The widget gets a number and a time, never a note's words. No App Group, nothing written.
    private func shareCount(_ count: Int) {
        guard let folder = MacGroupFolder.url else { return }
        if MacNoteCountFile.write(MacNoteCount(count: count, countedAt: .now), in: folder) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
