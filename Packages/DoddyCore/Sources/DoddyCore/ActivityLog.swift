import Foundation

// "What Doddy did" (docs/design/SETTINGS_AND_CONNECTIONS.md §5): every look-up and every change
// the voice agent asked for, with what actually happened. Kept on this iPhone only.

public enum ActivityApp: String, Codable, CaseIterable, Sendable {
    case memories, calendar, reminders, contacts, timers, maps, shortcuts, messages
    case gmail, drive, notion, todoist
    case web

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
        case .web: "Web search"
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
    /// Written before a change runs. If Doddy closes before the result, it becomes `notSure`.
    case inProgress

    public var text: String {
        switch self {
        case .lookedUp: "Looked up"
        case .done: "Done"
        case .alreadyThere: "Already there, nothing added"
        case .opened: "Opened"
        case .notSure: "Not sure it happened"
        case .notDone: "Didn't happen"
        case .declined: "You said no"
        case .inProgress: "In progress"
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
            let due = draft.due.map { " · due \(ReminderText.due($0))" } ?? ""
            return ActivityRequest(
                app: .reminders, title: "Add reminder", detail: "“\(draft.title)”\(due)", isLookup: false,
                reminderKey: ReminderWrite(draft).key)
        case .remindAboutNote(let draft):
            let target: String
            switch draft.target {
            case .time(let date, let zone):
                if let rule = draft.repeats {
                    let phrase = ReminderFormat.repeatPhrase(rule, anchor: date, timeZoneID: zone)
                    target = phrase.prefix(1).lowercased() + phrase.dropFirst()
                } else {
                    target = when(date, hasTime: true)
                }
            case .place(let query, let onArrival): target = "\(onArrival ? "arriving at" : "leaving") “\(query)”"
            }
            return ActivityRequest(app: .memories, title: "Remind about a note", detail: "“\(draft.noteText)” · \(target)", isLookup: false)
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
        case .addToList(let request):
            return ActivityRequest(app: .memories, title: "Add to a list", detail: "“\(request.list)”: \(request.items.joined(separator: ", "))", isLookup: false)
        case .readList(let name):
            return ActivityRequest(app: .memories, title: "Read a list", detail: "“\(name)”", isLookup: true)
        case .checkOff(let request):
            return ActivityRequest(app: .memories, title: "Tick on a list", detail: "“\(request.list)”: \(request.items.joined(separator: ", "))", isLookup: false)
        case .removeFromList(let request):
            return ActivityRequest(app: .memories, title: "Remove from a list", detail: "“\(request.list)”: \(request.items.joined(separator: ", "))", isLookup: false)
        case .createList(let request):
            return ActivityRequest(app: .memories, title: "Start a list", detail: "“\(request.list)”", isLookup: false)
        case .changeCalendarEvent(let draft):
            var parts: [String] = []
            if let start = draft.newStart { parts.append("to \(when(start, hasTime: !draft.currentIsDayOnly))") }
            if let title = draft.newTitle { parts.append("renamed “\(title)”") }
            return ActivityRequest(app: .calendar, title: "Change event", detail: "“\(draft.title)” \(parts.joined(separator: ", "))", isLookup: false)
        case .changeReminder(let draft):
            let what = draft.markDone ? "mark done" : "due \(draft.newDue.map(ReminderText.due) ?? "")"
            return ActivityRequest(app: .reminders, title: "Change reminder", detail: "“\(draft.title)” · \(what)", isLookup: false)
        case .unsupported, .invalid, .needsClarification, .startTranslator, .stopTranslator:
            // A clarification goes straight back to the agent; no app is used. Translator mode
            // uses no app either, and leaves no trace of the conversation (ADR-215).
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
        case CloudToolName.webSearch: ActivityRequest(app: .web, title: "Searched the web", detail: nil, isLookup: true)
        default: nil
        }
    }
}

/// Marks an entry as one step of a plan card (ADR-204), so the list can show them together.
public struct ActivityPlanRef: Codable, Equatable, Sendable {
    public let id: UUID
    public let step: Int
    public let count: Int

    public init(id: UUID, step: Int, count: Int) {
        self.id = id
        self.step = step
        self.count = count
    }

    public var text: String { "Step \(step) of \(count) in one plan" }
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
    /// Set when this was one step of a plan card. Older entries have none.
    public let plan: ActivityPlanRef?

    public init(
        id: UUID = UUID(), at: Date, app: ActivityApp, title: String, detail: String?,
        outcome: ActivityOutcome, note: String? = nil, reminderKey: String? = nil, checkedAt: Date? = nil,
        plan: ActivityPlanRef? = nil
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
        self.plan = plan
    }

    /// Builds the entry from what was asked and the reply the agent was given. The reply is the
    /// app's own verified result (VoiceToolReply), so the log can never claim more than the agent heard.
    public init(id: UUID = UUID(), request: ActivityRequest, reply: String, at: Date, plan: ActivityPlanRef? = nil) {
        let (outcome, note) = Self.outcome(of: reply, isLookup: request.isLookup)
        self.init(
            id: id, at: at, app: request.app, title: request.title, detail: request.detail, outcome: outcome,
            note: note, reminderKey: request.reminderKey, plan: plan)
    }

    /// Recorded the moment the user confirms a change, before it runs (see ActivityLog.recoverInterrupted).
    public static func started(_ request: ActivityRequest, at: Date, plan: ActivityPlanRef? = nil) -> ActivityEntry {
        ActivityEntry(
            at: at, app: request.app, title: request.title, detail: request.detail, outcome: .inProgress,
            reminderKey: request.reminderKey, plan: plan)
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
        if text.hasPrefix("paused:") { return (.notDone, "Connections were paused.") }
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
        for tail in [" Nothing was added.", " Nothing was opened.", " Nothing was saved.", " Nothing was changed.", " Nothing was set.", " Nothing was run.", " Nothing was done."] {
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

    public static let interruptedNote = "Doddy closed before this finished. Check before asking again, so it isn't done twice."

    /// At launch: anything still in progress was cut off (crash, force-quit, iOS ended the app).
    /// It is never shown as done; it becomes "Not sure", and an unsure reminder offers Check.
    public static func recoverInterrupted(_ entries: [ActivityEntry]) -> [ActivityEntry] {
        entries.map { entry in
            guard entry.outcome == .inProgress else { return entry }
            var recovered = entry
            recovered.outcome = .notSure
            recovered.note = interruptedNote
            return recovered
        }
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

/// One row in "What Doddy did": a single entry, or every step of one plan card together
/// (ADR-208), in step order under one heading.
public enum ActivityItem: Equatable, Identifiable, Sendable {
    case single(ActivityEntry)
    case plan(id: UUID, steps: [ActivityEntry])

    public var id: UUID {
        switch self {
        case .single(let entry): entry.id
        case .plan(let id, _): id
        }
    }

    /// The newest time in the item, for ordering and for the day it is listed under.
    public var at: Date {
        switch self {
        case .single(let entry): entry.at
        case .plan(_, let steps): steps.map(\.at).max() ?? .distantPast
        }
    }

    /// Newest first. Entries of the same plan are gathered where the plan's newest step falls,
    /// so a plan never appears twice or split around other entries.
    public static func items(_ entries: [ActivityEntry]) -> [ActivityItem] {
        var plans: [UUID: [ActivityEntry]] = [:]
        var order: [UUID] = []
        var singles: [UUID: ActivityEntry] = [:]
        for entry in entries.sorted(by: { $0.at > $1.at }) {
            if let plan = entry.plan {
                if plans[plan.id] == nil { order.append(plan.id) }
                plans[plan.id, default: []].append(entry)
            } else {
                order.append(entry.id)
                singles[entry.id] = entry
            }
        }
        return order.compactMap { id in
            if let entry = singles[id] { return .single(entry) }
            guard let steps = plans[id] else { return nil }
            return .plan(id: id, steps: steps.sorted { ($0.plan?.step ?? 0) < ($1.plan?.step ?? 0) })
        }
    }
}

public enum ActivityPlanSummary {
    /// "Plan · 3 steps", plus "(1 no longer listed)" when older steps were pruned.
    public static func title(_ steps: [ActivityEntry]) -> String {
        let count = steps.compactMap(\.plan?.count).max() ?? steps.count
        let missing = count - steps.count
        return "Plan · \(count) step\(count == 1 ? "" : "s")" + (missing > 0 ? " (\(missing) no longer listed)" : "")
    }

    /// "2 done · 1 not sure · 1 you said no", in a fixed order, only the outcomes present.
    /// Never counts a step as done unless its own entry is done.
    public static func outcomes(_ steps: [ActivityEntry]) -> String {
        let order: [(String, Set<ActivityOutcome>)] = [
            ("done", [.done, .alreadyThere]),
            ("not sure", [.notSure]),
            ("in progress", [.inProgress]),
            ("didn't happen", [.notDone]),
            ("you said no", [.declined]),
            ("opened", [.opened]),
            ("looked up", [.lookedUp]),
        ]
        return order.compactMap { label, outcomes in
            let count = steps.filter { outcomes.contains($0.outcome) }.count
            return count > 0 ? "\(count) \(label)" : nil
        }.joined(separator: " · ")
    }
}
