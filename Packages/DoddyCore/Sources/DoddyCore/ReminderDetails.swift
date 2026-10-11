import Foundation

// A reminder's details by voice (ADR-293). `change_reminder` also takes `add_note` (a line added
// at the end of the reminder's notes; notes are only added to), `priority` (high, medium, low or
// none) and `move_to_list` (one of the user's Reminders lists, matched by name: exactly one, or
// nothing is guessed). They can go with a new due; "done" stays on its own. The card shows the
// reminder as it is and each change; on the tap it must still look the same, everything is
// written in one save, and it is read back. Undo covers a new due or done only, and the card
// says so when a detail changes.

public enum ReminderPriority: String, CaseIterable, Codable, Equatable, Sendable {
    case none, low, medium, high

    /// What EventKit stores: 0 none, 1 high, 5 medium, 9 low (as the Reminders app writes them).
    public var eventKitValue: Int {
        switch self {
        case .none: 0
        case .high: 1
        case .medium: 5
        case .low: 9
        }
    }

    /// EventKit's 1–4 count as high and 6–9 as low, as Reminders shows them.
    public static func from(eventKit value: Int) -> ReminderPriority {
        switch value {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }

    public var text: String {
        switch self {
        case .none: "no priority"
        case .low: "low priority"
        case .medium: "medium priority"
        case .high: "high priority"
        }
    }
}

/// One of the user's Reminders lists.
public struct ReminderListRef: Codable, Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// What changes besides the due, resolved and checked, as the card shows it.
public struct ReminderDetailsChange: Equatable, Sendable {
    public let addNote: String?
    public let priority: ReminderPriority?
    public let toList: ReminderListRef?

    public init(addNote: String? = nil, priority: ReminderPriority? = nil, toList: ReminderListRef? = nil) {
        self.addNote = addNote
        self.priority = priority
        self.toList = toList
    }

    public var isEmpty: Bool { addNote == nil && priority == nil && toList == nil }
}

public enum ReminderDetails {
    public static let maxNoteLength = EventChange.maxNoteLength

    /// The list the user named: exactly one list whose name matches, ignoring case, accents and
    /// punctuation. Otherwise nothing is guessed.
    public static func matchList(_ name: String, in lists: [ReminderListRef]) -> ListMatchResult<ReminderListRef> {
        let wanted = SearchFolding.tokens(name).joined(separator: " ")
        guard !wanted.isEmpty else { return .none }
        let found = lists.filter { SearchFolding.tokens($0.title).joined(separator: " ") == wanted }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// True when the reminder read back shows every change (and the due, when one was asked for).
    public static func confirms(_ back: ReminderSnapshot, notes: String?, change: ReminderDetailsChange, newDue: ReminderDue?) -> Bool {
        guard !back.isCompleted else { return false }
        if let newDue, !EventChange.sameDue(back.due, newDue) { return false }
        if let line = change.addNote, !(notes ?? "").hasSuffix(line) { return false }
        if let priority = change.priority, back.priority != priority { return false }
        if let list = change.toList, back.listID != list.id { return false }
        return true
    }

    /// Nothing would change: the priority and list are already so, and there's no note or due.
    public static func changesNothing(_ reminder: ReminderSnapshot, change: ReminderDetailsChange, newDue: ReminderDue?) -> Bool {
        if newDue != nil, !EventChange.sameDue(reminder.due, newDue) { return false }
        if change.addNote != nil { return false }
        if let priority = change.priority, priority != reminder.priority { return false }
        if let list = change.toList, list.id != reminder.listID { return false }
        return true
    }

    /// The changes as one phrase, for the agent and the log: "note added, high priority, moved to "Shopping"".
    public static func summary(_ change: ReminderDetailsChange) -> String {
        var parts: [String] = []
        if change.addNote != nil { parts.append("note added") }
        if let priority = change.priority { parts.append(priority == .none ? "priority removed" : priority.text) }
        if let list = change.toList { parts.append("moved to the list \"\(list.title)\"") }
        return parts.joined(separator: ", ")
    }
}

extension VoiceToolReply {
    public static func reminderDetailsChanged(_ title: String, change: ReminderDetailsChange, due: ReminderDue?) -> String {
        var text = "changed: reminder \"\(title)\": \(ReminderDetails.summary(change))"
        if let due { text += ", now due \(ReminderText.due(due))" }
        return text + ". Checked in Reminders."
    }

    public static func reminderListNotFound(_ name: String, lists: [ReminderListRef]) -> String {
        let names = lists.map { "\"\($0.title)\"" }.joined(separator: ", ")
        return "not found: no Reminders list called \"\(name)\". The user's lists are: \(names.isEmpty ? "none" : names). Nothing changed; ask which one."
    }

    public static func reminderListAmbiguous(_ lists: [ReminderListRef]) -> String {
        "not changed: more than one Reminders list has that name (\(lists.map { "\"\($0.title)\"" }.joined(separator: ", "))). Nothing changed; ask the user to rename one in Reminders."
    }
}
