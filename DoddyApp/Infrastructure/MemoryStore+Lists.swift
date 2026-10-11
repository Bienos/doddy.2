import DoddyCore
import Foundation

/// One list change that can be taken back exactly (ADR-216). Undo reverses only this change:
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

    /// A shared list after a sync (ADR-263): exactly the merged name and items, read back.
    @discardableResult
    func replaceShared(_ listID: UUID, with state: SharedListState) async throws -> DoddyList {
        let list = try await environment.listRepository.replaceShared(listID: listID, with: state)
        await listChanged(listID)
        return list
    }

    func renameList(_ listID: UUID, to name: String) async throws {
        _ = try await environment.listRepository.rename(listID: listID, to: name)
        await listChanged(listID)
    }

    /// Takes back exactly the change `undo` describes. Items ticked since an add stay. Throws
    /// `ListUndoError` unless every item came back as it was (read back by the repository), so
    /// nothing says "Undone" for items that weren't (review C10).
    func undoListChange(_ undo: ListUndo) async throws {
        let repository = environment.listRepository
        let expected: [ListItem], reversed: [ListItem]
        switch undo.change {
        case .added(let items):
            let current = Set(list(id: undo.listID)?.open.map(\.id) ?? [])
            (expected, reversed) = (items, try await repository.remove(items.map(\.id).filter(current.contains)))
        case .ticked(let items):
            (expected, reversed) = (items, try await repository.setDone(items.map(\.id), done: false).filter { !$0.isDone })
        case .unticked(let items):
            (expected, reversed) = (items, try await repository.setDone(items.map(\.id), done: true).filter(\.isDone))
        case .removed(let items):
            (expected, reversed) = (items, try await repository.restore(items))
        }
        if listUndo == undo { listUndo = nil }
        await listChanged(undo.listID)
        try ListUndoError.check(expected: expected, reversed: reversed)
    }

    /// Undo from What Doddy did for a list change made by voice (ADR-276): only the items still as
    /// Doddy left them (ActivityUndo.listItemsToUndo), then the list is read back. When a write
    /// throws, a fresh look decides: all still as Doddy left them means nothing was written.
    func undoFromActivity(_ undo: ActivityUndo) async -> UndoResult {
        if case .savedNote(let id, let text) = undo { return await undoSavedNote(id: id, text: text) }
        guard let listID = undo.listID else { return .notDone("That isn't a list change.") }
        await reload()
        guard let items = undo.listItemsToUndo(in: list(id: listID)), !items.isEmpty else { return .leftAlone }
        let repository = environment.listRepository
        do {
            switch undo {
            case .listAdded: _ = try await repository.remove(items.map(\.id))
            case .listTicked: _ = try await repository.setDone(items.map(\.id), done: false)
            case .listRemoved: _ = try await repository.restore(items)
            default: return .notDone("That isn't a list change.")
            }
        } catch {
            await listChanged(listID)
            let still = undo.listItemsToUndo(in: list(id: listID)) ?? []
            return still.count == items.count ? .notDone(UserFacingError.listMessage(for: error)) : .notSure
        }
        await listChanged(listID)
        return undo.listUndoChecks(items, after: list(id: listID)) ? .undone : .notSure
    }

    /// Undo of a note Doddy saved by voice (ADR-277): deleted only while it is exactly as saved,
    /// with nothing added to it; then the store is read again to check it's gone. The notes
    /// screen still offers its own short Undo for the delete, as for any delete.
    private func undoSavedNote(id: UUID, text: String) async -> UndoResult {
        await reload()
        guard let record = record(id: id) else { return .leftAlone }
        let hasReminder: Bool
        do {
            hasReminder = try await environment.noteReminders?.reminder(forMemory: id) != nil
        } catch {
            return .notDone("Doddy couldn't check the note's reminder.")
        }
        guard ActivityUndo.noteUnchanged(
            record, savedText: text, corrections: corrections.filter { $0.memoryID == id }.count,
            hasPhoto: photos[id] != nil, hasRecording: recordings[id] != nil, hasReminder: hasReminder) else {
            return .leftAlone
        }
        do {
            try await delete(id: id)
        } catch {
            await reload()
            return self.record(id: id) == nil ? .notSure : .notDone(UserFacingError.message(for: error))
        }
        return self.record(id: id) == nil ? .undone : .notSure
    }

    private func listChanged(_ listID: UUID) async {
        await reload()
        await environment.noteReminders?.refreshContent(forMemory: listID)
    }
}

extension UserFacingError {
    static func listMessage(for error: any Error) -> String {
        if let undo = error as? ListUndoError { return undo.message }
        guard let error = error as? ListError else { return message(for: error) }
        switch error {
        case .emptyName: return NSLocalizedString("Give the list a name.", comment: "")
        case .nameTooLong(let maximum): return "A list name can be up to \(maximum) characters."
        case .nameTaken(let name): return "You already have a list called “\(name)”."
        case .tooManyLists(let maximum): return "You can have up to \(maximum) lists. Delete one to make another."
        case .notFound: return NSLocalizedString("That list no longer exists.", comment: "")
        case .notANote: return NSLocalizedString("Lists and notes can't be turned into each other.", comment: "")
        }
    }
}

/// Photo notes (ADR-218): the file is written and read back first, then linked to its note.
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

/// Voice memos (ADR-230): the recording is copied in and read back first, then linked to its note.
extension MemoryStore {
    func recording(for memoryID: UUID) -> MemoryAudio? { recordings[memoryID] }

    /// Where the recording is on this iPhone, or nil when its file is missing.
    func recordingURL(_ audio: MemoryAudio) -> URL? {
        guard environment.audioFiles.exists(audio.fileName) else { return nil }
        return environment.audioFiles.url(for: audio.fileName)
    }

    @discardableResult
    func attachRecording(from source: URL, durationMilliseconds: Int, to memoryID: UUID) async throws -> MemoryAudio {
        // As with photos, a note gets a recording only while it has none.
        guard recordings[memoryID] == nil else { throw AudioError.alreadyAttached }
        guard MemoryAudio.isValidDuration(durationMilliseconds) else { throw AudioError.badDuration }
        let fileName = MemoryAudio.fileName(for: memoryID)
        let files = environment.audioFiles
        try await Task.detached(priority: .userInitiated) { try files.store(from: source, fileName: fileName) }.value
        do {
            let audio = try await environment.audioRepository.attach(
                MemoryAudio(memoryID: memoryID, fileName: fileName, durationMilliseconds: durationMilliseconds, addedAt: Date()))
            await reload()
            return audio
        } catch {
            files.delete(fileName)
            throw error
        }
    }

    /// The recording's bytes, for the encrypted backup file (ADR-234). nil when the file is missing.
    func recordingData(_ audio: MemoryAudio) async -> Data? {
        guard let url = recordingURL(audio) else { return nil }
        return await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
    }

    /// A recording from a backup file: written to a temporary file, then attached and read back
    /// exactly like one just recorded. The temporary file is removed either way.
    @discardableResult
    func attachRecording(m4a: Data, durationMilliseconds: Int, to memoryID: UUID) async throws -> MemoryAudio {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DoddyRestore-\(UUID().uuidString).m4a")
        try m4a.write(to: temporary, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: temporary) }
        return try await attachRecording(from: temporary, durationMilliseconds: durationMilliseconds, to: memoryID)
    }

    /// Removes the recording from its note; the note's words stay.
    func removeRecording(from memoryID: UUID) async throws {
        if let removed = try await environment.audioRepository.detach(memoryID: memoryID) {
            environment.audioFiles.delete(removed.fileName)
        }
        await reload()
    }
}

/// Importing notes (ADR-231): notes go in through `restore` (one transaction, read back); a Keep
/// checklist becomes a list with its ticked items ticked, in one transaction read back by the
/// repository, so a failure leaves no half-imported list that Undo would miss (review G5).
extension MemoryStore {
    @discardableResult
    func importList(_ part: NoteImport.ListPart) async throws -> DoddyList {
        let created = try await environment.listRepository.create(
            name: part.name, items: part.open + part.ticked, done: Set(part.ticked), source: .typed)
        await reload()
        return list(id: created.id) ?? created
    }
}

/// Undo of an import (ADR-258): exactly the notes and lists that import added are removed, and
/// the store is reloaded to check they're gone.
extension MemoryStore {
    @discardableResult
    func removeImported(_ ids: [UUID]) async throws -> Int {
        var removed = 0
        for id in ids where record(id: id) != nil {
            try await environment.memoryRepository.delete(id: id)
            removed += 1
        }
        await reload()
        guard ids.allSatisfy({ record(id: $0) == nil }) else { throw MemoryStoreError.verificationFailed }
        return removed
    }
}
