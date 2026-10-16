import Foundation

/// Client tools the voice agent may call. Names must match the tools configured on the
/// ElevenLabs agent (see docs/implementation/V1_VOICE_STATUS.md).
public enum VoiceToolName {
    public static let searchMemories = "search_memories"
    public static let saveMemory = "save_memory"
    public static let readCalendar = "read_calendar"
    public static let createCalendarEvent = "create_calendar_event"
    public static let createReminder = "create_reminder"
    /// Doddy's own reminder about a saved note, at a time or a place (ADR-198). Not Apple Reminders.
    public static let remindAboutNote = "remind_me_about_note"
    public static let lookupContact = "lookup_contact"
    public static let setTimer = "set_timer"
    public static let openMap = "open_map"
    /// Opens Uber Eats only after a user confirmation; never creates a cart or places an order.
    public static let openUberEats = "open_ubereats"
    public static let runShortcut = "run_shortcut"
    public static let draftMessage = "draft_message"
    /// Several changes on one card (`PlanProposal`, ADR-204).
    public static let proposePlan = "propose_plan"
    /// The user asked for something no tool covers: a category, kept on the iPhone (ADR-440).
    public static let noteCapabilityGap = "note_capability_gap"
}

/// The functions a user turns on in Settings, Connections. All start off, and each one may also
/// need an iOS permission of its own.
public enum VoiceConnection: String, CaseIterable, Sendable {
    case calendar, reminders, contacts, timers, maps, shortcuts, messages

    /// The name shown in Settings and in the agent's replies.
    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .timers: "Timers"
        case .maps: "Maps"
        case .shortcuts: "Shortcuts"
        case .messages: "Messages and email"
        }
    }

    /// Per-device preference key for @AppStorage.
    public var preferenceKey: String { "voiceConnection.\(rawValue)" }

    /// The connection that serves a client tool. Memory tools are not listed: they are always on.
    public static func serving(_ toolName: String) -> VoiceConnection? {
        switch toolName {
        case VoiceToolName.readCalendar, VoiceToolName.findFreeTime, VoiceToolName.createCalendarEvent, VoiceToolName.changeCalendarEvent,
             VoiceToolName.deleteCalendarEvent, VoiceToolName.deleteCalendarEvents: .calendar
        case VoiceToolName.createReminder, VoiceToolName.changeReminder, VoiceToolName.deleteReminder,
             VoiceToolName.moveReminders: .reminders
        case VoiceToolName.lookupContact, VoiceToolName.upcomingBirthdays: .contacts
        case VoiceToolName.setTimer, VoiceToolName.setAlarm, VoiceToolName.listAlarms, VoiceToolName.cancelAlarm: .timers
        case VoiceToolName.openMap, VoiceToolName.remindWhenToLeave: .maps
        case VoiceToolName.runShortcut: .shortcuts
        case VoiceToolName.draftMessage: .messages
        default: nil
        }
    }
}

extension VoiceConnection: Identifiable {
    public var id: String { rawValue }
}

/// A window of time the agent asked about, resolved to absolute dates.
public struct VoiceTimeRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// An event the agent proposed. Nothing is added until the user taps Add on the card.
public struct CalendarEventDraft: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String?
    public let notes: String?
    /// Calendar's own repeat (ADR-282); nil for a one-off event.
    public var repeats: CalendarRepeat? = nil

    /// Nil while the event is still ahead (an all-day event counts until its day ends). Checked
    /// when the card is shown and again when the user taps Add, as for reminders (ADR-128).
    public func passed(now: Date, calendar: Calendar) -> ReminderClarification? {
        let gregorian = ReminderDueRules.gregorian(calendar)
        let fields = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        guard let year = fields.year, let month = fields.month, let day = fields.day else { return nil }
        let due = ReminderDue(
            year: year, month: month, day: day,
            hour: allDay ? nil : fields.hour, minute: allDay ? nil : fields.minute,
            timeZoneID: gregorian.timeZone.identifier)
        return ReminderDueRules.passed(due, now: now)
    }
}

/// A reminder the agent proposed. Nothing is added until the user taps Add on the card.
/// `due` is local wall-clock time in a named zone, already checked by `ReminderDueRules`.
public struct ReminderDraft: Equatable, Sendable {
    public let title: String
    public let due: ReminderDue?
    public let notes: String?
    /// Reminders' own repeat (ADR-282); needs a due.
    public let repeats: CalendarRepeat?

    public init(title: String, due: ReminderDue?, notes: String?, repeats: CalendarRepeat? = nil) {
        self.repeats = repeats
        self.title = title
        self.due = due
        self.notes = notes
    }

    public var dueHasTime: Bool { due?.hasTime ?? false }
}

/// A countdown the agent proposed. Nothing starts until the user taps Start on the card.
public struct TimerDraft: Equatable, Sendable {
    public let seconds: Int
    public let label: String?
}

public enum MessageChannel: String, Equatable, Sendable {
    case text, email
}

/// A text or email the agent drafted. Doddy never sends it: the user sends it in Messages or Mail.
public struct MessageDraft: Equatable, Sendable {
    public let recipientName: String
    public let channel: MessageChannel
    public let body: String
}

/// What the agent is allowed to hear about an event: title and time only.
public struct CalendarEventSummary: Codable, Equatable, Sendable {
    /// This occurrence of the event on this iPhone (event identifier + start), for nudges.
    /// Never sent to the voice agent.
    public let id: String?
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool

    public init(id: String? = nil, title: String, start: Date, end: Date, allDay: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
    }
}

/// A parsed tool call. The model only proposes; the app decides what actually happens.
public enum VoiceToolRequest: Equatable, Sendable {
    case searchMemories(query: String)
    /// Never saved directly: the app shows it and waits for the user's confirmation.
    case saveMemory(text: String)
    case readCalendar(VoiceTimeRange)
    /// Shown to the user for confirmation before anything is added.
    case createCalendarEvent(CalendarEventDraft)
    case createReminder(ReminderDraft)
    /// A reminder about one saved note (Doddy's own, not Apple Reminders); shown as a card first.
    case remindAboutNote(NoteReminderVoiceDraft)
    /// The request can't be shown as a card yet (unclear, past or skipped time). The agent gets a
    /// question to ask the user instead. `name` is the tool to call again (reminder or event).
    case needsClarification(name: String, ReminderClarification)
    /// Only names go back to the agent; details stay on the user's screen.
    case lookupContact(name: String)
    /// Birthdays saved in Contacts in the next `days` days, read only (ADR-269).
    case upcomingBirthdays(days: Int)
    /// Arithmetic and unit conversion, worked out on the iPhone (ADR-270).
    case calculate(expression: String)
    case convertUnits(UnitConversionRequest)
    /// Converted with the ECB's daily rates, fetched by the app (ADR-300).
    case convertCurrency(CurrencyConversionRequest)
    /// Save, find or clear the one parking spot kept on this iPhone (ADR-301).
    case parkingSpot(ParkingAction)
    /// A dish's ingredients on one card with ticks, added to a list on a tap (ADR-305).
    case addIngredients(IngredientsProposal)
    /// "Undo that": the newest undoable change from this conversation, after a card (ADR-271).
    case undoLast
    case setTimer(TimerDraft)
    /// A real alarm (ADR-260), on iOS 26 and later.
    case setAlarm(AlarmDraft)
    /// Doddy's alarms, read on the phone (ADR-283). No card: nothing changes.
    case listAlarms
    /// Turn one of Doddy's alarms off, after a card.
    case cancelAlarm(clock: String, label: String?)
    case openMap(place: String)
    /// User-reviewed handoff to Uber Eats. The summary is shown locally and is never sent to Uber.
    case openUberEats(orderSummary: String?)
    case runShortcut(name: String)
    case draftMessage(MessageDraft)
    /// Gmail, Google Drive, Notion or Todoist through the Doddy server (see OnlineAccounts).
    case cloudTool(CloudToolCall)
    /// Translator mode (ADR-215): proposed on a card; the conversation switches on Start.
    case startTranslator(TranslatorProposal)
    case stopTranslator
    /// Lists (ADR-216). Adding, ticking and removing run on the user's spoken request with a
    /// receipt and Undo (L1); a new list is a card (L2); reading is a lookup.
    case addToList(ListVoiceRequest)
    case readList(name: String)
    case checkOff(ListVoiceRequest)
    case removeFromList(ListVoiceRequest)
    case createList(ListVoiceRequest)
    /// Move or rename an event, or change or complete an Apple reminder (ADR-229): matched
    /// exactly on the iPhone, shown on a card, written only on the user's tap, read back.
    case changeCalendarEvent(EventChangeDraft)
    case changeReminder(ReminderChangeDraft)
    /// Delete one event occurrence (ADR-259), named as read_calendar returned it.
    case deleteCalendarEvent(EventChangeDraft)
    /// Delete one open reminder (ADR-259), by its exact title.
    case deleteReminder(title: String)
    /// Several changes on one card (ADR-280): events starting in the range, deleted.
    case deleteCalendarEvents(VoiceTimeRange)
    /// Open reminders due by a day, moved to another day at their own times.
    case moveReminders(dueBy: ReminderDue, to: ReminderDue)
    /// Something Doddy can't do yet, as a category (ADR-440). Nothing runs; one local row.
    case noteCapabilityGap(CapabilityGapCategory)
    /// "When am I free?" (ADR-332): read-only, worked out on the iPhone.
    case findFreeTime(FreeTimeRequest)
    /// "Remind me when to leave" (ADR-335): travel time from Apple Maps, then a card.
    case leaveBy(LeaveByRequest)
    case unsupported(name: String)
    case invalid(name: String, reason: String)

    public static func parse(name: String, parametersJSON: Data, now: Date = Date(), calendar: Calendar = .current) -> VoiceToolRequest {
        let args = Arguments(parametersJSON)
        // Online-account arguments are checked by Doddy's server (ADR-209).
        if !CloudToolName.all.contains(name), let (key, limit) = args.firstTooLong() {
            return .invalid(name: name, reason: "\(key) is longer than \(limit) characters")
        }
        switch name {
        case VoiceToolName.searchMemories:
            guard let query = args.text("query") else { return .invalid(name: name, reason: "missing query") }
            return .searchMemories(query: query)
        case VoiceToolName.saveMemory:
            guard let text = args.text("text") else { return .invalid(name: name, reason: "missing text") }
            return .saveMemory(text: text)
        case VoiceToolName.readCalendar:
            return parseRead(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.findFreeTime:
            return parseFreeTime(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.remindWhenToLeave:
            return parseLeaveBy(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.createCalendarEvent:
            return parseEvent(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.createReminder:
            return parseReminder(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.remindAboutNote:
            return parseNoteReminder(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.changeCalendarEvent:
            return parseEventChange(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.deleteCalendarEvent:
            return parseEventDelete(args, name: name, calendar: calendar)
        case VoiceToolName.deleteCalendarEvents:
            return parseDeleteEvents(args, name: name, calendar: calendar)
        case VoiceToolName.moveReminders:
            return parseMoveReminders(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.deleteReminder:
            guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
            return .deleteReminder(title: title)
        case VoiceToolName.changeReminder:
            return parseReminderChange(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.lookupContact:
            guard let person = args.text("name") else { return .invalid(name: name, reason: "missing name") }
            return .lookupContact(name: person)
        case VoiceToolName.upcomingBirthdays:
            return parseBirthdays(args, name: name)
        case VoiceToolName.calculate:
            return parseCalculate(args, name: name)
        case VoiceToolName.convertUnits:
            return parseConversion(args, name: name)
        case VoiceToolName.convertCurrency:
            return parseCurrency(args, name: name)
        case VoiceToolName.parkingSpot:
            return parseParking(args, name: name)
        case VoiceToolName.addIngredients:
            return parseIngredients(args, name: name)
        case VoiceToolName.undoLast:
            return .undoLast
        case VoiceToolName.setTimer:
            return parseTimer(args, name: name)
        case VoiceToolName.setAlarm:
            return parseAlarm(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.listAlarms:
            return .listAlarms
        case VoiceToolName.cancelAlarm:
            return parseCancelAlarm(args, name: name)
        case VoiceToolName.openMap:
            guard let place = args.text("place") else { return .invalid(name: name, reason: "missing place") }
            return .openMap(place: place)
        case VoiceToolName.openUberEats:
            return .openUberEats(orderSummary: args.text("order_summary"))
        case VoiceToolName.runShortcut:
            guard let shortcut = args.text("name") else { return .invalid(name: name, reason: "missing name") }
            return .runShortcut(name: shortcut)
        case VoiceToolName.draftMessage:
            return parseMessage(args, name: name)
        case VoiceToolName.startTranslator:
            return parseStartTranslator(args, name: name)
        case VoiceToolName.stopTranslator:
            return .stopTranslator
        case VoiceToolName.noteCapabilityGap:
            guard let raw = args.text("category") else { return .invalid(name: name, reason: "missing category") }
            return .noteCapabilityGap(CapabilityGapCategory(rawValue: raw) ?? .unknown)
        case VoiceToolName.addToList, VoiceToolName.readList, VoiceToolName.checkOff,
             VoiceToolName.removeFromList, VoiceToolName.createList:
            return parseList(args, name: name)
        default:
            return parseCloud(name: name, parametersJSON: parametersJSON) ?? .unsupported(name: name)
        }
    }

    private static func parseRead(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        if let range = args.text("range") {
            switch range.lowercased() {
            case "today": return .readCalendar(VoiceTimeRange(start: day(0), end: day(1)))
            case "tomorrow": return .readCalendar(VoiceTimeRange(start: day(1), end: day(2)))
            case "week": return .readCalendar(VoiceTimeRange(start: day(0), end: day(7)))
            default: return .invalid(name: name, reason: "range must be today, tomorrow or week")
            }
        }
        guard let fromText = args.text("from"), case .due(let from) = ReminderDueRules.wallClock(fromText, calendar: calendar),
              let start = from.date(in: calendar) else {
            return .invalid(name: name, reason: "missing range or from")
        }
        let end: Date
        if let toText = args.text("to") {
            guard case .due(let to) = ReminderDueRules.wallClock(toText, calendar: calendar), let toDate = to.date(in: calendar) else {
                return .invalid(name: name, reason: "to is not a date")
            }
            end = toDate
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        guard end > start else { return .invalid(name: name, reason: "to must be after from") }
        guard end.timeIntervalSince(start) <= 31 * 86_400 else { return .invalid(name: name, reason: "range is longer than 31 days") }
        return .readCalendar(VoiceTimeRange(start: start, end: end))
    }

    /// Strict like reminders (ADR-127, ADR-128): start and end are local wall-clock times the agent
    /// wrote out, in the phone's zone, not a time the clocks skip or repeat, and not already passed.
    /// Anything else goes back to the agent as a question rather than being shifted.
    private static func parseEvent(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        guard let startText = args.text("start") else { return .invalid(name: name, reason: "missing start") }
        let startDue: ReminderDue
        switch ReminderDueRules.wallClock(startText, calendar: calendar) {
        case .due(let checked): startDue = checked
        case .clarify(let clarification): return .needsClarification(name: name, clarification)
        }
        guard let start = startDue.date(in: calendar) else { return .invalid(name: name, reason: "missing start") }
        // The user's own words for when, if the agent passed them (ADR-253).
        if let said = args.text("said_time") {
            let day = ReminderDue(year: startDue.year, month: startDue.month, day: startDue.day, timeZoneID: startDue.timeZoneID)
            let allDay = args.flag("all_day")
            if let question = SaidTime.check(said, due: allDay ? day : startDue, now: now, timeRequired: !allDay) {
                return .needsClarification(name: name, question)
            }
        }
        let repeats: CalendarRepeat?
        switch parseRepeat(args, name: name, first: startDue, calendar: calendar) {
        case .success(let rule): repeats = rule
        case .failure(.invalid(let reason)): return .invalid(name: name, reason: reason)
        case .failure(.clarify(let clarification)): return .needsClarification(name: name, clarification)
        }
        if args.flag("all_day") {
            let dayStart = calendar.startOfDay(for: start)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return proposeEvent(CalendarEventDraft(
                title: title, start: dayStart, end: dayEnd, allDay: true,
                location: args.text("location"), notes: args.text("notes"), repeats: repeats), name: name, now: now, calendar: calendar)
        }
        guard startDue.hasTime else { return .invalid(name: name, reason: "start needs a time unless all_day is true") }
        let end: Date
        if let endText = args.text("end") {
            let endDue: ReminderDue
            switch ReminderDueRules.wallClock(endText, calendar: calendar) {
            case .due(let checked): endDue = checked
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            }
            guard endDue.hasTime, let parsed = endDue.date(in: calendar), parsed > start else {
                return .invalid(name: name, reason: "end must be a time after start")
            }
            end = parsed
        } else {
            end = start.addingTimeInterval(3600)
        }
        return proposeEvent(CalendarEventDraft(
            title: title, start: start, end: end, allDay: false,
            location: args.text("location"), notes: args.text("notes"), repeats: repeats), name: name, now: now, calendar: calendar)
    }

    private static func proposeEvent(_ draft: CalendarEventDraft, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        if let late = draft.passed(now: now, calendar: calendar) { return .needsClarification(name: name, late) }
        return .createCalendarEvent(draft)
    }

    /// Strict (M4): the due is a day the agent wrote out, local time in the phone's zone, still
    /// ahead and not skipped or repeated by a clock change. Otherwise the agent is asked to clarify.
    private static func parseReminder(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .invalid(name: name, reason: "missing title")
        }
        var due: ReminderDue?
        if let dueText = args.text("due") {
            switch ReminderDueRules.check(dueText, now: now, calendar: calendar) {
            case .due(let checked): due = checked
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            }
        }
        // The user's own words for when, if the agent passed them (ADR-253).
        if let said = args.text("said_time") {
            guard let due else {
                // Words about a time but no due: ask rather than add a reminder without one.
                return .needsClarification(name: name, ReminderClarification(
                    kind: .saidDifferently,
                    problem: "the user said \"\(said)\" but the request has no due date",
                    question: "which day, and what time if any, they want it"))
            }
            if let question = SaidTime.check(said, due: due, now: now, timeRequired: false) {
                return .needsClarification(name: name, question)
            }
        }
        let repeats: CalendarRepeat?
        switch parseRepeat(args, name: name, first: due, calendar: calendar) {
        case .success(let rule): repeats = rule
        case .failure(.invalid(let reason)): return .invalid(name: name, reason: reason)
        case .failure(.clarify(let clarification)): return .needsClarification(name: name, clarification)
        }
        return .createReminder(ReminderDraft(title: title, due: due, notes: args.text("notes"), repeats: repeats))
    }

    private static func parseTimer(_ args: Arguments, name: String) -> VoiceToolRequest {
        let minutes = args.number("minutes") ?? 0
        let seconds = args.number("seconds") ?? 0
        guard minutes >= 0, seconds >= 0 else { return .invalid(name: name, reason: "negative duration") }
        // Checked as a Double first: Int(_:) traps on a value it can't hold (review C6).
        let length = (minutes * 60 + seconds).rounded()
        guard length.isFinite, length <= 86_400 else { return .invalid(name: name, reason: "timer is longer than 24 hours") }
        let total = Int(length)
        guard total >= 1 else { return .invalid(name: name, reason: "missing duration") }
        return .setTimer(TimerDraft(seconds: total, label: args.text("label")))
    }

    private static func parseMessage(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let recipient = args.text("to") else { return .invalid(name: name, reason: "missing to") }
        guard let body = args.text("body") else { return .invalid(name: name, reason: "missing body") }
        guard let channel = MessageChannel(rawValue: (args.text("channel") ?? "text").lowercased()) else {
            return .invalid(name: name, reason: "channel must be text or email")
        }
        return .draftMessage(MessageDraft(recipientName: recipient, channel: channel, body: body))
    }
}

/// Tool arguments as the model sent them. Missing or blank values read as nil.
struct Arguments {
    private let values: [String: Any]

    init(_ data: Data) {
        values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func text(_ key: String) -> String? {
        guard let value = values[key] as? String, !value.allSatisfy(\.isWhitespace) else { return nil }
        return value
    }

    /// A list of strings; a single string counts as a list of one.
    func texts(_ key: String) -> [String]? {
        if let list = values[key] as? [Any] { return list.compactMap { $0 as? String } }
        return text(key).map { [$0] }
    }

    func flag(_ key: String) -> Bool {
        values[key] as? Bool ?? false
    }

    func number(_ key: String) -> Double? {
        values[key] as? Double
    }

    /// The first text argument longer than its bound, if any (review C11). Too long is refused,
    /// never cut: the agent hears which argument and asks the user. List items are bounded by
    /// the list itself (ListLimits.itemLength), item by item.
    func firstTooLong() -> (key: String, limit: Int)? {
        for key in values.keys.sorted() {
            guard let value = values[key] as? String else { continue }
            let limit = VoiceTextLimits.limit(for: key)
            if value.unicodeScalars.count > limit { return (key, limit) }
        }
        return nil
    }

    /// The key is present, whatever its value.
    func has(_ key: String) -> Bool {
        values[key] != nil
    }
}

/// Bounds on text the model sends to a phone tool (review C11). A note, or a note quoted back,
/// may be as long as a saved note; notes on an event or reminder and a message body are
/// paragraphs; everything else (titles, names, labels, times) is a line.
public enum VoiceTextLimits {
    public static let line = EventChange.maxTitleLength
    public static let paragraph = 2_000
    public static let search = 500

    public static func limit(for key: String) -> Int {
        switch key {
        case "text", "note": MemoryLimits.maxTextLength
        case "notes", "body": paragraph
        case "query", "place": search
        default: line
        }
    }
}

/// Links that open other apps. The user always taps; Doddy never sends a message or places a call.
public enum OpenLinks {
    public static func map(place: String) -> URL? {
        URL(string: "https://maps.apple.com/?q=\(encode(place))")
    }

    /// Opens the public Uber Eats entry point. Doddy does not transmit a menu query or cart.
    public static func uberEats() -> URL? {
        URL(string: "https://www.ubereats.com/")
    }

    public static func shortcut(name: String) -> URL? {
        URL(string: "shortcuts://run-shortcut?name=\(encode(name))")
    }

    /// Digits and a leading plus sign only. Nil when nothing dialable is left.
    public static func call(number: String) -> URL? {
        let digits = dialable(number)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    public static func text(number: String, body: String) -> URL? {
        let digits = dialable(number)
        guard !digits.isEmpty else { return nil }
        return URL(string: "sms:\(digits)&body=\(encode(body))")
    }

    public static func email(address: String, body: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return URL(string: "mailto:\(trimmed)?body=\(encode(body))")
    }

    private static func dialable(_ number: String) -> String {
        String(number.enumerated().compactMap { index, character in
            character.isNumber || (index == 0 && character == "+") ? character : nil
        })
    }

    /// Encodes everything except letters and digits, so "+", "&" and spaces survive the trip.
    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}

/// "Open camera" runs the user's "Doddy Camera" Shortcut, which opens the Camera app (ADR-291):
/// iOS gives other apps no public way to open Camera, and Doddy itself never uses the camera.
/// `installLink` is the owner's shared iCloud copy of that Shortcut, so a user can add it with one
/// tap instead of building it; nil until the owner shares one, and then the app shows the steps.
public enum CameraShortcut {
    /// Must match the name in `voice-agent/instructions.md` and `tools.json`.
    public static let name = "Doddy Camera"

    /// The run card is the camera one when the agent asks for this shortcut, whatever the case
    /// or spacing it used.
    public static func isCamera(_ shortcutName: String) -> Bool {
        shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(name, options: [.caseInsensitive]) == .orderedSame
    }

    /// The owner's shared copy. Set it with `installLink(from:)` so a mistyped link fails a test.
    public static let installLink: URL? = nil

    /// Only an iCloud Shortcuts share link (`https://www.icloud.com/shortcuts/<32 hex>`) is
    /// accepted, so the button can never open anything else.
    public static func installLink(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host == "www.icloud.com",
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0] == "shortcuts", parts[1].count == 32,
              parts[1].allSatisfy(\.isHexDigit) else { return nil }
        return url
    }
}

/// Text returned to the agent. Written for the model: it states only what the app verified.
/// Result prefixes ("added", "declined", "failed", "unknown", "saved", "opened") are what the
/// agent's prompt tells it to look for, so they must not change without changing the prompt.
public enum VoiceToolReply {
    /// How a reply starts when the change happened and was read back. "What Doddy did" and the
    /// plan summary both read these, so a new result verb must be added here (review C1, D3).
    public static let donePrefixes = [
        "added:", "saved:", "drafted:", "changed:", "completed:", "deleted:", "created:",
        // Round 3 (ADR-280, ADR-283): reminders moved, an alarm turned off. Round 4 (ADR-301,
        // ADR-303): a parking spot cleared, a Todoist task moved. Each read back first.
        "moved:", "turned off:", "cleared:",
    ]
    /// List results: `added to the list: 1 item.`, then the list's name and the items as data
    /// (listAdded, listChanged).
    public static let listDonePrefixes = ["added to the list:", "ticked on the list:", "removed on the list:"]
    /// Nothing changed; the agent asks the user which one, or offers something else.
    public static let nothingChangedPrefixes = ["not changed:", "not added:", "not created:"]

    public static let declined = "declined: the user chose not to save this note. Nothing was saved."
    public static let declinedEvent = "declined: the user chose not to add this event. Nothing was added."
    public static let declinedReminder = "declined: the user chose not to add this reminder. Nothing was added."
    public static let declinedTimer = "declined: the user chose not to start this timer. Nothing was set."
    public static let declinedMap = "declined: the user chose not to open the map. Nothing was opened."
    public static let declinedShortcut = "declined: the user chose not to run the shortcut. Nothing was run."
    public static let declinedMessage = "declined: the user chose not to open the draft. Nothing was sent."

    /// `question` is the query the search ran with; it lets the reply say when the notes cover
    /// only part of it (ADR-251). An empty question skips that check.
    public static func search(_ outcome: RecallOutcome, question: String = "", limit: Int = 5) -> String {
        guard case .matches(let candidates) = outcome, !candidates.isEmpty else {
            return "No saved note matched. Tell the user you couldn't find it in their saved memories. Do not guess."
        }
        let shown = candidates.prefix(limit)
        let mayDisagree = RecallConflicts.flagged(Array(shown))
        let noun = "saved note\(candidates.count == 1 ? "" : "s")"
        let coverage = RecallCoverage(question: question, candidates: candidates)
        var lines: [String] = []
        if coverage.isPartial {
            let missing = coverage.missing.map { "\"\($0.label)\"" }.joined(separator: ", ")
            lines.append("Found \(candidates.count) \(noun), but none contains every key word of the search.")
            lines.append(missing.isEmpty
                ? "Each note matches only some of the words."
                : "No saved note contains: \(missing). If a missing word is only a translation of a word that was found, ignore it. Otherwise tell the user plainly that no saved note mentions it, and that these notes match only part of what they asked. Do not present them as the answer.")
            lines.append("Partial matches (exact text, newest wording):")
        } else {
            lines.append("Found \(candidates.count) \(noun) (exact text, newest wording):")
        }
        lines.append(ToolData.block(shown.map { candidate in
            let flag = mayDisagree.contains(candidate.memoryID) ? " [may disagree]" : ""
            return "- \"\(ToolData.clean(candidate.record.currentText))\" (saved \(timestamp(candidate.record.capturedAt)))\(flag)"
        }))
        if !mayDisagree.isEmpty {
            lines.append("Notes marked [may disagree] give different numbers for the same thing. Mention each one with when it was saved and let the user decide which is current. Do not pick one.")
        }
        if candidates.count > shown.count {
            lines.append("…and \(candidates.count - shown.count) more. Ask the user to narrow it down if needed.")
        }
        return lines.joined(separator: "\n")
    }

    /// The note follows as data (ToolData).
    public static func saved(_ record: MemoryRecord) -> String {
        "saved: one note (saved \(timestamp(record.capturedAt))). Its exact text:\n"
            + ToolData.block(["\"\(ToolData.clean(record.currentText))\""])
    }

    public static func failed(_ reason: String) -> String {
        "failed: \(reason) Nothing was saved."
    }

    /// What a failed write left alone, so a failed change or delete doesn't say "saved" (review finding 8).
    public enum FailedWrite: String, Sendable {
        case saved, changed, deleted
    }

    public static func failed(_ reason: String, nothing: FailedWrite) -> String {
        "failed: \(reason) Nothing was \(nothing.rawValue)."
    }

    /// The tool's name is the agent's own text, so it follows as data (ToolData).
    public static func unsupported(_ name: String) -> String {
        "The app does not support the tool below. Tell the user this isn't available yet.\n"
            + ToolData.block([quoted("Tool", name)])
    }

    /// Used when a function is off or its iOS permission is not granted.
    public static func notConnected(_ connection: VoiceConnection) -> String {
        "\(connection.title) isn't connected. Tell the user they can connect it in Settings, Connections."
    }

    public static func calendarEvents(_ events: [CalendarEventSummary], range: VoiceTimeRange, calendar: Calendar, limit: Int = 20) -> String {
        let window = "from \(localText(range.start, hasTime: false, calendar: calendar)) to \(localText(range.end, hasTime: false, calendar: calendar))"
        guard !events.isEmpty else {
            return "No calendar events \(window). Say so; do not guess."
        }
        var lines = ["Found \(events.count) calendar event\(events.count == 1 ? "" : "s") \(window) (exact titles and times):"]
        lines.append(ToolData.block(events.prefix(limit).map { event in
            let when = event.allDay
                ? "\(localText(event.start, hasTime: false, calendar: calendar)) (all day)"
                : "\(localText(event.start, hasTime: true, calendar: calendar))–\(localText(event.end, hasTime: true, calendar: calendar))"
            return "- \"\(ToolData.clean(event.title))\" \(when)"
        }))
        if events.count > limit {
            lines.append("…and \(events.count - limit) more.")
        }
        return lines.joined(separator: "\n")
    }

    /// The title is the agent's words, so it follows as data (ToolData).
    public static func eventAdded(_ draft: CalendarEventDraft, calendar: Calendar) -> String {
        let repeats = draft.repeats.map { " Repeats \($0.text)." } ?? ""
        let when = draft.allDay
            ? "\(localText(draft.start, hasTime: false, calendar: calendar)) (all day)"
            : "\(localText(draft.start, hasTime: true, calendar: calendar)) to \(localText(draft.end, hasTime: true, calendar: calendar))"
        return "added: an event on \(when).\(repeats) Its title:\n" + ToolData.block([quoted("Title", draft.title)])
    }

    /// The timer is scheduled and confirmed. The user hears it ring at `endsAt`. A label is the
    /// agent's words, so it follows as data (ToolData).
    public static func timerAdded(_ draft: TimerDraft, endsAt: Date, calendar: Calendar) -> String {
        let text = "added: timer \(durationText(draft.seconds)), rings at \(localText(endsAt, hasTime: true, calendar: calendar))."
        guard let label = draft.label else { return text }
        return text + " Its label:\n" + ToolData.block([quoted("Label", label)])
    }

    /// Maps opened on the user's tap. Nothing else is claimed. The place follows as data.
    public static func mapOpened(_ place: String) -> String {
        "opened: Apple Maps opened for the place below.\n" + ToolData.block([quoted("Place", place)])
    }

    /// Opening Uber Eats is only a handoff. No cart, checkout, payment, or order is performed.
    public static let uberEatsOpened = "opened: Uber Eats was opened. Doddy did not create a cart or place an order; the user must choose items and complete checkout in Uber Eats."
    public static let uberEatsDeclined = "declined: Uber Eats was not opened. No cart or order was created."

    /// Shortcuts is asked to run; Doddy cannot see whether the shortcut finished.
    public static func shortcutRequested(_ name: String) -> String {
        "opened: asked Shortcuts to run the shortcut below. Doddy can't see whether it finished.\n"
            + ToolData.block([quoted("Shortcut", name)])
    }

    /// The draft opened in Messages or Mail. Doddy did not send it. The name is from Contacts,
    /// so it follows as data (ToolData).
    public static func messageOpened(_ draft: MessageDraft, recipient: String) -> String {
        let app = draft.channel == .text ? "Messages" : "Mail"
        return "opened: \(app) opened with the draft for the contact below. Nothing was sent by Doddy; the user sends it there.\n"
            + ToolData.block([quoted("Contact", recipient)])
    }

    /// The contact has no phone number or email for the channel the agent asked for. The name
    /// is from Contacts, so it follows as data.
    public static func noAddress(_ recipient: String, channel: MessageChannel) -> String {
        let what = channel == .text ? "phone number" : "email address"
        return "failed: the contact below has no \(what) in Contacts. Nothing was opened.\n"
            + ToolData.block(["Contact: \"\(ToolData.clean(recipient))\""])
    }

    /// The app could not open the other app.
    public static func notOpened(_ reason: String) -> String {
        "failed: \(reason) Nothing was opened."
    }

    /// The app could not add the item.
    public static func notAdded(_ reason: String) -> String {
        "failed: \(reason) Nothing was added."
    }

    /// The app saved the item but could not read it back. The user must check before retrying.
    public static let addUnconfirmed = "unknown: the app could not confirm it was added. It may not have gone through; ask the user to check before trying again."

    /// Names only. Details stay on the user's screen.
    public static func contactMatches(_ names: [String], query: String) -> String {
        // The search is the agent's words and the names are from Contacts: data, not instructions.
        let searched = quoted("Searched for", query)
        guard !names.isEmpty else {
            return "No contact matched the search below. Tell the user you couldn't find them in Contacts. Do not guess.\n"
                + ToolData.block([searched])
        }
        return "Found \(names.count) contact\(names.count == 1 ? "" : "s") matching the search, names only; the search, then the names:\n"
            + ToolData.block([searched] + names.map { "- \(ToolData.clean($0))" })
            + "\nTheir details are on the user's screen. Say you've put them on the screen; never read out or guess a number or address."
    }

    /// One line for a ToolData block: `Label: "text"`, the text cleaned (no markers, one line).
    static func quoted(_ label: String, _ text: String) -> String {
        "\(label): \"\(ToolData.clean(text))\""
    }

    static func durationText(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "date unavailable" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func localText(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
