import Foundation

// A voice diary (ADR-345). Off until the user turns it on. A line is added only when the user asks
// ("add to my diary: …") and taps Save on the card, or types it on the Diary screen. Doddy never
// asks how their day was, keeps no streaks and never nudges. The diary stays on this iPhone in its
// own file (complete file protection), apart from notes: it isn't given to the voice agent,
// search, Siri, widgets, Spotlight or the watch, and the voice agent can add to it but not read it.

public struct DiaryEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// The local day it belongs to, "YYYY-MM-DD".
    public let day: String
    public let text: String
    public let savedAt: Date

    public init(id: UUID = UUID(), day: String, text: String, savedAt: Date) {
        self.id = id
        self.day = day
        self.text = text
        self.savedAt = savedAt
    }
}

public enum DiaryProblem: Error, Equatable, Sendable {
    case empty, tooLong, full
}

public struct Diary: Codable, Equatable, Sendable {
    public static let enabledKey = "diary.enabled"
    public static let maxLength = 500
    public static let limit = 10_000
    public private(set) var entries: [DiaryEntry] = []

    public init() {}

    public init(stored: Data?) {
        self = stored.flatMap { try? JSONDecoder().decode(Diary.self, from: $0) } ?? Diary()
    }

    public var stored: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// The line as written, trimmed, for today's day.
    public static func checked(_ text: String) -> Result<String, DiaryProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxLength else { return .failure(.tooLong) }
        return .success(trimmed)
    }

    public static func day(_ date: Date, calendar: Calendar) -> String { LeaveBy.day(date, calendar: calendar) }

    public mutating func add(_ text: String, now: Date, calendar: Calendar) -> Result<DiaryEntry, DiaryProblem> {
        switch Self.checked(text) {
        case .failure(let problem): return .failure(problem)
        case .success(let line):
            guard entries.count < Self.limit else { return .failure(.full) }
            let entry = DiaryEntry(day: Self.day(now, calendar: calendar), text: line, savedAt: now)
            entries.append(entry)
            return .success(entry)
        }
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    /// Newest day first; within a day, in the order written.
    public var days: [(day: String, entries: [DiaryEntry])] {
        Dictionary(grouping: entries, by: \.day)
            .map { ($0.key, $0.value.sorted { $0.savedAt < $1.savedAt }) }
            .sorted { $0.0 > $1.0 }
    }

    public func contains(_ id: UUID) -> Bool { entries.contains { $0.id == id } }
}

extension VoiceToolName {
    public static let addToDiary = "add_to_diary"
}

extension VoiceToolRequest {
    static func parseDiary(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let text = args.text("text") else { return .invalid(name: name, reason: "missing text") }
        switch Diary.checked(text) {
        case .failure(.tooLong): return .invalid(name: name, reason: "text is longer than \(Diary.maxLength) characters")
        case .failure: return .invalid(name: name, reason: "missing text")
        case .success(let line): return .addToDiary(text: line)
        }
    }
}

extension VoiceToolReply {
    public static func diarySaved(_ entry: DiaryEntry) -> String {
        "saved: the line was added to the user's diary for \(entry.day), exactly as on the card. Say so in a few words; don't comment on what they wrote unless they ask."
    }

    public static let diaryDeclined = "declined: the user chose not to add it. Nothing was saved."
    public static let diaryFailed = "failed: the line couldn't be saved on this iPhone. Nothing was saved."
}
