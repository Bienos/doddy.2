import Foundation

// Apple Watch (ADR-232). The watch app shows what the widgets show (pinned notes, the next note
// reminders, lists) from a snapshot the iPhone sends, and can do two things, each only while the
// iPhone answers: tick or untick a list item, and save a new note written or dictated on the
// watch. The iPhone does the change in its own store, reads it back, and replies; the watch says
// "Saved" or "Ticked" only from that reply. Nothing is queued to happen later, and the watch keeps
// no database of its own.

/// What the watch asks the iPhone to do.
public enum WatchRequest: Codable, Equatable, Sendable {
    case tick(listID: UUID, itemID: UUID, shownDone: Bool)
    case saveNote(text: String)
    /// An item said or written on the watch, for one list (ADR-287).
    case addToList(listID: UUID, text: String)

    public func encoded() throws -> Data { try JSONEncoder().encode(Envelope(version: WatchLinkVersion.current, request: self)) }

    /// nil for anything unreadable or from another version: the iPhone does nothing.
    public static func decoded(_ data: Data) -> WatchRequest? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == WatchLinkVersion.current else { return nil }
        return envelope.request
    }

    private struct Envelope: Codable {
        let version: Int
        let request: WatchRequest
    }
}

/// The iPhone's answer, from its read-back store.
public enum WatchReply: Codable, Equatable, Sendable {
    case ticked
    case unticked
    /// The item or list changed on the iPhone since the watch drew it; nothing changed.
    case notFound
    case saved
    /// Nothing was saved; `reason` is shown on the watch.
    case notSaved(reason: String)
    /// Added to the list on the iPhone and read back (ADR-287).
    case addedToList(String)
    /// The same item is already open on the list; nothing added.
    case alreadyOnList(String)
    case failed

    public init(_ tick: WidgetTick) {
        switch tick {
        case .ticked: self = .ticked
        case .unticked: self = .unticked
        case .notFound: self = .notFound
        case .failed: self = .failed
        }
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decoded(_ data: Data) -> WatchReply? { try? JSONDecoder().decode(WatchReply.self, from: data) }

    /// What the watch shows.
    public var message: String {
        switch self {
        case .ticked: "Ticked on your iPhone."
        case .unticked: "Unticked on your iPhone."
        case .notFound: "That list changed on your iPhone. Nothing was changed."
        case .saved: "Saved in Doddy on your iPhone."
        case .notSaved(let reason): reason
        case .addedToList(let text): "Added “\(text)” on your iPhone."
        case .alreadyOnList(let text): "“\(text)” is already on the list. Nothing added."
        case .failed: "Your iPhone couldn't do that. Nothing was changed."
        }
    }
}

public enum WatchLinkVersion {
    public static let current = 1
    /// The application-context key holding the encoded `WidgetSnapshot`.
    public static let snapshotKey = "snapshot"
}

public enum WatchNote {
    /// Checked on the watch before sending and again on the iPhone before saving.
    public static func problem(_ text: String) -> String? {
        do {
            try MemoryTextValidator.validate(text)
            return nil
        } catch {
            if case .tooLong(_, let maximum) = error { return "A note can be up to \(maximum) characters." }
            return "Say or type a few words first."
        }
    }

    /// A list item from the watch: the same rules as one typed on the iPhone (ADR-287).
    public static func itemProblem(_ text: String) -> String? {
        guard let item = ListText.cleaned(text) else { return "Say or type an item first." }
        return item.count > ListLimits.itemLength ? "An item can be up to \(ListLimits.itemLength) characters." : nil
    }

    /// When the iPhone can't be reached: nothing was sent, and nothing is kept to send later.
    public static let unreachable = "Your iPhone isn't reachable, so nothing was saved or changed. Try again near your iPhone."
    /// Sent, but no answer came: it may or may not have happened. Never treated as done.
    public static let unanswered = "Your iPhone didn't answer, so Doddy can't say whether it happened. Check in Doddy on your iPhone before trying again."
}
