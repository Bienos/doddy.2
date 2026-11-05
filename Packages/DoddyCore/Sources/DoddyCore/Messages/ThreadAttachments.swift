import Foundation

/// Files Doddy made that belong under the thread but are not in it: a deck or document from a voice
/// conversation or a background task, which the server lists (`MadeDocumentsClient`) and the Files tab shows.
/// Nothing is copied into the saved thread; the cards are read from the server each time the screen opens, so a
/// file the server no longer keeps simply stops being offered. Plain Swift for the Linux tests.
public enum ThreadAttachments {
    /// At most this many cards, the newest ones, so a busy week does not bury the conversation.
    public static let limit = 6

    /// The document id inside a link Doddy's server made for a file (`/v1/documents/<id>?…`), or nil for any
    /// other link. A bubble made from the chat's Make it card keeps that link, so this finds the same file in the list.
    public static func documentID(of url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "v1", parts[1] == "documents", MadeDocument.isID(parts[2]) else { return nil }
        return parts[2]
    }

    /// The files to show as cards, oldest first: ready, still kept by the server, and not already a bubble in the
    /// thread. A file that is still being made, failed or stopped is not offered here (the Files tab says why).
    public static func shown(documents: [MadeDocument], thread: [ThreadMessage], now: Date) -> [MadeDocument] {
        let inThread = Set(thread.compactMap { $0.document.flatMap { documentID(of: $0.url) } })
        let candidates = documents
            .filter { $0.status == .ready && $0.deleteAfter > now && !inThread.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
        return candidates.sorted { $0.createdAt < $1.createdAt }
    }
}
