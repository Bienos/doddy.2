import DoddyCore
import Foundation

/// The diary (ADR-345) in Application Support/Diary/diary.json, readable only while the iPhone is
/// unlocked (complete file protection), apart from notes. Every add and remove is read back.
enum DiaryStore {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: Diary.enabledKey) }

    static func current() -> Diary {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return Diary() }
        return Diary(stored: data)
    }

    enum Outcome: Equatable {
        case saved(DiaryEntry)
        case problem(DiaryProblem)
        case notSaved
    }

    /// Adds one line for today and reads it back.
    static func add(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Outcome {
        var diary = current()
        switch diary.add(text, now: now, calendar: calendar) {
        case .failure(let problem): return .problem(problem)
        case .success(let entry):
            guard write(diary), current().contains(entry.id) else { return .notSaved }
            return .saved(entry)
        }
    }

    static func remove(_ id: UUID) -> Bool {
        var diary = current()
        diary.remove(id)
        return write(diary) && !current().contains(id)
    }

    /// Deletes the whole diary file.
    static func deleteAll() -> Bool {
        guard let url = fileURL() else { return false }
        try? FileManager.default.removeItem(at: url)
        return current().entries.isEmpty
    }

    private static func write(_ diary: Diary) -> Bool {
        guard let url = fileURL() else { return false }
        do {
            try diary.stored.write(to: url, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    private static func fileURL() -> URL? {
        let fileManager = FileManager.default
        guard let directory = try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Diary", isDirectory: true)
        else { return nil }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                         attributes: [.protectionKey: FileProtectionType.complete])
        return directory.appendingPathComponent("diary.json")
    }
}
