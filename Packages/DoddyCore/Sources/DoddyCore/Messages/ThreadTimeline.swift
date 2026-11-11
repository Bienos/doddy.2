import Foundation

/// Messages as one timeline (owner, 11 Nov 2026: "ma to być jako taka wrzucona rozmowa w czasie", the made file "nie
/// powinno tam cały czas widnieć"). Until then a file Doddy made without a bubble in the thread was drawn in a section
/// under the newest message, so a week-old deck looked pinned to the bottom of the conversation. Now each one takes
/// its place by the time it was made, among the messages, and nothing is drawn after the newest one but what is
/// happening now. Plain Swift for the Linux tests; nothing here is stored or sent.
public enum ThreadTimeline {
    public enum Item: Equatable, Sendable, Identifiable {
        /// A saved message; `index` is its place in the thread, for the bubble's run and day heading.
        case message(index: Int, ThreadMessage)
        /// A file Doddy made on this iPhone in a voice conversation, kept for a week.
        case localFile(LocalMadeFile)
        /// A file on Doddy's server that has no bubble in this thread (made from Doddy Web, a private conversation,
        /// an older app build, or a thread that was cleared).
        case serverFile(MadeDocument)

        public var id: String {
            switch self {
            case .message(_, let message): "m-\(message.id.uuidString)"
            case .localFile(let file): "l-\(file.id.uuidString)"
            case .serverFile(let document): "s-\(document.id)"
            }
        }

        public var date: Date {
            switch self {
            case .message(_, let message): message.createdAt
            case .localFile(let file): file.createdAt
            case .serverFile(let document): document.createdAt
            }
        }

        /// Messages before files at the same moment, then by id, so the order never changes between two reads.
        fileprivate var rank: Int {
            switch self {
            case .message: 0
            case .localFile: 1
            case .serverFile: 2
            }
        }
    }

    /// The thread with the files placed by time. `local` and `server` are what `LocalMadeFiles.shown` and
    /// `ThreadAttachments.shown`/`inProgress` already chose (not expired, not already a bubble).
    public static func items(messages: [ThreadMessage], local: [LocalMadeFile], server: [MadeDocument]) -> [Item] {
        let all: [Item] = messages.enumerated().map { Item.message(index: $0.offset, $0.element) }
            + local.map(Item.localFile) + server.map(Item.serverFile)
        // Stable: messages keep their saved order among themselves even when two have the same time.
        return all.enumerated().sorted { a, b in
            if a.element.date != b.element.date { return a.element.date < b.element.date }
            if a.element.rank != b.element.rank { return a.element.rank < b.element.rank }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// What the server says about a file Doddy put in the thread, for its bubble (11 Nov 2026). Until then the bubble kept
/// the words it was saved with ("I'm making …, it opens from here") and a file that failed looked ready to open.
public enum ThreadFileState: Equatable, Sendable {
    /// Not in the server's list (not read yet, or another account's): the bubble shows what it was saved with.
    case unknown
    case making
    case ready
    /// Failed or stopped on the server: nothing to open.
    case failed

    public static func of(_ document: ThreadDocument, in documents: [MadeDocument]) -> ThreadFileState {
        guard let id = document.documentID, let made = documents.first(where: { $0.id == id }) else { return .unknown }
        switch made.status {
        case .working: return .making
        case .ready: return .ready
        case .failed, .interrupted: return .failed
        }
    }

    /// The words above the file card now: the saved caption while it is being made or unknown, and what happened
    /// once the server says so. Only what the server reported; "ready" only for a file it lists as ready.
    public func caption(for message: ThreadMessage, polish: Bool) -> String? {
        guard let document = message.document else { return nil }
        let name = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = name.isEmpty ? document.label : name
        switch self {
        case .unknown, .making:
            return ThreadDelivery.caption(of: message)
        case .ready:
            // A file made from the chat's Make it card has no caption of its own; it keeps none.
            guard ThreadDelivery.caption(of: message) != nil else { return nil }
            return polish ? "Proszę, gotowe: „\(shown)”." : "Here it is: “\(shown)”."
        case .failed:
            return polish
                ? "Nie udało mi się zrobić „\(shown)”. Poproś mnie jeszcze raz, a spróbuję od nowa."
                : "I couldn't make “\(shown)”. Ask me again and I'll start over."
        }
    }
}
