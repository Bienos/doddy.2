import Foundation

// "What Doddy did" (docs/design/SETTINGS_AND_CONNECTIONS.md §5): every look-up and every change
// the voice agent asked for, with what actually happened. Kept on this iPhone only.

public enum ActivityApp: String, Codable, CaseIterable, Sendable {
    case memories, calendar, reminders, contacts, timers, maps, shortcuts, messages
    case gmail, drive, notion, todoist

    public var title: String {
        switch self {
        case .memories: "Notes"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .timers: "Timers"
        case .maps: "Maps"
        case .shortcuts: "Shortcuts"
        case .messages: "Messages and email"
        case .gmail: "Gmail"
        case .drive: "Google Drive"
        case .notion: "Notion"
        case .todoist: "Todoist"
        }
    }
}

public enum ActivityOutcome: String, Codable, Sendable {
    /// A look-up that returned an answer (possibly "nothing found").
    case lookedUp
    /// A change Doddy made and checked.
    case done
    /// Doddy found it was already there and added nothing.
    case alreadyThere
    /// Another app was opened; Doddy can't see what happened next.
    case opened
    /// Doddy couldn't confirm whether the change happened.
    case notSure
    case notDone
    case declined

    public var text: String {
        switch self {
        case .lookedUp: "Looked up"
        case .done: "Done"
        case .alreadyThere: "Already there, nothing added"
        case .opened: "Opened"
        case .notSure: "Not sure it happened"
        case .notDone: "Didn't happen"
        case .declined: "You said no"
        }
    }
}

/// What the agent asked for, before anything happened.
public struct ActivityRequest: Equatable, Sendable {
    public let app: ActivityApp
    /// Short verb phrase, e.g. "Add reminder".
    public let title: String
    /// The specifics, e.g. "“Buy milk” · due 17 Oct 2026, 09:00".
    public let detail: String?
    public let isLookup: Bool
    /// Set for reminders, so "Check" can look for exactly this reminder later.
    public let reminderKey: String?

    public init(app: ActivityApp, title: String, detail: String?, isLookup: Bool, reminderKey: String? = nil) {
        self.app = app
        self.title = title
        self.detail = detail
        self.isLookup = isLookup
        self.reminderKey = reminderKey
    }

    /// Nil for requests that never reach an app (unsupported or invalid tool calls).
    public static func describe(_ request: VoiceToolRequest, calendar: Calendar) -> ActivityRequest? {
        func when(_ date: Date, hasTime: Bool) -> String { VoiceToolReply.localText(date, hasTime: hasTime, calendar: calendar) }
        switch request {
        case .searchMemories(let query):
            return ActivityRequest(app: .memories, title: "Searched your notes", detail: "“\(query)”", isLookup: true)
        case .saveMemory(let text):
            return ActivityRequest(app: .memories, title: "Save a note", detail: "“\(text)”", isLookup: false)
        case .readCalendar(let range):
            return ActivityRequest(
                app: .calendar, title: "Read your calendar",
                detail: "\(when(range.start, hasTime: false)) to \(when(range.end, hasTime: false))", isLookup: true)
        case .createCalendarEvent(let draft):
            let time = draft.allDay ? "\(when(draft.start, hasTime: false)), all day" : when(draft.start, hasTime: true)
            return ActivityRequest(app: .calendar, title: "Add event", detail: "“\(draft.title)” · \(time)", isLookup: false)
        case .createReminder(let draft):
            let due = draft.due.map { " · due \(when($0, hasTime: draft.dueHasTime))" } ?? ""
            return ActivityRequest(
                app: .reminders, title: "Add reminder", detail: "“\(draft.title)”\(due)", isLookup: false,
                reminderKey: ReminderKey.key(for: draft, calendar: calendar))
        case .lookupContact(let name):
            return ActivityRequest(app: .contacts, title: "Looked for a contact", detail: "“\(name)”", isLookup: true)
        case .setTimer(let draft):
            let minutes = draft.seconds / 60, seconds = draft.seconds % 60
            let length = minutes > 0 ? "\(minutes) min\(seconds > 0 ? " \(seconds) s" : "")" : "\(seconds) s"
            return ActivityRequest(app: .timers, title: "Start timer", detail: [draft.label.map { "“\($0)”" }, length].compactMap { $0 }.joined(separator: " · "), isLookup: false)
        case .openMap(let place):
            return ActivityRequest(app: .maps, title: "Open in Maps", detail: "“\(place)”", isLookup: false)
        case .runShortcut(let name):
            return ActivityRequest(app: .shortcuts, title: "Run shortcut", detail: "“\(name)”", isLookup: false)
        case .draftMessage(let draft):
            let kind = draft.channel == .text ? "text" : "email"
            return ActivityRequest(app: .messages, title: "Draft a \(kind)", detail: "to \(draft.recipientName)", isLookup: false)
        case .cloudTool(let call):
            return describe(cloud: call.name)
        case .unsupported, .invalid:
            return nil
        }
    }

    /// Online-account calls: names only. Email subjects, file names and task text are not kept.
    static func describe(cloud name: String) -> ActivityRequest? {
        switch name {
        case CloudToolName.checkEmail: ActivityRequest(app: .gmail, title: "Checked email", detail: nil, isLookup: true)
        case CloudToolName.draftEmail: ActivityRequest(app: .gmail, title: "Create an email draft", detail: nil, isLookup: false)
        case CloudToolName.findDriveFile: ActivityRequest(app: .drive, title: "Looked for a file", detail: nil, isLookup: true)
        case CloudToolName.searchNotion: ActivityRequest(app: .notion, title: "Searched Notion", detail: nil, isLookup: true)
        case CloudToolName.listTodoistTasks: ActivityRequest(app: .todoist, title: "Read your tasks", detail: nil, isLookup: true)
        case CloudToolName.addTodoistTask: ActivityRequest(app: .todoist, title: "Add a task", detail: nil, isLookup: false)
        default: nil
        }
    }
}

public struct ActivityEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let at: Date
    public let app: ActivityApp
    public let title: String
    public let detail: String?
    public var outcome: ActivityOutcome
    /// Why it didn't happen, in plain words, when known.
    public var note: String?
    public let reminderKey: String?
    /// When "Check" last looked in Reminders.
    public var checkedAt: Date?

    public init(
        id: UUID = UUID(), at: Date, app: ActivityApp, title: String, detail: String?,
        outcome: ActivityOutcome, note: String? = nil, reminderKey: String? = nil, checkedAt: Date? = nil
    ) {
        self.id = id
        self.at = at
        self.app = app
        self.title = title
        self.detail = detail
        self.outcome = outcome
        self.note = note
        self.reminderKey = reminderKey
        self.checkedAt = checkedAt
    }

    /// Builds the entry from what was asked and the reply the agent was given. The reply is the
    /// app's own verified result (VoiceToolReply), so the log can never claim more than the agent heard.
    public init(request: ActivityRequest, reply: String, at: Date) {
        let (outcome, note) = Self.outcome(of: reply, isLookup: request.isLookup)
        self.init(
            at: at, app: request.app, title: request.title, detail: request.detail, outcome: outcome, note: note,
            reminderKey: request.reminderKey)
    }

    /// "Check" is offered when Doddy wasn't sure a reminder went in.
    public var canCheckInReminders: Bool { outcome == .notSure && reminderKey != nil }

    static func outcome(of reply: String, isLookup: Bool) -> (ActivityOutcome, String?) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        // Online accounts in test mode prefix their result (VoiceToolReply.cloudResult).
        let demoMarker = "Tell the user it is demo data. "
        if text.hasPrefix("DEMO DATA"), let range = text.range(of: demoMarker) {
            let (outcome, note) = Self.outcome(of: String(text[range.upperBound...]), isLookup: isLookup)
            return (outcome, note ?? "Demo data from a test server, not your account.")
        }
        if text.hasPrefix("failed:") { return (.notDone, reason(in: text)) }
        if text.contains("isn't connected") {
            return (.notDone, text.components(separatedBy: ". ").first.map { $0 + "." })
        }
        if isLookup { return (.lookedUp, nil) }
        if text.hasPrefix("declined:") { return (.declined, nil) }
        if text.hasPrefix("unknown:") { return (.notSure, "Doddy couldn't confirm it went through.") }
        if text.hasPrefix("added:"), text.contains("already in Reminders") { return (.alreadyThere, nil) }
        if text.hasPrefix("added:") || text.hasPrefix("saved:") || text.hasPrefix("drafted:") { return (.done, nil) }
        if text.hasPrefix("opened:") { return (.opened, nil) }
        // Anything the app didn't phrase as a result is never shown as done.
        return (.notSure, nil)
    }

    /// "failed: Reminders isn't connected. Nothing was added." → "Reminders isn't connected."
    private static func reason(in text: String) -> String? {
        var body = String(text.dropFirst("failed:".count)).trimmingCharacters(in: .whitespaces)
        for tail in [" Nothing was added.", " Nothing was opened.", " Nothing was saved.", " Nothing was changed.", " Nothing was set.", " Nothing was run."] {
            if body.hasSuffix(tail) { body.removeLast(tail.count) }
        }
        return body.isEmpty ? nil : body
    }
}

public enum ActivityLog {
    public static let keepDays = 30
    public static let maxEntries = 300

    /// Newest first, at most `maxEntries`, nothing older than `keepDays`.
    public static func appending(_ entry: ActivityEntry, to entries: [ActivityEntry], now: Date) -> [ActivityEntry] {
        pruned([entry] + entries, now: now)
    }

    public static func pruned(_ entries: [ActivityEntry], now: Date) -> [ActivityEntry] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return Array(entries.filter { $0.at >= cutoff }.sorted { $0.at > $1.at }.prefix(maxEntries))
    }

    /// Result of looking in Reminders for an entry Doddy wasn't sure about.
    public static func checked(_ entry: ActivityEntry, found: Bool, at date: Date) -> ActivityEntry {
        var updated = entry
        updated.checkedAt = date
        if found {
            updated.outcome = .done
            updated.note = "Found in Reminders when you checked."
        } else {
            updated.outcome = .notDone
            updated.note = "Not in Reminders when you checked. You can ask Doddy again."
        }
        return updated
    }
}
