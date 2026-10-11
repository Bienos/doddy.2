import DoddyCore
import Foundation

/// Recordings of voice memos (ADR-230), in a `NoteAudio` folder next to the notes database it
/// belongs to, so a test fixture or an in-memory launch never sees, or cleans up, the user's real
/// recordings. Protected until the iPhone is first unlocked and, like the notes database
/// (ADR-028), included in iPhone backups. Names come only from `MemoryAudio.fileName(for:)`.
/// Never shared, uploaded or sent anywhere.
struct AudioFiles: Sendable {
    /// nil when the notes database couldn't be opened: no recording is written or read.
    let directory: URL?

    static let unavailable = AudioFiles(directory: nil)

    /// The folder next to a database file.
    static func beside(database url: URL) -> AudioFiles {
        AudioFiles(directory: url.deletingLastPathComponent().appendingPathComponent("NoteAudio", isDirectory: true))
    }

    /// A fresh folder for an in-memory database, emptied with the temporary directory.
    static func temporary() -> AudioFiles {
        AudioFiles(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("DoddyNoteAudio-\(UUID().uuidString)", isDirectory: true))
    }

    func url(for fileName: String) -> URL? {
        guard let directory, MemoryAudio.isValidFileName(fileName) else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Copies a finished recording in and reads it back; throws when the bytes on disk differ.
    func store(from source: URL, fileName: String) throws {
        guard let directory else { throw DoddyError.capabilityUnavailable(.memoryStorage) }
        guard let url = url(for: fileName) else { throw AudioError.badFileName }
        let data = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        guard (try? Data(contentsOf: url)) == data else {
            try? FileManager.default.removeItem(at: url)
            throw MemoryStoreError.verificationFailed
        }
    }

    func exists(_ fileName: String) -> Bool {
        url(for: fileName).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func delete(_ fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Files no note points at any more (a crash between steps, or an Undo window that passed).
    func deleteOrphans(keeping linked: Set<String>) {
        guard let directory else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where MemoryAudio.isValidFileName(name) && !linked.contains(name) {
            delete(name)
        }
    }
}
