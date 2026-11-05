import XCTest
@testable import DoddyCore

/// ADR-723: every way into Doddy asks the Face ID lock, and with the lock off nothing changes.
final class AppLockPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: the policy

    /// "Keep the lock OFF behaviour unchanged": not locked, every entry goes ahead.
    func testEveryEntryGoesAheadWhenNothingIsLocked() {
        for entry in AppLockEntry.allCases {
            XCTAssertTrue(AppLockPolicy.allows(entry, isLocked: false), entry.rawValue)
        }
    }

    /// The finding: shortcuts, links, notifications and sheets reached the app past the lock.
    func testNoEntryGoesAheadWhileLocked() {
        for entry in AppLockEntry.allCases {
            XCTAssertFalse(AppLockPolicy.allows(entry, isLocked: true), entry.rawValue)
        }
    }

    func testTheWaysInThatTheBriefNamesAreAllEntries() {
        let names = Set(AppLockEntry.allCases.map(\.rawValue))
        for name in ["startConversation", "openRecordings", "openParking", "openNoteSheet", "readNotesAloud"] {
            XCTAssertTrue(names.contains(name), name)
        }
    }

    func testRequestsFromTheOutsideWaitForTheUnlockAndSiriAndTheIslandAreNotKept() {
        for entry in [AppLockEntry.startConversation, .openCapture, .openFind, .openNoteSheet, .openWays, .openRecordings, .openParking] {
            XCTAssertEqual(AppLockPolicy.whenLocked(entry), .afterUnlock, entry.rawValue)
        }
        // Siri cannot wait for a face, and the app brings a running conversation forward itself (ADR-577).
        XCTAssertEqual(AppLockPolicy.whenLocked(.readNotesAloud), .drop)
        XCTAssertEqual(AppLockPolicy.whenLocked(.showRunningConversation), .drop)
    }

    /// Siri and Shortcuts read, add to and tick off lists without opening Doddy (ADR-226). With the lock on they
    /// are refused like the note lookup, and nothing is kept for later: the answer is the locked answer.
    func testTheListIntentsAreRefusedWhileLockedAndNotKept() {
        for entry in [AppLockEntry.readListAloud, .changeList] {
            XCTAssertTrue(AppLockPolicy.allows(entry, isLocked: false), "\(entry.rawValue) with the lock off")
            XCTAssertFalse(AppLockPolicy.allows(entry, isLocked: true), "\(entry.rawValue) while locked")
            XCTAssertEqual(AppLockPolicy.whenLocked(entry), .drop, entry.rawValue)
        }
        XCTAssertTrue(AppLockEntry.allCases.contains(.readListAloud) && AppLockEntry.allCases.contains(.changeList))
    }

    func testSiriSaysDoddyIsLocked() {
        XCTAssertEqual(AppLockPolicy.lockedAnswer, "Doddy is locked. Open Doddy and unlock him.")
    }

    // MARK: the cover for the app switcher

    func testTheCoverIsNeverShownWithTheLockOff() {
        for active in [false, true] {
            XCTAssertFalse(AppLockPolicy.coverShown(lockOn: false, sceneIsActive: active), "active=\(active)")
        }
    }

    func testTheCoverIsShownWheneverTheLockIsOnAndDoddyIsNotInFront() {
        XCTAssertTrue(AppLockPolicy.coverShown(lockOn: true, sceneIsActive: false), "inactive or in the background: the app switcher's picture")
        XCTAssertFalse(AppLockPolicy.coverShown(lockOn: true, sceneIsActive: true))
    }

    // MARK: the hold

    func testHeldRequestsComeBackOldestFirstAndTheHoldIsEmptyAfterwards() {
        var hold = AppLockHold<String>()
        XCTAssertTrue(hold.isEmpty)
        hold.hold("talk", for: .startConversation, at: now)
        hold.hold("check-in", for: .openNoteSheet, at: now.addingTimeInterval(5))
        XCTAssertEqual(hold.entries, [.startConversation, .openNoteSheet])
        XCTAssertEqual(hold.release(at: now.addingTimeInterval(10)), ["talk", "check-in"])
        XCTAssertTrue(hold.isEmpty)
        XCTAssertEqual(hold.release(at: now.addingTimeInterval(11)), [], "nothing runs twice")
    }

    func testASecondRequestForTheSameEntryReplacesTheFirst() {
        var hold = AppLockHold<String>()
        hold.hold("first", for: .startConversation, at: now)
        hold.hold("tidy", for: .openNoteSheet, at: now)
        hold.hold("second", for: .startConversation, at: now.addingTimeInterval(1))
        XCTAssertEqual(hold.release(at: now.addingTimeInterval(2)), ["tidy", "second"])
    }

    /// A conversation asked for minutes ago must not start by itself when the person unlocks later.
    func testARequestExpires() {
        var hold = AppLockHold<String>()
        hold.hold("talk", for: .startConversation, at: now)
        hold.hold("recent", for: .openRecordings, at: now.addingTimeInterval(100))
        XCTAssertEqual(hold.release(at: now.addingTimeInterval(AppLockHold<String>.lifetime + 1)), ["recent"])
        XCTAssertTrue(hold.isEmpty)

        hold.hold("talk", for: .startConversation, at: now)
        XCTAssertEqual(hold.release(at: now.addingTimeInterval(AppLockHold<String>.lifetime)), ["talk"], "still fresh at the limit")
        XCTAssertLessThanOrEqual(AppLockHold<String>.lifetime, 120, "a couple of minutes at most")
    }

    func testTheHoldIsBoundedAndTheOldestGoesFirst() {
        var hold = AppLockHold<Int>()
        let entries: [AppLockEntry] = [.startConversation, .openCapture, .openFind, .openNoteSheet, .openWays, .openRecordings]
        for (index, entry) in entries.enumerated() { hold.hold(index, for: entry, at: now) }
        XCTAssertEqual(hold.entries.count, AppLockHold<Int>.capacity)
        XCTAssertEqual(hold.release(at: now), Array((entries.count - AppLockHold<Int>.capacity)..<entries.count))
    }

    func testClearForgetsEverything() {
        var hold = AppLockHold<String>()
        hold.hold("talk", for: .startConversation, at: now)
        hold.clear()
        XCTAssertTrue(hold.isEmpty)
        XCTAssertEqual(hold.release(at: now), [])
    }
}

/// ADR-724: a copied note leaves the clipboard on its own, and stays on this iPhone.
final class ClipboardPolicyTests: XCTestCase {
    func testACopiedNoteLeavesTheClipboardAfterTwoMinutes() {
        let copied = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ClipboardPolicy.noteLifetime, 120)
        XCTAssertEqual(ClipboardPolicy.noteExpiry(copiedAt: copied), copied.addingTimeInterval(120))
    }
}
