import Foundation

/// The Share button on a file Doddy made (owner, 10 Nov 2026: "wyślij mi to do plików albo wiadomości"). The
/// file is downloaded to this iPhone first and handed to iOS's share sheet, where the person picks Files, Messages,
/// Mail or another app and sends it themselves. Doddy sends nothing. Plain Swift for the Linux tests.
public enum MadeFileShare {
    public enum Lookup: Equatable, Sendable {
        /// Ready: download it and share.
        case ready(MadeDocument)
        /// Still being made: try again in a minute.
        case making
        /// Failed or stopped on the server.
        case failed
        /// The server no longer lists it (deleted after its days, or never this account's).
        case gone
    }

    /// Finds the file a link points at (`/v1/documents/<id>…`) in the server's list.
    public static func lookup(link: URL, in documents: [MadeDocument], now: Date) -> Lookup {
        guard let id = ThreadAttachments.documentID(of: link),
              let document = documents.first(where: { $0.id == id }),
              document.deleteAfter > now else { return .gone }
        switch document.status {
        case .ready: return document.canOpen ? .ready(document) : .gone
        case .working: return .making
        case .failed, .interrupted: return .failed
        }
    }
}
