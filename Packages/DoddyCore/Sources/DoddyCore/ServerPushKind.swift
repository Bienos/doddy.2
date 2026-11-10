import Foundation

/// What a push from Doddy's messaging server asks the app to open when it is tapped. The server puts a
/// routing hint next to `aps` under the key `doddy` (`{"doddy":{"kind":"call-result"}}`); it is a kind
/// only, never a case id or any words, because a notification's payload is readable on the Lock Screen.
/// Anything else, including a kind this build does not know, opens nothing special: the app just opens.
public enum ServerPushKind: String, Equatable, Sendable {
    /// A call Doddy made for the person has its answer ready: open Files › Calls.
    case callResult = "call-result"
    /// A task Doddy worked on in the background finished: open Messages, where his message about it is.
    case errandResult = "errand-result"
    /// A file Doddy was making is ready (or failed): open Messages, where the file is.
    case fileReady = "file-ready"

    /// Opens Messages when tapped (owner, 10 Nov 2026).
    public var opensMessages: Bool { self == .errandResult || self == .fileReady }

    public static func parse(_ userInfo: [AnyHashable: Any]) -> ServerPushKind? {
        guard let hint = userInfo["doddy"] as? [String: Any], let kind = hint["kind"] as? String else { return nil }
        return ServerPushKind(rawValue: kind)
    }
}
