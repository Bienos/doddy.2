import DoddyCore
import Foundation

/// The widgets' snapshot file (ADR-226) in the App Group folder that only Doddy and its widget
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

    /// Writes and reads back; throws when the file on disk isn't the snapshot written. Readable
    /// after the first unlock, so Lock Screen widgets can draw; note text there is still hidden
    /// by iOS while the iPhone is locked (`privacySensitive`).
    static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let data = try snapshot.encoded()
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        guard let back = try? Data(contentsOf: url), WidgetSnapshot.decoded(back) == snapshot else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
