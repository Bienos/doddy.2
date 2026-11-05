import DoddyCore
import Foundation

/// Builds the payments client for the server the app talks to (`DeviceSession.serverURL()`: the one built
/// into the app, or the development field in a Debug build only, ADR-720) with the session token in the
/// Keychain. Returns nil when either is missing, or the token was issued by another server, so callers say
/// "not set up" instead of pretending. It never signs the phone in by itself: a payment screen that finds
/// no session says so (ADR-731).
enum PaymentsClientFactory {
    static func make() -> (any PaymentsClient)? {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendPaymentsClient(
            baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}
