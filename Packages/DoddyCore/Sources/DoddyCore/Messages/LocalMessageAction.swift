import Foundation

/// A bounded allowlist shared with the voice parser. A model proposes; only the app's card authorises it.
public struct LocalMessageAction: Equatable, Sendable {
    public enum Name: String, Codable, CaseIterable, Sendable {
        case saveMemory = "save_memory", searchMemories = "search_memories"
        case createList = "create_list", readList = "read_list", addToList = "add_to_list"
        case checkOff = "check_off", removeFromList = "remove_from_list", createReminder = "create_reminder"
    }
    public static let maxParameterBytes = 12_000
    public let name: Name
    public let parametersJSON: String
    /// Resolved once, in the phone's time zone. At the tap ReminderAction checks it hasn't passed.
    public let request: VoiceToolRequest

    public static func make(name raw: String, parametersJSON: String, now: Date = Date(), calendar: Calendar = .current) -> LocalMessageAction? {
        guard let name = Name(rawValue: raw), parametersJSON.utf8.count <= maxParameterBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(parametersJSON.utf8)) as? [String: Any]
        else { return nil }
        let keys: Set<String>
        switch name {
        case .saveMemory: keys = ["text"]
        case .searchMemories: keys = ["query"]
        case .createList: keys = ["name", "items"]
        case .readList: keys = ["list"]
        case .addToList, .checkOff, .removeFromList: keys = ["list", "items"]
        case .createReminder: keys = ["title", "due", "said_time", "notes", "repeat", "repeat_until"]
        }
        guard Set(object.keys).isSubset(of: keys) else { return nil }
        guard object.allSatisfy({ key, value in key == "items" ? value is [String] : value is String }) else { return nil }
        if let items = object["items"] {
            guard let array = items as? [String], array.count <= ListLimits.itemsPerList,
                  array.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= ListLimits.itemLength }) else { return nil }
        }
        let request = VoiceToolRequest.parse(name: raw, parametersJSON: Data(parametersJSON.utf8), now: now, calendar: calendar)
        switch request {
        case .saveMemory(let text): guard (try? MemoryTextValidator.validate(text)) != nil else { return nil }
        case .searchMemories, .readList, .createList, .addToList, .checkOff, .removeFromList, .createReminder, .needsClarification: break
        default: return nil
        }
        return .init(name: name, parametersJSON: parametersJSON, request: request)
    }

    public func card(polish: Bool) -> AskCard {
        switch request {
        case .saveMemory(let text):
            return AskCard(title: polish ? "Zapisać notatkę?" : "Save this note?", lines: [text], confirmLabel: polish ? "Zapisz" : "Save")
        case .createList(let draft):
            return AskCard(title: polish ? "Utworzyć listę?" : "Create this list?", lines: [draft.list] + draft.items,
                           confirmLabel: polish ? "Utwórz" : "Create list")
        case .createReminder(let draft):
            let due = draft.due.map { ReminderText.due($0) } ?? (polish ? "Bez terminu" : "No due date")
            let lines = [draft.title, due] + [draft.notes, draft.repeats?.text].compactMap { $0 }
            return AskCard(title: polish ? "Dodać przypomnienie?" : "Add this reminder?", lines: lines, confirmLabel: polish ? "Dodaj" : "Add")
        case .searchMemories(let query):
            return AskCard(title: polish ? "Przeszukać notatki?" : "Search your saved notes?", lines: [query], confirmLabel: polish ? "Tak, szukaj" : "Yes, search")
        case .readList(let name):
            return AskCard(title: polish ? "Odczytać listę?" : "Read this list?", lines: [name], confirmLabel: polish ? "Tak, odczytaj" : "Yes, read it")
        case .addToList(let draft):
            return AskCard(title: polish ? "Dodać do listy „\(draft.list)”?" : "Add to \(draft.list)?", lines: draft.items, confirmLabel: polish ? "Dodaj" : "Add")
        case .checkOff(let draft):
            return AskCard(title: polish ? "Oznaczyć jako zrobione na liście „\(draft.list)”?" : "Check off on \(draft.list)?", lines: draft.items, confirmLabel: polish ? "Oznacz jako zrobione" : "Check off")
        case .removeFromList(let draft):
            return AskCard(title: polish ? "Usunąć z listy „\(draft.list)”?" : "Remove from \(draft.list)?", lines: draft.items, confirmLabel: polish ? "Usuń" : "Remove")
        case .needsClarification(_, let clarification):
            return AskCard(title: polish ? "Doprecyzuj termin" : "Clarify the date or time", lines: [clarification.question], confirmLabel: "")
        default:
            switch AskFirst.need(for: request, polish: polish) {
            case .yesFirst(let card), .tapFirst(let card): return card
            default: return AskCard(title: "Unavailable", lines: [], confirmLabel: "")
            }
        }
    }

    public var canExecute: Bool {
        if case .needsClarification = request { return false }
        return true
    }
}

/// Only opted-in Messages clients advertise this extension. Older clients and servers keep answering normally.
public struct LocalMessageActionContext: Equatable, Sendable, Codable {
    public let version: Int
    public let localNow: String
    public let timeZone: String

    public init(now: Date = Date(), calendar: Calendar = .current) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        version = 1; localNow = formatter.string(from: now); timeZone = calendar.timeZone.identifier
    }
}

public enum LocalMessageActionOutcome: Equatable, Sendable {
    case completed(String)
    case failed(String)
    /// Never automatically retried, even if the card is tapped twice or the screen reopens.
    case unknown(String)
    public var message: String {
        switch self { case .completed(let text), .failed(let text), .unknown(let text): text }
    }
}

@MainActor
public protocol LocalMessageActionExecuting {
    func execute(_ action: LocalMessageAction, stillAuthorised: @escaping @MainActor () -> Bool) async -> LocalMessageActionOutcome
}
