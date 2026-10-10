import DoddyCore
import Foundation

/// Where the Doddy messaging server (`server/messaging`) lives. None is deployed yet (S1 status),
/// so the default is empty and its features report "needs setup" until an address is entered.
enum ServerConfig {
    /// Fill in once `render.yaml` is applied, e.g. `https://doddy-messaging.onrender.com`.
    static let defaultBaseURL = ""

    /// Settings → Notifications and texts lets a development build point at a different server.
    static func baseURL(defaults: UserDefaults = .standard) -> URL? {
        let stored = defaults.string(forKey: PreferenceKey.messagingServerURL)?.trimmingCharacters(in: .whitespaces) ?? ""
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
