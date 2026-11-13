import Foundation

/// Files that exist only to be handed to the share sheet: a recording's transcript, the phone and text history.
/// They sit in one folder of their own in the temporary directory, one sub-folder per file so two exports with
/// the same title never replace each other, readable only while the iPhone is unlocked on iOS. The share's end
/// deletes the file (`remove`); a sweep at launch (`removeAll`) deletes what a closed app left behind. Nothing
/// outside that folder is ever deleted here.
///
/// Platforms: iPhone. Foundation only.
public enum TemporaryShareFiles {
    public static let folderName = "SharedFiles"
    /// The longest file name before its extension, in characters.
    public static let maxNameLength = 80

    public static func folder(in base: URL = FileManager.default.temporaryDirectory) -> URL {
        base.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `title` made into a file name: no path separators or characters file systems refuse, no control
    /// characters, no leading dot, not empty, not long. `fallback` when nothing is left.
    public static func fileName(for title: String, fileExtension: String, fallback: String) -> String {
        let refused = Set("/\\:*?\"<>|")
        var stem = String(String.UnicodeScalarView(title.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !refused.contains(Character($0))
        }))
        stem = stem.trimmingCharacters(in: .whitespaces)
        while stem.hasPrefix(".") { stem.removeFirst() }
        stem = String(stem.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        if stem.isEmpty { stem = fallback }
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    /// Writes `data` to `<folder>/<new id>/<file name>` and returns where. Throws what the write throws.
    public static func write(
        _ data: Data, title: String, fileExtension: String, fallback: String,
        in base: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let directory = folder(in: base).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: title, fileExtension: fileExtension, fallback: fallback))
        do {
            try data.write(to: url, options: writeOptions)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return url
    }

    /// Deletes one file made by `write`, with its sub-folder. True when the file is gone; false when it is not
    /// one of ours (nothing outside the share folder is touched) or couldn't be deleted.
    @discardableResult
    public static func remove(_ file: URL, in base: URL = FileManager.default.temporaryDirectory) -> Bool {
        let root = folder(in: base).standardizedFileURL
        let target = file.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else { return false }
        let parent = target.deletingLastPathComponent()
        let isOwnFolder = parent.deletingLastPathComponent().standardizedFileURL.path == root.path
        try? FileManager.default.removeItem(at: isOwnFolder ? parent : target)
        return !FileManager.default.fileExists(atPath: target.path)
    }

    /// Deletes every file made by `write`. True when none is left (also when there was nothing).
    @discardableResult
    public static func removeAll(in base: URL = FileManager.default.temporaryDirectory) -> Bool {
        let root = folder(in: base)
        guard FileManager.default.fileExists(atPath: root.path) else { return true }
        try? FileManager.default.removeItem(at: root)
        return !FileManager.default.fileExists(atPath: root.path)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        // Shared while the iPhone is unlocked; a locked iPhone can't read it (data protection class "complete").
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }
}
