import Foundation

/// ADR-674: deleting the account on Doddy's server (`DELETE /v1/account`, `backend/src/account.ts`).
/// Everything the server keeps for this person goes in one step (kept notes and conversations, the
/// Messages copy, Logbook, documents, receipts, browser sign-ins), and each online account they
/// connected is removed at its provider. The reply is a receipt; the app says "deleted" only from it.

/// What the server says it did.
public struct AccountErasureReceipt: Equatable, Sendable, Decodable {
    public struct OnlineAccounts: Equatable, Sendable, Decodable {
        /// Kinds removed at their provider (`gmail`, `google_calendar`, `notion`, …).
        public let removed: [String]
        /// Kinds whose removal failed or isn't confirmed; the server keeps trying.
        public let pending: [String]
    }

    /// True only when nothing of the person was left and every online account was removed.
    public let complete: Bool
    /// Rows of the person the server still found after deleting (0 unless something went wrong).
    public let remaining: Int
    public let onlineAccounts: OnlineAccounts
    /// Rows deleted, per table.
    public let deleted: [String: Int]
    public let erasedAt: String
}

public enum AccountErasureError: Error, Equatable, Sendable {
    /// No server in this build, or this iPhone never signed in to it: nothing there to delete.
    case notConfigured
    case unauthenticated
    /// 404: a server from before ADR-674, which can't delete an account.
    case notAvailable
    /// No answer. Deleting twice is harmless, so trying again is safe.
    case transport
    /// The reply didn't match the receipt; nothing is claimed.
    case unreadable
    case server(message: String)
}

/// What the app tells the person, and whether it goes on to delete the voice account.
public enum AccountErasureOutcome: Equatable, Sendable {
    /// Nothing on Doddy's server to delete (no server, or never signed in to it).
    case nothingThere
    case complete
    /// Every row is gone; removing access at these online accounts isn't confirmed yet.
    case onlineAccountsPending([String])
    /// The server can't delete accounts yet: what it keeps is still there.
    case notAvailable
    /// Not deleted, or not known to be. Nothing else is deleted, so it can be tried again.
    case failed

    public static func from(_ result: Result<AccountErasureReceipt, AccountErasureError>) -> AccountErasureOutcome {
        switch result {
        case .success(let receipt):
            // Rows still found after the delete: the server didn't do what it said; never "deleted".
            if receipt.remaining > 0 { return .failed }
            if !receipt.onlineAccounts.pending.isEmpty { return .onlineAccountsPending(receipt.onlineAccounts.pending) }
            return receipt.complete ? .complete : .failed
        case .failure(.notConfigured): return .nothingThere
        case .failure(.notAvailable): return .notAvailable
        case .failure: return .failed
        }
    }

    /// The voice account is deleted after this only when the server's part didn't fail, so a failed
    /// deletion can be tried again from the same button (it goes once the voice account is gone).
    public var mayDeleteVoiceAccount: Bool { self != .failed }
}

public struct BackendAccountClient: Sendable {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    /// `baseURL` must be https, or http on a loopback host for local development.
    public init?(baseURL: URL, sessionToken: @escaping @Sendable () -> String?, transport: any HTTPTransport) {
        guard BackendConnectedAppsClient.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.transport = transport
    }

    /// Same, with a token that is sent only to the server it was issued for.
    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        self.init(baseURL: baseURL, sessionToken: { boundToken()?.token(for: baseURL) }, transport: transport)
    }

    public func eraseAccount() async throws(AccountErasureError) -> AccountErasureReceipt {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        let request = HTTPRequest(
            method: "DELETE", url: baseURL.appendingPathComponent("v1/account"),
            headers: ["authorization": "Bearer \(token)", "accept": "application/json"], body: nil)
        let status: Int
        let payload: Data
        do {
            (status, payload) = try await transport.send(request)
        } catch {
            throw .transport
        }
        return try Self.decode(status: status, data: payload)
    }

    static func decode(status: Int, data: Data) throws(AccountErasureError) -> AccountErasureReceipt {
        if status == 200 {
            do { return try JSONDecoder().decode(AccountErasureReceipt.self, from: data) } catch { throw .unreadable }
        }
        if status == 401 { throw .unauthenticated }
        if status == 404 { throw .notAvailable }
        guard let body = try? JSONDecoder().decode(OnlineErrorBody.self, from: data) else { throw .unreadable }
        throw .server(message: body.error.message)
    }
}
