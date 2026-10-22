import Foundation

/// Keeps a copy of a file in the Messages thread's own folder (ADR-594). A copy counts as kept
/// only when it was read back: the file is there and has the size of the original. A copy that
/// can't be proved is removed, and the caller says so; nothing is added to the thread for it.
public struct ChatFileStore: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case sourceMissing
        case notKept
        /// Over `maxBytes`: a thread is not a place for a film.
        case tooBig
    }

    /// The largest file the thread keeps: 25 MB.
    public static let maxBytes = 25 * 1_048_576

    /// The folder that holds the thread: `Files/` is made inside it, and a message's
    /// `relativePath` is relative to it.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var filesDirectory: URL { directory.appendingPathComponent("Files", isDirectory: true) }

    /// Copies `source` as `Files/<id>/<name>` and returns its description for the thread.
    public func keep(copyOf source: URL, named name: String? = nil) throws -> ChatFile {
        let fileManager = FileManager.default
        guard let sourceSize = Self.size(of: source) else { throw Failure.sourceMissing }
        guard sourceSize <= Self.maxBytes else { throw Failure.tooBig }
        let fileName = Self.safeName(name ?? source.lastPathComponent)
        let relative = "Files/\(UUID().uuidString)/\(fileName)"
        let destination = directory.appendingPathComponent(relative)
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            throw Failure.notKept
        }
        guard Self.size(of: destination) == sourceSize else {
            try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            throw Failure.notKept
        }
        return ChatFile(name: fileName, kind: ChatFile.kind(forFileName: fileName), bytes: sourceSize, relativePath: relative)
    }

    /// Keeps bytes that arrived in memory (a photo from the camera) the same way.
    public func keep(data: Data, named name: String) throws -> ChatFile {
        let fileManager = FileManager.default
        guard data.count <= Self.maxBytes else { throw Failure.tooBig }
        let fileName = Self.safeName(name)
        let relative = "Files/\(UUID().uuidString)/\(fileName)"
        let destination = directory.appendingPathComponent(relative)
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: [.atomic])
        } catch {
            try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            throw Failure.notKept
        }
        guard Self.size(of: destination) == data.count else {
            try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            throw Failure.notKept
        }
        return ChatFile(name: fileName, kind: ChatFile.kind(forFileName: fileName), bytes: data.count, relativePath: relative)
    }

    /// Where a message's file lives now.
    public func url(for file: ChatFile) -> URL {
        directory.appendingPathComponent(file.relativePath)
    }

    /// Removes every kept file. Checked: the folder is gone afterwards.
    public func deleteAll() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filesDirectory.path) {
            do { try fileManager.removeItem(at: filesDirectory) } catch { throw Failure.notKept }
        }
        guard !fileManager.fileExists(atPath: filesDirectory.path) else { throw Failure.notKept }
    }

    static func size(of url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.intValue
    }

    /// A file name with no path parts, so a name can never leave its folder.
    static func safeName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let cleaned = last.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "file" : cleaned
    }
}
