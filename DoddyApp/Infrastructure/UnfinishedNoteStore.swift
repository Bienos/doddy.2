import DoddyCore
import Foundation
import Observation

/// Unfinished notes (OP-042, ADR-362), kept as JSON in the app's protected container so what the
/// user typed survives Doddy being closed or crashing. Every write is read back; when it can't
/// be, the capture screen says so. Never a note: not searched, sent, exported or backed up.
@MainActor
@Observable
final class UnfinishedNoteStore {
    static let shared = UnfinishedNoteStore()
    /// Typing writes this long after the last change; leaving the app or closing the screen writes at once.
    static let writeDelay: Duration = .milliseconds(600)

    private(set) var book = UnfinishedNoteBook()
    /// Why the last write couldn't be confirmed, or why an older file was set aside.
    private(set) var problem: String?
    private let fileURL: URL?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?

    init(fileURL: URL? = UnfinishedNoteStore.defaultURL(), now: Date = .now) {
        self.fileURL = fileURL
        load(now: now)
    }

    /// The capture screen's current words. A screen with no words has no draft.
    func keep(_ note: UnfinishedNote) {
        book.keep(note)
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else { return }
            self?.pendingWrite = nil
            self?.write()
        }
    }

    /// Saved as a note, or discarded. Written at once.
    func remove(id: UUID) {
        book.remove(id: id)
        pendingWrite?.cancel()
        pendingWrite = nil
        write()
    }

    /// Delete everything (Settings): drafts go with the notes, and so does a set-aside file.
    func removeAll() {
        book = UnfinishedNoteBook()
        pendingWrite?.cancel()
        pendingWrite = nil
        write()
        if let aside = asideURL { try? FileManager.default.removeItem(at: aside) }
    }

    /// Doddy is leaving the screen: a write still waiting happens now.
    func flush() {
        guard pendingWrite != nil else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        write()
    }

    private func load(now: Date) {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let read = UnfinishedNoteBook.decoded(data) else {
            // Not written over: kept next to it, in case a later Doddy can read it.
            if let aside = asideURL {
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: fileURL, to: aside)
            }
            problem = NSLocalizedString("An unfinished note from before couldn't be read, so it was set aside on this iPhone, not deleted.", comment: "")
            return
        }
        book = read.pruned(now: now)
        if book != read { write() }
    }

    @discardableResult
    private func write() -> Bool {
        guard let fileURL else {
            problem = NSLocalizedString("Doddy has no place on this iPhone to keep unfinished notes. Save this one before you leave.", comment: "")
            return false
        }
        do {
            if book.notes.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
            } else {
                try book.encoded().write(to: fileURL, options: Self.writeOptions)
                guard let back = try? Data(contentsOf: fileURL), UnfinishedNoteBook.decoded(back) == book else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            problem = nil
            return true
        } catch {
            problem = String(format: NSLocalizedString("Doddy couldn't keep a copy of this unfinished note on this iPhone (%@). Save it before you leave.", comment: ""), error.localizedDescription)
            return false
        }
    }

    private var asideURL: URL? {
        fileURL?.deletingPathExtension().appendingPathExtension("unreadable.json")
    }

    /// Readable only while the iPhone is unlocked: drafts can hold codes and addresses.
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    /// Application Support/Drafts/unfinished-notes.json. UI-test launches get a new file each
    /// time, so one run's draft never fills the next run's capture screen.
    private static func defaultURL() -> URL? {
        let fileManager = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("-inMemoryStore") {
            return fileManager.temporaryDirectory.appendingPathComponent("unfinished-notes-\(UUID().uuidString).json")
        }
        guard let directory = try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Drafts", isDirectory: true)
        else { return nil }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("unfinished-notes.json")
    }
}
