import Foundation

// "Change" on a plan card step (docs/design/SETTINGS_AND_CONNECTIONS.md §4 rule 3, ADR-205). The
// user edits the step's fields on screen; the result goes through the same parser and checks as
// the agent's own call, so an edit can never skip a rule (a past time, a skipped clock hour, a
// timer over 24 hours). The kind of step can't change.

/// The editable fields of one step, as the form shows them.
public struct PlanStepForm: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case note, event, reminder, timer }

    public let kind: Kind
    /// The note's text, or the event's or reminder's title.
    public var text: String
    public var notes: String
    /// Reminder only: whether it has a due date at all.
    public var hasDate: Bool
    /// Reminder: the due has a time. Event: not all day.
    public var hasTime: Bool
    /// Reminder due, or event start.
    public var start: Date
    public var end: Date
    public var location: String
    public var minutes: Int
    public var seconds: Int
    public var label: String

    public init(_ step: PlanStep, now: Date = Date(), calendar: Calendar = .current) {
        let hour = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        var form = PlanStepForm(kind: .note, start: hour, end: hour.addingTimeInterval(3600))
        switch step.request {
        case .saveMemory(let text):
            form = PlanStepForm(kind: .note, start: hour, end: hour)
            form.text = text
        case .createReminder(let draft):
            form = PlanStepForm(kind: .reminder, start: hour, end: hour)
            form.text = draft.title
            form.notes = draft.notes ?? ""
            if let due = draft.due, let date = due.date(in: calendar) {
                form.hasDate = true
                form.hasTime = due.hasTime
                form.start = date
            }
        case .createCalendarEvent(let draft):
            form = PlanStepForm(kind: .event, start: draft.start, end: draft.end)
            form.text = draft.title
            form.notes = draft.notes ?? ""
            form.location = draft.location ?? ""
            form.hasTime = !draft.allDay
        case .setTimer(let draft):
            form = PlanStepForm(kind: .timer, start: hour, end: hour)
            form.minutes = draft.seconds / 60
            form.seconds = draft.seconds % 60
            form.label = draft.label ?? ""
        default:
            break
        }
        self = form
    }

    private init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        text = ""
        notes = ""
        hasDate = false
        hasTime = true
        self.start = start
        self.end = end
        location = ""
        minutes = 0
        seconds = 0
        label = ""
    }

    /// The edited step, checked exactly like the agent's call, or what to fix, in words for the screen.
    public func apply(to step: PlanStep, now: Date = Date(), calendar: Calendar = .current) -> PlanStepEdit {
        var args: [String: Any] = [:]
        // Written in Gregorian, as the parser reads it back, so a Buddhist or Japanese phone calendar keeps the year.
        let gregorian = ReminderDueRules.gregorian(calendar)
        func wallClock(_ date: Date, time: Bool) -> String { VoiceToolReply.localText(date, hasTime: time, calendar: gregorian).replacingOccurrences(of: " ", with: "T") }
        switch kind {
        case .note:
            args["text"] = text
        case .reminder:
            args["title"] = text
            if hasDate { args["due"] = wallClock(start, time: hasTime) }
            if !notes.isEmpty { args["notes"] = notes }
        case .event:
            args["title"] = text
            if hasTime {
                args["start"] = wallClock(start, time: true)
                args["end"] = wallClock(end, time: true)
            } else {
                args["start"] = wallClock(start, time: false)
                args["all_day"] = true
            }
            if !location.isEmpty { args["location"] = location }
            if !notes.isEmpty { args["notes"] = notes }
        case .timer:
            args["minutes"] = Double(minutes)
            args["seconds"] = Double(seconds)
            if !label.isEmpty { args["label"] = label }
        }
        let data = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
        let request = VoiceToolRequest.parse(name: step.toolName, parametersJSON: data, now: now, calendar: calendar)
        switch request {
        case .saveMemory, .createCalendarEvent, .createReminder, .setTimer:
            return .step(PlanStep(number: step.number, toolName: step.toolName, request: request))
        case .needsClarification(_, let clarification):
            return .problem(clarification.screenLine)
        case .invalid(_, let reason):
            return .problem(Self.screenText(reason))
        default:
            return .problem("This step can't be changed.")
        }
    }

    /// The parser's reasons are written for the agent; these are for the person editing.
    static func screenText(_ reason: String) -> String {
        switch reason {
        case "missing text", "missing title": "Write something first."
        case "end must be a time after start": "The end has to be after the start."
        case "missing duration": "Set a time of at least one second."
        case "timer is longer than 24 hours": "A timer can be at most 24 hours."
        default: "This step isn't complete (\(reason))."
        }
    }
}

public enum PlanStepEdit: Equatable, Sendable {
    case step(PlanStep)
    case problem(String)
}
