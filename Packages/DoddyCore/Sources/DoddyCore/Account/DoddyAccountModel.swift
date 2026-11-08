import Foundation
import Observation

// Decision 2026-11-08-required-account: the signed-in Doddy account, as the screens see it. Everything
// here is UI-free and tested on Linux; the app gives it the Keychain (`DoddyAccountSessionStore`), the
// browser sheet for Google (`WebAuthenticator`) and its HTTP transport.
//
// Rules (constitution DOD-08, "never claim what didn't happen"):
// - `isSignedIn` is true only after Supabase answered with a checked session AND the store kept it;
// - a session that can't be refreshed any more signs the person out, with a plain message;
// - a refresh runs once at a time, however many callers ask.

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

    /// A server refused the access token: get a new one now, once.
    public func refreshAfterRefusal() async throws(DoddyAccountError) -> String {
        guard client != nil else { throw .notConfigured }
        guard let current = session else { throw .signedOut }
        return try await refreshed(from: current).accessToken
    }

    /// Ends the session at Supabase (best effort) and forgets it here.
    public func signOut() async {
        if let session, let client { await client.signOut(session) }
        forget(message: nil)
    }

    // MARK: Plumbing

    private func refreshed(from current: DoddyAccountSession) async throws(DoddyAccountError) -> DoddyAccountSession {
        if let refreshing { return try await refreshing.value.get() }
        guard let client else { throw .notConfigured }
        let now = self.now
        let task = Task { @MainActor () -> Result<DoddyAccountSession, DoddyAccountError> in
            do throws(DoddyAccountError) {
                return .success(try await client.refresh(current, now: now()))
            } catch {
                return .failure(error)
            }
        }
        refreshing = task
        let result = await task.value
        refreshing = nil
        switch result {
        case .success(let fresh):
            guard store.save(fresh) else { throw .unavailable }
            session = fresh
            return fresh
        case .failure(.signedOut):
            forget(message: DoddyAccountError.signedOut.userMessage)
            throw .signedOut
        case .failure(let error):
            throw error
        }
    }

    /// A new sign-in counts only once it is kept (DOD-08).
    private func adoptNew(_ signedIn: DoddyAccountSession) async -> Bool {
        guard store.save(signedIn) else {
            message = "This iPhone couldn't keep your sign-in, so you aren't signed in. Try again."
            return false
        }
        session = signedIn
        message = nil
        await afterSignIn?(signedIn)
        return true
    }

    private func forget(message: String?) {
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
