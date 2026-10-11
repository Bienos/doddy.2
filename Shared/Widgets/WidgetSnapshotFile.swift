import DoddyCore
import Foundation

/// The widgets' snapshot file (ADR-219) in the App Group folder that only Doddy and its widget
/// extension can open. The group's name is in both Info.plists as `DoddyAppGroup`. A build signed
/// without the App Group has no folder: the app then writes nothing and the widgets say so.
enum WidgetSnapshotFile {
    static let fileName = "widget-snapshot.json"

    static var groupID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DoddyAppGroup") as? String,
              id.hasPrefix("group."), !id.contains("$(") else { return nil }
        return id
    }

    static var url: URL? {
        #if canImport(Darwin)
        groupID
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            .map { $0.appendingPathComponent(fileName, isDirectory: false) }
        #else
        nil // App Groups exist only on Apple platforms; this branch is for the Linux type-check.
        #endif
    }

    static func read() -> WidgetSnapshot? {
        url.flatMap { try? Data(contentsOf: $0) }.flatMap(WidgetSnapshot.decoded)
    }

    /// Writes and reads back; throws when the file on disk isn't the bytes written or doesn't
    /// decode. Bytes, not decoded dates, are compared: a `Date` can read back a hair different
    /// even when the file is exactly right (review I1). Readable
    /// after the first unlock, so Lock Screen widgets can draw; note text there is still hidden
    /// by iOS while the iPhone is locked (`privacySensitive`).
    ///
    /// The read-back compares the bytes, not decoded values (review I1): dates are stored in whole
    /// milliseconds, so a decoded `writtenAt` almost never equals a sub-millisecond `Date.now`,
    /// and a correct write used to count as failed.
    static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let data = try snapshot.encoded()
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        guard let back = try? Data(contentsOf: url), back == data, WidgetSnapshot.decoded(back) != nil else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

extension WidgetSnapshot {
    /// Same switch, pinned notes, reminders, lists, parking spot and picture setting. The time stamp alone isn't news, so the
    /// widgets and the watch aren't sent a snapshot that only says a later time (review I11).
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        isOn == other.isOn && pinned == other.pinned && reminders == other.reminders && lists == other.lists
            && parking == other.parking && hidesDoddy == other.hidesDoddy
    }
}
