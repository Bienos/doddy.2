import DoddyCore
import Foundation

/// Where the Doddy messaging server (`server/messaging`) lives: the Render service `doddy-messaging` (owner, 22 Oct:
/// "2 yes"). Messages (ADR-586), notifications, texts, daily news, calls, tasks and Connected Apps all use it, so
/// they stop saying "needs setup" once a build has this address. The server is on Render's free plan today, which
/// sleeps and takes about 20 seconds to wake; a paid instance is the owner's step (MESSAGES_STATUS).
enum ServerConfig {
    /// The server's https origin.
    static let defaultBaseURL = "https://doddy-messaging-zw1n.onrender.com"

    /// Settings → Notifications and texts lets a development build point at a different server.
    /// The address typed in Settings counts in debug builds only (ADR-175); shipped builds use
    /// `defaultBaseURL`, so the account token can't be pointed at another server.
    static func baseURL(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        // UI-test launches (`-inMemoryStore`) have no server, as before this address was built in: they never
        // reach a real one and their screens stay the same.
        if arguments.contains("-inMemoryStore") { return nil }
        #if DEBUG
        let stored = defaults.string(forKey: PreferenceKey.messagingServerURL)?.trimmingCharacters(in: .whitespaces) ?? ""
        #else
        let stored = ""
        #endif
        return validated(stored.isEmpty ? defaultBaseURL : stored)
    }

    /// Only an https origin (no path) is accepted, so tokens never travel unencrypted.
    static func validated(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host() != nil,
              url.path().isEmpty || url.path() == "/", url.query() == nil
        else { return nil }
        return url
    }

    static var pushEnvironment: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    static func client(defaults: UserDefaults = .standard) -> DoddyServerClient? {
        baseURL(defaults: defaults).map {
            DoddyServerClient(transport: ServerHTTPTransport(baseURL: $0), credentials: ServerKeychainStore())
        }
    }
}
