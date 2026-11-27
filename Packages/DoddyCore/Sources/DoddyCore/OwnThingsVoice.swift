import Foundation

// Doddy's own things by voice (decision 2026-11-27-voice-first-doddy, step 1): change or delete one saved note, stop a
// note's reminder, rename or delete a list or clear its ticked items, stop a task handed over, stop following news.
//
// The model only names the thing, in the user's words (a note by its exact text from search_memories). The app finds
// exactly one (`NoteQuoteMatch`, `ListMatch`, `OwnThingsVoice.task`, `OwnThingsVoice.follow`), and the card shows what
// it found, never the model's words: the person approves the real note, list or task. The voice controller keeps the
// id the card showed (`OwnThingPin`) and runs only if the same thing is found again after the yes. Every reply starts
// with the word the prompt's rules read ("changed", "deleted", "turned off", "cleared", "stopped", "not found",
// "not changed", "failed"), and the user's words in it are data (`ToolData`).
//
// Platforms: iPhone and iPad (the voice conversation).

/// What a card showed, so the run after the yes touches exactly that and nothing else.
public struct OwnThingPin: Equatable, Sendable {
    public let tool: String
    public let id: String

    public init(tool: String, id: String) {
        self.tool = tool
        self.id = id
    }
}

public enum OwnThingsVoice {
    /// The tools of this step that show a card (a spoken yes or a tap runs them). `unfollow_news` runs at once.
    public static let cardTools: Set<String> = [
        VoiceToolName.changeNote, VoiceToolName.deleteNote, VoiceToolName.cancelNoteReminder,
        VoiceToolName.renameList, VoiceToolName.deleteList, VoiceToolName.clearTicked, VoiceToolName.cancelTask,
    ]

    // MARK: Reading the call

    static func parse(_ args: Arguments, name: String) -> VoiceToolRequest {
        func cleaned(_ key: String) -> String? { args.text(key).flatMap(ListText.cleaned) }
        switch name {
        case VoiceToolName.changeNote:
            guard let quote = cleaned("note") else { return .invalid(name: name, reason: "missing note") }
            guard let text = args.text("text")?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return .invalid(name: name, reason: "missing text")
            }
            guard NoteQuoteMatch.normalized(text) != NoteQuoteMatch.normalized(quote) else {
                return .invalid(name: name, reason: "the new text is the same as the note")
            }
            return .changeNote(quote: quote, newText: text)
        case VoiceToolName.deleteNote:
            guard let quote = cleaned("note") else { return .invalid(name: name, reason: "missing note") }
            return .deleteNote(quote: quote)
        case VoiceToolName.cancelNoteReminder:
            guard let quote = cleaned("note") else { return .invalid(name: name, reason: "missing note") }
            return .cancelNoteReminder(quote: quote)
        case VoiceToolName.renameList:
            guard let list = cleaned("list") else { return .invalid(name: name, reason: "missing list") }
            guard let newName = cleaned("new_name") else { return .invalid(name: name, reason: "missing new_name") }
            guard newName.count <= ListLimits.nameLength else {
                return .invalid(name: name, reason: "new_name longer than \(ListLimits.nameLength) characters")
            }
            guard ListMatch.key(newName) != ListMatch.key(list) else {
                return .invalid(name: name, reason: "the new name is the same as the list's")
            }
            return .renameList(list: list, newName: newName)
        case VoiceToolName.deleteList:
            guard let list = cleaned("list") else { return .invalid(name: name, reason: "missing list") }
            return .deleteList(list: list)
        case VoiceToolName.clearTicked:
            guard let list = cleaned("list") else { return .invalid(name: name, reason: "missing list") }
            return .clearTicked(list: list)
        case VoiceToolName.cancelTask:
            guard let about = cleaned("about") else { return .invalid(name: name, reason: "missing about") }
            return .cancelTask(about: about)
        default:
            guard let follow = cleaned("name") else { return .invalid(name: name, reason: "missing name") }
            return .unfollowNews(name: follow)
        }
    }

    // MARK: Finding the thing

    /// A note by its exact text (`NoteQuoteMatch`: case, spaces and quote marks aside), never a private one (those stay
    /// out of conversations). `notes` are the notes only, never lists (the store keeps those apart). Two notes with the
    /// same text ask which one, so the card never shows a guess.
    public static func note(_ quote: String, in notes: [MemoryRecord], privateIDs: Set<UUID>) -> ListMatchResult<MemoryRecord> {
        let wanted = NoteQuoteMatch.normalized(quote)
        guard !wanted.isEmpty else { return .none }
        let found = notes.filter { !privateIDs.contains($0.id) && NoteQuoteMatch.normalized($0.currentText) == wanted }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// The tasks that can still be stopped (handed over and not finished), matched by the words of their title or
    /// request (`ErrandResultText.matches`). One match runs; several ask which; none says so.
    public static func task(_ about: String, in errands: [StoredErrand]) -> ListMatchResult<StoredErrand> {
        let open = errands.filter { [.queued, .running].contains($0.state) }
        let found = open.filter { ErrandResultText.matches($0, about: about) }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// One follow by its name: the same name (`ListMatch.key`), or failing that the only one whose name contains it.
    public static func follow(_ name: String, in follows: [NewsFollow]) -> ListMatchResult<NewsFollow> {
        let wanted = ListMatch.key(name)
        guard !wanted.isEmpty else { return .none }
        let exact = follows.filter { ListMatch.key($0.label) == wanted }
        if exact.count == 1 { return .one(exact[0]) }
        if exact.count > 1 { return .several(exact) }
        let partial = follows.filter { ListMatch.key($0.label).contains(wanted) }
        switch partial.count {
        case 0: return .none
        case 1: return .one(partial[0])
        default: return .several(partial)
        }
    }

    // MARK: Cards (what the person approves: the thing found, never the model's words)

    public static func changeNoteCard(current: String, new: String, polish: Bool) -> AskCard {
        AskCard(title: polish ? "Zmienić notatkę?" : "Change this note?",
                lines: [(polish ? "Teraz: " : "Now: ") + current, (polish ? "Po zmianie: " : "New: ") + new],
                confirmLabel: polish ? "Zmień" : "Change")
    }

    public static func deleteNoteCard(_ text: String, polish: Bool) -> AskCard {
        AskCard(title: polish ? "Usunąć notatkę?" : "Delete this note?",
                lines: [text, polish ? "Cofniesz to w Notatkach przez krótką chwilę." : "You can undo it in Memories for a short while."],
                confirmLabel: polish ? "Usuń" : "Delete")
    }

    public static func cancelNoteReminderCard(_ text: String, when: String, polish: Bool) -> AskCard {
        AskCard(title: polish ? "Wyłączyć przypomnienie?" : "Turn off this reminder?",
                lines: [text, when], confirmLabel: polish ? "Wyłącz" : "Turn off")
    }

    public static func renameListCard(_ name: String, to newName: String, sharedNote: String?, polish: Bool) -> AskCard {
        AskCard(title: polish ? "Zmienić nazwę listy?" : "Rename this list?",
                lines: ["„\(name)” → „\(newName)”"] + [sharedNote].compactMap { $0 },
                confirmLabel: polish ? "Zmień nazwę" : "Rename")
    }

    public static func deleteListCard(_ name: String, items: Int, sharedWarning: String?, polish: Bool) -> AskCard {
        let count = polish ? "\(items) \(items == 1 ? "pozycja" : "pozycji")" : "\(items) item\(items == 1 ? "" : "s")"
        return AskCard(title: polish ? "Usunąć listę „\(name)”?" : "Delete the list \(name)?",
                       lines: [count] + [sharedWarning].compactMap { $0 },
                       confirmLabel: polish ? "Usuń listę" : "Delete list")
    }

    public static func clearTickedCard(_ name: String, ticked: [String], polish: Bool) -> AskCard {
        AskCard(title: polish ? "Usunąć odhaczone z listy „\(name)”?" : "Clear the ticked items from \(name)?",
                lines: ticked, confirmLabel: polish ? "Usuń odhaczone" : "Clear ticked")
    }

    public static func cancelTaskCard(_ title: String, polish: Bool) -> AskCard {
        AskCard(title: polish ? "Zatrzymać zadanie?" : "Stop this task?",
                lines: [title, polish ? "Doddy przestanie nad nim pracować." : "Doddy stops working on it."],
                confirmLabel: polish ? "Zatrzymaj" : "Stop")
    }

    // MARK: Replies (the first word is what the prompt's rules read; the user's words are data)

    public static func severalNotes() -> String {
        "not changed: more than one note has exactly this text. Ask the user which one (for example when it was saved). Nothing changed."
    }

    public static func noReminder(_ text: String) -> String {
        "not found: this note has no reminder, so nothing was turned off.\n" + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }

    public static func nothingTicked(_ list: String) -> String {
        "not changed: nothing is ticked on this list, so nothing was removed.\n" + ToolData.block([VoiceToolReply.quoted("List", list)])
    }

    public static func listNameTaken(_ name: String) -> String {
        "not changed: another list already has the new name below. Ask the user for another name.\n"
            + ToolData.block([VoiceToolReply.quoted("Name", name)])
    }

    public static func taskNotFound(_ about: String, open: [StoredErrand]) -> String {
        let lead = open.isEmpty
            ? "not found: no task is being worked on now, so nothing was stopped. A finished task can't be stopped."
            : "not found: no task that is being worked on matches the words below. Nothing was stopped. Ask the user which one; the open tasks follow."
        return lead + "\n" + ToolData.block([VoiceToolReply.quoted("Asked for", about)] + open.map { "- \"\(ToolData.clean($0.draft.title))\"" })
    }

    public static func severalTasks(_ about: String, _ tasks: [StoredErrand]) -> String {
        "not changed: more than one open task matches. Ask the user which one. The words asked for, then the tasks:\n"
            + ToolData.block([VoiceToolReply.quoted("Asked for", about)] + tasks.map { "- \"\(ToolData.clean($0.draft.title))\"" })
    }

    public static func followNotFound(_ name: String, follows: [NewsFollow]) -> String {
        "not found: nothing the user follows has the name below. Nothing changed. What they follow:\n"
            + ToolData.block([VoiceToolReply.quoted("Asked for", name)] + follows.map { "- \"\(ToolData.clean($0.label))\"" })
    }

    public static func severalFollows(_ name: String, _ follows: [NewsFollow]) -> String {
        "not changed: the name below matches more than one thing the user follows. Ask which one:\n"
            + ToolData.block([VoiceToolReply.quoted("Asked for", name)] + follows.map { "- \"\(ToolData.clean($0.label))\"" })
    }

    /// The thing changed between the card and the yes (edited, deleted, renamed elsewhere): nothing ran.
    public static let changedMeanwhile =
        "not changed: what the card showed is no longer the same (it was changed or removed meanwhile), so nothing ran. Look it up again and ask once more."

    public static func noteChanged(_ text: String) -> String {
        "changed: the note now says the text below. Say it was changed.\n" + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }

    public static func noteDeleted(_ text: String) -> String {
        "deleted: the note below is deleted. The user can undo it in Memories for a short while.\n"
            + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }

    public static func reminderOff(_ text: String) -> String {
        "turned off: the note's reminder is turned off; the note itself stays.\n" + ToolData.block([VoiceToolReply.quoted("Note", text)])
    }

    public static func listRenamed(_ old: String, _ new: String) -> String {
        "changed: the list is renamed.\n" + ToolData.block([VoiceToolReply.quoted("Was", old), VoiceToolReply.quoted("Now", new)])
    }

    public static func listDeleted(_ name: String) -> String {
        "deleted: the list below is deleted with its items. The user can undo it in Memories for a short while.\n"
            + ToolData.block([VoiceToolReply.quoted("List", name)])
    }

    public static func tickedCleared(_ name: String, count: Int) -> String {
        "cleared: \(count) ticked item\(count == 1 ? " was" : "s were") removed from the list below; Undo is on the list.\n"
            + ToolData.block([VoiceToolReply.quoted("List", name)])
    }

    public static func taskStopped(_ title: String) -> String {
        "stopped: Doddy stopped working on the task below. Its result so far stays in Tasks.\n"
            + ToolData.block([VoiceToolReply.quoted("Task", title)])
    }

    /// The server didn't confirm the stop, or the task's state afterwards isn't "cancelled": never said as stopped.
    public static func taskNotStopped(_ title: String, reason: String) -> String {
        "unknown: Doddy couldn't confirm the task stopped (\(ToolData.clean(reason))). Tell the user to check Tasks; don't try again by yourself.\n"
            + ToolData.block([VoiceToolReply.quoted("Task", title)])
    }

    public static func unfollowed(_ name: String) -> String {
        "changed: the user no longer follows the topic below. It can be followed again any time with follow_news.\n"
            + ToolData.block([VoiceToolReply.quoted("Stopped following", name)])
    }
}
