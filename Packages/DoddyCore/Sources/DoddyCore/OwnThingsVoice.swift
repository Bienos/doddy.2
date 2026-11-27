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
    /// Run when asked, with no card and no question (owner, 27 Nov 2026, following the rule of 25 Nov: "he should not be
    /// really asking anything"), and Doddy says what he did. Each is undone in one step (Undo in Memories or on the
    /// list, renaming back, the note's history keeps the old words), or is a stop the person asked for ("stop the
    /// research": a stopped task is started again by asking again). `unfollow_news` is in `AskFirst.ownSmallActions`.
    public static let atOnceTools: Set<String> = [
        VoiceToolName.changeNote, VoiceToolName.deleteNote, VoiceToolName.renameList, VoiceToolName.deleteList,
        VoiceToolName.clearTicked, VoiceToolName.cancelTask,
    ]

    /// The one tool of this step that keeps a card: a note's reminder, once off, has to be set up again from scratch.
    /// A spoken yes or a tap runs it.
    public static let cardTools: Set<String> = [VoiceToolName.cancelNoteReminder]

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
            return .cancelTask(about: cleaned("about"))
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

    /// Everything that can still be stopped: tasks handed over and Studio jobs that aren't finished.
    public static func stoppable(tasks: [StoredErrand], studio: [StudioItemSummary]) -> [StoppableWork] {
        tasks.filter { [.queued, .running].contains($0.state) }.map {
            StoppableWork(id: $0.id, kind: .task, title: $0.draft.title, words: $0.draft.words)
        } + studio.filter { [.queued, .researching, .making, .checking].contains($0.state) }.map {
            StoppableWork(id: $0.id, kind: .studio, title: $0.title ?? "", words: "")
        }
    }

    /// The one thing to stop. Words from its title or request pick it (`ErrandResultText`'s stem match); with no words,
    /// or words that match nothing while only one thing is being worked on, that one thing ("stop the research" while
    /// one task runs). Several ask which; nothing running says so.
    public static func work(_ about: String?, in open: [StoppableWork]) -> ListMatchResult<StoppableWork> {
        var found = open
        if let about, !about.isEmpty {
            let matching = open.filter { $0.matches(about) }
            if !matching.isEmpty || open.count != 1 { found = matching }
        }
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

    public static func taskNotFound(_ about: String?, open: [StoppableWork]) -> String {
        let lead = open.isEmpty
            ? "not found: nothing is being worked on now (no task and no Studio job), so nothing was stopped. Something already finished can't be stopped. A file being made in Messages can't be stopped either."
            : "not found: nothing being worked on matches the words below. Nothing was stopped. Ask the user which one; what is being worked on follows."
        return lead + "\n" + ToolData.block([about.map { VoiceToolReply.quoted("Asked for", $0) }].compactMap { $0 } + open.map(\.line))
    }

    public static func severalTasks(_ about: String?, _ work: [StoppableWork]) -> String {
        "not changed: more than one thing is being worked on and the words don't pick one. Ask the user which one:\n"
            + ToolData.block([about.map { VoiceToolReply.quoted("Asked for", $0) }].compactMap { $0 } + work.map(\.line))
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

    public static func taskStopped(_ work: StoppableWork) -> String {
        let place = work.kind == .studio ? "Studio" : "Tasks"
        return "stopped: Doddy stopped working on the \(work.kind.spoken) below. It stays in \(place); to do it after all, the user asks again.\n"
            + ToolData.block([work.line])
    }

    /// The server didn't confirm the stop, or the state afterwards isn't "cancelled": never said as stopped.
    public static func taskNotStopped(_ work: StoppableWork, reason: String) -> String {
        let place = work.kind == .studio ? "Studio" : "Tasks"
        return "unknown: Doddy couldn't confirm the \(work.kind.spoken) stopped (\(ToolData.clean(reason))). Tell the user to check \(place); don't try again by yourself.\n"
            + ToolData.block([work.line])
    }

    public static func unfollowed(_ name: String) -> String {
        "changed: the user no longer follows the topic below. It can be followed again any time with follow_news.\n"
            + ToolData.block([VoiceToolReply.quoted("Stopped following", name)])
    }
}

/// A task handed over or a Studio job that is still being worked on, for cancel_task.
public struct StoppableWork: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case task, studio
        var spoken: String { self == .studio ? "Studio job" : "task" }
    }

    public let id: UUID
    public let kind: Kind
    /// A Studio job has no title until its plan step names it; then it is "".
    public let title: String
    /// The task's request in the user's words; "" for a Studio job (the list doesn't carry its topic).
    public let words: String

    public init(id: UUID, kind: Kind, title: String, words: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.words = words
    }

    /// A word of `about` (four letters or more, folded) whose stem appears in the title or words, as for check_errands.
    func matches(_ about: String) -> Bool {
        let haystack = PolishText.fold(title + " " + words)
        let wanted = PolishText.fold(about).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 }
        return wanted.contains { haystack.contains(String($0.prefix(max(3, $0.count - 2)))) }
    }

    /// One line for a ToolData block.
    var line: String {
        let name = title.isEmpty ? (kind == .studio ? "(a Studio job, not named yet)" : "(a task)") : ToolData.clean(title)
        return "- \(kind == .studio ? "Studio" : "Task"): \"\(name)\""
    }
}
