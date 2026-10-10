import DoddyCore
import Foundation

/// One list change that can be taken back exactly (ADR-223). Undo reverses only this change:
/// added items are removed if still open, ticks are unticked, removed items are put back.
struct ListUndo: Equatable, Identifiable {
    enum Change: Equatable {
        case added([ListItem])
        case ticked([ListItem])
        case unticked([ListItem])
        case removed([ListItem])
    }

    let id = UUID()
    let listID: UUID
    let change: Change
    /// "Added eggs, 2 packs of bananas", shown on the receipt.
    let message: String
}

/// Lists on the main actor. Every method returns only after the repository read its change back;
/// the screen then reloads from the store, and a list's waiting reminder is rewritten.
extension MemoryStore {
    func createList(name: String, items: [String], source: ListItemSource) async throws -> DoddyList {
        let list = try await environment.listRepository.create(name: name, items: items, source: source)
        await reload()
        return list
    }

    @discardableResult
    func addToList(_ texts: [String], listID: UUID, source: ListItemSource) async throws -> ListAddResult {
        let result = try await environment.listRepository.add(texts, to: listID, source: source)
        if !result.added.isEmpty {
            listUndo = ListUndo(listID: listID, change: .added(result.added), message: "Added \(result.added.map(\.text).joined(separator: ", "))")
        }
        await listChanged(listID)
        return result
    }

    @discardableResult
    func setDone(_ items: [ListItem], done: Bool, listID: UUID) async throws -> [ListItem] {
        let changed = try await environment.listRepository.setDone(items.map(\.id), done: done)
        if !changed.isEmpty {
            listUndo = ListUndo(
                listID: listID, change: done ? .ticked(changed) : .unticked(changed),
                message: "\(done ? "Ticked" : "Unticked") \(changed.map(\.text).joined(separator: ", "))")
        }
        await listChanged(listID)
        return changed
    }

    @discardableResult
    func removeFromList(_ items: [ListItem], listID: UUID) async throws -> [ListItem] {
        let removed = try await environment.listRepository.remove(items.map(\.id))
        if !removed.isEmpty {
            listUndo = ListUndo(listID: listID, change: .removed(removed), message: "Removed \(removed.map(\.text).joined(separator: ", "))")
        }
        await listChanged(listID)
        return removed
    }

    func clearTicked(listID: UUID) async throws {
        let removed = try await environment.listRepository.clearDone(listID: listID)
        if !removed.isEmpty {
            listUndo = ListUndo(listID: listID, change: .removed(removed), message: "Removed \(removed.count) ticked item\(removed.count == 1 ? "" : "s")")
        }
        await listChanged(listID)
    }

    func untickAll(listID: UUID) async throws {
        let changed = try await environment.listRepository.untickAll(listID: listID)
        if !changed.isEmpty {
            listUndo = ListUndo(listID: listID, change: .unticked(changed), message: "Unticked \(changed.count) item\(changed.count == 1 ? "" : "s")")
        }
        await listChanged(listID)
    }

    func renameList(_ listID: UUID, to name: String) async throws {
        _ = try await environment.listRepository.rename(listID: listID, to: name)
        await listChanged(listID)
    }

    /// Takes back exactly the change `undo` describes. Items ticked since an add stay.
    func undoListChange(_ undo: ListUndo) async throws {
        let repository = environment.listRepository
        switch undo.change {
        case .added(let items):
            let current = Set(list(id: undo.listID)?.open.map(\.id) ?? [])
            _ = try await repository.remove(items.map(\.id).filter(current.contains))
        case .ticked(let items):
            _ = try await repository.setDone(items.map(\.id), done: false)
        case .unticked(let items):
            _ = try await repository.setDone(items.map(\.id), done: true)
        case .removed(let items):
            _ = try await repository.restore(items)
        }
        if listUndo == undo { listUndo = nil }
        await listChanged(undo.listID)
    }

    private func listChanged(_ listID: UUID) async {
        await reload()
        await environment.noteReminders?.refreshContent(forMemory: listID)
    }
}

extension UserFacingError {
    static func listMessage(for error: any Error) -> String {
        guard let error = error as? ListError else { return message(for: error) }
        switch error {
        case .emptyName: return "Give the list a name."
        case .nameTooLong(let maximum): return "A list name can be up to \(maximum) characters."
        case .nameTaken(let name): return "You already have a list called “\(name)”."
        case .tooManyLists(let maximum): return "You can have up to \(maximum) lists. Delete one to make another."
        case .notFound: return "That list no longer exists."
        case .notANote: return "Lists and notes can't be turned into each other."
        }
    }
}

/// Photo notes (ADR-225): the file is written and read back first, then linked to its note.
extension MemoryStore {
    func photo(for memoryID: UUID) -> MemoryPhoto? { photos[memoryID] }

    func photoData(_ photo: MemoryPhoto) async -> Data? {
        let files = environment.photoFiles
        return await Task.detached(priority: .userInitiated) { files.data(photo.fileName) }.value
    }

    @discardableResult
    func attachPhoto(jpeg: Data, width: Int, height: Int, to memoryID: UUID) async throws -> MemoryPhoto {
        // The file name comes from the note's id, so writing over an existing photo and then
        // failing would lose it. A note gets a photo only while it has none.
        guard photos[memoryID] == nil else { throw PhotoError.alreadyAttached }
        let fileName = MemoryPhoto.fileName(for: memoryID)
        try environment.photoFiles.write(jpeg, fileName: fileName)
        do {
            let photo = try await environment.photoRepository.attach(
                MemoryPhoto(memoryID: memoryID, fileName: fileName, width: width, height: height, addedAt: Date()))
            await reload()
            return photo
        } catch {
            environment.photoFiles.delete(fileName)
            throw error
        }
    }

    /// Removes the photo from its note; the note's words stay.
    func removePhoto(from memoryID: UUID) async throws {
        if let removed = try await environment.photoRepository.detach(memoryID: memoryID) {
            environment.photoFiles.delete(removed.fileName)
        }
        await reload()
    }
}
