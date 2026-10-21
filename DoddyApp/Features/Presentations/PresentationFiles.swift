import DoddyCore
import Foundation

/// Where the presentations Doddy makes are written (ADR-563): Doddy's own temporary folder, one
/// folder per file so two decks with the same title never overwrite each other. iOS clears it in
/// time, and Doddy removes folders older than a day; the user keeps a deck by saving it in Keynote
/// or Files from the share sheet. Nothing here leaves the iPhone.
enum PresentationFiles {
    enum Failure: LocalizedError {
        case notReadBack

        var errorDescription: String? {
            switch self {
            case .notReadBack: "The file couldn't be read back after saving it."
            }
        }
    }

    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Presentations", isDirectory: true)
    }

    /// Writes the file and reads it back. Returns its address only when every byte is there.
    static func write(_ draft: PresentationDraft, created: Date) throws -> URL {
        removeOld(now: created)
        let data = try PresentationFile.pptx(draft, created: created)
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(draft.fileName)
        try data.write(to: url, options: .atomic)
        guard (try? Data(contentsOf: url)) == data else { throw Failure.notReadBack }
        return url
    }

    /// Folders from earlier days. A failure here doesn't stop a new deck.
    private static func removeOld(now: Date) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for old in folders {
            let created = (try? old.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? now
            if now.timeIntervalSince(created) > 24 * 3600 { try? manager.removeItem(at: old) }
        }
    }
}
