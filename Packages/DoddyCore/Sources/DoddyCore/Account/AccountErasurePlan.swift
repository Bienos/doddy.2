import Foundation

// Deleting a Doddy account reports success only when each server confirms (decision
// 2026-11-12-account-deletion-truth, DOD-08). The steps that decide what counts as confirmed are here, UI-free and
// tested on Linux; the app (`DoddyAccountServers.deleteAccount`, `ServerAccountErasure`) does the requests.

public enum AccountErasurePlan {
    // MARK: The messaging server

    /// One `DELETE /v1/account` on the messaging server.
    public enum Attempt: Equatable, Sendable {
        /// 204: the server deleted the account the token belongs to.
        case deleted
        /// This iPhone keeps no token for the messaging server (after a reinstall, say). Not "nothing there":
        /// the Doddy account can still have its account on the server.
        case noToken
        /// 401: the token isn't valid any more. Not "deleted" either.
        case refused
        /// Offline, timed out, or any other answer.
        case failed
    }

    /// The Doddy account's own token for the messaging server, asked for with the account
    /// (`POST /v1/accounts/sign-in`, as after a sign-in). For an account the server doesn't know yet it makes an
    /// empty one, which the delete that follows removes.
    public enum Mint: Equatable, Sendable {
        case token(String)
        /// 503 `not_configured`: the server takes no Doddy accounts, so it holds none for this one.
        case serverTakesNoAccounts
        case failed

        public init(_ signIn: DoddyAccountLink.MessagingSignIn) {
            switch signIn {
            case .signedIn(_, let token): self = .token(token)
            case .notSetUp: self = .serverTakesNoAccounts
            case .conflict, .accountRefused, .retryLater: self = .failed
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// The server confirmed the delete (204).
        case deleted
        /// The server said it takes no Doddy accounts: nothing of this account is there.
        case nothingForAccount
        /// Not confirmed. Nothing else is deleted and the person stays signed in, so it can be tried again.
        case notDeleted

        public var isConfirmed: Bool { self != .notDeleted }
    }

    /// The messaging step: the token this iPhone keeps first; with none, or a refused one, the account's own token
    /// is minted and the delete tried once more. Only a 204, or the server saying it takes no accounts, counts.
    public static func run(
        deleteWithStoredToken: @Sendable () async -> Attempt,
        mintAccountToken: @Sendable () async -> Mint,
        deleteWithToken: @Sendable (String) async -> Attempt
    ) async -> Outcome {
        switch await deleteWithStoredToken() {
        case .deleted: return .deleted
        case .failed: return .notDeleted
        case .noToken, .refused: break
        }
        switch await mintAccountToken() {
        case .token(let token): return await deleteWithToken(token) == .deleted ? .deleted : .notDeleted
        case .serverTakesNoAccounts: return .nothingForAccount
        case .failed: return .notDeleted
        }
    }

    // MARK: Doddy's backend (ADR-674)

    /// Before the backend is asked to erase (`ServerAccountErasure`), after the app tried to make or renew a session.
    public enum BackendStart: Equatable, Sendable {
        /// This iPhone has a session with the server: ask it to erase.
        case erase
        /// Provably nothing there: this iPhone never made a device ID and doesn't use a Doddy account with the server.
        case nothingThere
        /// Something may be there (a device ID, or the account) but there is no session to reach it: not deleted.
        case failed
    }

    public static func backendStart(hasSession: Bool, hasDeviceID: Bool, usesAccount: Bool) -> BackendStart {
        if hasSession { return .erase }
        return hasDeviceID || usesAccount ? .failed : .nothingThere
    }

    /// What the erase answered, once it was asked with a session. A missing session now ("not configured") means
    /// the session went away, not that nothing was there.
    public static func backendOutcome(_ result: Result<AccountErasureReceipt, AccountErasureError>) -> AccountErasureOutcome {
        if result == .failure(.notConfigured) { return .failed }
        return AccountErasureOutcome.from(result)
    }
}
