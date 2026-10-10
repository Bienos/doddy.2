import Foundation

// Morning brief (ADR-212): the day at a glance, once a day, when the user turns it on.
// Built on the iPhone from what Home → Today already reads (Calendar and Reminders, only with
// their Connections switches on) and Doddy's own note reminders. Nothing is sent anywhere.
// The daily notification says only that the brief is ready: no titles or notes on the Lock Screen.
// Wording is plain and neutral: counts and times, no pressure, no praise, no guessing.

/// When the brief appears. Off unless the user turns it on.
public struct MorningBriefSchedule: Equatable, Sendable {
    public static let defaultHour = 7
    public static let defaultMinute = 30
    /// How long after its time the brief stays at the top of Home (never past the end of the day).
    public static let showingHours = 5

    public var isOn: Bool
    public let hour: Int
    public let minute: Int

    /// Out-of-range values fall back to the default time.
    public init(isOn: Bool, hour: Int = defaultHour, minute: Int = defaultMinute) {
        self.isOn = isOn
        let valid = (0...23).contains(hour) && (0...59).contains(minute)
        self.hour = valid ? hour : Self.defaultHour
        self.minute = valid ? minute : Self.defaultMinute
    }

    /// Today's brief time in `calendar`'s zone.
    public func start(on now: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// Whether Home shows the brief now: on, from its time for `showingHours` (until midnight at
    /// the latest), and not already closed today.
    public func isShowing(now: Date, dismissedDay: String?, calendar: Calendar) -> Bool {
        guard isOn, dismissedDay != Self.dayKey(now, calendar: calendar),
              let start = start(on: now, calendar: calendar) else { return false }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let end = min(start.addingTimeInterval(Double(Self.showingHours) * 3600), endOfDay)
        return now >= start && now < end
    }

    /// "2026-10-10" in `calendar`'s zone: which day the user closed the brief.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The daily local notification. Same text every day, so nothing personal is on the Lock Screen
/// and nothing has to be worked out in the background.
public enum MorningBriefNotification {
    public static let identifier = "doddy.brief.daily"
    public static let title = "Morning brief"
    public static let body = "Your day at a glance is ready in Doddy."

    public static func isBrief(_ identifier: String) -> Bool { identifier == Self.identifier }
}

/// What the user chose to have in the brief (Settings → Morning brief → In your brief, ADR-213).
/// What's on the iPhone is in by default; anything fetched from a server is out until chosen.
public struct MorningBriefSections: Equatable, Sendable {
    public var events: Bool
    public var reminders: Bool
    public var noteReminders: Bool
    /// Today's daily news digest from Doddy's server.
    public var news: Bool
    /// Todoist tasks due today or earlier, through Doddy's server.
    public var todoist: Bool
    /// Unread Gmail from the last day, through Doddy's server: sender and subject only.
    public var gmail: Bool
    /// Gmail: only mail Gmail marks important.
    public var gmailImportantOnly: Bool

    public init(events: Bool = true, reminders: Bool = true, noteReminders: Bool = true,
                news: Bool = false, todoist: Bool = false, gmail: Bool = false, gmailImportantOnly: Bool = false) {
        self.events = events
        self.reminders = reminders
        self.noteReminders = noteReminders
        self.news = news
        self.todoist = todoist
        self.gmail = gmail
        self.gmailImportantOnly = gmailImportantOnly
    }

    public static let standard = MorningBriefSections()

    /// Calendar or Reminders need reading at all.
    public var readsDevice: Bool { events || reminders }
    public var readsServer: Bool { news || todoist || gmail }
}

/// One section fetched from a server for the brief.
public enum BriefFetch<Value: Equatable & Sendable>: Equatable, Sendable {
    /// Not chosen in Settings: nothing was fetched.
    case notIncluded
    /// Chosen but can't be read: not set up, not connected or switched off. Says why.
    case unavailable(String)
    /// Tried and failed this time. Says why.
    case failed(String)
    case loaded(Value)
}

/// Emails or tasks as the server listed them, and whether they are a test server's demo data.
public struct BriefOnlineList: Equatable, Sendable {
    public let items: [ResultItem]
    public let truncated: Bool
    public let isDemo: Bool

    public init(items: [ResultItem], truncated: Bool, isDemo: Bool) {
        self.items = items
        self.truncated = truncated
        self.isDemo = isDemo
    }
}

/// What the server-backed sections returned (all `.notIncluded` by default).
public struct BriefOnline: Equatable, Sendable {
    public var news: BriefFetch<[NewsDigest.Item]>
    public var todoist: BriefFetch<BriefOnlineList>
    public var gmail: BriefFetch<BriefOnlineList>

    public init(news: BriefFetch<[NewsDigest.Item]> = .notIncluded,
                todoist: BriefFetch<BriefOnlineList> = .notIncluded,
                gmail: BriefFetch<BriefOnlineList> = .notIncluded) {
        self.news = news
        self.todoist = todoist
        self.gmail = gmail
    }

    public static let none = BriefOnline()
}

/// A note reminder that fires later today, with the note's current words.
public struct BriefNoteReminder: Equatable, Sendable {
    public let fireAt: Date
    public let noteText: String

    public init(fireAt: Date, noteText: String) {
        self.fireAt = fireAt
        self.noteText = noteText
    }
}

/// What the brief could read.
public enum BriefSource: Equatable, Sendable {
    /// Calendar and/or Reminders were read (each `nil` when its switch is off or iOS blocks it).
    case agenda(TodayAgenda, calendarRead: Bool, remindersRead: Bool)
    /// Calendar and Reminders are both off or blocked.
    case notConnected
    /// Settings → Pause all is on.
    case paused
}

public struct MorningBrief: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case greeting, events, reminders, noteReminders, notice, news, newsItem, todoist, gmail
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        /// A news story's link, opened only when the user taps it.
        public let url: String?

        public init(kind: Kind, text: String, url: String? = nil) {
            self.kind = kind
            self.text = text
            self.url = url
        }
    }

    public let lines: [Line]

    /// Everything in one paragraph, for reading aloud.
    public var spokenText: String { lines.map(\.text).joined(separator: " ") }

    static let namedItems = 3

    /// `timeText` formats a time of day ("10:00"); the app passes the user's locale.
    public static func compose(
        source: BriefSource, noteReminders: [BriefNoteReminder], name: String?,
        now: Date, calendar: Calendar, timeText: (Date) -> String,
        sections: MorningBriefSections = .standard, online: BriefOnline = .none
    ) -> MorningBrief {
        var lines: [Line] = []
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(Line(kind: .greeting, text: (cleanName?.isEmpty == false) ? "Good morning, \(cleanName!)." : "Good morning."))

        if sections.readsDevice {
            switch source {
            case .paused:
                lines.append(Line(kind: .notice, text: "Connections are paused, so your calendar and reminders aren't in this brief."))
            case .notConnected:
                lines.append(Line(kind: .notice, text: "Calendar and Reminders are off in Settings, Connections, so they aren't in this brief."))
            case .agenda(let agenda, let calendarRead, let remindersRead):
                if sections.events {
                    lines.append(calendarRead
                        ? Line(kind: .events, text: eventsText(agenda, timeText: timeText))
                        : Line(kind: .notice, text: "Calendar is off, so events aren't in this brief."))
                }
                if sections.reminders {
                    lines.append(remindersRead
                        ? Line(kind: .reminders, text: remindersText(agenda, now: now, calendar: calendar))
                        : Line(kind: .notice, text: "Reminders is off, so your reminders aren't in this brief."))
                }
            }
        }

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let later = !sections.noteReminders ? [] : noteReminders
            .filter { $0.fireAt >= now && $0.fireAt < endOfDay }
            .sorted { ($0.fireAt, $0.noteText) < ($1.fireAt, $1.noteText) }
        if !later.isEmpty {
            let shown = later.prefix(namedItems).map { "at \(timeText($0.fireAt)), “\(clip($0.noteText))”" }
            let more = later.count > namedItems ? ", and \(later.count - namedItems) more" : ""
            lines.append(Line(
                kind: .noteReminders,
                text: "\(later.count == 1 ? "A note reminder" : "\(later.count) note reminders") today: \(list(Array(shown)))\(more)."))
        }

        lines += onlineLines(online)
        return MorningBrief(lines: lines)
    }

    static func onlineLines(_ online: BriefOnline) -> [Line] {
        var lines: [Line] = []
        switch online.todoist {
        case .notIncluded: break
        case .unavailable(let why): lines.append(Line(kind: .notice, text: "Todoist isn't in this brief: \(why)"))
        case .failed(let why): lines.append(Line(kind: .notice, text: "Couldn't get your Todoist tasks just now. \(why)"))
        case .loaded(let result):
            let tasks = result.items.filter { $0.kind == .task }
            let names = tasks.prefix(namedItems).map { clip($0.title) + ($0.urgent ? " (priority 1)" : "") }
            let text = tasks.isEmpty
                ? "No Todoist tasks due today."
                : "\(count(tasks.count, "Todoist task", "Todoist tasks")) for today: \(list(Array(names)))\(moreText(tasks.count, truncated: result.truncated, where: "in Todoist"))."
            lines.append(Line(kind: .todoist, text: demoPrefix(result) + text))
        }
        switch online.gmail {
        case .notIncluded: break
        case .unavailable(let why): lines.append(Line(kind: .notice, text: "Gmail isn't in this brief: \(why)"))
        case .failed(let why): lines.append(Line(kind: .notice, text: "Couldn't check Gmail just now. \(why)"))
        case .loaded(let result):
            let emails = result.items.filter { $0.kind == .email }
            let shown = emails.prefix(namedItems).map { "“\(clip($0.title))” from \(senderName($0.from))" }
            let text = emails.isEmpty
                ? "No unread email from the last day."
                : "\(count(emails.count, "unread email", "unread emails")) from the last day: \(list(Array(shown)))\(moreText(emails.count, truncated: result.truncated, where: "in Gmail"))."
            lines.append(Line(kind: .gmail, text: demoPrefix(result) + text))
        }
        switch online.news {
        case .notIncluded: break
        case .unavailable(let why): lines.append(Line(kind: .notice, text: "Daily news isn't in this brief: \(why)"))
        case .failed(let why): lines.append(Line(kind: .notice, text: "Couldn't get today's news just now. \(why)"))
        case .loaded(let items):
            if items.isEmpty {
                lines.append(Line(kind: .news, text: "No daily news digest yet today."))
            } else {
                lines.append(Line(kind: .news, text: "From your daily news:"))
                for item in items.prefix(namedItems) {
                    lines.append(Line(kind: .newsItem, text: "\(clip(item.line, max: 200)) (\(clip(item.source, max: 40)))", url: item.url))
                }
            }
        }
        return lines
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "One \(one)" : "\(n) \(many)"
    }

    /// ", and 2 more" past the named items, or ", and more in Gmail" when the server cut the list.
    static func moreText(_ n: Int, truncated: Bool, where place: String) -> String {
        if truncated { return ", and more \(place)" }
        return n > namedItems ? ", and \(n - namedItems) more" : ""
    }

    /// Demo data from a test server is never presented as the user's.
    static func demoPrefix(_ result: BriefOnlineList) -> String {
        result.isDemo ? "Demo data, not your account: " : ""
    }

    /// "Anna Demo <anna@demo.example>" → "Anna Demo"; an address alone stays as it is.
    static func senderName(_ from: String?) -> String {
        guard let from = from?.trimmingCharacters(in: .whitespaces), !from.isEmpty else { return "an unknown sender" }
        if let open = from.firstIndex(of: "<") {
            let name = from[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return clip(name, max: 40) }
            return clip(String(from[from.index(after: open)...]).trimmingCharacters(in: CharacterSet(charactersIn: ">")), max: 60)
        }
        return clip(from, max: 60)
    }

    static func eventsText(_ agenda: TodayAgenda, timeText: (Date) -> String) -> String {
        let total = agenda.events.count + agenda.moreEvents
        guard total > 0 else { return "No events left in your calendar today." }
        let allDay = agenda.events.filter(\.allDay)
        let timed = agenda.events.filter { !$0.allDay }
        var parts: [String] = []
        if !allDay.isEmpty {
            parts.append("all day, \(list(allDay.prefix(namedItems).map { clip($0.title) }))")
        }
        if let first = timed.first {
            if timed.count == 1 {
                parts.append("\(clip(first.title)) at \(timeText(first.start))")
            } else {
                parts.append("first \(clip(first.title)) at \(timeText(first.start))")
            }
        }
        let count = total == 1 ? "One event left today" : "\(total) events left today"
        return parts.isEmpty ? "\(count)." : "\(count): \(parts.joined(separator: "; "))."
    }

    static func remindersText(_ agenda: TodayAgenda, now: Date, calendar: Calendar) -> String {
        let total = agenda.reminders.count + agenda.moreReminders
        guard total > 0 else { return "No reminders due today." }
        let earlier = agenda.reminders.filter { TodayAgenda.isOverdue($0, now: now, calendar: calendar) && !isToday($0, now: now, calendar: calendar) }
        let names = agenda.reminders.prefix(namedItems).map { clip($0.title) }
        let more = total > names.count ? ", and \(total - names.count) more" : ""
        var text = "\(total == 1 ? "One reminder" : "\(total) reminders") due: \(list(Array(names)))\(more)."
        if !earlier.isEmpty {
            text += earlier.count == 1 ? " One is from an earlier day." : " \(earlier.count) are from earlier days."
        }
        return text
    }

    private static func isToday(_ reminder: ReminderSummary, now: Date, calendar: Calendar) -> Bool {
        reminder.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    /// Long titles and notes are shortened for the brief only (the note itself is never changed).
    static func clip(_ text: String, max: Int = 80) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > max ? String(flat.prefix(max - 1)) + "…" : flat
    }
}

/// Fetches the server-backed sections the user chose (ADR-213). Each read is the same one the voice
/// agent can make, with the same switch, connection check, limits and server receipt; read only,
/// never retried here. Nothing is fetched for a section that isn't chosen.
public enum MorningBriefFetcher {
    public static let gmailMax = 5

    /// Unread inbox mail from the last day; with `importantOnly`, only what Gmail marks important.
    public static func gmailQuery(importantOnly: Bool) -> String {
        importantOnly ? "in:inbox is:unread is:important newer_than:1d" : "in:inbox is:unread newer_than:1d"
    }

    public static func gmail(_ client: (any OnlineAccountsClient)?, importantOnly: Bool, timeZone: String) async -> BriefFetch<BriefOnlineList> {
        await run(client, CloudToolCall(
            name: CloudToolName.checkEmail,
            arguments: ["query": .string(gmailQuery(importantOnly: importantOnly)), "max": .number(Double(gmailMax))]),
            timeZone: timeZone)
    }

    /// Due today or earlier (Todoist's "today | overdue").
    public static func todoist(_ client: (any OnlineAccountsClient)?, timeZone: String) async -> BriefFetch<BriefOnlineList> {
        await run(client, CloudToolCall(name: CloudToolName.listTodoistTasks, arguments: ["when": .string("today")]), timeZone: timeZone)
    }

    /// Server answers that mean "can't be read until the user changes something", not "try again".
    static let unavailableCodes: Set<String> = [
        "not_connected", "permission_insufficient", "connection_expired", "capability_disabled", "live_not_configured",
    ]

    static func run(_ client: (any OnlineAccountsClient)?, _ call: CloudToolCall, timeZone: String) async -> BriefFetch<BriefOnlineList> {
        guard let client else {
            return .unavailable("Doddy's server for online accounts isn't set up in Settings.")
        }
        do {
            let result = try await client.run(call, timeZone: timeZone, approvalId: nil)
            guard let items = result.items else {
                return .failed("Doddy's server is an older version that can't list them here.")
            }
            return .loaded(BriefOnlineList(items: items, truncated: result.truncated, isDemo: result.mode == .mock))
        } catch {
            if case .notConfigured = error {
                return .unavailable("Doddy's server for online accounts isn't set up in Settings.")
            }
            if let code = error.code, unavailableCodes.contains(code) {
                return .unavailable("\(error.userMessage) Check Settings, Online accounts.")
            }
            return .failed(error.userMessage)
        }
    }

    /// Today's newest digest that has stories (in `calendar`'s zone), or an empty list.
    public static func news(_ digests: @Sendable () async throws -> [NewsDigest], now: Date, calendar: Calendar) async -> BriefFetch<[NewsDigest.Item]> {
        do {
            let today = try await digests()
                .filter { digest in
                    !digest.items.isEmpty && (digest.createdDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
                }
                .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            return .loaded(today.first?.items ?? [])
        } catch {
            return .failed("Doddy's server couldn't be reached.")
        }
    }
}
