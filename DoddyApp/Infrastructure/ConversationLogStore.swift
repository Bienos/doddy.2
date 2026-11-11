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
    private let readFile: (URL) throws -> Data
    private var unreadableHistory = false

    /// Explicit nil is an in-memory test store; a failed production path is never called durable.
    init(fileURL: URL?, storageUnavailable: Bool = false, readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.fileURL = fileURL
        self.readFile = readFile
        if storageUnavailable {
            unreadableHistory = true
            problem = "Couldn't open the conversation log. New conversations won't be remembered until storage is available."
        } else {
            load()
        }
    }

    convenience init() {
        let url = Self.defaultURL()
        self.init(fileURL: url, storageUnavailable: url == nil)
    }

    /// Settings → "Remember recent conversations". On unless the user switched it off.
    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: PreferenceKey.rememberConversations) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.rememberConversations)
    }

    @discardableResult
    func append(_ log: ConversationLog) -> Bool {
        guard isEnabled, !log.lines.isEmpty else { return false }
        // Do not overwrite a corrupt/unreadable archive with an apparently new empty history.
        // The person's explicit Clear action can still replace it once they review the error.
        guard !unreadableHistory else { return false }
        let kept = Array((logs + [log]).suffix(Self.maxLogs))
        guard save(kept, failure: "Couldn't keep the conversation log.") else { return false }
        logs = kept
        return true
    }

    /// The list empties only after the rewrite was verified. If the write succeeded but its
    /// read-back failed, `problem` reports an unknown outcome and blocks stale later writes.
    @discardableResult
    func clear() -> Bool {
        guard save([], failure: "Couldn't forget the conversations; they are still kept.") else { return false }
        logs = []
        unreadableHistory = false
        return true
    }

    /// Settings → Remembered conversations → Delete. The file is rewritten without it, so it
    /// can't come back as context in a later conversation; the list changes only after that.
    @discardableResult
    func remove(_ id: ConversationLog.ID) -> Bool {
        guard !unreadableHistory else { return false }
        guard logs.contains(where: { $0.id == id }) else { return true }
        let kept = logs.filter { $0.id != id }
        guard save(kept, failure: "Couldn't delete the conversation; it is still kept.") else { return false }
        logs = kept
        return true
    }

    private func load() {
        guard let fileURL else { return }
        do {
            let data = try readFile(fileURL)
            logs = Array(try JSONDecoder().decode([ConversationLog].self, from: data).suffix(Self.maxLogs))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A new installation has no history file yet.
        } catch {
            unreadableHistory = true
            problem = "Couldn't read the conversation log. The file was not changed. (\(error.localizedDescription))"
        }
    }

    /// True when `logs` is what the file now holds (or there is no file to keep them in).
    private func save(_ logs: [ConversationLog], failure: String) -> Bool {
        guard let fileURL else {
            guard !unreadableHistory else {
                problem = failure
                return false
            }
            return true // Explicit in-memory test store.
        }
        var wroteFile = false
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            wroteFile = true
            guard try JSONDecoder().decode([ConversationLog].self, from: readFile(fileURL)) == logs else {
                throw MemoryStoreError.verificationFailed
            }
            problem = nil
            return true
        } catch {
            if wroteFile {
                // The replacement may have succeeded: preserve the unknown outcome and stop
                // later appends from overwriting it with a stale in-memory snapshot.
                unreadableHistory = true
                problem = "Couldn't verify the conversation log. Reopen Doddy to check its current contents."
            } else {
                problem = "\(failure) (\(error.localizedDescription))"
            }
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
