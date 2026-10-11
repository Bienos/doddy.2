import Foundation

// List templates (ADR-334). A template is a list's name and items kept for reuse, e.g.
// "Packing" or "Weekly shop". Saving one copies the list's items as they are written (ticks are
// not kept); starting from one makes a new list with those items, through the same card as
// create_list. Kept on this iPhone in the app's preferences.

public struct ListTemplate: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let items: [String]

    public init(id: UUID = UUID(), name: String, items: [String]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public struct ListTemplates: Equatable, Sendable {
    public static let storageKey = "lists.templates"
    public static let maxTemplates = 20

    public private(set) var all: [ListTemplate]

    public init(_ all: [ListTemplate] = []) {
        self.all = all
    }

    /// Read from what was stored; anything unreadable counts as no templates.
    public init(stored: Data?) {
        all = stored.flatMap { try? JSONDecoder().decode([ListTemplate].self, from: $0) } ?? []
    }

    public var stored: Data? { try? JSONEncoder().encode(all) }

    public enum SaveOutcome: Equatable, Sendable {
        case saved(ListTemplate)
        /// One with this name was replaced by the list's current items.
        case replaced(ListTemplate)
        case empty
        case full
    }

    /// Saves `list` as a template named like it. A template with the same name (any case) is
    /// replaced, so "save as template" again updates it.
    public mutating func save(_ list: DoddyList) -> SaveOutcome {
        let items = list.items.sorted { $0.position < $1.position }.map(\.text)
        var seen: [String] = []
        for item in items where !ListMatch.isDuplicate(item, of: seen) { seen.append(item) }
        let capped = Array(seen.prefix(ListLimits.itemsPerList))
        guard !capped.isEmpty else { return .empty }
        if let index = all.firstIndex(where: { ListMatch.key($0.name) == ListMatch.key(list.name) }) {
            let template = ListTemplate(id: all[index].id, name: list.name, items: capped)
            all[index] = template
            return .replaced(template)
        }
        guard all.count < Self.maxTemplates else { return .full }
        let template = ListTemplate(name: list.name, items: capped)
        all.append(template)
        return .saved(template)
    }

    public mutating func remove(_ id: UUID) {
        all.removeAll { $0.id == id }
    }

    /// The template the user named, by the same exact matching as lists ("packing list" finds
    /// "Packing"). Nil when none or several match; the caller says which exist.
    public func named(_ name: String) -> ListTemplate? {
        let wanted = ListMatch.key(name)
        let exact = all.filter { ListMatch.key($0.name) == wanted }
        if exact.count == 1 { return exact[0] }
        let loose = all.filter { ListMatch.key($0.name).contains(wanted) || wanted.contains(ListMatch.key($0.name)) }
        return loose.count == 1 ? loose[0] : nil
    }

    /// The new list's items: the template's, then any the user added that aren't already there.
    public static func items(from template: ListTemplate, plus extra: [String]) -> [String] {
        var items = template.items
        for item in extra where !ListMatch.isDuplicate(item, of: items) { items.append(item) }
        return Array(items.prefix(ListLimits.itemsPerList))
    }

    /// For the voice agent's context: template names only.
    public var promptLine: String? {
        guard !all.isEmpty else { return nil }
        return "List templates (start one with create_list and template): " + all.map(\.name).joined(separator: ", ")
    }
}

extension VoiceToolReply {
    /// The name asked for (the agent's words) and the user's template names follow as data (ToolData).
    public static func templateNotFound(_ name: String, templates: ListTemplates) -> String {
        let asked = quoted("Asked for", name)
        guard !templates.all.isEmpty else {
            return "not found: there is no list template with the name below. Nothing was made. "
                + "The user has no templates yet; they can save one from a list's menu in Doddy (Save as template).\n"
                + ToolData.block([asked])
        }
        return "not found: there is no list template with the name below. Nothing was made. "
            + "Ask which one they mean. The name asked for, then their templates:\n"
            + ToolData.block([asked] + templates.all.map { "- \"\(ToolData.clean($0.name))\"" })
    }
}
