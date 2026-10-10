import DoddyCore
import Foundation

/// Photo files of photo notes (ADR-218), in a `NotePhotos` folder next to the notes database it
/// belongs to, so a test fixture or an in-memory launch never sees, or cleans up, the user's real
/// photos. Protected until the iPhone is first unlocked and, like the notes database (ADR-028),
/// included in iPhone backups. Names come only from `MemoryPhoto.fileName(for:)`. Never shared,
/// uploaded or sent anywhere.
struct PhotoFiles: Sendable {
    /// nil when the notes database couldn't be opened: no photo is written or read.
    let directory: URL?

    static let unavailable = PhotoFiles(directory: nil)

    /// The folder next to a database file.
    static func beside(database url: URL) -> PhotoFiles {
        PhotoFiles(directory: url.deletingLastPathComponent().appendingPathComponent("NotePhotos", isDirectory: true))
    }

    /// A fresh folder for an in-memory database, emptied with the temporary directory.
    static func temporary() -> PhotoFiles {
        PhotoFiles(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("DoddyNotePhotos-\(UUID().uuidString)", isDirectory: true))
    }

    func url(for fileName: String) -> URL? {
        guard let directory, MemoryPhoto.isValidFileName(fileName) else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Writes the file and reads it back; throws when the bytes on disk differ.
    func write(_ jpeg: Data, fileName: String) throws {
        guard let directory else { throw DoddyError.capabilityUnavailable(.memoryStorage) }
        guard let url = url(for: fileName) else { throw PhotoError.badFileName }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try jpeg.write(to: url, options: [.atomic])
        #endif
        guard (try? Data(contentsOf: url)) == jpeg else {
            try? FileManager.default.removeItem(at: url)
            throw MemoryStoreError.verificationFailed
        }
    }

    func data(_ fileName: String) -> Data? {
        url(for: fileName).flatMap { try? Data(contentsOf: $0) }
    }

    func delete(_ fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Files no note points at any more (a crash between steps, or an Undo window that passed).
    func deleteOrphans(keeping linked: Set<String>) {
        guard let directory else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where MemoryPhoto.isValidFileName(name) && !linked.contains(name) {
            delete(name)
        }
    }
}
