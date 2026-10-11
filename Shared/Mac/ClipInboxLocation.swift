import DoddyCore
import Foundation

/// Where the Mac clip inbox lives (ADR-352): a folder inside the App Group the Mac app, the Mac
/// Share extension and the Safari extension share. Each target's Info.plist has `DoddyAppGroup`
/// (the group's identifier). A build signed without the App Group has no folder: the extensions
/// then say sending to Doddy isn't set up, and the app finds nothing.
enum ClipInboxLocation {
    static let folderName = "clip-inbox"

    /// Nil when the App Group is missing from this build.
    static var directory: URL? {
        #if canImport(Darwin)
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DoddyAppGroup") as? String,
              id.hasPrefix("group."), !id.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent(folderName, isDirectory: true)
        #else
        return nil // App Groups exist only on Apple platforms; this branch is for the Linux parse check.
        #endif
    }

    static var isAvailable: Bool { directory != nil }

    static var inbox: ClipInbox? { directory.map(ClipInbox.init(directory:)) }
}
