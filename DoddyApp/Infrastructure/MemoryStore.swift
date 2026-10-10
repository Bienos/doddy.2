import DoddyCore
import Foundation
import Observation

/// Main-actor view state over the repository. The list is only ever what the repository
/// returned; it is reloaded after every successful write.
@MainActor
@Observable
final class MemoryStore {
    let environment: AppEnvironment
    private(set) var memories: [MemoryRecord] = []
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    /// Bumped on every reload so searches re-run after edits and deletes.
    private(set) var revision = 0
    /// The note deleted a moment ago, for the Undo bar (ADR-183). Memory only, never stored.
    private(set) var recentlyDeleted: DeletedNote?
    /// Reloaded with the memories: a deleted memory takes its note reminder with it.
    var noteReminders: NoteReminderStore?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isStorageAvailable: Bool { environment.capabilities.isAvailable(.memoryStorage) }

    func record(id: UUID) -> MemoryRecord? { memories.first { $0.id == id } }

    func reload() async {
        do {
            memories = try await environment.memoryRepository.list(limit: nil)
            loadError = nil
        } catch {
            loadError = UserFacingError.message(for: error)
        }
        hasLoaded = true
        revision += 1
        await noteReminders?.reload()
    }

    /// Returns only after the repository confirmed a committed, read-back write.
    /// `capturedAt` is when it was said: now, or the time of the phone call a note came from.
    func save(
        text: String, category: MemoryCategory, source: MemorySource = .explicitText, capturedAt: Date = Date()
    ) async throws -> MemoryRecord {
        let draft = try NewMemory(text: text, category: category, source: source, capturedAt: capturedAt)
        let record = try await environment.memoryRepository.save(draft)
        await reload()
        return record
    }

    func correct(id: UUID, text: String) async throws -> MemoryRecord {
        let record = try await environment.memoryRepository.update(id: id, currentText: text)
        await environment.noteReminders?.refreshContent(forMemory: id)
        await reload()
        return record
    }

    /// The memory's note reminder row is deleted with it (same database); its notification after.
    func delete(id: UUID) async throws {
        let copy = self.record(id: id)
        let reminderID = try? await environment.noteReminders?.reminder(forMemory: id)?.id
        try await environment.memoryRepository.delete(id: id)
        if let reminderID { await environment.noteReminders?.memoryDeleted(reminderID: reminderID) }
        noteReminders?.clearReceipt(memoryID: id)
        recentlyDeleted = copy.map { DeletedNote(record: $0, deletedAt: .now) }
        await reload()
    }

    /// Adds the just-deleted note back exactly as it was (ADR-183). Does nothing once the
    /// undo window has passed. On failure the copy stays until the bar times out.
    func undoDelete(now: Date = .now) async throws {
        guard let deleted = recentlyDeleted, deleted.canUndo(at: now) else {
            recentlyDeleted = nil
            return
        }
        _ = try await environment.memoryRepository.restore([deleted.record])
        if recentlyDeleted == deleted { recentlyDeleted = nil }
        await reload()
    }

    /// The Undo bar timed out: forget the copy.
    func forgetDeleted(_ deleted: DeletedNote) {
        if recentlyDeleted == deleted { recentlyDeleted = nil }
    }

    /// Adds notes from an export; returns only what was committed and read back (ADR-178).
    func restore(_ records: [MemoryRecord]) async throws -> [MemoryRecord] {
        let added = try await environment.memoryRepository.restore(records)
        await reload()
        return added
    }

    /// No undo: deleting everything is final.
    func deleteAll() async throws {
        recentlyDeleted = nil
        try await environment.memoryRepository.deleteAll()
        await environment.noteReminders?.allMemoriesDeleted()
        await reload()
    }

    func recall(_ question: String) async throws -> RecallOutcome {
        try await environment.recallService.recall(question, limit: 20)
    }
}

enum UserFacingError {
    static func message(for error: any Error) -> String {
        if let error = error as? MemoryValidationError {
            switch error {
            case .empty:
                return "Write something first. Empty notes aren't saved."
            case .tooLong(let length, let maximum):
                return "That's \(length) characters; the limit is \(maximum). Nothing was cut and nothing was saved."
            default:
                return "This note can't be saved as it is."
            }
        }
        if let error = error as? MemoryStoreError {
            switch error {
            case .notFound:
                return "That memory no longer exists."
            case .verificationFailed:
                return "The save couldn't be confirmed, so it wasn't counted as saved. Your text is still here."
            case .corruptRecord:
                return "A stored memory couldn't be read. Nothing was deleted."
            }
        }
        if error is DoddyError {
            return "The memory store isn't available on this iPhone right now."
        }
        return "Something went wrong and nothing was changed. (\(error.localizedDescription))"
    }
}

enum DateText {
    static func full(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable"
    }
}
