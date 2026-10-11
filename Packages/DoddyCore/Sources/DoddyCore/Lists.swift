import Foundation

// Lists (ADR-216). A list is a kind of note: a `memories` row with category `list` whose text is
// the list's name, plus items in `list_items` that are deleted with it. Items keep the words the
// user used. Every change is one transaction, read back before success. Voice changes name a list
// and items in words; the app matches them exactly (ignoring case, accents, punctuation and a
// leading article) and never picks "the closest" one.

public enum ListLimits {
    public static let nameLength = 60
    public static let itemLength = 200
    public static let itemsPerList = 200
    public static let lists = 50
    /// How many open items Doddy reads out before saying how many more there are.
    public static let readAloud = 10
}

public enum ListItemSource: String, Codable, CaseIterable, Sendable {
    case typed, voice
}

public struct ListItem: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let listID: UUID
    /// As the user typed or said it, trimmed; never reworded.
    public let text: String
    public let source: ListItemSource
    public let addedAt: Date
    public let doneAt: Date?
    public let position: Int

    public init(id: UUID, listID: UUID, text: String, source: ListItemSource, addedAt: Date, doneAt: Date?, position: Int) {
        self.id = id
        self.listID = listID
        self.text = text
        self.source = source
        self.addedAt = addedAt
        self.doneAt = doneAt
        self.position = position
    }

    public var isDone: Bool { doneAt != nil }
}

/// One list as stored: its note row and its items in list order.
public struct DoddyList: Equatable, Sendable, Identifiable {
    public let record: MemoryRecord
    public let items: [ListItem]

    public init(record: MemoryRecord, items: [ListItem]) {
        self.record = record
        self.items = items.sorted { $0.position < $1.position }
    }

    public var id: UUID { record.id }
    public var name: String { record.currentText }
    /// Not ticked, in list order.
    public var open: [ListItem] { items.filter { !$0.isDone } }
    /// Ticked, most recently ticked first.
    public var done: [ListItem] {
        items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    /// "5 to get · 2 done", "Nothing left · 3 done", "Empty".
    public var summary: String {
        switch (open.count, done.count) {
        case (0, 0): return "Empty"
        case (0, let done): return "Nothing left · \(done) done"
        case (let open, 0): return "\(open) left"
        case (let open, let done): return "\(open) left · \(done) done"
        }
    }

    /// The notification and share text: "Shopping: milk, eggs" or "Shopping: nothing left".
    public var text: String {
        let items = open.map(\.text)
        return items.isEmpty ? "\(name): nothing left" : "\(name): \(items.joined(separator: ", "))"
    }

    /// Share as text: the name, then one open item per line.
    public var shareText: String {
        ([name] + open.map { "- \($0.text)" }).joined(separator: "\n")
    }
}

public enum ListError: Error, Equatable, Sendable {
    case emptyName
    case nameTooLong(maximum: Int)
    /// A list with the same name (ignoring case and accents) already exists.
    case nameTaken(String)
    case tooManyLists(maximum: Int)
    case notFound
    /// A note can't be filed as a list, and a list can't be filed as a note type.
    case notANote
}

/// What an add actually did. Only `added` changed anything.
public struct ListAddResult: Equatable, Sendable {
    public let added: [ListItem]
    /// Already open on the list (or said twice): not added again.
    public let alreadyThere: [String]
    public let tooLong: [String]
    /// The list was full when these came.
    public let noRoom: [String]

    public init(added: [ListItem], alreadyThere: [String], tooLong: [String], noRoom: [String]) {
        self.added = added
        self.alreadyThere = alreadyThere
        self.tooLong = tooLong
        self.noRoom = noRoom
    }
}

public protocol ListRepository: Sendable {
    /// Every list with its items, in the order the lists were made.
    func lists() async throws -> [DoddyList]
    func list(id: UUID) async throws -> DoddyList?
    /// A new list (a `list` note) with its first items, in one transaction.
    func create(name: String, items: [String], source: ListItemSource) async throws -> DoddyList
    func add(_ texts: [String], to listID: UUID, source: ListItemSource) async throws -> ListAddResult
    /// A new name: same rules as a new list; the first name stays as the original text.
    func rename(listID: UUID, to name: String) async throws -> DoddyList
    /// Ticks or unticks. Returns the items that changed, as stored now.
    func setDone(_ itemIDs: [UUID], done: Bool) async throws -> [ListItem]
    /// Returns the removed items exactly as they were, for Undo.
    func remove(_ itemIDs: [UUID]) async throws -> [ListItem]
    func clearDone(listID: UUID) async throws -> [ListItem]
    func untickAll(listID: UUID) async throws -> [ListItem]
    /// Puts removed items back as they were (Undo). Items whose list is gone, or whose list is
    /// full, are skipped; an item whose place was taken meanwhile goes after the last one.
    /// Returns the items as stored.
    func restore(_ items: [ListItem]) async throws -> [ListItem]
    /// Every item of every list, for export.
    func allItems() async throws -> [ListItem]
    /// A shared list after a sync (ADR-263): its name and items become exactly `state`, in one
    /// transaction, read back. Throws `ListError.nameTaken` if another list has that name.
    func replaceShared(listID: UUID, with state: SharedListState) async throws -> DoddyList
}

public struct UnavailableListRepository: ListRepository {
    public init() {}
    private var error: DoddyError { .capabilityUnavailable(.memoryStorage) }
    public func lists() async throws -> [DoddyList] { throw error }
    public func list(id: UUID) async throws -> DoddyList? { throw error }
    public func create(name: String, items: [String], source: ListItemSource) async throws -> DoddyList { throw error }
    public func add(_ texts: [String], to listID: UUID, source: ListItemSource) async throws -> ListAddResult { throw error }
    public func rename(listID: UUID, to name: String) async throws -> DoddyList { throw error }
    public func setDone(_ itemIDs: [UUID], done: Bool) async throws -> [ListItem] { throw error }
    public func remove(_ itemIDs: [UUID]) async throws -> [ListItem] { throw error }
    public func clearDone(listID: UUID) async throws -> [ListItem] { throw error }
    public func untickAll(listID: UUID) async throws -> [ListItem] { throw error }
    public func restore(_ items: [ListItem]) async throws -> [ListItem] { throw error }
    public func allItems() async throws -> [ListItem] { throw error }
}

/// Validation shared by the screens, the voice path and the database.
public enum ListText {
    /// Trimmed; nil when empty.
    public static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).joined(separator: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func checkedName(_ name: String) throws(ListError) -> String {
        guard let cleaned = cleaned(name) else { throw .emptyName }
        guard cleaned.count <= ListLimits.nameLength else { throw .nameTooLong(maximum: ListLimits.nameLength) }
        return cleaned
    }
}

public enum ListMatchResult<T: Equatable & Sendable>: Equatable, Sendable {
    case one(T)
    case none
    case several([T])
}

/// Exact matching, done by the app (never by the model).
public enum ListMatch {
    private static let articles: Set<String> = ["the", "a", "an", "my"]
    /// "shopping list" finds "Shopping"; "lista zakupów" finds "Zakupy" only if typed so.
    private static let listWords: Set<String> = ["list", "lista", "liste", "listă", "lijst", "listan", "listen"]

    /// Folded words: lower case, no accents, no punctuation, no leading article.
    public static func key(_ text: String) -> String {
        var words = SearchFolding.tokens(text)
        while let first = words.first, words.count > 1, articles.contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    private static func nameKey(_ text: String) -> String {
        var words = key(text).split(separator: " ").map(String.init)
        if words.count > 1, let last = words.last, listWords.contains(last) { words.removeLast() }
        if words.count > 1, let first = words.first, listWords.contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    public static func list(named name: String, in lists: [DoddyList]) -> ListMatchResult<DoddyList> {
        let exact = lists.filter { key($0.name) == key(name) }
        if exact.count == 1 { return .one(exact[0]) }
        if exact.count > 1 { return .several(exact) }
        let loose = lists.filter { nameKey($0.name) == nameKey(name) }
        switch loose.count {
        case 0: return .none
        case 1: return .one(loose[0])
        default: return .several(loose)
        }
    }

    /// The same words first; then items that contain all the said words as whole words
    /// ("milk" finds "oat milk"). Two or more: `.several`, and nothing is changed.
    public static func item(_ phrase: String, in items: [ListItem]) -> ListMatchResult<ListItem> {
        let wanted = key(phrase)
        guard !wanted.isEmpty else { return .none }
        let exact = items.filter { key($0.text) == wanted }
        if exact.count == 1 { return .one(exact[0]) }
        if exact.count > 1 { return .several(exact) }
        let words = Set(wanted.split(separator: " ").map(String.init))
        let containing = items.filter { words.isSubset(of: Set(key($0.text).split(separator: " ").map(String.init))) }
        switch containing.count {
        case 0: return .none
        case 1: return .one(containing[0])
        default: return .several(containing)
        }
    }

    /// The same item already open on the list (or earlier in the same request).
    public static func isDuplicate(_ text: String, of existing: [String]) -> Bool {
        let wanted = key(text)
        return !wanted.isEmpty && existing.contains { key($0) == wanted }
    }
}

// MARK: Voice

/// What a list tool asked for. Lists and items are words; the app resolves them.
public struct ListVoiceRequest: Equatable, Sendable {
    public let list: String
    public let items: [String]

    public init(list: String, items: [String]) {
        self.list = list
        self.items = items
    }
}

extension VoiceToolName {
    public static let addToList = "add_to_list"
    public static let readList = "read_list"
    public static let checkOff = "check_off"
    public static let removeFromList = "remove_from_list"
    /// Shown as a card; nothing is made until the user taps Create list (L2).
    public static let createList = "create_list"
}

extension VoiceToolRequest {
    static func parseList(_ args: Arguments, name: String) -> VoiceToolRequest {
        let listKey = name == VoiceToolName.createList ? "name" : "list"
        guard let list = args.text(listKey).flatMap(ListText.cleaned) else {
            return .invalid(name: name, reason: "missing \(listKey)")
        }
        let items = (args.texts("items") ?? []).compactMap(ListText.cleaned)
        let request = ListVoiceRequest(list: list, items: items)
        switch name {
        case VoiceToolName.readList:
            return .readList(name: list)
        case VoiceToolName.createList:
            guard list.count <= ListLimits.nameLength else {
                return .invalid(name: name, reason: "name longer than \(ListLimits.nameLength) characters")
            }
            return .createList(request)
        default:
            guard !items.isEmpty else { return .invalid(name: name, reason: "missing items") }
            switch name {
            case VoiceToolName.addToList: return .addToList(request)
            case VoiceToolName.checkOff: return .checkOff(request)
            default: return .removeFromList(request)
            }
        }
    }
}

/// Agent context: list names and counts at the start of a conversation (L6). Items only when read.
public enum ListsPrompt {
    public static let variableName = "saved_lists"

    public static func render(_ lists: [DoddyList]) -> String {
        guard !lists.isEmpty else { return "(no lists yet)" }
        return lists.map { list in
            "- \(list.name) (\(list.open.count) open, \(list.done.count) ticked)"
        }.joined(separator: "\n")
    }
}

extension VoiceToolReply {
    /// No list by that name: nothing changed; the agent asks.
    public static func listNotFound(_ name: String, lists: [DoddyList]) -> String {
        let names = lists.map { "\"\($0.name)\"" }.joined(separator: ", ")
        return "not found: there is no list called \"\(name)\". Nothing changed. "
            + (lists.isEmpty ? "The user has no lists yet. " : "Their lists: \(names). ")
            + "Ask the user which list they mean, or whether to start a new one with create_list."
    }

    public static func listAmbiguous(_ name: String, lists: [DoddyList]) -> String {
        "not changed: \"\(name)\" matches more than one list (\(lists.map { "\"\($0.name)\"" }.joined(separator: ", "))). Ask the user which one."
    }

    public static func listAdded(_ result: ListAddResult, list: String) -> String {
        var parts: [String] = []
        if result.added.isEmpty {
            parts.append("not added: nothing new was added to \"\(list)\".")
        } else {
            parts.append("added to \"\(list)\": \(result.added.map(\.text).joined(separator: ", ")).")
        }
        if !result.alreadyThere.isEmpty {
            parts.append("Already on the list, not added again: \(result.alreadyThere.joined(separator: ", ")).")
        }
        if !result.tooLong.isEmpty {
            parts.append("Too long to add (over \(ListLimits.itemLength) characters): \(result.tooLong.joined(separator: ", ")).")
        }
        if !result.noRoom.isEmpty {
            parts.append("Not added, the list is full (\(ListLimits.itemsPerList) items): \(result.noRoom.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    public static func listRead(_ list: DoddyList) -> String {
        let open = list.open
        guard !open.isEmpty else {
            return "\"\(list.name)\": nothing left\(list.done.isEmpty ? "; the list is empty" : " (\(list.done.count) ticked)")."
        }
        let shown = open.prefix(ListLimits.readAloud).map(\.text)
        var text = "\"\(list.name)\", \(open.count) open, in order: \(shown.joined(separator: "; "))"
        if open.count > shown.count { text += "; and \(open.count - shown.count) more (all on the user's screen)" }
        text += "."
        if !list.done.isEmpty { text += " Ticked: \(list.done.count)." }
        return text + " Read the items in the user's own words; never add any."
    }

    /// `changed` were ticked or removed; the rest could not be matched.
    public static func listChanged(
        verb: String, changed: [ListItem], list: String, notFound: [String], ambiguous: [(said: String, options: [ListItem])]
    ) -> String {
        var parts: [String] = []
        if changed.isEmpty {
            parts.append("not changed: nothing on \"\(list)\" was \(verb).")
        } else {
            parts.append("\(verb) on \"\(list)\": \(changed.map(\.text).joined(separator: ", ")).")
        }
        for (said, options) in ambiguous {
            parts.append("\"\(said)\" matches several items (\(options.map { "\"\($0.text)\"" }.joined(separator: ", "))): not \(verb); ask the user which one.")
        }
        if !notFound.isEmpty {
            parts.append("Not on the list: \(notFound.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    public static func listCreated(_ list: DoddyList) -> String {
        "created: the list \"\(list.name)\" with \(list.items.count) item\(list.items.count == 1 ? "" : "s")\(list.items.isEmpty ? "" : ": " + list.items.map(\.text).joined(separator: ", "))."
    }

    public static let declinedList = "declined: the user chose not to start this list. Nothing was made."

    public static func listNameTaken(_ name: String) -> String {
        "not created: a list called \"\(name)\" already exists. Offer to add the items to it with add_to_list instead."
    }

    public static func listFailed(_ reason: String) -> String {
        "failed: \(reason) The list didn't change."
    }
}

/// Find (ADR-216 follow-up): lists whose name or items hold a word of the search. Every word
/// is matched as the start of a word, ignoring case and accents, as notes are; nothing is guessed.
public struct ListSearchHit: Equatable, Sendable, Identifiable {
    public let list: DoddyList
    /// True when the list's name matched.
    public let nameMatched: Bool
    /// Items with a matching word, in list order.
    public let items: [ListItem]

    public var id: UUID { list.id }
}

public enum ListSearch {
    public static func hits(_ query: String, in lists: [DoddyList]) -> [ListSearchHit] {
        let terms = SearchFolding.queryTerms(query)
        guard !terms.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            let words = SearchFolding.tokens(text)
            return terms.contains { term in words.contains { $0.hasPrefix(term) } }
        }
        return lists.compactMap { list in
            let nameMatched = matches(list.name)
            let items = list.items.filter { matches($0.text) }
            return nameMatched || !items.isEmpty ? ListSearchHit(list: list, nameMatched: nameMatched, items: items) : nil
        }
    }
}
