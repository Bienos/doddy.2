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
    private var repository: SQLiteMemoryRepository?
    private let openTask: Task<MacStoreOpenResult, Never>
    private(set) var isOpeningStore = true
    /// Set when the database can't be opened. Save is then not offered.
    private(set) var openProblem: String?
    /// Every note on this Mac, newest first: the Doddy window lists them all (ADR-451).
    private(set) var notes: [MemoryRecord] = []
    /// The menu bar window only reads and renders the five notes it shows.
    private(set) var recent: [MemoryRecord] = []
    private(set) var recentProblem: String?
    private(set) var isRefreshingAllNotes = false

    init() {
        // Opening SQLite and applying migrations must not hold up the first menu bar window.
        openTask = Task.detached(priority: .utility) { Self.open() }
    }

    nonisolated private static func open() -> MacStoreOpenResult {
        do {
            let folder = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Doddy", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return .opened(try SQLiteMemoryRepository(path: folder.appendingPathComponent("doddy-mac.sqlite").path))
        } catch {
            return .failed("Doddy's notes on this Mac can't be opened, so nothing can be saved.")
        }
    }

    var canSave: Bool { repository != nil }

    private func readyRepository() async -> SQLiteMemoryRepository? {
        if let repository { return repository }
        guard isOpeningStore else { return nil }
        switch await openTask.value {
        case .opened(let opened):
            repository = opened
        case .failed(let message):
            openProblem = message
        }
        isOpeningStore = false
        return repository
    }

    /// `nil` only when the database isn't open (nothing was tried).
    func save(_ text: String, refreshAllNotes: Bool = false) async -> QuickCaptureOutcome? {
        guard let repository = await readyRepository() else { return nil }
        let outcome = await QuickCapture.save(text, to: repository)
        if refreshAllNotes {
            await refreshAll()
        } else {
            await refreshRecent()
        }
        return outcome
    }

    /// Save as the windows show it: what to say, or `nil` when the database isn't open.
    func saveForDisplay(_ text: String, refreshAllNotes: Bool = false) async -> MacSaveResult? {
        (await save(text, refreshAllNotes: refreshAllNotes)).map(MacSaveResult.init)
    }

    /// The five rows the menu bar window displays plus the desktop widget's count (ADR-439).
    func refreshRecent() async {
        await refresh(limit: 5, allNotes: false)
    }

    /// The full archive shown only in the dedicated Doddy window (ADR-451).
    func refreshAll() async {
        isRefreshingAllNotes = true
        defer { isRefreshingAllNotes = false }
        await refresh(limit: nil, allNotes: true)
    }

    private func refresh(limit: Int?, allNotes: Bool) async {
        guard let repository = await readyRepository() else { return }
        do {
            let page = try await repository.listWithCount(limit: limit)
            recent = Array(page.records.prefix(5))
            if allNotes { notes = page.records }
            recentProblem = nil
            shareCount(page.count)
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

private enum MacStoreOpenResult: Sendable {
    case opened(SQLiteMemoryRepository)
    case failed(String)
}
