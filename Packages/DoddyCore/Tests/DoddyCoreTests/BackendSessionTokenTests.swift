import Foundation
import XCTest
@testable import DoddyCore

/// Two `ds1.` tokens live in the iPhone's Keychain side by side now: the earlier device session (the iPhone's own, minted
/// from its device id) and the backend's account session (`POST /v1/session/account`). Both start with `ds1.`, so the old
/// rule "a stored token that starts with `ds1.` is the earlier device session" (`DoddyAccountServers.linkBackend`) would
/// hand the account session to the link routes, which refuse it (401). The two are kept apart by what the token says it is
/// (`acc` in its claims) and by what the app holds as the account session, and the link calls themselves refuse an account
/// session, whoever calls them (decision 2026-11-14-backend-account-session, rule 9).
///
/// Platforms: iPhone. The Watch and Mac apps are paused.

final class BackendSessionTokenTests: XCTestCase {
    private let device = fakeBackendToken(sub: "device-user", dev: nil, acc: false)
    private let deviceOfAStoredIPhone = fakeBackendToken(sub: "device-user", dev: "00000000-0000-4000-8000-000000000002", acc: false)
    private let account = fakeBackendToken(sub: "account-1", dev: "00000000-0000-4000-8000-000000000001", acc: true)

    // MARK: Which kind a token is

    func testTheAccountSessionClaimIsReadFromTheTokenItself() {
        XCTAssertTrue(BackendSessionToken.isAccountSession(account))
        XCTAssertFalse(BackendSessionToken.isAccountSession(device))
        XCTAssertFalse(BackendSessionToken.isAccountSession(deviceOfAStoredIPhone), "`dev` alone is a device session of a stored iPhone")
        XCTAssertFalse(BackendSessionToken.isAccountSession("eyJhbGciOiJIUzI1NiJ9.e30.sig"), "a Supabase token is not a ds1 token")
        XCTAssertFalse(BackendSessionToken.isAccountSession("ds1.not-readable.sig"))
        XCTAssertFalse(BackendSessionToken.isAccountSession(""))
    }

    // MARK: The selection rule for the link routes

    func testTheEarlierDeviceSessionIsPickedAndTheAccountSessionNever() {
        XCTAssertEqual(BackendSessionToken.earlierDeviceSession(stored: device, accountSession: nil), device)
        XCTAssertEqual(BackendSessionToken.earlierDeviceSession(stored: deviceOfAStoredIPhone, accountSession: account), deviceOfAStoredIPhone,
                       "a device session stays the earlier session while an account session is held")
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: account, accountSession: nil), "its own claim says what it is")
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: account, accountSession: account))
    }

    func testTheHeldAccountSessionIsNeverPickedWhateverItsClaimsSay() {
        // An earlier token of the same account (replaced at a renewal) or one whose claims can't be read is still not a device session
        // when it is the one the app holds as the account session.
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: "ds1.not-readable.sig", accountSession: "ds1.not-readable.sig"))
        let renewedAway = fakeBackendToken(sub: "account-1", dev: "00000000-0000-4000-8000-000000000001", acc: true, iat: 1_800_000_001)
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: renewedAway, accountSession: account))
    }

    func testAnythingElseStoredIsNotAnEarlierDeviceSession() {
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: nil, accountSession: account))
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: "", accountSession: nil))
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: "eyJhbGciOiJIUzI1NiJ9.e30.sig", accountSession: nil), "the Supabase token the app saved at the link")
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: "supabase-1-not-real", accountSession: nil))
        XCTAssertNil(BackendSessionToken.earlierDeviceSession(stored: "ds1." + String(repeating: "a", count: 2_100), accountSession: nil), "as the link call's own limit")
    }

    func testATokenWhoseClaimsCannotBeReadIsPickedAsBeforeThisChange() {
        // Before this change every stored `ds1.` token was taken. A token typed in Settings may not carry readable claims;
        // it is not an account session this server made (those always do), so it keeps working as it did.
        XCTAssertEqual(BackendSessionToken.earlierDeviceSession(stored: "ds1.not-readable.sig", accountSession: nil), "ds1.not-readable.sig")
    }

    // MARK: The link calls refuse an account session themselves

    private let user = "0b9d6b52-6a53-4b3b-9d0e-6d6f7f3f7a11"
    private var accountSignIn: DoddyAccountSession {
        DoddyAccountSession(accessToken: "supabase-1-not-real", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1_800_003_600), userID: user, email: nil, method: .google)
    }

    func testTheLinkRoutesAreNeverSentAnAccountSession() async {
        let server = ModelBackendServer()
        let linked = await DoddyAccountLink.linkBackend(server: backendTestServer, account: accountSignIn, deviceToken: account, transport: server)
        XCTAssertEqual(linked, .nothingToLink, "there is no earlier device session to bring")
        let undone = await DoddyAccountLink.undoBackendLink(server: backendTestServer, deviceToken: account, transport: server)
        XCTAssertEqual(undone, .notAllowed)
        XCTAssertTrue(server.seen.isEmpty, "not one request carried it")
    }

    func testTheLinkStillStartsWithTheEarlierDeviceSessionWhileAnAccountSessionIsHeld() async throws {
        let server = ModelBackendServer()
        server.addDeviceSession(device)
        // What `DoddyAccountServers.linkBackend` does: pick, then link with the pick.
        let earlier = try XCTUnwrap(BackendSessionToken.earlierDeviceSession(stored: device, accountSession: account))
        _ = await DoddyAccountLink.linkBackend(server: backendTestServer, account: accountSignIn, deviceToken: earlier, transport: server)
        let start = try XCTUnwrap(server.seen.first)
        XCTAssertEqual(start.path, "/v1/account/link-device/start")
        XCTAssertEqual(start.bearer, device, "the iPhone's own earlier session asks for the code, as before")
        XCTAssertEqual(server.seen.filter { $0.bearer == account }, [])
    }

    func testTheAccountsTokenForTheLinkIsStillTheSupabaseToken() async throws {
        let server = ModelBackendServer()
        server.addDeviceSession(device)
        _ = await DoddyAccountLink.linkBackend(server: backendTestServer, account: accountSignIn, deviceToken: device, transport: server)
        // The code was issued; the second step carries the account's token, never an account session.
        let link = try XCTUnwrap(server.seen.first { $0.path == "/v1/account/link-device" })
        XCTAssertEqual(link.bearer, "supabase-1-not-real")
    }
}
