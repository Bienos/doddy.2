import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-12-local-data-owner: this iPhone's data belongs to the account that made it, and nothing of it
/// goes to another account's copy on Doddy's servers. The uploaders' own gates are tested with their models
/// (`WebMemoryModelTests`, `LogbookModelTests`); the Messages copy and Memory on calls ask `mayUpload(for:)`.
@MainActor
final class LocalDataOwnerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "local-data-owner-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testTheFirstSignInOnAnIPhoneWithNoOwnerTakesItsDataOver() async {
        var asked = false
        let claim = await LocalDataOwner.claim(for: "Account-A", defaults: defaults) {
            asked = true
            return false
        }
        XCTAssertEqual(claim, .adopted)
        XCTAssertFalse(asked, "with no owner recorded nothing needs checking, so nothing waits")
        XCTAssertEqual(LocalDataOwner.owner(in: defaults), "account-a")
        XCTAssertTrue(LocalDataOwner.mayUpload(for: "account-a", defaults: defaults))
        XCTAssertNil(LocalDataOwner.mismatch(for: "account-a", defaults: defaults))
    }

    func testTheOwnerSigningInAgainKeepsItsData() async {
        defaults.set("account-a", forKey: LocalDataOwner.ownerKey)
        let claim = await LocalDataOwner.claim(for: "account-a", defaults: defaults) {
            XCTFail("the owner's own data needs no check")
            return false
        }
        XCTAssertEqual(claim, .alreadyOwner)
        XCTAssertTrue(LocalDataOwner.mayUpload(for: "account-a", defaults: defaults))
    }

    func testAnotherAccountOnAnIPhoneWithDataIsAMismatchAndMaySendNothing() async {
        defaults.set("account-a", forKey: LocalDataOwner.ownerKey)
        let claim = await LocalDataOwner.claim(for: "account-b", defaults: defaults) { false }
        let mismatch = DataOwnerMismatch(owner: "account-a", signedIn: "account-b")
        XCTAssertEqual(claim, .mismatch(mismatch))
        XCTAssertEqual(LocalDataOwner.owner(in: defaults), "account-a", "the data still belongs to A")
        XCTAssertEqual(LocalDataOwner.mismatch(for: "account-b", defaults: defaults), mismatch)
        // Every uploader asks this one gate: the Messages copy, Memory on calls, notes and conversations kept on
        // the server, Logbook.
        XCTAssertEqual(LocalDataOwner.upload(for: "account-b", defaults: defaults), .otherAccount)
        XCTAssertFalse(LocalDataOwner.mayUpload(for: "account-b", defaults: defaults))
        // A signs in again: the data goes to A as before.
        XCTAssertTrue(LocalDataOwner.mayUpload(for: "account-a", defaults: defaults))
    }

    func testAnotherAccountOnAnEmptyIPhoneTakesItOver() async {
        defaults.set("account-a", forKey: LocalDataOwner.ownerKey)
        let claim = await LocalDataOwner.claim(for: "account-b", defaults: defaults) { true }
        XCTAssertEqual(claim, .adopted)
        XCTAssertEqual(LocalDataOwner.owner(in: defaults), "account-b")
        XCTAssertTrue(LocalDataOwner.mayUpload(for: "account-b", defaults: defaults))
        XCTAssertFalse(LocalDataOwner.mayUpload(for: "account-a", defaults: defaults), "A's next sign-in finds B's iPhone")
    }

    func testAnEmptyAccountIDClaimsNothing() async {
        let claim = await LocalDataOwner.claim(for: "  ", defaults: defaults) { true }
        XCTAssertNil(claim)
        XCTAssertNil(LocalDataOwner.owner(in: defaults))
    }

    func testNobodySignedInOrNoOwnerYetSendsNothing() {
        XCTAssertEqual(LocalDataOwner.upload(owner: "a", signedIn: nil, accountsConfigured: true), .waiting)
        XCTAssertEqual(LocalDataOwner.upload(owner: nil, signedIn: "a", accountsConfigured: true), .waiting)
        XCTAssertEqual(LocalDataOwner.upload(owner: "", signedIn: "a", accountsConfigured: true), .waiting)
        XCTAssertEqual(LocalDataOwner.upload(owner: "A", signedIn: "a ", accountsConfigured: true), .allowed)
        XCTAssertEqual(LocalDataOwner.upload(owner: "a", signedIn: "b", accountsConfigured: true), .otherAccount)
        XCTAssertFalse(LocalDataOwner.mayUpload(for: nil, defaults: defaults))
        XCTAssertNil(LocalDataOwner.mismatch(for: nil, defaults: defaults))
    }

    /// A build with no Doddy accounts set up has only its own device sign-in: nothing can reach another person.
    func testABuildWithoutAccountsKeepsItsUploads() {
        XCTAssertEqual(LocalDataOwner.upload(owner: nil, signedIn: nil, accountsConfigured: false), .allowed)
        XCTAssertTrue(LocalDataOwner.mayUpload(for: nil, accountsConfigured: false, defaults: defaults))
    }

    func testTheRuleItself() {
        XCTAssertEqual(LocalDataOwner.decide(owner: nil, signedIn: "a", localDataIsEmpty: false), .adopted)
        XCTAssertEqual(LocalDataOwner.decide(owner: "a", signedIn: "A", localDataIsEmpty: false), .alreadyOwner)
        XCTAssertEqual(LocalDataOwner.decide(owner: "a", signedIn: "b", localDataIsEmpty: true), .adopted)
        XCTAssertEqual(
            LocalDataOwner.decide(owner: "a", signedIn: "b", localDataIsEmpty: false),
            .mismatch(DataOwnerMismatch(owner: "a", signedIn: "b")))
    }

    /// "Erase everything on this iPhone" clears the owner only after every store was read back as empty, then the
    /// signed-in account takes the empty iPhone over. Until then the record stays, so nothing left behind can be handed
    /// to whoever signs in next.
    func testErasingTheIPhoneClearsTheOwnerAndTheSignedInAccountTakesItOver() async {
        defaults.set("account-a", forKey: LocalDataOwner.ownerKey)
        LocalDataOwner.forgetOwner(in: defaults)
        XCTAssertNil(LocalDataOwner.owner(in: defaults))
        XCTAssertFalse(LocalDataOwner.mayUpload(for: "account-b", defaults: defaults), "waiting, until the claim")
        let claim = await LocalDataOwner.claim(for: "account-b", defaults: defaults) {
            XCTFail("an iPhone with no owner recorded needs no check")
            return false
        }
        XCTAssertEqual(claim, .adopted)
        XCTAssertTrue(LocalDataOwner.mayUpload(for: "account-b", defaults: defaults))
    }

    func testTheOwnerRecordSurvivesTheErasePreferenceSweep() {
        defaults.set("account-a", forKey: LocalDataOwner.ownerKey)
        let suiteName = suite!
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .afterAccountDeleted)
        XCTAssertEqual(LocalDataOwner.owner(in: defaults), "account-a",
                       "only the app clears it, and only once the erase was confirmed")
    }

    func testSigningOutTurnsTheUploadSwitchesOff() {
        defaults.set(true, forKey: "memoryCopyOn")
        defaults.set(true, forKey: "unrelated")
        AccountSignOutReset.apply(switchesOff: ["memoryCopyOn"], to: defaults)
        XCTAssertFalse(defaults.bool(forKey: "memoryCopyOn"))
        XCTAssertTrue(defaults.bool(forKey: "unrelated"), "only the switches named")
    }
}
