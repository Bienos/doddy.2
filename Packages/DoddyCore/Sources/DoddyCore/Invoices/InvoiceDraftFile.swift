import Foundation

// The invoice draft kept on this iPhone between conversations (ADR-668). One file, JSON, in the
// app's own container: written whole, read back and compared before the voice agent is told it is
// kept; never sent anywhere, never backed up (the app excludes the folder), readable only while the
// iPhone is unlocked (`.completeFileProtection` on iOS). Closing the card and Delete all remove it.
// A file that can't be read is set aside next to it, not written over, and the person is told.
//
// Platforms: iPhone and iPad. Foundation only; tested on Linux with real files.

public struct InvoiceDraftFile: Sendable {
    public enum Loaded: Equatable, Sendable {
        case none
        case draft(InvoiceVoiceSession)
        /// The file was there but couldn't be read; it was moved aside, not deleted.
        case setAside
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Application Support/Invoices/invoice-draft.json, the folder excluded from backups.
    public static func inApplicationSupport(fileManager: FileManager = .default) -> InvoiceDraftFile? {
        guard var directory = try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Invoices", isDirectory: true)
        else { return nil }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if canImport(Darwin)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        #endif
        return InvoiceDraftFile(url: directory.appendingPathComponent("invoice-draft.json"))
    }

    var asideURL: URL { url.deletingPathExtension().appendingPathExtension("unreadable.json") }

    /// Writes the draft and reads it back. True only when what is on disk is this draft.
    @discardableResult
    public func save(_ session: InvoiceVoiceSession) -> Bool {
        guard session.operation != nil else { return remove() }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(session).write(to: url, options: Self.writeOptions)
            return read() == session
        } catch {
            return false
        }
    }

    /// The kept draft, if any.
    public func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        if let session = read(), session.operation != nil { return .draft(session) }
        try? FileManager.default.removeItem(at: asideURL)
        try? FileManager.default.moveItem(at: url, to: asideURL)
        return .setAside
    }

    /// Removes the draft (and a set-aside copy). True when neither is there any more.
    @discardableResult
    public func remove() -> Bool {
        let fileManager = FileManager.default
        for file in [url, asideURL] where fileManager.fileExists(atPath: file.path) {
            try? fileManager.removeItem(at: file)
        }
        return !fileManager.fileExists(atPath: url.path) && !fileManager.fileExists(atPath: asideURL.path)
    }

    private func read() -> InvoiceVoiceSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(InvoiceVoiceSession.self, from: data)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }
}
