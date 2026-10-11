import Foundation

// Moving and renaming calendar events, and changing or completing Apple reminders, by voice
// (ADR-229). The agent names the event exactly as read_calendar returned it (title and start), or
// the reminder by its exact title. The app finds exactly one match on the iPhone, shows a card
// with the change ("Before → After"), and changes it only after the user taps Change. The write
// is read back from Calendar or Reminders before Doddy says it's done. Deleting is still not
// offered, and a repeating event changes only this occurrence.

extension VoiceToolName {
    public static let changeCalendarEvent = "change_calendar_event"
    public static let changeReminder = "change_reminder"
    /// Deleting (ADR-259): one event occurrence, or one open reminder, after a card.
    public static let deleteCalendarEvent = "delete_calendar_event"
    public static let deleteReminder = "delete_reminder"
}

public struct EventChangeDraft: Equatable, Sendable {
    /// The event as the agent read it: exact title and its current start.
    public let title: String
    public let currentStart: Date
    /// Only this date counts (an all-day event named by its day).
    public let currentIsDayOnly: Bool
    public let newStart: Date?
    /// `newStart` named only a day ("move it to Friday"): a timed event keeps its time of day.
    public let newStartIsDayOnly: Bool
    public let newEnd: Date?
    public let newTitle: String?
    /// A new place (ADR-281). Replaces the old one, which the card shows (never the agent).
    public let newLocation: String?
    /// A line added to the end of the event's notes (ADR-281).
    public let addNote: String?
    /// The notes replaced by this text, "" to clear them (ADR-314). The card shows the old notes.
    public let replaceNotes: String?

    public init(
        title: String, currentStart: Date, currentIsDayOnly: Bool, newStart: Date?, newEnd: Date?, newTitle: String?,
        newLocation: String? = nil, addNote: String? = nil, replaceNotes: String? = nil, newStartIsDayOnly: Bool = false
    ) {
        self.replaceNotes = replaceNotes
        self.newLocation = newLocation
        self.addNote = addNote
        self.title = title
        self.currentStart = currentStart
        self.currentIsDayOnly = currentIsDayOnly
        self.newStart = newStart
        self.newStartIsDayOnly = newStartIsDayOnly
        self.newEnd = newEnd
        self.newTitle = newTitle
    }
}

public struct ReminderChangeDraft: Equatable, Sendable {
    public let title: String
    public let newDue: ReminderDue?
    public let markDone: Bool
    /// A line to add at the end of the notes (ADR-302).
    public let addNote: String?
    public let priority: ReminderPriority?
    /// The Reminders list the user named; matched on the iPhone into `toList`.
    public let listName: String?
    /// The one list `listName` matched, set by the app before the card is shown.
    public var toList: ReminderListRef?
    /// ADR-314: a new title, a new repeat or none, the notes replaced.
    public let newTitle: String?
    public let repeatChange: ReminderRepeatChange?
    public let replaceNotes: String?

    public init(title: String, newDue: ReminderDue?, markDone: Bool, addNote: String? = nil,
                priority: ReminderPriority? = nil, listName: String? = nil, toList: ReminderListRef? = nil,
                newTitle: String? = nil, repeatChange: ReminderRepeatChange? = nil, replaceNotes: String? = nil) {
        self.newTitle = newTitle
        self.repeatChange = repeatChange
        self.replaceNotes = replaceNotes
        self.title = title
        self.newDue = newDue
        self.markDone = markDone
        self.addNote = addNote
        self.priority = priority
        self.listName = listName
        self.toList = toList
    }

    /// The details change as the card shows it (ADR-302); empty for a due or done alone.
    public var details: ReminderDetailsChange {
        ReminderDetailsChange(addNote: addNote, priority: priority, toList: toList,
                              newTitle: newTitle, repeatChange: repeatChange, replaceNotes: replaceNotes)
    }
    public var changesDetails: Bool {
        addNote != nil || priority != nil || listName != nil || newTitle != nil || repeatChange != nil || replaceNotes != nil
    }
}

/// What the card shows and what is written: the event as it is now and as it will be.
public struct EventChangePlan: Codable, Equatable, Sendable {
    public let before: CalendarEventSummary
    public let after: CalendarEventSummary
    /// The place now, read on this iPhone for the card and the stale check only (ADR-281).
    public let locationBefore: String?
    /// The new place; nil: the place doesn't change.
    public let newLocation: String?
    /// A line to add at the end of the notes.
    public let addNote: String?
    /// Undo of `addNote`: this exact line comes off the end of the notes again.
    public let removeNote: String?
    /// The notes now, read on this iPhone for the card, the stale check and Undo (ADR-314).
    public let notesBefore: String?
    /// The notes replaced by this text ("" clears them); nil: not replaced.
    public let replaceNotes: String?

    public init(before: CalendarEventSummary, after: CalendarEventSummary, locationBefore: String? = nil,
                newLocation: String? = nil, addNote: String? = nil, removeNote: String? = nil,
                notesBefore: String? = nil, replaceNotes: String? = nil) {
        self.notesBefore = notesBefore
        self.replaceNotes = replaceNotes
        self.before = before
        self.after = after
        self.locationBefore = locationBefore
        self.newLocation = newLocation
        self.addNote = addNote
        self.removeNote = removeNote
    }

    /// Something besides the time and title changes.
    public var changesDetails: Bool { newLocation != nil || addNote != nil || removeNote != nil || replaceNotes != nil }
}

/// What a reminder change does on the iPhone (ADR-229, ADR-258).
public enum ReminderChange: Equatable, Sendable {
    /// A new due, or nil to clear it (only Undo clears a due).
    case due(ReminderDue?)
    case complete
    /// Undo of a completion: the reminder is open again.
    case reopen
    /// A note, priority or list, with a new due or nil to keep it (ADR-302), in one save.
    case details(newDue: ReminderDue?, ReminderDetailsChange)
}

public enum EventChange {
    public static let maxTitleLength = 200
    public static let maxLocationLength = 200
    public static let maxNoteLength = 500

    /// Notes with `line` added at the end, on a line of its own.
    public static func notes(_ current: String?, adding line: String) -> String {
        guard let current, !current.isEmpty else { return line }
        return current.hasSuffix("\n") ? current + line : current + "\n" + line
    }

    /// Notes with `line` taken off the end again (Undo); nil when they no longer end with it.
    public static func notes(_ current: String?, removing line: String) -> String?? {
        guard let current else { return nil }
        if current == line { return .some(nil) }
        guard current.hasSuffix("\n" + line) else { return nil }
        return .some(String(current.dropLast(line.count + 1)))
    }

    /// Exactly one event with this title (ignoring case, accents and punctuation) starting at the
    /// same minute (or on the same day, for a day-only name). Otherwise nothing is guessed.
    public static func match(_ draft: EventChangeDraft, in events: [CalendarEventSummary], calendar: Calendar) -> ListMatchResult<CalendarEventSummary> {
        let wanted = SearchFolding.tokens(draft.title).joined(separator: " ")
        guard !wanted.isEmpty else { return .none }
        let found = events.filter { event in
            guard SearchFolding.tokens(event.title).joined(separator: " ") == wanted else { return false }
            if draft.currentIsDayOnly { return calendar.isDate(event.start, inSameDayAs: draft.currentStart) }
            return abs(event.start.timeIntervalSince(draft.currentStart)) < 60
        }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// The new event. A new start alone keeps the length; a new end alone keeps the start. An
    /// all-day event moved to a day stays all day. Nil when the result makes no sense.
    public static func plan(_ draft: EventChangeDraft, for event: CalendarEventSummary, locationBefore: String? = nil,
                            notesBefore: String? = nil, calendar: Calendar) -> EventChangePlan? {
        var start = event.start, end = event.end
        let length = event.end.timeIntervalSince(event.start)
        if let newStart = draft.newStart {
            if event.allDay {
                start = calendar.startOfDay(for: newStart)
                end = calendar.date(byAdding: .day, value: max(1, Int((length / 86_400).rounded())), to: start) ?? start
            } else if draft.newStartIsDayOnly {
                // A day alone keeps the event's time of day, never midnight (review C7).
                let time = calendar.dateComponents([.hour, .minute, .second], from: event.start)
                var moved = calendar.dateComponents([.year, .month, .day], from: newStart)
                (moved.hour, moved.minute, moved.second) = (time.hour, time.minute, time.second)
                // A time the clocks skip on that day is not shifted: no plan, and the agent asks.
                guard let date = calendar.date(from: moved),
                      calendar.dateComponents([.hour, .minute], from: date) == DateComponents(hour: time.hour, minute: time.minute)
                else { return nil }
                start = date
                end = date.addingTimeInterval(length)
            } else {
                start = newStart
                end = newStart.addingTimeInterval(length)
            }
        }
        if let newEnd = draft.newEnd, !event.allDay { end = newEnd }
        guard end > start else { return nil }
        let title = draft.newTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? event.title
        guard title.count <= maxTitleLength else { return nil }
        let after = CalendarEventSummary(id: event.id, title: title, start: start, end: end, allDay: event.allDay)
        let location = draft.newLocation?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let newLocation = location == (locationBefore ?? "").nonEmpty ? nil : location
        let note = draft.addNote?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        // Replacing with the same notes is no change (ADR-314).
        let replace = draft.replaceNotes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0 == (notesBefore ?? "") ? nil : $0 }
        guard after != event || newLocation != nil || note != nil || replace != nil else { return nil }
        return EventChangePlan(before: event, after: after, locationBefore: locationBefore, newLocation: newLocation, addNote: note,
                               notesBefore: replace == nil ? nil : notesBefore, replaceNotes: replace)
    }

    /// Where to look for the event: the whole day it starts on.
    public static func searchRange(_ draft: EventChangeDraft, calendar: Calendar) -> VoiceTimeRange {
        let day = calendar.startOfDay(for: draft.currentStart)
        return VoiceTimeRange(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400))
    }

    /// The new start passed while the card waited: nothing is moved into the past.
    public static func startPassed(_ plan: EventChangePlan, now: Date, calendar: Calendar) -> Bool {
        guard plan.after.start != plan.before.start else { return false }
        return plan.after.allDay ? plan.after.start < calendar.startOfDay(for: now) : plan.after.start <= now
    }

    /// Read-back for a reminder's due: the same day and wall-clock time (the zone may come back
    /// spelled differently).
    public static func sameDue(_ a: ReminderDue?, _ b: ReminderDue?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.year == b.year && a.month == b.month && a.day == b.day && a.hour == b.hour && (a.minute ?? 0) == (b.minute ?? 0)
        default: return false
        }
    }

    /// The moment a due stands for: in its own time zone when it has one, else on this iPhone's
    /// clock (a floating day or time, as Reminders keeps it).
    public static func moment(_ due: ReminderDue, local: Calendar) -> Date? {
        due.date(in: due.timeZoneID == nil ? local : due.calendar)
    }

    /// A new timed due passed while the card waited.
    public static func duePassed(_ due: ReminderDue?, now: Date, local: Calendar) -> Bool {
        guard let due, due.hasTime, let date = moment(due, local: local) else { return false }
        return date <= now
    }

    /// An occurrence's id is its calendar item id and its start, so it changes when it moves.
    public static func occurrenceID(itemID: String, start: Date) -> String {
        // One format for the whole app (ADR-268 merge): CalendarEventSummary builds it.
        CalendarEventSummary.occurrenceID(itemID: itemID, start: start)
    }

    /// Undo (ADR-258): the change backwards. Its "before" is the event as Doddy left it, with the
    /// occurrence id it has at its new start, so the usual check (it must still look exactly so)
    /// refuses an undo after anyone else changed it.
    public static func reversed(_ plan: EventChangePlan) -> EventChangePlan {
        let itemID = plan.before.id.map { CalendarEventSummary.itemID(fromOccurrence: $0) ?? $0 }
        let now = CalendarEventSummary(
            id: itemID.map { occurrenceID(itemID: $0, start: plan.after.start) }, title: plan.after.title,
            start: plan.after.start, end: plan.after.end, allDay: plan.after.allDay)
        let back = CalendarEventSummary(
            id: itemID.map { occurrenceID(itemID: $0, start: plan.before.start) }, title: plan.before.title,
            start: plan.before.start, end: plan.before.end, allDay: plan.before.allDay)
        // The place goes back; an added line comes off the notes again; replaced notes come back.
        return EventChangePlan(
            before: now, after: back, locationBefore: plan.newLocation ?? plan.locationBefore,
            newLocation: plan.newLocation.map { _ in plan.locationBefore ?? "" }, addNote: nil, removeNote: plan.addNote,
            notesBefore: plan.replaceNotes, replaceNotes: plan.replaceNotes.map { _ in plan.notesBefore ?? "" })
    }

    /// Exactly one open reminder with this title.
    public static func matchReminder(_ title: String, in reminders: [ReminderSnapshot]) -> ListMatchResult<ReminderSnapshot> {
        let wanted = SearchFolding.tokens(title).joined(separator: " ")
        guard !wanted.isEmpty else { return .none }
        let found = reminders.filter { !$0.isCompleted && SearchFolding.tokens($0.title).joined(separator: " ") == wanted }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}

extension VoiceToolReply {
    /// The title is the agent's words, so it follows as data (ToolData).
    public static func eventNotFound(_ title: String) -> String {
        "not found: no event with the title below at that time on the user's calendar. Nothing changed. Call read_calendar for that day and use the exact title and start it returns.\n"
            + eventTitle(title)
    }

    public static func eventAmbiguous(_ events: [CalendarEventSummary], calendar: Calendar) -> String {
        let times = events.prefix(4).map { "- \"\(ToolData.clean($0.title))\" \(localText($0.start, hasTime: !$0.allDay, calendar: calendar))" }
        return "not changed: more than one event matches. Ask the user which one:\n" + ToolData.block(times)
    }

    public static let eventChangeInvalid = "failed: that change doesn't make sense (the end would be before the start, or nothing would change). Nothing changed. Ask the user what they want."

    public static func eventChanged(_ after: CalendarEventSummary, calendar: Calendar) -> String {
        eventChanged(after, extra: "", data: [], calendar: calendar)
    }

    /// The title, and any new place or added note, follow as data (ToolData).
    private static func eventChanged(_ after: CalendarEventSummary, extra: String, data: [String], calendar: Calendar) -> String {
        let when = after.allDay
            ? "\(localText(after.start, hasTime: false, calendar: calendar)) (all day)"
            : "\(localText(after.start, hasTime: true, calendar: calendar))–\(localText(after.end, hasTime: true, calendar: calendar))"
        return "changed: the event is now \(when).\(extra) Checked in Calendar.\n"
            + ToolData.block(["Title: \"\(ToolData.clean(after.title))\""] + data)
    }

    /// A title read from Calendar or Reminders, as data (ToolData): an invite's title is someone else's text.
    private static func eventTitle(_ title: String) -> String {
        ToolData.block(["Title: \"\(ToolData.clean(title))\""])
    }

    /// With the place or an added note (ADR-281). The old place is never sent to the agent.
    public static func eventChanged(_ plan: EventChangePlan, calendar: Calendar) -> String {
        var extra = ""
        var data: [String] = []
        if let place = plan.newLocation {
            extra += place.isEmpty ? " Its place was cleared." : " Its place changed."
            if !place.isEmpty { data.append("New place: \"\(ToolData.clean(place))\"") }
        }
        if let note = plan.addNote {
            extra += " A line was added to its notes."
            data.append("Added to its notes: \"\(ToolData.clean(note))\"")
        }
        if plan.removeNote != nil { extra += " The added line came off its notes again." }
        return eventChanged(plan.after, extra: extra, data: data, calendar: calendar)
    }

    public static let eventChangeTimePassed = "failed: the new time passed while the card was waiting. Nothing changed. Ask the user for a new time."
    public static let eventChangedElsewhere = "failed: the event changed or disappeared in Calendar since the card was shown. Nothing was changed by Doddy. Ask the user to check Calendar."
    public static let eventChangeUnconfirmed = "unknown: Calendar didn't confirm the change. Ask the user to check Calendar before trying again."
    public static let changeNothingNew = "not changed: it already looks like that. Nothing changed."
    public static let changeDeclined = "declined: the user chose not to make this change. Nothing changed."

    public static func reminderNotFound(_ title: String) -> String {
        "not found: no open reminder with the title below in Reminders. Nothing changed. Ask the user for its exact name.\n"
            + eventTitle(title)
    }

    public static func reminderAmbiguous(_ reminders: [ReminderSnapshot]) -> String {
        let lists = reminders.prefix(4).map {
            "- \"\(ToolData.clean($0.title))\" in \(ToolData.clean($0.listTitle))\($0.due.map { ", due \(ReminderText.due($0))" } ?? "")"
        }
        return "not changed: more than one open reminder matches. Ask the user which one:\n" + ToolData.block(lists)
    }

    public static func reminderChanged(_ title: String, due: ReminderDue?) -> String {
        "changed: the reminder is now due \(due.map(ReminderText.due) ?? "with no date"). Checked in Reminders.\n" + eventTitle(title)
    }

    public static func reminderCompleted(_ title: String) -> String {
        "completed: the reminder is marked done in Reminders. Checked.\n" + eventTitle(title)
    }

    public static let reminderChangedElsewhere = "failed: the reminder changed, was completed or disappeared in Reminders since the card was shown. Nothing was changed by Doddy. Ask the user to check Reminders."
    public static let undoUnconfirmed = "unknown: Calendar or Reminders didn't confirm putting it back. Ask the user to check."
    public static func eventDeleted(_ event: CalendarEventSummary, calendar: Calendar) -> String {
        "deleted: the event at \(localText(event.start, hasTime: !event.allDay, calendar: calendar)) is gone from Calendar. Checked.\n"
            + eventTitle(event.title)
    }

    public static func reminderDeleted(_ title: String) -> String {
        "deleted: the reminder is gone from Reminders. Checked.\n" + eventTitle(title)
    }

    public static let deleteDeclined = "declined: the user chose not to delete it. Nothing changed."
    public static let deleteUnconfirmed = "unknown: Calendar or Reminders didn't confirm it's gone. Ask the user to check before trying again."
    public static let reminderChangeUnconfirmed = "unknown: Reminders didn't confirm the change. Ask the user to check Reminders before trying again."
}

extension VoiceToolRequest {
    /// title + start (as read_calendar returned them), and at least one of new_start, new_end,
    /// new_title. New times follow the same strict rules as a new event: written out, local,
    /// not skipped or repeated by a clock change, not already passed.
    static func parseEventChange(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        guard let startText = args.text("start") else { return .invalid(name: name, reason: "missing start (the event's current start, as read_calendar gave it)") }
        guard case .due(let current) = ReminderDueRules.wallClock(startText, calendar: calendar), let currentStart = current.date(in: calendar) else {
            return .invalid(name: name, reason: "start is not a date")
        }
        var newStart: Date?, newEnd: Date?, newStartIsDayOnly = false
        if let text = args.text("new_start") {
            switch ReminderDueRules.check(text, now: now, calendar: calendar) {
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            case .due(let due):
                guard let date = due.date(in: calendar) else { return .invalid(name: name, reason: "new_start is not a date") }
                newStart = date
                newStartIsDayOnly = !due.hasTime
            }
        }
        if let text = args.text("new_end") {
            switch ReminderDueRules.wallClock(text, calendar: calendar) {
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            case .due(let due):
                guard due.hasTime, let date = due.date(in: calendar) else { return .invalid(name: name, reason: "new_end needs a time") }
                newEnd = date
            }
        }
        let newTitle = args.text("new_title")
        let newLocation = args.text("new_location"), addNote = args.text("add_note")
        // ADR-314: replace or clear the notes; never together with add_note.
        var replaceNotes: String? = args.flag("clear_notes") ? "" : nil
        if let text = args.text("replace_notes") {
            guard replaceNotes == nil else { return .invalid(name: name, reason: "give replace_notes or clear_notes, not both") }
            guard text.count <= ReminderDetails.maxReplacedNotesLength else { return .invalid(name: name, reason: "replace_notes is too long") }
            replaceNotes = text
        }
        if replaceNotes != nil, addNote != nil { return .invalid(name: name, reason: "give add_note or replace_notes, not both") }
        guard newStart != nil || newEnd != nil || newTitle != nil || newLocation != nil || addNote != nil || replaceNotes != nil else {
            return .invalid(name: name, reason: "give new_start, new_end, new_title, new_location, add_note, replace_notes or clear_notes")
        }
        if let newTitle, newTitle.count > EventChange.maxTitleLength { return .invalid(name: name, reason: "new_title is too long") }
        if let newLocation, newLocation.count > EventChange.maxLocationLength { return .invalid(name: name, reason: "new_location is too long") }
        if let addNote, addNote.count > EventChange.maxNoteLength { return .invalid(name: name, reason: "add_note is too long") }
        return .changeCalendarEvent(EventChangeDraft(
            title: title, currentStart: currentStart, currentIsDayOnly: !current.hasTime,
            newStart: newStart, newEnd: newEnd, newTitle: newTitle, newLocation: newLocation, addNote: addNote,
            replaceNotes: replaceNotes, newStartIsDayOnly: newStartIsDayOnly))
    }

    /// title + start (as read_calendar returned them): the occurrence to delete (ADR-259).
    static func parseEventDelete(_ args: Arguments, name: String, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        guard let startText = args.text("start") else { return .invalid(name: name, reason: "missing start (the event's current start, as read_calendar gave it)") }
        guard case .due(let current) = ReminderDueRules.wallClock(startText, calendar: calendar), let currentStart = current.date(in: calendar) else {
            return .invalid(name: name, reason: "start is not a date")
        }
        return .deleteCalendarEvent(EventChangeDraft(
            title: title, currentStart: currentStart, currentIsDayOnly: !current.hasTime, newStart: nil, newEnd: nil, newTitle: nil))
    }

    /// title (exact), and done: true on its own, or any of new_due, add_note, priority and
    /// move_to_list (ADR-302).
    static func parseReminderChange(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        let done = args.flag("done")
        var newDue: ReminderDue?
        if let text = args.text("new_due") {
            switch ReminderDueRules.check(text, now: now, calendar: calendar) {
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            case .due(let due): newDue = due
            }
        }
        let addNote = args.text("add_note")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let addNote, addNote.count > ReminderDetails.maxNoteLength { return .invalid(name: name, reason: "add_note is too long") }
        var priority: ReminderPriority?
        if let text = args.text("priority") {
            guard let value = ReminderPriority(rawValue: text.lowercased()) else {
                return .invalid(name: name, reason: "priority must be high, medium, low or none")
            }
            priority = value
        }
        let listName = args.text("move_to_list")
        // ADR-314: rename, repeat (or "none" to stop), replace or clear the notes.
        let newTitle = args.text("new_title")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newTitle, newTitle.isEmpty || newTitle.count > ReminderDetails.maxTitleLength {
            return .invalid(name: name, reason: "new_title must be 1 to \(ReminderDetails.maxTitleLength) characters")
        }
        var repeatChange: ReminderRepeatChange?
        if args.text("repeat")?.lowercased() == "none" {
            guard args.text("repeat_until") == nil else { return .invalid(name: name, reason: "repeat_until goes with a repeat, not none") }
            repeatChange = .stop
        } else {
            switch parseRepeat(args, name: name, first: newDue ?? ReminderDue(year: 2000, month: 1, day: 1, timeZoneID: nil), calendar: calendar) {
            case .success(let rule): repeatChange = rule.map { .set($0) }
            case .failure(.invalid(let reason)): return .invalid(name: name, reason: reason)
            case .failure(.clarify(let clarification)): return .needsClarification(name: name, clarification)
            }
        }
        var replaceNotes: String?
        if args.flag("clear_notes") { replaceNotes = "" }
        if let text = args.text("replace_notes")?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard replaceNotes == nil else { return .invalid(name: name, reason: "give replace_notes or clear_notes, not both") }
            guard text.count <= ReminderDetails.maxReplacedNotesLength else { return .invalid(name: name, reason: "replace_notes is too long") }
            replaceNotes = text
        }
        if replaceNotes != nil, addNote != nil { return .invalid(name: name, reason: "give add_note or replace_notes, not both") }
        let details = addNote != nil || priority != nil || listName != nil || newTitle != nil || repeatChange != nil || replaceNotes != nil
        if done {
            guard newDue == nil, !details else { return .invalid(name: name, reason: "done: true goes on its own; mark it done first, or change it without done") }
        } else {
            guard newDue != nil || details else {
                return .invalid(name: name, reason: "give new_due, new_title, add_note, replace_notes, clear_notes, priority, repeat or move_to_list, or done: true")
            }
        }
        return .changeReminder(ReminderChangeDraft(
            title: title, newDue: newDue, markDone: done, addNote: addNote, priority: priority, listName: listName,
            newTitle: newTitle, repeatChange: repeatChange, replaceNotes: replaceNotes))
    }
}
