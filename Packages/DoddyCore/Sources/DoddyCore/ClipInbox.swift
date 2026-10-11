import Foundation

// The clip inbox (ADR-352): where the Mac Share extension and the Safari extension leave what the
// user sent to Doddy. A folder of small files, one per clip, in the App Group folder shared with the
// Mac app. Extensions can't open Doddy's database, so they only add a file; the Mac app lists the
// waiting clips and saves one only when the user presses Save. Several clips can wait at once; a
// new one never replaces an older one. The folder is given to this type, so it is tested with an
// ordinary temporary folder.

public struct ClipInbox: Sendable {
    /// No more than this many wait at once; the extension then says the inbox is full.
    public static let maxWaiting = 20
    static let fileExtension = "clip"

    public enum AddOutcome: Equatable, Sendable {
        case added
        case full
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Leaves one clip and reads it back; throws when what is on disk isn't the clip written.
    public func add(_ item: ShareInboxItem, now: Date = .now) throws -> AddOutcome {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard waiting(now: now).count < Self.maxWaiting else { return .full }
        let url = fileURL(for: item.id)
        try item.encoded().write(to: url, options: [.atomic])
        guard let back = try? Data(contentsOf: url), ShareInboxItem.decoded(back) == item else {
            try? manager.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        return .added
    }

    /// The clips waiting, oldest first. A clip too old to show (never saved) and a file that can't
    /// be read as a clip are removed here; nothing else in the folder is touched.
    public func waiting(now: Date = .now) -> [ShareInboxItem] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return [] }
        var items: [ShareInboxItem] = []
        for name in names where name.hasSuffix(".\(Self.fileExtension)") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), let item = ShareInboxItem.decoded(data), !item.isStale(now: now) else {
                try? manager.removeItem(at: url)
                continue
            }
            items.append(item)
        }
        return items.sorted { ($0.sharedAt, $0.id.uuidString) < ($1.sharedAt, $1.id.uuidString) }
    }

    /// Removes one clip after it was saved or the user threw it away. True when it is gone.
    @discardableResult
    public func remove(id: UUID) -> Bool {
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
        return !FileManager.default.fileExists(atPath: url.path)
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)", isDirectory: false)
    }
}
