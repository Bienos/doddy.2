import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-12-account-deletion-truth: deleting a Doddy account says "deleted" only when each server
/// confirmed it (DOD-08). A missing or refused messaging token is never success: the account's own token is
/// minted and the delete tried once more.
final class AccountErasurePlanTests: XCTestCase {
    /// Records the steps in order and answers each from a script.
    private actor Steps {
        var log: [String] = []
        func note(_ step: String) { log.append(step) }
    }

    private func run(
        first: AccountErasurePlan.Attempt, mint: AccountErasurePlan.Mint, retry: AccountErasurePlan.Attempt = .deleted
    ) async -> (AccountErasurePlan.Outcome, [String]) {
        let steps = Steps()
        let outcome = await AccountErasurePlan.run(
            deleteWithStoredToken: { await steps.note("delete:stored"); return first },
            mintAccountToken: { await steps.note("mint"); return mint },
            deleteWithToken: { token in await steps.note("delete:\(token)"); return retry })
        return (outcome, await steps.log)
    }

    func testAConfirmedDeleteNeedsNothingMore() async {
        let (outcome, log) = await run(first: .deleted, mint: .failed)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(log, ["delete:stored"])
    }

    func testNoTokenMintsTheAccountsTokenAndTriesAgain() async {
        // After a reinstall the iPhone has no messaging token, but the account can still be on the server.
        let (outcome, log) = await run(first: .noToken, mint: .token("minted"), retry: .deleted)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(log, ["delete:stored", "mint", "delete:minted"])
    }

    func testARefusedTokenMintsAndTriesAgain() async {
        let (outcome, log) = await run(first: .refused, mint: .token("minted"), retry: .deleted)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(log, ["delete:stored", "mint", "delete:minted"])
    }

    func testASecondFailureIsNotDeleted() async {
        for retry in [AccountErasurePlan.Attempt.refused, .failed, .noToken] {
            let (outcome, log) = await run(first: .noToken, mint: .token("minted"), retry: retry)
            XCTAssertEqual(outcome, .notDeleted, "\(retry)")
            XCTAssertFalse(outcome.isConfirmed)
            XCTAssertEqual(log.count, 3, "tried once more, not again and again")
        }
    }

    func testAMintThatFailsIsNotDeleted() async {
        let (outcome, log) = await run(first: .refused, mint: .failed)
        XCTAssertEqual(outcome, .notDeleted)
        XCTAssertEqual(log, ["delete:stored", "mint"])
    }

    func testAServerThatTakesNoAccountsHoldsNothingForThisOne() async {
        let (outcome, _) = await run(first: .noToken, mint: .serverTakesNoAccounts)
        XCTAssertEqual(outcome, .nothingForAccount)
        XCTAssertTrue(outcome.isConfirmed)
    }

    func testOfflineIsNotDeletedAndMintsNothing() async {
        let (outcome, log) = await run(first: .failed, mint: .token("minted"))
        XCTAssertEqual(outcome, .notDeleted)
        XCTAssertEqual(log, ["delete:stored"])
    }

    func testTheMintFollowsTheSignInAnswer() {
        XCTAssertEqual(AccountErasurePlan.Mint(.signedIn(accountID: "a", deviceToken: "t")), .token("t"))
        XCTAssertEqual(AccountErasurePlan.Mint(.notSetUp), .serverTakesNoAccounts)
        XCTAssertEqual(AccountErasurePlan.Mint(.retryLater), .failed)
        XCTAssertEqual(AccountErasurePlan.Mint(.accountRefused), .failed)
        XCTAssertEqual(AccountErasurePlan.Mint(.conflict(reason: "x")), .failed)
    }

    // MARK: Doddy's backend

    func testADeviceIDWithoutASessionIsAFailureNotNothingThere() {
        XCTAssertEqual(AccountErasurePlan.backendStart(hasSession: false, hasDeviceID: true, usesAccount: false), .failed)
        XCTAssertEqual(AccountErasurePlan.backendStart(hasSession: false, hasDeviceID: false, usesAccount: true), .failed)
        XCTAssertEqual(AccountErasurePlan.backendStart(hasSession: false, hasDeviceID: false, usesAccount: false), .nothingThere)
        XCTAssertEqual(AccountErasurePlan.backendStart(hasSession: true, hasDeviceID: true, usesAccount: false), .erase)
    }

    func testASessionThatVanishesIsNotNothingThere() {
        XCTAssertEqual(AccountErasurePlan.backendOutcome(.failure(.notConfigured)), .failed)
        XCTAssertEqual(AccountErasurePlan.backendOutcome(.failure(.transport)), .failed)
        let receipt = AccountErasureReceipt(
            complete: true, remaining: 0, onlineAccounts: .init(removed: [], pending: []), deleted: [:], erasedAt: "x")
        XCTAssertEqual(AccountErasurePlan.backendOutcome(.success(receipt)), .complete)
    }

    // MARK: The messaging client's own answer

    func testTheMessagingClientNeverCountsAMissingOrRefusedTokenAsDeleted() async {
        let none = DoddyServerClient(transport: Scripted([]), credentials: Credentials(token: nil))
        let noTokenAnswer = await none.deleteAccountWithStoredToken()
        XCTAssertEqual(noTokenAnswer, .noToken)

        let refusedCredentials = Credentials(token: "old")
        let refused = DoddyServerClient(transport: Scripted([ServerResponse(status: 401)]), credentials: refusedCredentials)
        let refusedAnswer = await refused.deleteAccountWithStoredToken()
        XCTAssertEqual(refusedAnswer, .refused)
        XCTAssertNil(try refusedCredentials.load(), "a refused token is dead")

        let brokenCredentials = Credentials(token: "kept")
        let broken = DoddyServerClient(transport: Scripted([ServerResponse(status: 500)]), credentials: brokenCredentials)
        let brokenAnswer = await broken.deleteAccountWithStoredToken()
        XCTAssertEqual(brokenAnswer, .failed)
        XCTAssertEqual(try brokenCredentials.load(), "kept", "kept for the next try")

        let transport = Scripted([ServerResponse(status: 204)])
        let deletedCredentials = Credentials(token: "good")
        let deleted = DoddyServerClient(transport: transport, credentials: deletedCredentials)
        let deletedAnswer = await deleted.deleteAccountWithStoredToken()
        XCTAssertEqual(deletedAnswer, .deleted)
        XCTAssertNil(try deletedCredentials.load())
        let sent = transport.requests
        XCTAssertEqual(sent.map(\.path), ["/v1/account"])
        XCTAssertEqual(sent.first?.method, .delete)
        XCTAssertEqual(sent.first?.bearerToken, "good")
    }

    func testAMintedTokenIsUsedOnceAndNotKept() async {
        let credentials = Credentials(token: nil)
        let transport = Scripted([ServerResponse(status: 204)])
        let client = DoddyServerClient(transport: transport, credentials: credentials)
        let answer = await client.deleteAccount(withToken: "minted")
        XCTAssertEqual(answer, .deleted)
        XCTAssertEqual(transport.requests.first?.bearerToken, "minted")
        XCTAssertNil(try credentials.load())
    }

    // MARK: Settings › Messaging › Delete (one DELETE with the stored token)

    func testSettingsDeleteSaysDeletedOnlyOnA204() {
        XCTAssertEqual(AccountErasurePlan.SettingsDelete(.deleted), .deleted)
    }

    func testSettingsDeleteWithNoTokenIsNotCalledDeleted() {
        // After a reinstall the token is gone but the server can still hold the account: "nothing was deleted from
        // here", never "deleted".
        XCTAssertEqual(AccountErasurePlan.SettingsDelete(.noToken), .nothingKept)
    }

    func testSettingsDeleteThatWasRefusedOrFailedIsNotConfirmed() {
        XCTAssertEqual(AccountErasurePlan.SettingsDelete(.refused), .notConfirmed)
        XCTAssertEqual(AccountErasurePlan.SettingsDelete(.failed), .notConfirmed)
    }
}

private final class Scripted: ServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [ServerResponse]
    private var sent: [ServerRequest] = []
    init(_ responses: [ServerResponse]) { self.responses = responses }
    var requests: [ServerRequest] { lock.withLock { sent } }
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        try lock.withLock {
            sent.append(request)
            guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
            return responses.removeFirst()
        }
    }
}

private final class Credentials: ServerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(token: String?) { self.token = token }
    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
