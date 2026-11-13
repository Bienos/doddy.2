import Foundation

/// Owner, 12 Nov 2026 (decision `2026-11-12-deleted-files-stay-gone`): a file Doddy made before the person deleted
/// the conversation, or before this copy of the app was installed, is not offered again on this iPhone, neither as a
/// card in Messages nor in Files. Doddy's server still keeps each file until its own deletion date (a week, ADR-564);
/// only the iPhone stops showing it. Plain Swift for the Linux tests.
public enum FilesShownSince {
    /// The moment from which made files are shown: the later of the install and the last deletion of the
    /// conversation. Nil when neither is known; then everything the server still keeps is shown, as before.
    public static func start(installedAt: Date?, conversationDeletedAt: Date?) -> Date? {
        switch (installedAt, conversationDeletedAt) {
        case let (installed?, deleted?): max(installed, deleted)
        case let (installed?, nil): installed
        case let (nil, deleted?): deleted
        case (nil, nil): nil
        }
    }

    /// The server's list without the files made before `since`. The server's own record (kept days) is unchanged.
    public static func visible(_ list: MadeDocumentList, since: Date?) -> MadeDocumentList {
        guard let since else { return list }
        return MadeDocumentList(documents: list.documents.filter { $0.createdAt >= since }, keptDays: list.keptDays)
    }

    /// The files made on this iPhone in a voice conversation, without those made before `since`.
    public static func visible(_ files: [LocalMadeFile], since: Date?) -> [LocalMadeFile] {
        guard let since else { return files }
        return files.filter { $0.createdAt >= since }
    }
}
