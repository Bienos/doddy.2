import DoddyCore
import Foundation
import Observation

/// The Mac app's state (ADR-351): notes, lists and the clips waiting from the Share menu and
/// Safari (ADR-352). Every write returns only after the repository read it back; a clip leaves the
/// inbox only after the note made from it was saved.
@MainActor
@Observable
final class MacStore {
    let environment: MacEnvironment
    private(set) var notes: [MemoryRecord] = []
    private(set) var lists: [DoddyList] = []
    private(set) var clips: [ShareInboxItem] = []
    private(set) var loadError: String?
    private(set) var hasLoaded = false
    /// Counts each successful reload, so a screen showing a search can look again when data changed.
    private(set) var revision = 0
    /// Set when a note was saved from a clip but the clip's file could not be removed. The clip is
    /// hidden for this session so it can't be saved twice; the message says what to do.
    private(set) var clipProblem: String?
    @ObservationIgnored private var savedClipIDs: Set<UUID> = []

    /// What the sidebar shows.
    var section: MacSection? = .notes
    /// The new-note window (⌘N, the toolbar and the menu bar item all set this).
    var newNote: NewNoteRequest?

    init(environment: MacEnvironment) {
        self.environment = environment
    }

    var isStorageAvailable: Bool { environment.storageProblem == nil }

    // MARK: Loading

    func reload() async {
        if let problem = environment.storageProblem {
            loadError = problem
            return
        }
        do {
            // Read everything first, so a failed read changes nothing.
            let stored = try await environment.memoryRepository.list(limit: nil).filter { $0.category != .list }
            let storedLists = try await environment.listRepository.lists()
            notes = stored
            lists = storedLists
            loadError = nil
            hasLoaded = true
            revision += 1
        } catch {
            loadError = MacError.message(for: error)
        }
    }

    /// Looks in the clip inbox. Called when the app starts and each time it comes to the front.
    func refreshClips() {
        guard let inbox = ClipInboxLocation.inbox else { clips = []; return }
        clips = inbox.waiting().filter { !savedClipIDs.contains($0.id) }
    }

    // MARK: Notes

    @discardableResult
    func save(text: String, category: MemoryCategory, source: MemorySource = .explicitText) async throws -> MemoryRecord {
        let draft = try NewMemory(text: text, category: category, source: source, capturedAt: Date())
        let record = try await environment.memoryRepository.save(draft)
        await reload()
        return record
    }

    func correct(id: UUID, text: String) async throws {
        _ = try await environment.memoryRepository.update(id: id, currentText: text)
        await reload()
    }

    func setCategory(id: UUID, to category: MemoryCategory) async throws {
        _ = try await environment.memoryRepository.setCategory(id: id, to: category)
        await reload()
    }

    func delete(id: UUID) async throws {
        try await environment.memoryRepository.delete(id: id)
        await reload()
    }

    /// Notes matching a search, best first; every note when the search is empty. Words with a
    /// leading # or @ pick tags and people (ADR-333, ADR-341).
    func notes(matching query: String) async -> [MemoryRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        if let tag = NoteTags.tagQuery(trimmed) { return NoteTags.filter(notes, tag: tag) }
        if let person = NotePeople.personQuery(trimmed) { return NotePeople.notes(notes, about: person) }
        guard case .matches(let found)? = try? await environment.recallService.recall(trimmed, limit: 100) else { return [] }
        return found.map(\.record).filter { $0.category != .list }
    }

    // MARK: Clips

    /// Saves a waiting clip as a note and, only after that is read back, removes it from the inbox.
    @discardableResult
    func saveClip(_ clip: ShareInboxItem, text: String, category: MemoryCategory) async throws -> MemoryRecord {
        let record = try await save(text: text, category: category, source: .sharedContent)
        discardClip(clip, savedAsNote: true)
        return record
    }

    func discardClip(_ clip: ShareInboxItem, savedAsNote: Bool = false) {
        guard let inbox = ClipInboxLocation.inbox else { return }
        if inbox.remove(id: clip.id) {
            clipProblem = nil
        } else if savedAsNote {
            savedClipIDs.insert(clip.id)
            clipProblem = NSLocalizedString("The note was saved, but its clip couldn't be cleared from the inbox. It is hidden for now; you can delete the clip file in Settings › Extensions.", comment: "")
        } else {
            clipProblem = NSLocalizedString("That clip couldn't be thrown away. Try again.", comment: "")
        }
        refreshClips()
    }

    // MARK: Lists

    func createList(name: String, items: [String]) async throws -> DoddyList {
        let list = try await environment.listRepository.create(name: name, items: items, source: .typed)
        await reload()
        return list
    }

    func addToList(_ texts: [String], listID: UUID) async throws -> ListAddResult {
        let result = try await environment.listRepository.add(texts, to: listID, source: .typed)
        await reload()
        return result
    }

    func setDone(_ item: ListItem, done: Bool) async throws {
        _ = try await environment.listRepository.setDone([item.id], done: done)
        await reload()
    }

    func removeFromList(_ item: ListItem) async throws {
        _ = try await environment.listRepository.remove([item.id])
        await reload()
    }

    func clearTicked(listID: UUID) async throws {
        _ = try await environment.listRepository.clearDone(listID: listID)
        await reload()
    }

    func renameList(_ id: UUID, to name: String) async throws {
        _ = try await environment.listRepository.rename(listID: id, to: name)
        await reload()
    }

    func deleteList(_ id: UUID) async throws {
        try await environment.memoryRepository.delete(id: id)
        await reload()
    }
}

enum MacSection: Hashable {
    case notes, lists, clips, voice
}

/// A request to open the new-note window, optionally pre-filled and tied to a clip.
struct NewNoteRequest: Identifiable, Equatable {
    let id = UUID()
    var text = ""
    var clip: ShareInboxItem?
}

enum MacError {
    static func message(for error: any Error) -> String {
        if let error = error as? MemoryValidationError {
            switch error {
            case .empty:
                return NSLocalizedString("Write something first. Empty notes aren't saved.", comment: "")
            case .tooLong(let length, let maximum):
                return String(format: NSLocalizedString("That's %lld characters; the limit is %lld. Nothing was cut and nothing was saved.", comment: ""), length, maximum)
            default:
                return NSLocalizedString("This note can't be saved as it is.", comment: "")
            }
        }
        if let error = error as? MemoryStoreError {
            switch error {
            case .notFound:
                return NSLocalizedString("That note no longer exists.", comment: "")
            case .verificationFailed:
                return NSLocalizedString("The save couldn't be confirmed, so it wasn't counted as saved. Your text is still here.", comment: "")
            case .corruptRecord:
                return NSLocalizedString("A stored note couldn't be read. Nothing was deleted.", comment: "")
            }
        }
        if let error = error as? ListError {
            switch error {
            case .emptyName: return NSLocalizedString("Give the list a name.", comment: "")
            case .nameTooLong(let maximum): return String(format: NSLocalizedString("A list name can have up to %lld characters.", comment: ""), maximum)
            case .nameTaken: return NSLocalizedString("You already have a list with that name.", comment: "")
            case .tooManyLists(let maximum): return String(format: NSLocalizedString("Doddy keeps up to %lld lists.", comment: ""), maximum)
            case .notFound: return NSLocalizedString("That list no longer exists.", comment: "")
            case .notANote: return NSLocalizedString("This can't be changed as it is.", comment: "")
            }
        }
        if error is DoddyError {
            return NSLocalizedString("The notes file isn't available on this Mac right now.", comment: "")
        }
        return String(format: NSLocalizedString("Something went wrong and nothing was changed. (%@)", comment: ""), error.localizedDescription)
    }
}
