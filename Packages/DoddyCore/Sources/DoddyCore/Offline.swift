import Foundation

// Offline (ADR-273). Doddy's voice needs the internet. When a conversation can't start, or drops,
// because the iPhone has no connection, the voice screen says so plainly ("You're offline")
// instead of a technical error, and offers what works without the internet: writing or dictating
// a note that is saved on this iPhone, checked, as on Capture. Nothing is queued to send later.
// The app doesn't watch the network itself (no Network framework, by the capability guard); it
// recognises the errors it already gets.

public enum Offline {
    /// URL loading errors that mean "no connection", not "the server said no".
    static let networkCodes: Set<Int> = [
        URLError.notConnectedToInternet.rawValue,
        URLError.networkConnectionLost.rawValue,
        URLError.cannotFindHost.rawValue,
        URLError.cannotConnectToHost.rawValue,
        URLError.dnsLookupFailed.rawValue,
        URLError.timedOut.rawValue,
        URLError.dataNotAllowed.rawValue,
        URLError.internationalRoamingOff.rawValue,
        URLError.callIsActive.rawValue,
    ]

    /// True when the error, or an error inside it, is a lost or missing connection.
    public static func isNoConnection(_ error: any Error) -> Bool {
        if let token = error as? VoiceTokenError { return token == .offline }
        var current: NSError? = error as NSError
        var depth = 0
        while let ns = current, depth < 5 {
            if ns.domain == NSURLErrorDomain, networkCodes.contains(ns.code) { return true }
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    public static let title = "You're offline"
    public static let explanation = "Doddy's voice needs the internet. You can still write or dictate a note here; it's saved on this iPhone."
}
