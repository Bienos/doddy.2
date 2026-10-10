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
        save()
    }

    func clear() {
        logs = []
        save()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        logs = (try? JSONDecoder().decode([ConversationLog].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            problem = nil
        } catch {
            problem = "Couldn't keep the conversation log. (\(error.localizedDescription))"
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
