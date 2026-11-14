import Foundation
import Observation

// Decision 2026-11-08-required-account: the signed-in Doddy account, as the screens see it. Everything
// here is UI-free and tested on Linux; the app gives it the Keychain (`DoddyAccountSessionStore`), the
// browser sheet for Google (`WebAuthenticator`) and its HTTP transport.
//
// Rules (constitution DOD-08, "never claim what didn't happen"):
// - `isSignedIn` is true only after Supabase answered with a checked session AND the store kept it;
// - a session that can't be refreshed any more signs the person out, with a plain message;
// - a refresh runs once at a time, however many callers ask;
// - an answer that arrives after the account moved on (signed out, or another account signed in) changes
//   nothing: every sign-out, sign-in and account change starts a new `identityEpoch`, and a refresh
//   applies its result only if the epoch and the account are still the ones it started with (security
//   audit 2026-11-09, finding 2). `@MainActor` doesn't give that: state can change at every `await`.

/// Where the signed-in account is kept: the Keychain (this device only) in the app, memory in tests.
public protocol DoddyAccountSessionStore: Sendable {
    func load() -> DoddyAccountSession?
    /// False when it couldn't be kept; the account then isn't treated as signed in.
    func save(_ session: DoddyAccountSession) -> Bool
    func delete()
}

/// How each of Doddy's servers is used for this account (decision 2026-11-08-required-account).
/// While a server isn't set up for Doddy accounts yet, the iPhone keeps signing in to it as before.
public enum DoddyAccountServerUse: String, Codable, Sendable {
    /// The server doesn't take Doddy accounts yet: the iPhone's earlier sign-in is used, as before.
    case notYet
    /// The account's own token is used.
    case account

    /// What the backend's link answer means for how it is used next. Nil: ask again later.
    public static func backend(after outcome: DoddyAccountLink.Outcome) -> DoddyAccountServerUse? {
        switch outcome {
        case .linked, .nothingToLink, .conflict: .account
        case .notSetUp: .notYet
        case .retryLater: nil
        }
    }
}

@MainActor
@Observable
public final class DoddyAccountModel {
    public enum EmailStep: Equatable, Sendable {
        case enterEmail
        /// The code went to this address.
        case enterCode(email: String)
    }

    public private(set) var session: DoddyAccountSession?
    public private(set) var isWorking = false
    /// A plain sentence about the last thing that didn't work, or nil.
    public var message: String?
    public private(set) var emailStep: EmailStep = .enterEmail
    /// How many sign-ins this model has kept since launch: one more for each one, never for a refresh.
    /// The welcome ends on each one. Watching `isSignedIn` instead missed a sign-in made while a session
    /// was already kept (the welcome shown again from Settings, or after a reinstall, which keeps the
    /// Keychain): it stayed true, so the welcome never closed (TestFlight build 20, 9 Nov 2026).
    public private(set) var signInCount = 0

    /// False in a build with no Doddy accounts set up (no project in Info.plist): nobody can sign in.
    public var isConfigured: Bool { client != nil }
    public var isSignedIn: Bool { session != nil }

    /// Runs once after each new sign-in (the app brings the iPhone's earlier data in here). Not after a refresh.
    public var afterSignIn: (@MainActor (DoddyAccountSession) async -> Void)?
    /// Runs when the account is signed out, by the person or because it no longer works.
    public var afterSignOut: (@MainActor () -> Void)?

    @ObservationIgnored private let client: DoddyAccountClient?
    @ObservationIgnored private let store: any DoddyAccountSessionStore
    @ObservationIgnored private let authenticator: any WebAuthenticator
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var refreshing: Task<Result<DoddyAccountSession, DoddyAccountError>, Never>?
    @ObservationIgnored private var epoch = 0

    /// Changes whenever this iPhone's signed-in account is signed out, replaced or signed in again. Code
    /// that waits on a server for the account (linking, a token for another server) reads it before
    /// and after, and drops an answer that is for an account this iPhone no longer has.
    public var identityEpoch: Int { epoch }

    public init(
        config: DoddyAccountConfig?, transport: any HTTPTransport, store: any DoddyAccountSessionStore,
        authenticator: any WebAuthenticator, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        client = config.map { DoddyAccountClient(config: $0, transport: transport) }
        self.store = store
        self.authenticator = authenticator
        self.now = now
        session = config == nil ? nil : store.load()
    }

    // MARK: Email

    public func sendEmailCode(_ email: String) async {
        guard let client else { return fail(.notConfigured) }
        guard let address = EmailAddress.normalized(email) else { return fail(.invalidEmail) }
        await working {
            do throws(DoddyAccountError) {
                try await client.sendEmailCode(to: address)
                emailStep = .enterCode(email: address)
                message = nil
            } catch {
                fail(error)
            }
        }
    }

    /// Back to typing the address (a typo, or another address).
    public func changeEmail() {
        emailStep = .enterEmail
        message = nil
    }

    public func verifyEmailCode(_ code: String) async {
        guard let client else { return fail(.notConfigured) }
        guard case .enterCode(let email) = emailStep else { return fail(.invalidEmail) }
        guard EmailCode.normalized(code) != nil else { return fail(.invalidCode) }
        await working {
            do throws(DoddyAccountError) {
                let signedIn = try await client.verifyEmailCode(email: email, code: code, now: now())
                if await adoptNew(signedIn) { emailStep = .enterEmail }
            } catch {
                fail(error)
            }
        }
    }

    // MARK: Apple and Google

    /// After Apple's sheet: its identity token, and the nonce whose SHA-256 went to Apple.
    public func signInWithApple(identityToken: String, rawNonce: String) async {
        guard let client else { return fail(.notConfigured) }
        await working {
            do throws(DoddyAccountError) {
                _ = await adoptNew(try await client.signInWithApple(identityToken: identityToken, rawNonce: rawNonce, now: now()))
            } catch {
                fail(error)
            }
        }
    }

    public func signInWithGoogle() async {
        guard let client else { return fail(.notConfigured) }
        let pkce = PKCEPair.random()
        let callback: URL
        do throws(WebAuthenticationError) {
            callback = try await authenticator.authenticate(
                url: client.googleAuthorizeURL(pkce: pkce), callbackScheme: client.config.redirectURL.scheme ?? "doddy")
        } catch {
            // Closing the sheet is a choice, not an error.
            if error != .canceled { fail(.refused) }
            return
        }
        guard let code = client.googleCode(from: callback) else { return fail(.refused) }
        await working {
            do throws(DoddyAccountError) {
                _ = await adoptNew(try await client.exchangeGoogleCode(code, pkce: pkce, now: now()))
            } catch {
                fail(error)
            }
        }
    }

    // MARK: Using the account

    /// An access token with time left, refreshed first when needed. `.signedOut` signs the person out.
    public func accessToken() async throws(DoddyAccountError) -> String {
        guard client != nil else { throw .notConfigured }
        guard let current = session else { throw .signedOut }
        if current.isFresh(at: now()) { return current.accessToken }
        return try await refreshed(from: current).accessToken
    }

    /// The signed-in session with an access token that has time left, refreshed first when needed.
    /// Nil when signed out or when the refresh didn't work (`accessToken()` says why). Ask this before a
    /// question whose `401` would be read as an answer: an expired token is refused like a server that
    /// doesn't take accounts yet.
    public func freshSession() async -> DoddyAccountSession? {
        guard (try? await accessToken()) != nil else { return nil }
        return session
    }

    /// A server refused the access token: get a new one now, once.
    public func refreshAfterRefusal() async throws(DoddyAccountError) -> String {
        guard client != nil else { throw .notConfigured }
        guard let current = session else { throw .signedOut }
        return try await refreshed(from: current).accessToken
    }

    /// Forgets the session here at once, then ends it at Supabase (best effort). Forgetting comes first, so
    /// nothing still waiting on a server can bring the account back while the request is on its way.
    public func signOut() async {
        let leaving = session
        forget(message: nil)
        if let leaving, let client { await client.signOut(leaving) }
    }

    // MARK: Plumbing

    private func refreshed(from current: DoddyAccountSession) async throws(DoddyAccountError) -> DoddyAccountSession {
        guard let client else { throw .notConfigured }
        // A refresh that is running always belongs to the current epoch: sign-out and sign-in end it (`newEpoch`).
        let startedIn = epoch
        let task: Task<Result<DoddyAccountSession, DoddyAccountError>, Never>
        if let running = refreshing {
            task = running
        } else {
            let now = self.now
            task = Task { @MainActor [weak self] () -> Result<DoddyAccountSession, DoddyAccountError> in
                let result: Result<DoddyAccountSession, DoddyAccountError>
                do throws(DoddyAccountError) {
                    result = .success(try await client.refresh(current, now: now()))
                } catch {
                    result = .failure(error)
                }
                // Applied here, once, for every caller waiting on this refresh.
                return self?.apply(result, startedIn: startedIn, for: current.userID) ?? .failure(.signedOut)
            }
            refreshing = task
        }
        let result = await task.value
        if refreshing == task { refreshing = nil }
        // Resumed after the account moved on (a waiter that joined a refresh, or the one that started it):
        // what it was given is for an account that is gone, so it gets nothing of it.
        guard epoch == startedIn else { throw .signedOut }
        return try result.get()
    }

    /// Applies a finished refresh to the account that asked for it, and only to that account: a result that
    /// arrives after a sign-out, or after another account signed in, is dropped, whether it succeeded or
    /// failed. A late failure must not sign out the new account, a late success must not bring the old one back.
    private func apply(
        _ result: Result<DoddyAccountSession, DoddyAccountError>, startedIn: Int, for userID: String
    ) -> Result<DoddyAccountSession, DoddyAccountError> {
        guard epoch == startedIn, session?.userID == userID else { return .failure(.signedOut) }
        switch result {
        case .success(let fresh):
            guard store.save(fresh) else { return .failure(.unavailable) }
            session = fresh
            return .success(fresh)
        case .failure(.signedOut):
            forget(message: DoddyAccountError.signedOut.userMessage)
            return .failure(.signedOut)
        case .failure:
            return result
        }
    }

    /// A new epoch: anything started in an earlier one is over. A refresh still on its way is cancelled as a
    /// courtesy; what keeps it from changing anything is the epoch check, not the cancellation.
    private func newEpoch() {
        epoch += 1
        refreshing?.cancel()
        refreshing = nil
    }

    /// A new sign-in counts only once it is kept (DOD-08).
    private func adoptNew(_ signedIn: DoddyAccountSession) async -> Bool {
        guard store.save(signedIn) else {
            message = "This iPhone couldn't keep your sign-in, so you aren't signed in. Try again."
            return false
        }
        let previous = session
        newEpoch()
        session = signedIn
        message = nil
        signInCount += 1
        // Another account took this iPhone over without a sign-out: the earlier account's credentials on
        // Doddy's servers go the way they do at a sign-out, before anything is signed in for the new one.
        if let previous, previous.userID != signedIn.userID { afterSignOut?() }
        await afterSignIn?(signedIn)
        return true
    }

    private func forget(message: String?) {
        newEpoch()
        store.delete()
        let wasSignedIn = session != nil
        session = nil
        emailStep = .enterEmail
        self.message = message
        if wasSignedIn { afterSignOut?() }
    }

    private func fail(_ error: DoddyAccountError) {
        message = error.userMessage
    }

    private func working(_ body: () async -> Void) async {
        isWorking = true
        defer { isWorking = false }
        await body()
    }
}
