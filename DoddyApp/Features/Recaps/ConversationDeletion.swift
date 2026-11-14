import DoddyCore
import Foundation

/// Deleting a remembered conversation together with what was made from it (decision
/// 2026-11-10-local-memory-foundation, "linked deletion").
///
/// The history file is rewritten first. Only then is the conversation tombstoned, so a recap still being
/// written is dropped instead of saved, and the recap note is deleted only if the person chose that.
/// Notes saved before recaps were linked are never matched by date or wording and are left alone.
/// Copies on Doddy's server or at a provider have their own lifecycle and are not touched here.
@MainActor
enum ConversationDeletion {
    enum Outcome: Equatable {
        /// The conversation is gone from this iPhone; its recap note was kept or there was none.
        case deleted
        /// The conversation and its recap note are gone from this iPhone.
        case deletedWithRecap
        /// The history couldn't be rewritten: nothing was deleted.
        case historyNotDeleted
        /// The conversation is gone, but its recap note couldn't be deleted and is still kept.
        case recapNotDeleted
    }

    /// The recap note made from this conversation, if it is still in the notes.
    static func linkedRecapID(for log: ConversationLog, store: MemoryStore,
                              defaults: UserDefaults = .standard) -> UUID? {
        guard let id = RecapKeeper.links(defaults).memoryID(for: log.id), store.record(id: id) != nil else { return nil }
        return id
    }

    static func delete(_ log: ConversationLog, alsoRecap: Bool, logs: ConversationLogStore, memories: MemoryStore,
                       defaults: UserDefaults = .standard) async -> Outcome {
        // Look the note up before anything changes; both steps below run without a suspension in between.
        let recapID = alsoRecap ? linkedRecapID(for: log, store: memories, defaults: defaults) : nil
        guard logs.remove(log.id) else { return .historyNotDeleted }
        RecapKeeper.updateLinks(defaults) { $0.tombstoning([log.id]) }
        if let recapID {
            do {
                try await memories.delete(id: recapID)
            } catch {
                return .recapNotDeleted // Still linked, so the person can try again from Notes.
            }
            RecapKeeper.updateLinks(defaults) { $0.unlinking(conversation: log.id) }
            return .deletedWithRecap
        }
        RecapKeeper.updateLinks(defaults) { $0.unlinking(conversation: log.id) }
        return .deleted
    }

    /// "Forget remembered conversations": the history is cleared, and recaps still being written for
    /// these conversations are dropped. Recap notes already saved stay (the copy says so).
    @discardableResult
    static func clearAll(logs: ConversationLogStore, defaults: UserDefaults = .standard) -> Bool {
        let ids = logs.logs.map(\.id)
        guard logs.clear() else { return false }
        RecapKeeper.updateLinks(defaults) { current in
            ids.reduce(current.tombstoning(ids)) { $0.unlinking(conversation: $1) }
        }
        return true
    }
}
