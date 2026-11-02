import DoddyCore
import Foundation

/// ADR-674: deleting the account on Doddy's server (online accounts, kept notes and conversations, the
/// Messages copy, Logbook, documents) before the voice account goes. It says only what the server's
/// receipt says; the rules are `AccountErasureOutcome` in DoddyCore, tested on Linux.
enum ServerAccountErasure {
    static func run() async -> AccountErasureOutcome {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return .nothingThere }
        var result = await erase(url)
        // An expired session (tokens last 30 days): a fresh one, then once more. Deleting twice is harmless.
        if result == .failure(.unauthenticated), await DeviceSession.renew(server: url) { result = await erase(url) }
        return AccountErasureOutcome.from(result)
    }

    private static func erase(_ url: URL) async -> Result<AccountErasureReceipt, AccountErasureError> {
        guard let client = BackendAccountClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared) else {
            return .failure(.notConfigured)
        }
        do { return .success(try await client.eraseAccount()) } catch { return .failure(error) }
    }

    /// One line for Settings; nil when there was nothing on the server.
    static func message(for outcome: AccountErasureOutcome) -> String? {
        switch outcome {
        case .nothingThere:
            return nil
        case .complete:
            return NSLocalizedString("What Doddy's server kept for you was deleted, and your online accounts were disconnected.", comment: "ADR-674")
        case .onlineAccountsPending(let kinds):
            return String(format: NSLocalizedString("What Doddy's server kept for you was deleted. Removing Doddy's access at %@ isn't confirmed yet; the server keeps trying. You can also remove Doddy in that account's settings.", comment: "ADR-674: online account kinds"), kinds.joined(separator: ", "))
        case .notAvailable:
            return NSLocalizedString("Doddy's server can't delete accounts yet, so what it keeps for you is still there.", comment: "ADR-674")
        case .failed:
            return NSLocalizedString("Couldn't confirm that what Doddy's server keeps for you was deleted, so your voice account was kept. Check your connection and try again.", comment: "ADR-674")
        }
    }
}
