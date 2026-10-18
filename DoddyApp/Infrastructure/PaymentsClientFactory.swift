import DoddyCore
import Foundation

/// Builds the purchases client (ADR-530) from the same server settings Connected Apps and online
/// accounts use (server address in preferences, session token in the Keychain). Nil when either is
/// missing or the token belongs to another server, so the agent hears "not set up" instead of a guess.
enum PaymentsClientFactory {
    static func make() -> (any PaymentsClient)? {
        let address = UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let url = URL(string: address), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendPaymentsClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}
