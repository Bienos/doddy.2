import DoddyCore
import Foundation

/// The one file the app writes and Doddy's widgets read (ADR-215), in the App Group set by the
/// DODDY_APP_GROUP build setting. Compiled into the app and the widget extension. Only the app
/// writes; the widgets only read.
enum WidgetSnapshotFile {
    static let infoKey = "DoddyAppGroup"
    static let fileName = "widget-snapshot.json"

    enum ReadResult: Equatable {
        /// No App Group in this build: the note widgets can't get anything from the app.
        case notSetUp
        /// Set up, but the app hasn't written the file yet (not opened since install) or it's unreadable.
        case notWritten
        case snapshot(WidgetSnapshot)
    }

    /// nil when the build has no App Group (the setting is empty or wasn't substituted).
    static var appGroup: String? {
        guard let value = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
            .trimmingCharacters(in: .whitespaces), !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var url: URL? {
        guard let appGroup,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return directory.appendingPathComponent(fileName)
    }

    static func read() -> ReadResult {
        guard let url else { return .notSetUp }
        guard let data = try? Data(contentsOf: url), let snapshot = WidgetSnapshot.decode(data) else { return .notWritten }
        return .snapshot(snapshot)
    }

    /// Atomic write, readable after first unlock (widgets draw while the iPhone is locked).
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url, let data = try? snapshot.encoded() else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
