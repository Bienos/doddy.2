import DoddyCore
import Foundation
import Observation

/// The last few voice conversations, kept as JSON in the app's protected container so Doddy can
/// continue where it left off. Bounded, shown in Settings, switched off or cleared with one tap.
/// Lines come from the SDK's text events; no audio is kept. Logs never become memory records.
@MainActor
@Observable
final class ConversationLogStore {
    static let shared = ConversationLogStore()
    static let maxLogs = 10

    private(set) var logs: [ConversationLog] = []
    private(set) var problem: String?
    private let fileURL: URL?

    init(fileURL: URL? = ConversationLogStore.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    /// Settings → "Remember recent conversations". On unless the user switched it off.
    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: PreferenceKey.rememberConversations) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.rememberConversations)
    }

    func append(_ log: ConversationLog) {
        guard isEnabled, !log.lines.isEmpty else { return }
        logs.append(log)
        if logs.count > Self.maxLogs {
            logs.removeFirst(logs.count - Self.maxLogs)
        }
        _ = save(logs, failure: "Couldn't keep the conversation log.")
    }

    /// The list empties only after the file was rewritten; otherwise `problem` says they're kept
    /// (review G6), so a failed write can't look deleted and come back on relaunch.
    @discardableResult
    func clear() -> Bool {
        guard save([], failure: "Couldn't forget the conversations; they are still kept.") else { return false }
        logs = []
        return true
    }

    /// Settings → Remembered conversations → Delete. The file is rewritten without it, so it
    /// can't come back as context in a later conversation; the list changes only after that.
    @discardableResult
    func remove(_ id: ConversationLog.ID) -> Bool {
        guard logs.contains(where: { $0.id == id }) else { return true }
        let kept = logs.filter { $0.id != id }
        guard save(kept, failure: "Couldn't delete the conversation; it is still kept.") else { return false }
        logs = kept
        return true
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        logs = (try? JSONDecoder().decode([ConversationLog].self, from: data)) ?? []
    }

    /// True when `logs` is what the file now holds (or there is no file to keep them in).
    private func save(_ logs: [ConversationLog], failure: String) -> Bool {
        guard let fileURL else { return true }
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            problem = nil
            return true
        } catch {
            problem = "\(failure) (\(error.localizedDescription))"
            return false
        }
    }

    /// Application Support/Conversations/recent.json, readable after first unlock only.
    private static func defaultURL() -> URL? {
        let fileManager = FileManager.default
        guard let directory = try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Conversations", isDirectory: true)
        else { return nil }
        try? fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory.appendingPathComponent("recent.json")
    }
}
