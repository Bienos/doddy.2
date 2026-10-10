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
    }

    /// Returns only after the repository confirmed a committed, read-back write.
    func save(text: String, category: MemoryCategory, source: MemorySource = .explicitText) async throws -> MemoryRecord {
        let draft = try NewMemory(text: text, category: category, source: source, capturedAt: Date())
        let record = try await environment.memoryRepository.save(draft)
        await reload()
        return record
    }

    func correct(id: UUID, text: String) async throws -> MemoryRecord {
        let record = try await environment.memoryRepository.update(id: id, currentText: text)
        await reload()
        return record
    }

    func delete(id: UUID) async throws {
        try await environment.memoryRepository.delete(id: id)
        await reload()
    }

    /// Adds notes from an export; returns only what was committed and read back (ADR-135).
    func restore(_ records: [MemoryRecord]) async throws -> [MemoryRecord] {
        let added = try await environment.memoryRepository.restore(records)
        await reload()
        return added
    }

    func deleteAll() async throws {
        try await environment.memoryRepository.deleteAll()
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
