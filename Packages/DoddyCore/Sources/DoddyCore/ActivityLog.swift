import Foundation

// "What Doddy did" (docs/design/SETTINGS_AND_CONNECTIONS.md §5): every look-up and every change
// the voice agent asked for, with what actually happened. Kept on this iPhone only.

public enum ActivityApp: String, Codable, CaseIterable, Sendable {
    case memories, calendar, reminders, contacts, timers, maps, shortcuts, messages
    case gmail, drive, notion, todoist
    /// Microsoft Outlook (ADR-340).
    case outlook
    case web
    /// The ECB's public rates file (ADR-300).
    case exchangeRates
    /// A BLIK phone transfer shown for the user to send in their bank app (ADR-510).
    case blik

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
        case .outlook: "Outlook"
        case .web: "Web search"
        case .exchangeRates: "Exchange rates"
        case .blik: "BLIK transfers"
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
    /// Shown on a card for the user to do themselves, as a BLIK transfer in their bank app
    /// (ADR-510). Doddy did nothing and can't see whether the user did.
    case shown

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
        case .shown: "Shown for you to send"
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
    /// What "What Doddy did" keeps of `detail`. Note text, searches, list names and items are not
    /// kept (review C2): the log stays for 30 days, after the note or list may be deleted. The card
    /// still shows `detail` in full.
    public let logDetail: String?
    public let isLookup: Bool
    /// Set for reminders, so "Check" can look for exactly this reminder later.
    public let reminderKey: String?
    /// The same change asked again has the same key (ADR-319, ADR-320): new reminders, events,
    /// timers and alarms, whose adds look first and so can be retried safely. Nil for everything else.
    public let operationKey: String?
    /// For notes and lists: what Doddy looks for in its own database to settle an unsure entry (ADR-321).
    public let check: ActivityCheck?
    /// The voice tool that asked (ADR-440): an identifier for outcome events, never user text.
    public let tool: String?

    public init(
        app: ActivityApp, title: String, detail: String?, isLookup: Bool, reminderKey: String? = nil,
        operationKey: String? = nil, check: ActivityCheck? = nil, tool: String? = nil
    ) {
        self.init(app: app, title: title, detail: detail, logDetail: detail, isLookup: isLookup, reminderKey: reminderKey,
                  operationKey: operationKey, check: check, tool: tool)
    }

    public init(
        app: ActivityApp, title: String, detail: String?, logDetail: String?, isLookup: Bool, reminderKey: String? = nil,
        operationKey: String? = nil, check: ActivityCheck? = nil, tool: String? = nil
    ) {
        self.app = app
        self.title = title
        self.detail = detail
        self.logDetail = logDetail
        self.isLookup = isLookup
        self.reminderKey = reminderKey
        self.operationKey = operationKey ?? reminderKey
        self.check = check
        self.tool = tool
    }

    /// The same request, naming the tool that made it.
    public func naming(_ tool: String) -> ActivityRequest {
        ActivityRequest(app: app, title: title, detail: detail, logDetail: logDetail, isLookup: isLookup, reminderKey: reminderKey,
                        operationKey: operationKey, check: check, tool: tool)
    }

    /// Nil for requests that never reach an app (unsupported or invalid tool calls).
    public static func describe(_ request: VoiceToolRequest, calendar: Calendar) -> ActivityRequest? {
        func when(_ date: Date, hasTime: Bool) -> String { VoiceToolReply.localText(date, hasTime: hasTime, calendar: calendar) }
        func items(_ request: ListVoiceRequest) -> String { "\(request.items.count) item\(request.items.count == 1 ? "" : "s")" }
        switch request {
        case .searchMemories(let query):
            return ActivityRequest(app: .memories, title: "Searched your notes", detail: "“\(query)”", logDetail: nil, isLookup: true)
        case .saveMemory(let text):
            return ActivityRequest(
                app: .memories, title: "Save a note", detail: "“\(text)”", logDetail: nil, isLookup: false,
                operationKey: NoteIdempotency.key(text), check: .note(key: NoteIdempotency.key(text)))
        case .leaveBy(let request):
            return ActivityRequest(
                app: .maps, title: "Remind when to leave",
                detail: "“\(request.place)” · arrive by \(when(request.arriveBy, hasTime: true))", isLookup: false,
                operationKey: LeaveByIdempotency.key(request))
        case .findFreeTime(let request):
            let range = request.range(calendar: .current)
            return ActivityRequest(
                app: .calendar, title: "Looked for free time",
                detail: "\(when(range.start, hasTime: false)) to \(when(range.end, hasTime: false))", isLookup: true)
        case .readCalendar(let range):
            return ActivityRequest(
                app: .calendar, title: "Read your calendar",
                detail: "\(when(range.start, hasTime: false)) to \(when(range.end, hasTime: false))", isLookup: true)
        case .createCalendarEvent(let draft):
            let time = draft.allDay ? "\(when(draft.start, hasTime: false)), all day" : when(draft.start, hasTime: true)
            let repeats = draft.repeats.map { " · repeats \($0.text)" } ?? ""
            return ActivityRequest(
                app: .calendar, title: "Add event", detail: "“\(draft.title)” · \(time)\(repeats)", isLookup: false,
                operationKey: EventIdempotency.key(draft))
        case .createReminder(let draft):
            let due = draft.due.map { " · due \(ReminderText.due($0))" } ?? ""
            let repeats = draft.repeats.map { " · repeats \($0.text)" } ?? ""
            return ActivityRequest(
                app: .reminders, title: "Add reminder", detail: "“\(draft.title)”\(due)\(repeats)", isLookup: false,
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
            let logged: String
            if case .place(_, let onArrival) = draft.target { logged = onArrival ? "arriving at a place" : "leaving a place" } else { logged = target }
            return ActivityRequest(
                app: .memories, title: "Remind about a note", detail: "“\(draft.noteText)” · \(target)", logDetail: logged, isLookup: false)
        case .lookupContact(let name):
            return ActivityRequest(app: .contacts, title: "Looked for a contact", detail: "“\(name)”", isLookup: true)
        case .upcomingBirthdays(let days):
            return ActivityRequest(app: .contacts, title: "Read birthdays", detail: days == 1 ? "Today" : "Next \(days) days", isLookup: true)
        case .setTimer(let draft):
            let minutes = draft.seconds / 60, seconds = draft.seconds % 60
            let length = minutes > 0 ? "\(minutes) min\(seconds > 0 ? " \(seconds) s" : "")" : "\(seconds) s"
            return ActivityRequest(
                app: .timers, title: "Start timer", detail: [draft.label.map { "“\($0)”" }, length].compactMap { $0 }.joined(separator: " · "),
                isLookup: false, operationKey: TimerIdempotency.key(draft))
        case .setAlarm(let draft):
            return ActivityRequest(
                app: .timers, title: "Set alarm", detail: [draft.label.map { "“\($0)”" }, draft.summary].compactMap { $0 }.joined(separator: " · "),
                isLookup: false, operationKey: AlarmIdempotency.key(draft))
        case .openMap(let place):
            return ActivityRequest(app: .maps, title: "Open in Maps", detail: "“\(place)”", isLookup: false)
        case .runShortcut(let name):
            return ActivityRequest(app: .shortcuts, title: "Run shortcut", detail: "“\(name)”", isLookup: false)
        case .draftMessage(let draft):
            return ActivityRequest(
                app: .messages, title: draft.channel == .text ? "Draft a text" : "Draft an email",
                detail: "to \(draft.recipientName)", isLookup: false)
        case .draftBlikTransfer(let draft):
            // The amount and title are on the card; the 30-day log keeps only who it was for.
            return ActivityRequest(
                app: .blik, title: "Prepare a BLIK transfer", detail: "\(draft.amount.agentText) to \(draft.recipientName)",
                logDetail: "to \(draft.recipientName)", isLookup: false)
        case .cloudTool(let call):
            // Writes carry a key (ADR-322): a hash of the tool and its arguments, never the words.
            guard let request = describe(cloud: call.name), let key = CloudIdempotency.key(call) else { return describe(cloud: call.name) }
            return ActivityRequest(app: request.app, title: request.title, detail: request.detail, isLookup: request.isLookup, operationKey: key)
        case .addToList(let request):
            return ActivityRequest(
                app: .memories, title: "Add to a list", detail: "“\(request.list)”: \(request.items.joined(separator: ", "))", logDetail: items(request), isLookup: false,
                operationKey: ListOpIdempotency.key("add", list: request.list, items: request.items),
                check: .listAdd(list: request.list, items: request.items))
        case .readList(let name):
            return ActivityRequest(app: .memories, title: "Read a list", detail: "“\(name)”", logDetail: nil, isLookup: true)
        case .checkOff(let request):
            return ActivityRequest(
                app: .memories, title: "Tick on a list", detail: "“\(request.list)”: \(request.items.joined(separator: ", "))", logDetail: items(request), isLookup: false,
                operationKey: ListOpIdempotency.key("tick", list: request.list, items: request.items),
                check: .listTick(list: request.list, items: request.items))
        case .removeFromList(let request):
            return ActivityRequest(
                app: .memories, title: "Remove from a list", detail: "“\(request.list)”: \(request.items.joined(separator: ", "))", logDetail: items(request), isLookup: false,
                operationKey: ListOpIdempotency.key("remove", list: request.list, items: request.items),
                check: .listRemove(list: request.list, items: request.items))
        case .createList(let request):
            return ActivityRequest(
                app: .memories, title: "Start a list", detail: "“\(request.list)”", logDetail: nil, isLookup: false,
                operationKey: ListOpIdempotency.key("create", list: request.list, items: []), check: .listCreate(name: request.list))
        case .changeCalendarEvent(let draft):
            var parts: [String] = []
            if let start = draft.newStart { parts.append("to \(when(start, hasTime: !draft.newStartIsDayOnly))") }
            if let title = draft.newTitle { parts.append("renamed “\(title)”") }
            return ActivityRequest(app: .calendar, title: "Change event", detail: "“\(draft.title)” \(parts.joined(separator: ", "))", isLookup: false)
        case .changeReminder(let draft):
            var parts: [String] = []
            if draft.markDone { parts.append("mark done") }
            if let due = draft.newDue { parts.append("due \(ReminderText.due(due))") }
            // ADR-302: which details, not the note's text.
            if draft.addNote != nil { parts.append("add a note") }
            if let priority = draft.priority { parts.append(priority.text) }
            if let list = draft.listName { parts.append("to the list “\(list)”") }
            // ADR-314: the new title is the user's own words; notes text is not kept.
            if let title = draft.newTitle { parts.append("rename to “\(title)”") }
            if let text = draft.replaceNotes { parts.append(text.isEmpty ? "clear notes" : "replace notes") }
            switch draft.repeatChange {
            case .set(let rule)?: parts.append("repeat \(rule.text)")
            case .stop?: parts.append("stop repeating")
            case nil: break
            }
            let what = parts.joined(separator: ", ")
            return ActivityRequest(app: .reminders, title: "Change reminder", detail: "“\(draft.title)” · \(what)", isLookup: false)
        case .deleteCalendarEvent(let draft):
            return ActivityRequest(app: .calendar, title: "Delete event", detail: "“\(draft.title)” \(when(draft.currentStart, hasTime: !draft.currentIsDayOnly))", isLookup: false)
        case .listAlarms:
            return ActivityRequest(app: .timers, title: "Read alarms", detail: "Doddy's alarms", isLookup: true)
        case .cancelAlarm(let clock, let label):
            return ActivityRequest(app: .timers, title: "Turn off alarm", detail: [clock, label.map { "“\($0)”" }].compactMap { $0 }.joined(separator: " · "), isLookup: false)
        case .deleteCalendarEvents(let range):
            return ActivityRequest(app: .calendar, title: "Delete events", detail: "\(when(range.start, hasTime: true)) – \(when(range.end, hasTime: true))", isLookup: false)
        case .moveReminders(let dueBy, let to):
            return ActivityRequest(app: .reminders, title: "Move reminders", detail: "due by \(ReminderText.due(dueBy)) → \(ReminderText.due(to))", isLookup: false)
        case .deleteReminder(let title):
            return ActivityRequest(app: .reminders, title: "Delete reminder", detail: "“\(title)”", isLookup: false)
        case .undoLast:
            // The row being undone records what happened (ActivityLog.undid), not a new row.
            return nil
        case .parkingSpot(let action):
            // No coordinates in the log, only what was asked (ADR-301).
            switch action {
            case .save: return ActivityRequest(app: .memories, title: "Save parking spot", detail: nil, isLookup: false)
            case .find: return ActivityRequest(app: .memories, title: "Found parking spot", detail: nil, isLookup: true)
            case .clear: return ActivityRequest(app: .memories, title: "Clear parking spot", detail: nil, isLookup: false)
            }
        case .addIngredients(let proposal):
            return ActivityRequest(
                app: .memories, title: "Add ingredients to a list", detail: "“\(proposal.list)” · \(proposal.dish)",
                logDetail: "\(proposal.items.count) item\(proposal.items.count == 1 ? "" : "s")", isLookup: false)
        case .convertCurrency(let request):
            // Only that the rates file was fetched; the amount stays in the conversation (ADR-300).
            return ActivityRequest(app: .exchangeRates, title: "Converted currency", detail: "\(CurrencyConversion.code(request.from)) → \(CurrencyConversion.code(request.to))", isLookup: true)
        case .noteCapabilityGap:
            // A category Doddy notes for itself (ADR-440); no app is used and nothing changes.
            return nil
        case .unsupported, .invalid, .needsClarification, .startTranslator, .stopTranslator, .calculate, .convertUnits:
            // A clarification goes straight back to the agent; no app is used. Translator mode
            // uses no app either, and leaves no trace of the conversation (ADR-215). Sums and
            // unit conversions are worked out inside Doddy and use no app (ADR-270).
            return nil
        }
    }

    /// Online-account calls: names only. Email subjects, file names and task text are not kept.
    static func describe(cloud name: String) -> ActivityRequest? {
        // ADR-486/487: Google Calendar is listed under Calendar, Outlook's under Outlook.
        if let more = CloudToolName.more[name] {
            let app: ActivityApp = switch more.account {
            case "Outlook": .outlook
            case "Todoist": .todoist
            case "Notion": .notion
            case "Google Drive": .drive
            // ADR-564: Claude is listed with the web lookups (no account, Doddy's server).
            case "Web search", "Claude": .web
            default: .calendar
            }
            return ActivityRequest(app: app, title: more.title, detail: nil, isLookup: !more.write)
        }
        return switch name {
        case CloudToolName.checkEmail: ActivityRequest(app: .gmail, title: "Checked email", detail: nil, isLookup: true)
        case CloudToolName.draftEmail: ActivityRequest(app: .gmail, title: "Create an email draft", detail: nil, isLookup: false)
        case CloudToolName.readEmail: ActivityRequest(app: .gmail, title: "Read an email", detail: nil, isLookup: true)
        case CloudToolName.draftEmailReply: ActivityRequest(app: .gmail, title: "Create a reply draft", detail: nil, isLookup: false)
        case CloudToolName.sendEmail: ActivityRequest(app: .gmail, title: "Send an email", detail: nil, isLookup: false)
        case CloudToolName.replyToEmail: ActivityRequest(app: .gmail, title: "Send a reply", detail: nil, isLookup: false)
        case CloudToolName.forwardEmail: ActivityRequest(app: .gmail, title: "Forward an email", detail: nil, isLookup: false)
        case CloudToolName.changeEmail: ActivityRequest(app: .gmail, title: "Archive or mark an email", detail: nil, isLookup: false)
        case CloudToolName.trashEmail: ActivityRequest(app: .gmail, title: "Move an email to Trash", detail: nil, isLookup: false)
        case CloudToolName.readNotionPage: ActivityRequest(app: .notion, title: "Read a Notion page", detail: nil, isLookup: true)
        case CloudToolName.completeTodoistTask: ActivityRequest(app: .todoist, title: "Complete a task", detail: nil, isLookup: false)
        case CloudToolName.moveTodoistTask: ActivityRequest(app: .todoist, title: "Move a task", detail: nil, isLookup: false)
        case CloudToolName.findDriveFile: ActivityRequest(app: .drive, title: "Looked for a file", detail: nil, isLookup: true)
        case CloudToolName.searchNotion: ActivityRequest(app: .notion, title: "Searched Notion", detail: nil, isLookup: true)
        case CloudToolName.listTodoistTasks: ActivityRequest(app: .todoist, title: "Read your tasks", detail: nil, isLookup: true)
        case CloudToolName.addTodoistTask: ActivityRequest(app: .todoist, title: "Add a task", detail: nil, isLookup: false)
        case CloudToolName.webSearch: ActivityRequest(app: .web, title: "Searched the web", detail: nil, isLookup: true)
        case CloudToolName.checkOutlookEmail: ActivityRequest(app: .outlook, title: "Checked email", detail: nil, isLookup: true)
        case CloudToolName.readOutlookEmail: ActivityRequest(app: .outlook, title: "Read an email", detail: nil, isLookup: true)
        case CloudToolName.draftOutlookEmail: ActivityRequest(app: .outlook, title: "Create an email draft", detail: nil, isLookup: false)
        case CloudToolName.readOutlookCalendar: ActivityRequest(app: .outlook, title: "Read your calendar", detail: nil, isLookup: true)
        default: nil
        }
    }
}

/// Marks an entry as one step of a plan card (ADR-204), so the list can show them together.
extension ActivityLog {
    /// The note on an entry for a card nobody answered before the conversation ended.
    public static let unansweredNote = "The conversation ended before you answered."
}

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
    /// What Doddy needs to put it back (ADR-268). Only kept for changes Doddy made and checked.
    public let undo: ActivityUndo?
    /// Set after the user tapped Undo.
    public var undoState: UndoState?
    // ADR-319. All optional, so entries saved before them still load.
    /// The same change asked again has the same key (`ActivityRequest.operationKey`).
    public let operationKey: String?
    /// What the app read back. Only ever kept on a confirmed entry.
    public private(set) var receipt: ActivityReceipt?
    /// True when the app was asked to write; false when Doddy stopped before writing. Nil when not known.
    public let attempted: Bool?
    /// For notes and lists: what Doddy looks for to settle it if unsure (ADR-321).
    public let check: ActivityCheck?
    private var statusHistory: [ActivityStatusChange]?
    /// The voice tool that asked (ADR-440). Entries from before it have none.
    public let tool: String?

    public init(
        id: UUID = UUID(), at: Date, app: ActivityApp, title: String, detail: String?,
        outcome: ActivityOutcome, note: String? = nil, reminderKey: String? = nil, checkedAt: Date? = nil,
        plan: ActivityPlanRef? = nil, undo: ActivityUndo? = nil, undoState: UndoState? = nil,
        operationKey: String? = nil, receipt: ActivityReceipt? = nil, attempted: Bool? = nil, check: ActivityCheck? = nil,
        tool: String? = nil
    ) {
        self.tool = tool
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
        self.undo = outcome == .done ? undo : nil
        self.undoState = undoState
        self.operationKey = operationKey ?? reminderKey
        self.receipt = outcome.status == .confirmed ? receipt : nil
        self.attempted = attempted
        self.check = check
    }

    /// Builds the entry from what was asked and the reply the agent was given. The reply is the
    /// app's own verified result (VoiceToolReply), so the log can never claim more than the agent heard.
    /// `undo` is kept only when that reply says the change was made and checked; a receipt only
    /// when it is a confirmed result.
    public init(
        id: UUID = UUID(), request: ActivityRequest, reply: String, at: Date, plan: ActivityPlanRef? = nil,
        undo: ActivityUndo? = nil, receipt: ActivityReceipt? = nil, attempted: Bool? = nil
    ) {
        let (outcome, note) = Self.outcome(of: reply, isLookup: request.isLookup)
        self.init(
            id: id, at: at, app: request.app, title: request.title, detail: request.logDetail, outcome: outcome,
            note: note, reminderKey: request.reminderKey, plan: plan, undo: undo, operationKey: request.operationKey,
            receipt: receipt, attempted: attempted, check: request.check, tool: request.tool)
    }

    /// Recorded the moment the user confirms a change, before it runs (see ActivityLog.recoverInterrupted).
    public static func started(_ request: ActivityRequest, at: Date, plan: ActivityPlanRef? = nil) -> ActivityEntry {
        var entry = ActivityEntry(
            at: at, app: request.app, title: request.title, detail: request.logDetail, outcome: .inProgress,
            reminderKey: request.reminderKey, plan: plan, operationKey: request.operationKey, check: request.check, tool: request.tool)
        entry.statusHistory = [ActivityStatusChange(status: .proposed, at: at), ActivityStatusChange(status: .pending, at: at)]
        return entry
    }

    /// The result of a started entry: same id and time, its history kept and the result added.
    public static func finished(
        _ started: ActivityEntry, request: ActivityRequest, reply: String, at: Date,
        undo: ActivityUndo? = nil, receipt: ActivityReceipt? = nil, attempted: Bool? = nil
    ) -> ActivityEntry {
        var entry = ActivityEntry(
            id: started.id, request: request, reply: reply, at: started.at, plan: started.plan,
            undo: undo, receipt: receipt, attempted: attempted)
        entry.statusHistory = started.history
        entry.record(entry.status, at: at, note: nil)
        return entry
    }

    /// Typed status (ADR-319). Nil for look-ups.
    public var status: ActionStatus? { outcome.status }

    /// How the status moved, oldest first. Entries saved before ADR-319 show their one known status.
    public var history: [ActivityStatusChange] {
        if let statusHistory { return statusHistory }
        return status.map { [ActivityStatusChange(status: $0, at: at)] } ?? []
    }

    /// Moves to `outcome` only if the status model allows it; otherwise nothing changes.
    /// Returns whether it moved.
    @discardableResult
    mutating func move(to outcome: ActivityOutcome, at date: Date, note: String?) -> Bool {
        guard let from = status, let to = outcome.status, from.canMove(to: to) else { return false }
        self.outcome = outcome
        self.note = note
        if to != .confirmed { receipt = nil }
        record(to, at: date, note: note)
        return true
    }

    private mutating func record(_ status: ActionStatus?, at date: Date, note: String?) {
        guard let status else { return }
        var steps = history
        if steps.last?.status != status { steps.append(ActivityStatusChange(status: status, at: date, note: note)) }
        statusHistory = steps
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
        // Only the start of the reply is read: a note or a title quoted later in it can't change
        // the outcome (review C1).
        func starts(_ prefixes: [String]) -> Bool { prefixes.contains { text.hasPrefix($0) } }
        if text.hasPrefix("failed:") { return (.notDone, reason(in: text)) }
        if text.hasPrefix("paused:") { return (.notDone, "Connections were paused.") }
        if text.hasPrefix("refused:") { return (.notDone, "Translator mode was on, so nothing was run.") }
        // VoiceToolReply.notConnected: "Calendar isn't connected. Tell the user …"
        if let connection = VoiceConnection.allCases.first(where: { text.hasPrefix("\($0.title) isn't connected") }) {
            return (.notDone, "\(connection.title) isn't connected.")
        }
        if isLookup { return (.lookedUp, nil) }
        if text.hasPrefix("declined:") { return (.declined, nil) }
        if text.hasPrefix("unknown:") { return (.notSure, "Doddy couldn't confirm it went through.") }
        if text.hasPrefix("not found:") { return (.notDone, "Doddy couldn't find it, so nothing changed.") }
        // Round 3 (ADR-280, ADR-283): "partly" means only some of the ticked ones changed, so the
        // row says which part.
        if text.hasPrefix("partly ") { return (.done, ActivityLog.partlyNote) }
        // Lists (ADR-272): nothing new added only because every item was already there.
        if text.hasPrefix("not added:"), text.contains("Already on the list, not added again:"),
           !text.contains("Too long"), !text.contains("the list is full") {
            return (.alreadyThere, nil)
        }
        if starts(VoiceToolReply.nothingChangedPrefixes) { return (.notDone, nil) }
        // Found already there when Doddy looked first (ADR-319 to ADR-322, ADR-363): Doddy's own
        // endings, read from the end so a quoted title can't fake one (review C1).
        if starts(["added:", "saved:"]), alreadyThereTails.contains(where: withoutCheckedFirst(text).hasSuffix) { return (.alreadyThere, nil) }
        if starts(VoiceToolReply.donePrefixes) || starts(VoiceToolReply.listDonePrefixes) { return (.done, nil) }
        if text.hasPrefix("opened:") { return (.opened, nil) }
        // A BLIK transfer card (ADR-510): the user sends it in their bank app; Doddy can't see it.
        if text.hasPrefix("shown:") { return (.shown, "Doddy didn't send any money. You send it in your bank app.") }
        // Anything the app didn't phrase as a result is never shown as done.
        return (.notSure, nil)
    }

    /// How replies end when nothing new was written because it was already there.
    static let alreadyThereTails = [
        VoiceToolReply.alreadyInRemindersTail,
        " was already in Calendar, so Doddy did not add it a second time.",
        " was already set, so Doddy did not set a second one.",
        ", so Doddy did not start a second one.",
        ", so Doddy did not do it a second time. Tell the user it is already there.",
        ", so Doddy did not save it a second time.",
    ]

    /// The reply without `VoiceToolReply.checkedFirst`'s closing sentence.
    private static func withoutCheckedFirst(_ text: String) -> String {
        guard text.hasSuffix(" first because an earlier try wasn't confirmed."),
              let range = text.range(of: " Doddy checked ", options: .backwards) else { return text }
        return String(text[..<range.lowerBound])
    }

    /// "failed: Reminders isn't connected. Nothing was added." → "Reminders isn't connected."
    /// Only the first line: data that follows (ToolData) never becomes the shown reason.
    private static func reason(in text: String) -> String? {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        var body = String(firstLine.dropFirst("failed:".count)).trimmingCharacters(in: .whitespaces)
        for tail in [" Nothing was added.", " Nothing was opened.", " Nothing was saved.", " Nothing was changed.", " Nothing was deleted.", " Nothing was set.", " Nothing was run.", " Nothing was done."] {
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

    /// Also drops note text that older versions kept (review C2), and what Undo needed once Undo
    /// is no longer offered (a day, `ActivityUndo.window`): that can quote a note or list items,
    /// and the row stays for 30 days. The app prunes at launch and on every new entry, and saves
    /// when anything changed, so it leaves the file too.
    public static func pruned(_ entries: [ActivityEntry], now: Date) -> [ActivityEntry] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return Array(entries.filter { $0.at >= cutoff }.sorted { $0.at > $1.at }.prefix(maxEntries).map { entry in
            let kept = withoutNoteText(entry)
            return now.timeIntervalSince(kept.at) >= ActivityUndo.window ? withoutUndo(kept) : kept
        })
    }

    /// A note or list was deleted: rows keep what happened, but no longer what Undo needed for it
    /// (its text or items). Undo of it couldn't run anyway.
    public static func forgetting(memoryID: UUID, in entries: [ActivityEntry]) -> [ActivityEntry] {
        entries.map { $0.undo?.memoryID == memoryID ? withoutUndo($0) : $0 }
    }

    /// "Delete all memories": the Notes and lists rows go with them. Rows for Calendar, Reminders
    /// and the other apps stay, since those changes are still there.
    public static func forgettingNotes(_ entries: [ActivityEntry]) -> [ActivityEntry] {
        entries.filter { $0.app != .memories && $0.undo?.memoryID == nil }
    }

    /// The same row without what Undo needed; its outcome, note and any Undo result stay.
    static func withoutUndo(_ entry: ActivityEntry) -> ActivityEntry {
        guard entry.undo != nil else { return entry }
        return ActivityEntry(
            id: entry.id, at: entry.at, app: entry.app, title: entry.title, detail: entry.detail, outcome: entry.outcome,
            note: entry.note, reminderKey: entry.reminderKey, checkedAt: entry.checkedAt, plan: entry.plan,
            undo: nil, undoState: entry.undoState, tool: entry.tool)
    }

    /// Notes and lists rows used to start their detail with the quoted note, search or list name
    /// ("“Buy milk”"); `ActivityRequest.logDetail` never does.
    static func withoutNoteText(_ entry: ActivityEntry) -> ActivityEntry {
        guard entry.app == .memories, let detail = entry.detail, detail.hasPrefix("“") else { return entry }
        return ActivityEntry(
            id: entry.id, at: entry.at, app: entry.app, title: entry.title, detail: nil, outcome: entry.outcome,
            note: entry.note, reminderKey: entry.reminderKey, checkedAt: entry.checkedAt, plan: entry.plan)
    }

    /// The note on a several-at-once row where only some changed (ADR-280).
    public static let partlyNote = "Only some of them were changed."

    public static let interruptedNote = "Doddy closed before this finished. Check before asking again, so it isn't done twice."

    /// At launch: anything still in progress was cut off (crash, force-quit, iOS ended the app).
    /// It is never shown as done; it becomes "Not sure", and an unsure reminder offers Check.
    public static func recoverInterrupted(_ entries: [ActivityEntry], at date: Date = Date()) -> [ActivityEntry] {
        entries.map { entry in
            guard entry.outcome == .inProgress else { return entry }
            var recovered = entry
            recovered.move(to: .notSure, at: date, note: interruptedNote)
            return recovered
        }
    }

    /// Result of looking in Reminders for an entry Doddy wasn't sure about. Only an unsure entry
    /// changes: a check never turns a confirmed or failed result into something else.
    public static func checked(_ entry: ActivityEntry, found: Bool, at date: Date) -> ActivityEntry {
        guard entry.status == .unknown else { return entry }
        var updated = entry
        updated.checkedAt = date
        if found {
            updated.move(to: .done, at: date, note: "Found in Reminders when you checked.")
        } else {
            updated.move(to: .notDone, at: date, note: "Not in Reminders when you checked. You can ask Doddy again.")
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
