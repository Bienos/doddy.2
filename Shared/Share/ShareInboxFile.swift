import DoddyCore
import Foundation

/// The one shared item waiting for the app (ADR-311), in the same App Group folder as the
/// widgets' snapshot. Written by the share extension, taken (read and removed) by the app.
/// A build signed without the App Group has no folder: the extension then says sharing isn't
/// set up, and the app finds nothing.
enum ShareInboxFile {
    /// Which waiting item. A note to save is what "Send to Doddy" leaves. A product link to check the price of
    /// ("Check the price", docs/implementation/SHOPPING.md "Check this") has a file of its own, so one never
    /// replaces the other and an older app, which only knows the note's file, never sees it.
    enum Slot: CaseIterable {
        case note
        case priceCheck

        var fileName: String {
            switch self {
            case .note: "share-inbox.json"
            case .priceCheck: "share-inbox-price-check.json"
            }
        }
    }

    static let fileName = Slot.note.fileName

    static var isAvailable: Bool { url != nil }

    static var url: URL? { url(for: .note) }

    static func url(for slot: Slot) -> URL? {
        #if canImport(Darwin)
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DoddyAppGroup") as? String,
              id.hasPrefix("group."), !id.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent(slot.fileName, isDirectory: false)
        #else
        return nil // App Groups exist only on Apple platforms; this branch is for the Linux type-check.
        #endif
    }

    /// True if an item is already waiting (a new share replaces it).
    static var hasWaitingItem: Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Writes and reads back; throws when the file on disk isn't the item written.
    static func write(_ item: ShareInboxItem, slot: Slot = .note) throws {
        guard let url = url(for: slot) else { throw CocoaError(.fileNoSuchFile) }
        let data = try item.encoded()
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        guard let back = try? Data(contentsOf: url), ShareInboxItem.decoded(back) == item else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// The waiting item, removed from the folder so it is shown once. Nil when there is none, the
    /// file can't be read, or it is too old (it is removed then too).
    static func take(slot: Slot = .note, now: Date = .now) -> ShareInboxItem? {
        guard let url = url(for: slot), let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let item = ShareInboxItem.decoded(data), !item.isStale(now: now) else { return nil }
        return item
    }
}
