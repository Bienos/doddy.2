import DoddyCore
import Foundation
import Observation

/// Files Doddy made on this iPhone in a voice conversation, kept for a week so Messages can offer them again
/// ("Files Doddy made for you"). The deck from `make_presentation` is written to a temporary folder that iOS and
/// `PresentationFiles` clear within a day (ADR-567), so a copy is kept here: Application Support/MadeFiles/<id>/<name>
/// and an index (`index.json`), both readable after first unlock only. A copy counts as kept only when it reads back
/// byte for byte. Nothing leaves the iPhone and nothing is added to the saved thread.
@MainActor
@Observable
final class LocalMadeFilesStore {
    static let shared = LocalMadeFilesStore()

    private(set) var files: [LocalMadeFile] = []
    /// The last thing that could not be kept or deleted, in words. Nil when nothing failed.
    private(set) var problem: String?
    private let directory: URL?

    init(directory: URL? = LocalMadeFilesStore.defaultDirectory()) {
        self.directory = directory
        load()
        removeExpired(now: Date())
    }

    /// Copies the file in and reads the copy back. True only when the copy is complete and listed.
    @discardableResult
    func add(copying source: URL, title: String, kind: String, now: Date = Date()) -> Bool {
        guard let directory else { return false }
        let entry = LocalMadeFile(name: source.lastPathComponent, title: title, kind: kind, createdAt: now)
        let folder = directory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(entry.name)
        do {
            let original = try Data(contentsOf: source)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try original.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            guard (try? Data(contentsOf: target)) == original else {
                try? FileManager.default.removeItem(at: folder)
                problem = NSLocalizedString("The file couldn't be kept for Messages.", comment: "Messages: a made file could not be copied")
                return false
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            problem = NSLocalizedString("The file couldn't be kept for Messages.", comment: "Messages: a made file could not be copied")
            return false
        }
        let updated = files + [entry]
        guard saveIndex(updated) else {
            try? FileManager.default.removeItem(at: folder)
            problem = NSLocalizedString("The file couldn't be kept for Messages.", comment: "Messages: a made file could not be copied")
            return false
        }
        files = updated
        problem = nil
        removeExpired(now: now)
        return true
    }

    /// Where a listed file is, or nil when its bytes are gone (then it is dropped from the list).
    func url(for file: LocalMadeFile) -> URL? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(file.id.uuidString, isDirectory: true).appendingPathComponent(file.name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            _ = remove(file.id)
            return nil
        }
        return url
    }

    /// The list changes only after the index was rewritten without it; the bytes are deleted then. False when it
    /// could not be rewritten, so nothing is claimed gone.
    @discardableResult
    func remove(_ id: LocalMadeFile.ID) -> Bool {
        guard files.contains(where: { $0.id == id }) else { return true }
        let kept = files.filter { $0.id != id }
        guard saveIndex(kept) else {
            problem = NSLocalizedString("The file couldn't be deleted; it is still kept.", comment: "Messages: a made file could not be deleted")
            return false
        }
        files = kept
        if let directory { try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString, isDirectory: true)) }
        problem = nil
        return true
    }

    /// "Erase everything on this iPhone": the index is rewritten empty, then every file's folder goes. False when the index
    /// couldn't be rewritten, so nothing is claimed gone. The list changes only after that, as in `remove`.
    @discardableResult
    func removeAll() -> Bool {
        guard saveIndex([]) else {
            problem = NSLocalizedString("The file couldn't be deleted; it is still kept.", comment: "Messages: a made file could not be deleted")
            return false
        }
        let old = files
        files = []
        if let directory {
            for file in old { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file.id.uuidString, isDirectory: true)) }
        }
        problem = nil
        return true
    }

    private func removeExpired(now: Date) {
        for old in LocalMadeFiles.expired(files, now: now) { remove(old.id) }
    }

    private var indexURL: URL? { directory?.appendingPathComponent("index.json") }

    private func load() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return }
        files = (try? JSONDecoder().decode([LocalMadeFile].self, from: data)) ?? []
    }

    private func saveIndex(_ list: [LocalMadeFile]) -> Bool {
        guard let indexURL else { return false }
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return (try? JSONDecoder().decode([LocalMadeFile].self, from: Data(contentsOf: indexURL))) == list
        } catch {
            return false
        }
    }

    /// Application Support/MadeFiles.
    private static func defaultDirectory() -> URL? {
        let manager = FileManager.default
        guard let directory = try? manager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MadeFiles", isDirectory: true)
        else { return nil }
        try? manager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }
}
