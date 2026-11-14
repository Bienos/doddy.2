import Foundation

/// The last few timing lines of an Action Button press, kept on the iPhone so they can be read without a Mac
/// (decision `2026-11-14-start-timing-on-the-phone`). The log lines (`talk start launch`, `talk start timing`,
/// `voice first audible sound after start`) are only readable in Console.app with the phone connected to a
/// Mac; this keeps the same lines, and Settings › About › Advanced › Start timing shows them and copies them.
///
/// Privacy, enforced here and not only by the callers: a line is kept only if it starts with one of the three
/// fixed openings and holds nothing but letters, digits, spaces and a few marks (`. : · ( ) - ,`), so no
/// address, name, number from a person, text or quote can be written into it, and it is at most
/// `maxLineLength` characters. Only seconds and the fixed words of the stages. It never leaves the iPhone: no
/// code sends it anywhere, and "Erase everything on this iPhone" removes it (`DevicePreferences`).
///
/// Plain Swift in DoddyCore, tested on Linux. Used by the iPhone app; the Watch and Mac apps (paused) don't.
public struct StartTimingJournal: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let at: Date
        public let text: String

        public init(at: Date, text: String) {
            self.at = at
            self.text = text
        }
    }

    /// The fixed openings a line must have. Each is what one of the three log lines starts with.
    public static let openings = [
        "talk start launch: ",
        "talk start timing: ",
        "voice first audible sound after start: ",
    ]
    /// About six presses of three lines each.
    public static let capacity = 18
    public static let maxLineLength = 300

    /// Oldest first.
    public private(set) var entries: [Entry]

    public init() {
        entries = []
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Whether `text` may be kept: one of the fixed openings, only the allowed characters, not too long.
    public static func accepts(_ text: String) -> Bool {
        guard text.count <= maxLineLength, openings.contains(where: { text.hasPrefix($0) }) else { return false }
        return text.unicodeScalars.allSatisfy(Self.isAllowed)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a" ... "z", "A" ... "Z", "0" ... "9", " ", ".", ":", "\u{00B7}", "(", ")", "-", ",": true
        default: false
        }
    }

    /// Adds a line at the end, dropping the oldest ones past `capacity`. Returns false, and keeps nothing, for a
    /// line that isn't one of ours (`accepts`).
    @discardableResult
    public mutating func record(_ text: String, at date: Date) -> Bool {
        guard Self.accepts(text) else { return false }
        entries.append(Entry(at: date, text: text))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        return true
    }

    /// The lines as one text to paste, oldest first: "13:05:41  talk start launch: …", one per line. Empty when
    /// there is nothing. `timeZone` is the iPhone's own unless a test says otherwise.
    public func copyText(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return entries.map { "\(formatter.string(from: $0.at))  \($0.text)" }.joined(separator: "\n")
    }

    // MARK: Storage

    /// What is stored; nil if it can't be encoded.
    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// The journal from what is stored. Nothing, or something this build can't read, is an empty journal; lines
    /// that fail `accepts` are dropped, so a damaged or hand-edited value can't show anything else.
    public static func decode(_ data: Data?) -> StartTimingJournal {
        guard let data, let stored = try? JSONDecoder().decode(StartTimingJournal.self, from: data) else { return StartTimingJournal() }
        var journal = StartTimingJournal()
        for entry in stored.entries { journal.record(entry.text, at: entry.at) }
        return journal
    }
}
