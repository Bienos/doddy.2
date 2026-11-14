import Foundation
import XCTest
@testable import DoddyCore

/// Security audit 2026-11-09, finding 2: an answer that arrives after the account moved on must change
/// nothing. `@MainActor` serialises the model's code, but state can change at every `await`, so each test
/// here holds one request open (a gate the test opens), changes the account meanwhile, then lets it finish:
/// the order of events is the test's, not the scheduler's.

private final class SessionStore: DoddyAccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: DoddyAccountSession?
    private var writes: [String] = []
    init(_ session: DoddyAccountSession? = nil) { kept = session }
    var saved: DoddyAccountSession? { lock.withLock { kept } }
    var savedAccessTokens: [String] { lock.withLock { writes } }
    func load() -> DoddyAccountSession? { lock.withLock { kept } }
    func save(_ session: DoddyAccountSession) -> Bool { lock.withLock { kept = session; writes.append(session.accessToken); return true } }
    func delete() { lock.withLock { kept = nil } }
}

/// Answers by `replies`; a request whose key is `hold`-ing waits until `open(key)`. Keys: `refresh` (a token
/// refresh), `logout`, or the last path part (`token` for a sign-in).
private final class GatedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    var replies: [String: (Int, Data)] = [:]
    private var holding: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var recorded: [String] = []

    func hold(_ key: String) { lock.withLock { _ = holding.insert(key) } }
    func open(_ key: String) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding.remove(key)
            return waiting.removeValue(forKey: key) ?? []
        }
        continuations.forEach { $0.resume() }
    }
    /// Until a request is waiting at this gate (a condition, not a delay: the loop ends the moment it is true).
    func requestArrived(at key: String, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<4_000 {
            if lock.withLock({ !(waiting[key] ?? []).isEmpty }) { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("no request reached the \(key) gate", file: file, line: line)
    }
    func count(_ key: String) -> Int { lock.withLock { recorded.filter { $0 == key }.count } }

    private func key(for request: HTTPRequest) -> String {
        let last = request.url.path.components(separatedBy: "/auth/v1/").last ?? ""
        return last == "token" && (request.url.query ?? "").contains("grant_type=refresh_token") ? "refresh" : last
    }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let key = key(for: request)
        lock.withLock { recorded.append(key) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passThrough = lock.withLock { () -> Bool in
                guard holding.contains(key) else { return true }
                waiting[key, default: []].append(continuation)
                return false
            }
            if passThrough { continuation.resume() }
        }
        return lock.withLock { replies[key] } ?? (500, Data())
    }
}

private struct NoBrowser: WebAuthenticator {
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL { throw .canceled }
}

/// A free function, not a method: `async let` can't send the (non-Sendable) test case to another task.
private func token(_ account: DoddyAccountModel) async -> Result<String, DoddyAccountError> {
    do throws(DoddyAccountError) { return .success(try await account.accessToken()) } catch { return .failure(error) }
}

private let now0 = Date(timeIntervalSince1970: 1_794_000_000)
private let ana = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab"
private let ben = "6c1d9a8f-3b52-4d4e-8f70-123456789abc"

@MainActor
final class DoddyAccountRaceTests: XCTestCase {
    private let config = DoddyAccountConfig(
        projectURL: URL(string: "https://abcdefghijklmnopqrst.supabase.co"), publishableKey: "pk", redirectURL: URL(string: "doddy://auth-callback"))

    /// A session whose access token has run out, so any use of it refreshes first.
    private func stale(_ user: String = ana, access: String = "a0", refresh: String = "r0") -> DoddyAccountSession {
        DoddyAccountSession(accessToken: access, refreshToken: refresh, expiresAt: now0.addingTimeInterval(-60), userID: user, email: nil, method: .apple)
    }

    private func reply(user: String, access: String, refresh: String) -> (Int, Data) {
        let body: [String: Any] = [
            "access_token": access, "refresh_token": refresh, "expires_at": 1_794_003_600,
            "user": ["id": user, "email": "x@example.com", "app_metadata": ["provider": "apple"]],
        ]
        return (200, try! JSONSerialization.data(withJSONObject: body))
    }
    private let deadRefresh = (400, Data(#"{"error_code":"refresh_token_not_found"}"#.utf8))

    private func model(_ transport: GatedTransport, _ store: SessionStore) -> DoddyAccountModel {
        DoddyAccountModel(config: config, transport: transport, store: store, authenticator: NoBrowser(), now: { now0 })
    }

    // MARK: 1. Signing out while a refresh is pending

    func testARefreshThatFinishesAfterSignOutLeavesThePersonSignedOut() async {
        let transport = GatedTransport()
        transport.replies = ["refresh": reply(user: ana, access: "a1", refresh: "r1"), "logout": (204, Data())]
        transport.hold("refresh")
        let store = SessionStore(stale())
        let account = model(transport, store)
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }

        async let late = token(account)
        await transport.requestArrived(at: "refresh")
        await account.signOut()
        XCTAssertFalse(account.isSignedIn)
        transport.open("refresh")

        let outcome = await late
        XCTAssertEqual(outcome, .failure(.signedOut), "the caller is told it is signed out, and is given no token")
        XCTAssertFalse(account.isSignedIn, "the late success did not bring the account back")
        XCTAssertNil(account.session)
        XCTAssertNil(store.saved, "nothing was written to the Keychain")
        XCTAssertEqual(store.savedAccessTokens, [], "not even briefly")
        XCTAssertEqual(signedOut, 1, "the sign-out hook ran once, not again for the late answer")
    }

    func testSigningOutIsImmediateAndDoesNotWaitForTheServer() async {
        let transport = GatedTransport()
        transport.replies = ["logout": (204, Data())]
        transport.hold("logout")
        let store = SessionStore(stale())
        let account = model(transport, store)
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }

        let leaving = Task { await account.signOut() }
        await transport.requestArrived(at: "logout")
        XCTAssertFalse(account.isSignedIn, "signed out here while the request to Supabase is still on its way")
        XCTAssertNil(store.saved)
        XCTAssertEqual(signedOut, 1)
        transport.open("logout")
        await leaving.value
        XCTAssertEqual(transport.count("logout"), 1, "Supabase is still told")
    }

    // MARK: 2. Switching from A to B while A's refresh is pending

    func testARefreshForTheOldAccountCannotReplaceTheNewOne() async {
        let transport = GatedTransport()
        transport.replies = [
            "refresh": reply(user: ana, access: "ana-fresh", refresh: "ana-r"),
            "token": reply(user: ben, access: "ben-1", refresh: "ben-r"),
        ]
        transport.hold("refresh")
        let store = SessionStore(stale(ana))
        let account = model(transport, store)
        var hooks: [String] = []
        account.afterSignOut = { hooks.append("out") }
        account.afterSignIn = { hooks.append("in:\($0.userID)") }

        async let late = token(account)
        await transport.requestArrived(at: "refresh")
        await account.signInWithApple(identityToken: "apple.jwt", rawNonce: "n")   // Ben takes the iPhone over
        XCTAssertEqual(account.session?.userID, ben)
        transport.open("refresh")

        let outcome = await late
        XCTAssertEqual(outcome, .failure(.signedOut), "Ana's caller gets no token for an account that is gone")
        XCTAssertEqual(account.session?.userID, ben)
        XCTAssertEqual(account.session?.accessToken, "ben-1", "Ana's late refresh did not replace Ben")
        XCTAssertEqual(store.saved?.userID, ben)
        XCTAssertEqual(store.savedAccessTokens, ["ben-1"], "Ana's tokens were never written")
        XCTAssertEqual(hooks, ["out", "in:\(ben)"], "Ana's credentials on the servers are dropped first, then Ben's sign-in runs")
    }

    func testAFailureForTheOldAccountCannotSignTheNewOneOut() async {
        let transport = GatedTransport()
        transport.replies = ["refresh": deadRefresh, "token": reply(user: ben, access: "ben-1", refresh: "ben-r")]
        transport.hold("refresh")
        let store = SessionStore(stale(ana))
        let account = model(transport, store)
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }

        async let late = token(account)
        await transport.requestArrived(at: "refresh")
        await account.signInWithApple(identityToken: "apple.jwt", rawNonce: "n")
        let hooksAfterSwitch = signedOut
        transport.open("refresh")

        let outcome = await late
        XCTAssertEqual(outcome, .failure(.signedOut))
        XCTAssertTrue(account.isSignedIn, "Ana's dead refresh token says nothing about Ben")
        XCTAssertEqual(account.session?.userID, ben)
        XCTAssertEqual(store.saved?.accessToken, "ben-1")
        XCTAssertNil(account.message, "no \"you were signed out\" for the person who just signed in")
        XCTAssertEqual(signedOut, hooksAfterSwitch, "the late failure ran no sign-out of its own")
    }

    func testAFailureThatFinishesAfterSignOutSaysNothingAndSignsOutNobodyTwice() async {
        let transport = GatedTransport()
        transport.replies = ["refresh": deadRefresh, "logout": (204, Data())]
        transport.hold("refresh")
        let account = model(transport, SessionStore(stale()))
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }
        async let late = token(account)
        await transport.requestArrived(at: "refresh")
        await account.signOut()
        transport.open("refresh")
        let outcome = await late
        XCTAssertEqual(outcome, .failure(.signedOut))
        XCTAssertEqual(signedOut, 1)
        XCTAssertNil(account.message, "a person who chose to sign out isn't told they were signed out")
    }

    // MARK: 3. Callers sharing one refresh

    func testEveryCallerSharingARefreshIsRefusedWhenTheAccountChangesBeforeItEnds() async {
        let transport = GatedTransport()
        transport.replies = ["refresh": reply(user: ana, access: "ana-fresh", refresh: "ana-r"), "logout": (204, Data())]
        transport.hold("refresh")
        let account = model(transport, SessionStore(stale()))

        // Both callers start before the test waits, so the second one joins the refresh the first started.
        async let first = token(account)
        async let second = token(account)
        await transport.requestArrived(at: "refresh")
        await account.signOut()
        transport.open("refresh")

        let outcomes = await [first, second]
        XCTAssertEqual(outcomes, [.failure(.signedOut), .failure(.signedOut)], "neither caller is handed the old account's token")
        XCTAssertEqual(transport.count("refresh"), 1, "still one refresh, not one per caller")
    }

    // MARK: Still working: no change in the ordinary cases

    func testARefreshWithNothingInTheWayStillWorksAndKeepsTheNewSession() async {
        let transport = GatedTransport()
        transport.replies = ["refresh": reply(user: ana, access: "a1", refresh: "r1")]
        let store = SessionStore(stale())
        let account = model(transport, store)
        let epoch = account.identityEpoch
        let outcome = await token(account)
        XCTAssertEqual(outcome, .success("a1"))
        XCTAssertEqual(account.session?.accessToken, "a1")
        XCTAssertEqual(store.saved?.refreshToken, "r1")
        XCTAssertEqual(account.identityEpoch, epoch, "a refresh is not a change of account")
    }

    func testTheSameAccountSigningInAgainRunsNoSignOutHookButStartsANewEpoch() async {
        let transport = GatedTransport()
        transport.replies = ["token": reply(user: ana, access: "a2", refresh: "r2")]
        let account = model(transport, SessionStore(stale(ana)))
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }
        let epoch = account.identityEpoch
        await account.signInWithApple(identityToken: "apple.jwt", rawNonce: "n")
        XCTAssertEqual(signedOut, 0, "the same person: nothing of theirs is dropped")
        XCTAssertNotEqual(account.identityEpoch, epoch, "but whatever was started for the earlier session is over")
    }

    func testEveryChangeOfAccountStartsANewEpoch() async {
        let transport = GatedTransport()
        transport.replies = ["token": reply(user: ben, access: "b1", refresh: "br"), "logout": (204, Data())]
        let account = model(transport, SessionStore(stale(ana)))
        var seen = [account.identityEpoch]
        await account.signInWithApple(identityToken: "apple.jwt", rawNonce: "n")
        seen.append(account.identityEpoch)
        await account.signOut()
        seen.append(account.identityEpoch)
        XCTAssertEqual(Set(seen).count, 3, "sign-in over another account, then sign-out: three different epochs")
    }
}
