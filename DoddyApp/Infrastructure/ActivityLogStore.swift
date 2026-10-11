import DoddyCore
import Foundation
import Observation

/// "What Doddy did": every look-up and change the voice agent asked for, with what actually
/// happened. Kept as JSON in the app's protected container, newest first, 30 days or 300 entries
/// (ActivityLog). Shown in Settings, cleared with one tap. Clearing never touches Reminders or
/// any other app.
@MainActor
@Observable
final class ActivityLogStore {
    static let shared = ActivityLogStore()

    private(set) var entries: [ActivityEntry] = []
    private(set) var problem: String?
    private let fileURL: URL?

    init(fileURL: URL? = ActivityLogStore.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    func append(_ entry: ActivityEntry) {
        entries = ActivityLog.appending(entry, to: entries, now: Date())
        save()
    }

    func replace(_ entry: ActivityEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    /// Settles unsure note and list entries from Doddy's own notes and lists (ADR-302). Call only
    /// once the store has loaded: empty lists here would read as "not there".
    func settleLocal(notes: [MemoryRecord], lists: [DoddyList]) {
        let settled = LocalCheck.settledAll(entries, notes: notes, lists: lists, at: Date())
        guard settled != entries else { return }
        entries = settled
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let stored = (try? JSONDecoder().decode([ActivityEntry].self, from: data)) ?? []
        // Anything still "in progress" from the last run was cut off; it is never shown as done.
        let now = Date()
        entries = ActivityLog.pruned(ActivityLog.recoverInterrupted(stored, at: now), now: now)
        if entries != stored { save() }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            problem = nil
        } catch {
            problem = "Couldn't keep the activity list. (\(error.localizedDescription))"
        }
    }

    /// Application Support/Activity/activity.json, readable after first unlock only.
    private static func defaultURL() -> URL? {
        let fileManager = FileManager.default
        guard let directory = try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Activity", isDirectory: true)
        else { return nil }
        try? fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory.appendingPathComponent("activity.json")
    }
}
