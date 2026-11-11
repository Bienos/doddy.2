import Foundation

/// Which recap note came from which conversation, and which conversations the person deleted.
///
/// A recap is saved as an ordinary note, so nothing tied it to its conversation. This keeps the tie
/// for recaps saved from now on (never guessed from dates or wording, so an older or edited note is
/// never taken for a recap). A deleted conversation leaves a tombstone: a recap still being written
/// when the person deletes the conversation sees it and is not saved. Stored in UserDefaults under
/// `key`; anything unreadable is empty.
public struct RecapLinks: Equatable, Sendable, Codable {
    public static let key = "recaps.links.v1"
    /// Oldest entries are dropped beyond this. A recap is written within a minute or two, so a
    /// tombstone this old can no longer be raced by one.
    public static let maxEntries = 500

    public struct Link: Equatable, Sendable, Codable {
        public let conversationID: UUID
        public let memoryID: UUID

        public init(conversationID: UUID, memoryID: UUID) {
            self.conversationID = conversationID
            self.memoryID = memoryID
        }
    }

    public private(set) var links: [Link]
    public private(set) var deleted: [UUID]

    public init(links: [Link] = [], deleted: [UUID] = []) {
        self.links = Array(links.suffix(Self.maxEntries))
        self.deleted = Array(deleted.suffix(Self.maxEntries))
    }

    public init(stored: String?) {
        let decoded = stored.flatMap { try? JSONDecoder().decode(RecapLinks.self, from: Data($0.utf8)) }
        self = decoded.map { RecapLinks(links: $0.links, deleted: $0.deleted) } ?? RecapLinks()
    }

    public var stored: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public func memoryID(for conversation: UUID) -> UUID? {
        links.last { $0.conversationID == conversation }?.memoryID
    }

    public func isDeleted(_ conversation: UUID) -> Bool { deleted.contains(conversation) }

    /// Records that `memory` is the recap of `conversation`. A deleted conversation gets no link, unless
    /// the note exists anyway (it couldn't be removed) and must stay findable.
    public func linking(conversation: UUID, memory: UUID, evenIfDeleted: Bool = false) -> RecapLinks {
        guard evenIfDeleted || !isDeleted(conversation) else { return self }
        let others = links.filter { $0.conversationID != conversation }
        return RecapLinks(links: others + [Link(conversationID: conversation, memoryID: memory)], deleted: deleted)
    }

    /// Marks conversations as deleted, so a recap that finishes later is not saved.
    public func tombstoning(_ conversations: [UUID]) -> RecapLinks {
        let fresh = conversations.filter { !deleted.contains($0) }
        return RecapLinks(links: links, deleted: deleted + fresh)
    }

    /// Forgets the tie between a conversation and its recap note (the note itself is not touched).
    public func unlinking(conversation: UUID) -> RecapLinks {
        RecapLinks(links: links.filter { $0.conversationID != conversation }, deleted: deleted)
    }
}
