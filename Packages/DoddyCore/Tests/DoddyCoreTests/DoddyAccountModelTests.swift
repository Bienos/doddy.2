import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-08-required-account: the signed-in account as the screens see it.

private final class MemoryStore: DoddyAccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: DoddyAccountSession?
    var refuses = false
    var deletes = 0
    init(_ session: DoddyAccountSession? = nil) { kept = session }
    var saved: DoddyAccountSession? { lock.withLock { kept } }
    func load() -> DoddyAccountSession? { lock.withLock { kept } }
    func save(_ session: DoddyAccountSession) -> Bool {
        lock.withLock {
            if refuses { return false }
            kept = session
            return true
        }
    }
    func delete() { lock.withLock { kept = nil; deletes += 1 } }
}

private final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    var replies: [String: (Int, Data)] = [:]
    /// Held before answering, so two callers can arrive while one request is in flight.
    var delay: Duration = .zero
    var requests: [HTTPRequest] { lock.withLock { recorded } }
    func count(_ path: String) -> Int { requests.filter { $0.url.path.hasSuffix(path) }.count }
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if delay != .zero { try await Task.sleep(for: delay) }
        let key = request.url.path.components(separatedBy: "/auth/v1/").last ?? ""
        return replies[key] ?? (500, Data())
    }
}

private struct Browser: WebAuthenticator {
    let result: Result<URL, WebAuthenticationError>
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL { try result.get() }
}

/// The tests' fixed "now" (a plain constant, so a @Sendable clock closure can read it).
private let testClock = Date(timeIntervalSince1970: 1_794_000_000)

@MainActor
final class DoddyAccountModelTests: XCTestCase {
    private let config = DoddyAccountConfig(
        projectURL: URL(string: "https://abcdefghijklmnopqrst.supabase.co"), publishableKey: "pk",
        redirectURL: URL(string: "doddy://auth-callback"))
    private let user = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab"

    private func reply(access: String = "access-1", refresh: String = "refresh-1", provider: String = "email") -> (Int, Data) {
        let body: [String: Any] = [
            "access_token": access, "refresh_token": refresh, "expires_at": 1_794_003_600,
            "user": ["id": user, "email": "ana@example.com", "app_metadata": ["provider": provider]],
        ]
        return (200, try! JSONSerialization.data(withJSONObject: body))
    }

    private func model(
        _ transport: RoutedTransport, store: MemoryStore = MemoryStore(), browser: Browser = Browser(result: .failure(.canceled)),
        configured: Bool = true
    ) -> DoddyAccountModel {
        DoddyAccountModel(config: configured ? config : nil, transport: transport, store: store, authenticator: browser, now: { testClock })
    }

    func testABuildWithoutAccountsSetUpSaysSoAndSignsNobodyIn() async {
        let transport = RoutedTransport()
        let account = model(transport, store: MemoryStore(DoddyAccountSession(accessToken: "a", refreshToken: "r", expiresAt: testClock, userID: user, email: nil, method: .email)), configured: false)
        XCTAssertFalse(account.isConfigured)
        XCTAssertFalse(account.isSignedIn, "a stored session is not used without a project")
        await account.sendEmailCode("ana@example.com")
        XCTAssertEqual(account.message, DoddyAccountError.notConfigured.userMessage)
        XCTAssertTrue(transport.requests.isEmpty)
        do { _ = try await account.accessToken(); XCTFail() } catch { XCTAssertEqual(error, .notConfigured) }
    }

    func testTheEmailCodeSignsInOnlyOnceTheSessionIsKept() async {
        let transport = RoutedTransport()
        transport.replies = ["otp": (200, Data("{}".utf8)), "verify": reply()]
        let store = MemoryStore()
        let account = model(transport, store: store)
        var signedIn: [DoddyAccountSession] = []
        account.afterSignIn = { signedIn.append($0) }

        await account.sendEmailCode("not an address")
        XCTAssertEqual(account.message, DoddyAccountError.invalidEmail.userMessage)
        XCTAssertEqual(account.emailStep, .enterEmail)

        await account.sendEmailCode(" Ana@Example.com ")
        XCTAssertEqual(account.emailStep, .enterCode(email: "ana@example.com"))
        XCTAssertNil(account.message)
        XCTAssertFalse(account.isSignedIn)

        await account.verifyEmailCode("123 456")
        XCTAssertTrue(account.isSignedIn)
        XCTAssertEqual(store.saved?.accessToken, "access-1")
        XCTAssertEqual(signedIn.map(\.userID), [user])
        XCTAssertEqual(account.emailStep, .enterEmail)
        XCTAssertFalse(account.isWorking)
    }

    func testASessionTheIPhoneCouldNotKeepIsNotASignIn() async {
        let transport = RoutedTransport()
        transport.replies = ["otp": (200, Data("{}".utf8)), "verify": reply()]
        let store = MemoryStore()
        store.refuses = true
        let account = model(transport, store: store)
        var calls = 0
        account.afterSignIn = { _ in calls += 1 }
        await account.sendEmailCode("ana@example.com")
        await account.verifyEmailCode("123456")
        XCTAssertFalse(account.isSignedIn)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(account.message, "This iPhone couldn't keep your sign-in, so you aren't signed in. Try again.")
    }

    func testAWrongCodeStaysOnTheCodeStepAndTheAddressCanBeChanged() async {
        let transport = RoutedTransport()
        transport.replies = ["otp": (200, Data("{}".utf8)), "verify": (403, Data(#"{"error_code":"otp_expired"}"#.utf8))]
        let account = model(transport)
        await account.sendEmailCode("ana@example.com")
        await account.verifyEmailCode("123456")
        XCTAssertFalse(account.isSignedIn)
        XCTAssertEqual(account.message, DoddyAccountError.invalidCode.userMessage)
        XCTAssertEqual(account.emailStep, .enterCode(email: "ana@example.com"))
        account.changeEmail()
        XCTAssertEqual(account.emailStep, .enterEmail)
        XCTAssertNil(account.message)
    }

    func testGoogleClosedIsSilentAndItsOwnReturnSignsIn() async {
        let closed = model(RoutedTransport(), browser: Browser(result: .failure(.canceled)))
        await closed.signInWithGoogle()
        XCTAssertNil(closed.message)
        XCTAssertFalse(closed.isSignedIn)

        let stranger = model(RoutedTransport(), browser: Browser(result: .success(URL(string: "doddy://auth-callback?error=access_denied")!)))
        await stranger.signInWithGoogle()
        XCTAssertEqual(stranger.message, DoddyAccountError.refused.userMessage)

        let transport = RoutedTransport()
        transport.replies = ["token": reply(provider: "google")]
        let account = model(transport, browser: Browser(result: .success(URL(string: "doddy://auth-callback?code=abc")!)))
        await account.signInWithGoogle()
        XCTAssertTrue(account.isSignedIn)
        XCTAssertEqual(account.session?.method, .google)
        XCTAssertEqual(transport.requests.first?.url.query, "grant_type=pkce")
    }

    func testAppleSignsIn() async {
        let transport = RoutedTransport()
        transport.replies = ["token": reply(provider: "apple")]
        let account = model(transport)
        await account.signInWithApple(identityToken: "apple.jwt", rawNonce: "nonce")
        XCTAssertEqual(account.session?.method, .apple)
    }

    func testAFreshTokenIsUsedAsItIsAndAStaleOneIsRefreshedOnceForEveryCaller() async throws {
        let fresh = DoddyAccountSession(accessToken: "a0", refreshToken: "r0", expiresAt: testClock.addingTimeInterval(600), userID: user, email: nil, method: .apple)
        let transport = RoutedTransport()
        let account = model(transport, store: MemoryStore(fresh))
        XCTAssertTrue(account.isSignedIn, "restored from the store")
        let token = try await account.accessToken()
        XCTAssertEqual(token, "a0")
        XCTAssertTrue(transport.requests.isEmpty)

        let stale = DoddyAccountSession(accessToken: "a0", refreshToken: "r0", expiresAt: testClock.addingTimeInterval(30), userID: user, email: nil, method: .apple)
        let refreshing = RoutedTransport()
        refreshing.replies = ["token": reply(access: "a1", refresh: "r1", provider: "apple")]
        refreshing.delay = .milliseconds(50)
        let store = MemoryStore(stale)
        let busy = model(refreshing, store: store)
        async let first = busy.accessToken()
        async let second = busy.accessToken()
        let tokens = try await [first, second]
        XCTAssertEqual(tokens, ["a1", "a1"])
        XCTAssertEqual(refreshing.count("/token"), 1, "one refresh for both callers")
        XCTAssertEqual(store.saved?.refreshToken, "r1")
    }

    func testARefreshThatNoLongerWorksSignsThePersonOut() async {
        let stale = DoddyAccountSession(accessToken: "a0", refreshToken: "r0", expiresAt: testClock, userID: user, email: nil, method: .email)
        let transport = RoutedTransport()
        transport.replies = ["token": (400, Data(#"{"error_code":"refresh_token_not_found"}"#.utf8))]
        let store = MemoryStore(stale)
        let account = model(transport, store: store)
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }
        do { _ = try await account.accessToken(); XCTFail("a dead session passed") } catch { XCTAssertEqual(error, .signedOut) }
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(store.saved)
        XCTAssertEqual(signedOut, 1)
        XCTAssertEqual(account.message, DoddyAccountError.signedOut.userMessage)
    }

    func testOfflineDuringARefreshKeepsTheSession() async {
        let stale = DoddyAccountSession(accessToken: "a0", refreshToken: "r0", expiresAt: testClock, userID: user, email: nil, method: .email)
        let transport = RoutedTransport()
        transport.replies = ["token": (503, Data())]
        let account = model(transport, store: MemoryStore(stale))
        do { _ = try await account.accessToken(); XCTFail() } catch { XCTAssertEqual(error, .unavailable) }
        XCTAssertTrue(account.isSignedIn, "a server error is not a sign-out")
    }

    func testSigningOutEndsTheSessionAndForgetsIt() async {
        let session = DoddyAccountSession(accessToken: "a0", refreshToken: "r0", expiresAt: testClock.addingTimeInterval(600), userID: user, email: nil, method: .google)
        let transport = RoutedTransport()
        transport.replies = ["logout": (204, Data())]
        let store = MemoryStore(session)
        let account = model(transport, store: store)
        var signedOut = 0
        account.afterSignOut = { signedOut += 1 }
        await account.signOut()
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(store.saved)
        XCTAssertEqual(signedOut, 1)
        XCTAssertEqual(transport.count("/logout"), 1)
        XCTAssertNil(account.message)
    }

    func testHowEachBackendAnswerDecidesHowTheBackendIsUsed() {
        XCTAssertEqual(DoddyAccountServerUse.backend(after: .linked), .account)
        XCTAssertEqual(DoddyAccountServerUse.backend(after: .nothingToLink), .account)
        XCTAssertEqual(DoddyAccountServerUse.backend(after: .conflict(message: "x")), .account, "the earlier data stays apart; the account is used")
        XCTAssertEqual(DoddyAccountServerUse.backend(after: .notSetUp), .notYet)
        XCTAssertNil(DoddyAccountServerUse.backend(after: .retryLater))
    }
}
