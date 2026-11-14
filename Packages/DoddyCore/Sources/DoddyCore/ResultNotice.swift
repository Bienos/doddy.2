import Foundation

/// When Doddy shows his own "it's in Messages" notice for a finished task (owner, 12 Nov 2026: "proszę go o zrobienie
/// jakiegoś taska, mówi, że to będzie w wiadomościach i potem ja nie dostaję notyfikacji żadnej").
///
/// A finished task reaches Messages when the app asks Doddy's server (`ErrandsModel.refresh`): when it comes to the
/// front, every 30 seconds while it is open and a task runs, and when the server's push about it arrives. The server's
/// push is the notice when it comes; this one covers the times it doesn't (notifications for Doddy's server not set
/// up on this iPhone, or the app's own check found the result first). The rules, so the two never both show:
/// - only while the app is in front (in the background only the server's push can arrive at all);
/// - never while Messages is on screen (the message itself shows there);
/// - not when a task's push from the server, or an earlier notice of this kind, arrived within the last `window`;
/// - a server push that arrives while the app is open is not shown when this notice was, within `window`.
///
/// The notice says only that a task finished, never its title or result: like the server's push, it can be read on
/// the Lock Screen. It carries the same `doddy.kind` as the server's push, so a tap opens Messages the same way.
public enum ResultNotice {
    public static let identifierPrefix = "doddy.resultNotice."
    /// Two notices about one finished task this close together are one too many.
    public static let window: TimeInterval = 10 * 60

    public static func identifier(for errandID: UUID) -> String { identifierPrefix + errandID.uuidString }
    public static func isLocal(identifier: String) -> Bool { identifier.hasPrefix(identifierPrefix) }

    /// The same routing hint the server's push carries (`ServerPushKind.parse` reads it).
    public static var userInfo: [String: [String: String]] { ["doddy": ["kind": ServerPushKind.errandResult.rawValue]] }

    /// A notification already in Notification Center, as these rules need it.
    public struct Delivered: Equatable, Sendable {
        public let identifier: String
        public let kind: ServerPushKind?
        public let date: Date

        public init(identifier: String, kind: ServerPushKind?, date: Date) {
            self.identifier = identifier
            self.kind = kind
            self.date = date
        }

        var isLocalNotice: Bool { ResultNotice.isLocal(identifier: identifier) }
        var isServerTaskPush: Bool { kind == .errandResult && !isLocalNotice }
    }

    /// Whether to show the app's own notice for a task result it has just saved in Messages.
    public static func shouldPost(appActive: Bool, threadVisible: Bool, delivered: [Delivered], now: Date) -> Bool {
        guard appActive, !threadVisible else { return false }
        return !delivered.contains { ($0.isServerTaskPush || $0.isLocalNotice) && recent($0.date, now) }
    }

    /// Whether to show a push from Doddy's server that arrives while the app is open. Only a finished task's push is
    /// ever held back, and only when the app's own notice about a result showed within `window`.
    public static func shouldPresentServerPush(kind: ServerPushKind?, delivered: [Delivered], now: Date) -> Bool {
        guard kind == .errandResult else { return true }
        return !delivered.contains { $0.isLocalNotice && recent($0.date, now) }
    }

    private static func recent(_ date: Date, _ now: Date) -> Bool { abs(now.timeIntervalSince(date)) <= window }
}
