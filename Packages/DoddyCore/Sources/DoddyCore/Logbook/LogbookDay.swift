import Foundation

// Logbook, the iPhone's half (ADR-602, docs/product/WEB_LOGBOOK.md; decision
// 2026-11-09-usage-counts-on-by-default). One local day of how the person used Doddy, as counts
// only, in exactly the shape the server's allow-list accepts (`backend/src/web/logbook.ts`, schema
// `doddy.logbook.day.v1`). There is no field for a word anyone said, a note's text, a name, a
// place or an address: the only names that can appear are Doddy's own tool ids, the nine note
// types and short language codes.

public struct LogbookDay: Codable, Equatable, Sendable {
    public static let schemaName = "doddy.logbook.day.v1"
    /// The note types the server accepts (`MemoryCategory` without `list`: lists are counted under lists).
    public static let noteKinds: Set<String> = ["fact", "preference", "commitment", "recommendation", "decision", "item", "place", "intention", "other"]
    /// The largest value the server takes for a count, and for a day's seconds.
    public static let maxCount = 10_000
    public static let maxSeconds = 86_400

    public struct Conversations: Codable, Equatable, Sendable {
        public var count = 0
        public var seconds = 0
        public var byHour = Array(repeating: 0, count: 24)
        public var lengths = Lengths()
        public var ended = Endings()
        public var languages: [String: Int] = [:]
        public var waysIn = WaysIn()

        public init() {}

        enum CodingKeys: String, CodingKey {
            case count, seconds, lengths, ended, languages
            case byHour = "by_hour"
            case waysIn = "ways_in"
        }
    }

    public struct Lengths: Codable, Equatable, Sendable {
        public var under1 = 0, from1To3 = 0, from3To5 = 0, from5To10 = 0
        public init() {}
        enum CodingKeys: String, CodingKey {
            case under1 = "under_1", from1To3 = "1_3", from3To5 = "3_5", from5To10 = "5_10"
        }
        var total: Int { under1 + from1To3 + from3To5 + from5To10 }
    }

    public struct Endings: Codable, Equatable, Sendable {
        public var you = 0, doddy = 0, quiet = 0, dropped = 0
        public init() {}
        var total: Int { you + doddy + quiet + dropped }
    }

    public struct WaysIn: Codable, Equatable, Sendable {
        public var app = 0, backTap = 0, actionButton = 0, widget = 0, siri = 0, island = 0
        public init() {}
        enum CodingKeys: String, CodingKey {
            case app, widget, siri, island
            case backTap = "back_tap"
            case actionButton = "action_button"
        }
        var total: Int { app + backTap + actionButton + widget + siri + island }
    }

    /// One tool's results that day. `undone` counts changes that were made and then undone, so they
    /// are in `done` too.
    public struct Outcomes: Codable, Equatable, Sendable {
        public var done = 0, declined = 0, unsure = 0, failed = 0, undone = 0
        public init() {}
    }

    public struct Notes: Codable, Equatable, Sendable {
        public var bySource = Sources()
        public var byKind: [String: Int] = [:]
        public var edited = 0
        public init() {}
        enum CodingKeys: String, CodingKey {
            case edited
            case bySource = "by_source"
            case byKind = "by_kind"
        }
    }

    public struct Sources: Codable, Equatable, Sendable {
        public var voice = 0, typed = 0, shared = 0, imported = 0
        public init() {}
    }

    public struct Lists: Codable, Equatable, Sendable {
        public var addedVoice = 0, addedTyped = 0, ticked = 0
        public init() {}
        enum CodingKeys: String, CodingKey {
            case ticked
            case addedVoice = "added_voice"
            case addedTyped = "added_typed"
        }
    }

    public struct Errands: Codable, Equatable, Sendable {
        public var handedOver = 0, finished = 0, stopped = 0, minutes = 0, searches = 0, pages = 0
        public init() {}
        enum CodingKeys: String, CodingKey {
            case finished, stopped, minutes, searches, pages
            case handedOver = "handed_over"
        }
    }

    public struct Translator: Codable, Equatable, Sendable {
        public var sessions = 0, minutes = 0
        public init() {}
    }

    public let schema: String
    /// The phone's local calendar day, `YYYY-MM-DD`.
    public let day: String
    public var conversations = Conversations()
    /// Keyed by the voice tool's id (`ToolCatalog`).
    public var tools: [String: Outcomes] = [:]
    public var notes = Notes()
    public var lists = Lists()
    public var errands = Errands()
    public var translator = Translator()

    public init(day: String) {
        schema = Self.schemaName
        self.day = day
    }

    /// The body the server receives: keys sorted, so the same day always reads the same.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Why the server would refuse this day, in the server's own terms (empty when it would take it).
    /// The same checks as `DaySummarySchema` in `backend/src/web/logbook.ts`; a test sends every kind
    /// of refusal through both.
    public func problems(toolNames: Set<String>) -> [String] {
        var found: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { found.append(what) } }
        func inRange(_ value: Int, max: Int = Self.maxCount) -> Bool { value >= 0 && value <= max }

        check(schema == Self.schemaName, "schema")
        check(LogbookCalendar.isCalendarDay(day), "day")

        let c = conversations
        let counts = [c.count] + c.byHour + [c.lengths.under1, c.lengths.from1To3, c.lengths.from3To5, c.lengths.from5To10]
            + [c.ended.you, c.ended.doddy, c.ended.quiet, c.ended.dropped]
            + [c.waysIn.app, c.waysIn.backTap, c.waysIn.actionButton, c.waysIn.widget, c.waysIn.siri, c.waysIn.island]
            + Array(c.languages.values)
        check(counts.allSatisfy { inRange($0) } && inRange(c.seconds, max: Self.maxSeconds), "conversations: a value out of range")
        check(c.byHour.count == 24, "conversations: by_hour needs 24 hours")
        check(c.byHour.reduce(0, +) == c.count, "conversations: hours must add up to the count")
        check(c.lengths.total == c.count, "conversations: lengths must add up to the count")
        check(c.ended.total == c.count, "conversations: endings must add up to the count")
        check(c.languages.values.reduce(0, +) <= c.count, "conversations: languages can't exceed the count")
        check(c.waysIn.total <= c.count, "conversations: ways in can't exceed the count")
        check(c.languages.count <= 12 && c.languages.keys.allSatisfy(LogbookCalendar.isLanguageCode), "conversations: languages")

        check(tools.keys.allSatisfy(toolNames.contains), "tools: a tool Doddy doesn't have")
        check(tools.values.allSatisfy { [$0.done, $0.declined, $0.unsure, $0.failed, $0.undone].allSatisfy { inRange($0) } }, "tools: a value out of range")

        check(notes.byKind.keys.allSatisfy(Self.noteKinds.contains), "notes: a type the server doesn't know")
        let noteCounts = [notes.bySource.voice, notes.bySource.typed, notes.bySource.shared, notes.bySource.imported, notes.edited] + Array(notes.byKind.values)
        check(noteCounts.allSatisfy { inRange($0) }, "notes: a value out of range")

        check([lists.addedVoice, lists.addedTyped, lists.ticked].allSatisfy { inRange($0) }, "lists: a value out of range")
        let e = errands
        check([e.handedOver, e.finished, e.stopped, e.minutes, e.searches, e.pages].allSatisfy { inRange($0) }, "errands: a value out of range")
        check(e.finished + e.stopped <= e.handedOver, "errands: finished and stopped can't exceed handed over")
        check([translator.sessions, translator.minutes].allSatisfy { inRange($0) }, "translator: a value out of range")
        return found
    }
}

/// Day keys and the small format rules both halves share.
public enum LogbookCalendar {
    /// `YYYY-MM-DD` for the day `date` falls on in `calendar`'s time zone.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The day key `days` days before the day `date` falls on.
    public static func dayKey(_ date: Date, daysBefore days: Int, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: date)
        // Noon avoids a daylight-saving change landing the result on the wrong side of midnight.
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        let earlier = calendar.date(byAdding: .day, value: -days, to: noon) ?? noon
        return dayKey(earlier, calendar: calendar)
    }

    /// A real calendar day written `YYYY-MM-DD` (2026-02-30 is not).
    public static func isCalendarDay(_ text: String) -> Bool {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return false }
        return dayKey(date, calendar: gregorian) == text
    }

    /// A short language code as the server takes it: `pl`, `en`, `pt-BR`, `zh-Hans`.
    public static func isLanguageCode(_ code: String) -> Bool {
        code.range(of: #"^[a-z]{2,3}(-[A-Za-z]{2,4})?$"#, options: .regularExpression) != nil
    }
}
