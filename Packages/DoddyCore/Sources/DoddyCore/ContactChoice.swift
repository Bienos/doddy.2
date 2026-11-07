import Foundation

// Contacts for a drafted text or email (ADR-717). The agent asks for these with a name and no
// yes first (the card comes after the search), so the search is held to what the card needs and
// no more:
//  - it runs only with Doddy's own Contacts switch on, as `lookup_contact` does, and iOS's
//    permission; with the switch off a text or email card still works from the name as typed,
//  - at most three such searches in a conversation, so a run of one-letter names can't walk
//    through the address book,
//  - several matches are never guessed between and never listed in full: the agent hears how many
//    and at most three names, and asks the user for the full name.
// What the card shows the user (the contact, the number or address) never goes to the agent.

/// The searches of Contacts a conversation may make before a card exists.
public struct ContactSearchBudget: Equatable, Sendable {
    public static let perConversation = 3
    public private(set) var used = 0

    public init() {}

    /// True while a search is still allowed, and counts it.
    public mutating func take() -> Bool {
        guard used < Self.perConversation else { return false }
        used += 1
        return true
    }
}

/// Whether Contacts may be searched now for a draft.
public enum ContactRead {
    public enum Decision: Equatable, Sendable {
        /// Search. One of the conversation's searches is used up.
        case search
        /// Doddy's Contacts switch (Settings, Connections) is off: nothing is read.
        case switchOff
        /// iOS has not allowed Contacts for Doddy: nothing is read.
        case notAllowedByIOS
        /// The conversation already made `ContactSearchBudget.perConversation` searches.
        case budgetSpent
    }

    /// The switch first, then iOS, then the budget; a search that isn't allowed costs nothing.
    public static func decide(switchOn: Bool, iosAllows: Bool, budget: inout ContactSearchBudget) -> Decision {
        guard switchOn else { return .switchOff }
        guard iosAllows else { return .notAllowedByIOS }
        return budget.take() ? .search : .budgetSpent
    }
}

enum ContactName {
    /// The match to use among several: the only one whose whole name is what was asked for, ignoring
    /// case and accents ("Anna Nowak" among "Anna Nowak" and "Anna Nowakowska"). Nil when none or
    /// more than one is; nothing is guessed. With one match, that one.
    static func only(query: String, names: [String]) -> Int? {
        if names.count == 1 { return 0 }
        let wanted = SearchFolding.tokens(query)
        guard !wanted.isEmpty else { return nil }
        let exact = names.indices.filter { SearchFolding.tokens(names[$0]) == wanted }
        return exact.count == 1 ? exact[0] : nil
    }
}

/// Who a text or email draft is for, decided from the Contacts search.
public enum MessageRecipient: Equatable, Sendable {
    /// Nobody matched.
    case nobody
    /// One contact; either list may be empty.
    case contact(name: String, phoneNumbers: [String], emailAddresses: [String])
    /// More than one matched and none is exactly the name asked for; the agent asks for the full name.
    case several(names: [String])

    /// `matches` is what the Contacts search found, in its order.
    public static func resolve(_ matches: [(name: String, phoneNumbers: [String], emailAddresses: [String])], query: String) -> MessageRecipient {
        guard !matches.isEmpty else { return .nobody }
        guard let index = ContactName.only(query: query, names: matches.map(\.name)) else {
            return .several(names: matches.map(\.name))
        }
        let match = matches[index]
        return .contact(name: match.name, phoneNumbers: match.phoneNumbers, emailAddresses: match.emailAddresses)
    }
}

extension VoiceToolReply {
    /// The most names a "several contacts match" reply carries (ADR-717).
    public static let maxContactNames = 3

    /// The search and at most `maxContactNames` of the names, as data (ToolData): names come from
    /// Contacts. How many matched is said before it, in the reply's first line.
    static func severalContactsData(_ names: [String], query: String) -> String {
        let shown = names.prefix(maxContactNames)
        var lines = [quoted("Searched for", query)] + shown.map { "- \(ToolData.clean($0))" }
        if names.count > shown.count { lines.append("(\(names.count - shown.count) more, not listed)") }
        return ToolData.block(lines)
    }

    /// More than one contact has the name the agent sent for a text or email draft.
    public static func messageSeveralContacts(_ names: [String], query: String) -> String {
        "failed: \(names.count) contacts match the name below, so no draft was opened. Ask the user for the person's full name, then call "
            + "\(VoiceToolName.draftMessage) again with it. Never read out a number or an address. Nothing was sent.\n"
            + severalContactsData(names, query: query)
    }

    /// The conversation used its searches of Contacts for drafts.
    public static let contactSearchesSpent =
        "failed: Doddy already looked in Contacts \(ContactSearchBudget.perConversation) times for drafts in this conversation and won't look again, so no draft was opened. "
        + "Nothing was sent. Tell the user in one short sentence; they can write it in Messages or Mail themselves."
}
