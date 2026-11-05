import XCTest
@testable import DoddyCore

/// The key a person pastes in for their own account (ADR-640): safe to put in one header, never
/// shown again, and nothing here knows what a valid inFakt key looks like.
final class AccountKeyTests: XCTestCase {
    func testPastedSpacesAndLineBreaksAroundAKeyAreDropped() throws {
        let key = try XCTUnwrap(AccountKey("  abcdef0123456789\n"))
        XCTAssertEqual(key.value, "abcdef0123456789")
    }

    func testALineBreakOrSpaceInsideAKeyRefusesIt() {
        // A second line pasted with the key would otherwise become a second header.
        XCTAssertNil(AccountKey("abcdef0123\nX-Other: 1"))
        XCTAssertNil(AccountKey("abcdef0123\r\nX-Other: 1"))
        XCTAssertNil(AccountKey("abcdef 0123456789"))
        XCTAssertNil(AccountKey("abcdef\t0123456789"))
    }

    func testOnlyPrintableAsciiIsAccepted() {
        XCTAssertNil(AccountKey("abcdef0123456789ł"))
        XCTAssertNil(AccountKey("abcdef0123456789\u{7F}"))
        XCTAssertNil(AccountKey("abcdef0123456789\u{0}"))
        XCTAssertNil(AccountKey("abcdef01\u{200B}23456789"), "a zero-width space inside is refused")
        XCTAssertNil(AccountKey("abcdef01\u{FEFF}23456789"))
        XCTAssertNotNil(AccountKey("aB3-_.~+/=aB3-_.~+/="))
    }

    func testInvisibleCharactersAroundAPastedKeyAreDroppedOnEveryPlatform() throws {
        for dust in ["\u{200B}", "\u{FEFF}", "\u{00A0}", "\u{2060}", "\u{200D}"] {
            let key = try XCTUnwrap(AccountKey(dust + "abcdef0123456789" + dust), "dust \(dust.unicodeScalars.map(\.value))")
            XCTAssertEqual(key.value, "abcdef0123456789")
        }
    }

    func testLengthLimits() {
        XCTAssertNil(AccountKey(""))
        XCTAssertNil(AccountKey("   \n "))
        XCTAssertNil(AccountKey(String(repeating: "a", count: AccountKey.minLength - 1)))
        XCTAssertNotNil(AccountKey(String(repeating: "a", count: AccountKey.minLength)))
        XCTAssertNotNil(AccountKey(String(repeating: "a", count: AccountKey.maxLength)))
        XCTAssertNil(AccountKey(String(repeating: "a", count: AccountKey.maxLength + 1)))
    }

    func testMaskedShowsOnlyTheLastFourOfALongKeyAndNothingOfAShortOne() throws {
        let long = try XCTUnwrap(AccountKey("0123456789abcdef0123456789abcdef"))
        XCTAssertEqual(long.masked, "••••cdef")
        XCTAssertFalse(long.masked.contains("0123456789abcdef0123456789ab"))
        let short = try XCTUnwrap(AccountKey("abcdefghij"))
        XCTAssertEqual(short.masked, "••••")
    }

    func testStateSaysSavedOnlyWhenSaved() {
        XCTAssertFalse(AccountKeyState.none.isSaved)
        XCTAssertFalse(AccountKeyState.unavailable.isSaved, "a Keychain error is not 'no key' and not 'saved'")
        XCTAssertTrue(AccountKeyState.saved(masked: "••••cdef").isSaved)
    }
}

/// An in-memory stand-in for the Keychain, with the ways a real one fails.
private final class FakeKeyStore: AccountKeyStoring, @unchecked Sendable {
    struct Refused: Error {}
    enum Fault { case none, refuseWrite, refuseRead, forgetOnWrite, keepOnRemove, storeSomethingElse }

    private let lock = NSLock()
    private var key: AccountKey?
    private var fault: Fault
    private(set) var writes = 0

    init(_ fault: Fault = .none, holding key: AccountKey? = nil) {
        self.fault = fault
        self.key = key
    }

    func read() throws -> AccountKey? {
        lock.lock(); defer { lock.unlock() }
        if fault == .refuseRead { throw Refused() }
        return key
    }

    func save(_ new: AccountKey) throws {
        lock.lock(); defer { lock.unlock() }
        writes += 1
        switch fault {
        case .refuseWrite: throw Refused()
        case .forgetOnWrite: break
        case .storeSomethingElse: key = AccountKey("zzzzzzzzzzzz")
        default: key = new
        }
    }

    func remove() throws {
        lock.lock(); defer { lock.unlock() }
        if fault == .keepOnRemove { return }
        key = nil
    }
}

/// Saving and removing a key says so only after asking the store again.
final class AccountKeyManagerTests: XCTestCase {
    private let pasted = "  0123456789abcdef0123456789abcdef\n"

    func testASavedKeyIsReportedMaskedAndHeldByTheStore() throws {
        let store = FakeKeyStore()
        let manager = AccountKeyManager(store: store)
        XCTAssertEqual(manager.state(), .none)
        XCTAssertEqual(manager.save(pasted: pasted), .saved(masked: "••••cdef"))
        XCTAssertEqual(manager.state(), .saved(masked: "••••cdef"))
        XCTAssertEqual(try store.read()?.value, "0123456789abcdef0123456789abcdef")
    }

    func testSomethingThatCannotBeAKeyIsNeverStored() {
        let store = FakeKeyStore()
        let manager = AccountKeyManager(store: store)
        XCTAssertEqual(manager.save(pasted: "short"), .notAKey)
        XCTAssertEqual(manager.save(pasted: "0123456789\nX-Evil: 1"), .notAKey)
        XCTAssertEqual(store.writes, 0, "the Keychain was not even asked")
    }

    func testARefusedWriteIsNotSaid_ToBeSaved() {
        let manager = AccountKeyManager(store: FakeKeyStore(.refuseWrite))
        XCTAssertEqual(manager.save(pasted: pasted), .couldNotSave)
        XCTAssertEqual(manager.state(), .none)
    }

    func testAWriteThatTheStoreDoesNotHoldIsNotSaid_ToBeSaved() {
        XCTAssertEqual(AccountKeyManager(store: FakeKeyStore(.forgetOnWrite)).save(pasted: pasted), .couldNotSave)
        XCTAssertEqual(AccountKeyManager(store: FakeKeyStore(.storeSomethingElse)).save(pasted: pasted), .couldNotSave)
    }

    func testAnUnreadableStoreIsUnavailableNotEmpty() {
        let manager = AccountKeyManager(store: FakeKeyStore(.refuseRead))
        XCTAssertEqual(manager.state(), .unavailable)
        XCTAssertEqual(manager.save(pasted: pasted), .couldNotSave, "can't be verified, so not claimed")
    }

    func testRemovalIsReportedOnlyWhenTheKeyIsReallyGone() throws {
        let key = try XCTUnwrap(AccountKey(pasted))
        let store = FakeKeyStore(holding: key)
        XCTAssertEqual(AccountKeyManager(store: store).remove(), .removed)
        XCTAssertNil(try store.read())
        XCTAssertEqual(AccountKeyManager(store: FakeKeyStore(.keepOnRemove, holding: key)).remove(), .couldNotRemove)
        XCTAssertEqual(AccountKeyManager(store: FakeKeyStore(.refuseRead, holding: key)).remove(), .couldNotRemove)
        XCTAssertEqual(AccountKeyManager(store: FakeKeyStore()).remove(), .removed, "nothing to remove is already removed")
    }

    func testNothingTheManagerReturnsContainsTheKey() throws {
        let manager = AccountKeyManager(store: FakeKeyStore())
        let outcome = manager.save(pasted: pasted)
        let state = manager.state()
        XCTAssertFalse("\(outcome)".contains("0123456789abcdef0123456789ab"))
        XCTAssertFalse("\(state)".contains("0123456789abcdef0123456789ab"))
    }
}
