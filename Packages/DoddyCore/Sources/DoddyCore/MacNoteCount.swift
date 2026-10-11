import Foundation

// The Mac desktop widget (ADR-439, the owner's review deck, slide 10: "Widget z liczbą zapisanych
// myśli, bez prywatnych treści"). The menu bar app writes how many notes are saved on that Mac,
// and when it counted, to the App Group folder it shares with the widget. A desktop is seen by
// anyone nearby, so the file can hold a number and a time, never a note's words.

public struct MacNoteCount: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let count: Int
    public let countedAt: Date

    public init(count: Int, countedAt: Date) {
        version = Self.currentVersion
        self.count = max(0, count)
        self.countedAt = countedAt
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// `nil` for another version or anything that isn't a count.
    public static func decode(_ data: Data) -> MacNoteCount? {
        guard let value = try? JSONDecoder().decode(MacNoteCount.self, from: data),
              value.version == currentVersion, value.count >= 0 else { return nil }
        return value
    }
}

public enum MacNoteCountFile {
    public static let fileName = "mac-note-count.json"

    /// Writes the count into `folder` and reads it back. True only when what is read is what was
    /// written; the app reloads the widget only then.
    public static func write(_ count: MacNoteCount, in folder: URL) -> Bool {
        let url = folder.appendingPathComponent(fileName)
        guard let data = try? count.encoded(), (try? data.write(to: url, options: .atomic)) != nil else { return false }
        return read(in: folder) == count
    }

    public static func read(in folder: URL) -> MacNoteCount? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return MacNoteCount.decode(data)
    }
}
