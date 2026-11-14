import Foundation

// The file side of "Erase everything on this iPhone": a folder's contents are removed and read back from the file
// system, whatever a model in memory believes. A folder or file that isn't there is already empty. Removing
// continues past a failure, so one stuck file doesn't keep the others, and the failure is reported. A symbolic link
// is removed as the link it is, never followed.

public enum FolderErasure {
    public enum Failure: Error, Equatable, Sendable {
        /// This many entries could not be removed (the rest were).
        case couldNotRemove(Int)
        case couldNotRead
    }

    /// Removes everything inside `folder`, hidden entries too, except the entry names in `keeping`. The folder itself
    /// stays (its protection class and "excluded from backup" mark stay with it).
    public static func eraseContents(of folder: URL, keeping: Set<String> = [], fileManager: FileManager = .default) throws {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            // Missing is empty. A folder that exists but can't be listed is not.
            if !fileManager.fileExists(atPath: folder.path) { return }
            throw Failure.couldNotRead
        }
        var failed = 0
        for name in names where !keeping.contains(name) {
            do {
                try fileManager.removeItem(at: folder.appendingPathComponent(name))
            } catch {
                failed += 1
            }
        }
        if failed > 0 { throw Failure.couldNotRemove(failed) }
    }

    /// True when `folder` holds nothing, ignoring the names in `ignoring`. A folder that isn't there is empty.
    public static func isEmpty(_ folder: URL, ignoring: Set<String> = [], fileManager: FileManager = .default) throws -> Bool {
        guard fileManager.fileExists(atPath: folder.path) else { return true }
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { throw Failure.couldNotRead }
        return names.allSatisfy { ignoring.contains($0) }
    }

    /// Removes one file or folder; one that isn't there is fine.
    public static func eraseFile(_ url: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: url.path) || isLink(url, fileManager) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw Failure.couldNotRemove(1)
        }
    }

    /// True when nothing is at `url`.
    public static func fileIsGone(_ url: URL, fileManager: FileManager = .default) -> Bool {
        !fileManager.fileExists(atPath: url.path) && !isLink(url, fileManager)
    }

    /// A link whose target is gone isn't "there" for `fileExists`, but it is still an entry.
    private static func isLink(_ url: URL, _ fileManager: FileManager) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
