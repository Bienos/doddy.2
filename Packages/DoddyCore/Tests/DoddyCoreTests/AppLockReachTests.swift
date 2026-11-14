import XCTest
@testable import DoddyCore

/// App Lock also covers widgets, Shortcuts and unmuting (ADR-723, `changes/app-lock-covers-intents.md`):
/// what the widgets are given, what Shortcuts and Siri learn about the lists, the island's Mute and
/// Unmute, and which voice tools run while the iPhone is locked. With the lock off nothing changes.
final class AppLockReachTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: widgets

    func testWidgetsShowContentOnlyWithTheLockOff() {
        XCTAssertTrue(AppLockPolicy.widgetsShowContent(lockOn: false))
        XCTAssertFalse(AppLockPolicy.widgetsShowContent(lockOn: true))
    }

    func testWithTheLockOnTheWidgetsGetALockedSnapshotWithNothingOfThePersons() throws {
        let note = try MemoryRecord(id: UUID(), rawText: "Locker code 4512", source: .explicitText, category: .other, capturedAt: now)
        let listRecord = try MemoryRecord(id: UUID(), rawText: "Shopping", source: .explicitText, category: .list, capturedAt: now)
        let list = DoddyList(record: listRecord, items: [
            ListItem(id: UUID(), listID: listRecord.id, text: "oat milk", source: .typed, addedAt: now, doneAt: nil, position: 0),
        ])
        let reminder = MemoryReminder(id: UUID(), memoryID: note.id, fireAt: now.addingTimeInterval(3600), timeZoneID: "UTC", createdAt: now)
        let spot = ParkingSpot(latitude: 52.2, longitude: 21.0, accuracyMeters: 8, savedAt: now, note: "level 2, row C")

        let locked = WidgetSnapshot.make(
            memories: [note, listRecord], lists: [list], pinned: PinnedNotes(ids: [note.id]), reminders: [reminder],
            showReminderText: true, isOn: true, now: now, parking: spot, hidesDoddy: true, appLockOn: true)

        XCTAssertTrue(locked.isLocked)
        XCTAssertFalse(locked.isOn, "a reader that doesn't know the lock still shows nothing")
        XCTAssertTrue(locked.pinned.isEmpty && locked.reminders.isEmpty && locked.lists.isEmpty)
        XCTAssertNil(locked.parking)
        XCTAssertNil(locked.shelf, "not even the counts")
        XCTAssertTrue(locked.hidesPictures, "Hide character artwork still travels")
        let json = String(decoding: try locked.encoded(), as: UTF8.self)
        for word in ["Locker", "4512", "Shopping", "oat milk", "level 2"] {
            XCTAssertFalse(json.contains(word), word)
        }
        XCTAssertEqual(WidgetSnapshot.decoded(try locked.encoded()), locked)
        XCTAssertEqual(WidgetSnapshot.decoded(try locked.encoded())?.isLocked, true)
    }

    func testWithTheLockOffTheSnapshotIsAsBeforeAndOldSnapshotsAreNotLocked() throws {
        let note = try MemoryRecord(id: UUID(), rawText: "Locker code 4512", source: .explicitText, category: .other, capturedAt: now)
        let shown = WidgetSnapshot.make(memories: [note], lists: [], pinned: PinnedNotes(ids: [note.id]), reminders: [],
                                        showReminderText: true, isOn: true, now: now)
        XCTAssertFalse(shown.isLocked)
        XCTAssertEqual(shown.pinned.map(\.text), ["Locker code 4512"])
        XCTAssertFalse(String(decoding: try shown.encoded(), as: UTF8.self).contains("locked"), "written only when true")
        let old = Data(#"{"version":1,"writtenAt":1800000000000,"isOn":true,"pinned":[],"reminders":[],"lists":[]}"#.utf8)
        XCTAssertEqual(WidgetSnapshot.decoded(old)?.isLocked, false)
    }

    /// Widgets switched off say so; the lock adds nothing to hide there.
    func testTurnedOffStaysTurnedOffWithTheLockOn() {
        let off = WidgetSnapshot.make(memories: [], lists: [], pinned: PinnedNotes(ids: []), reminders: [],
                                      showReminderText: false, isOn: false, now: now, appLockOn: true)
        XCTAssertFalse(off.isOn)
        XCTAssertFalse(off.isLocked)
        XCTAssertTrue(WidgetSnapshot.locked(at: now).isLocked)
        XCTAssertFalse(WidgetSnapshot.off(at: now).isLocked)
    }

    /// A tick from a widget drawn before the lock was turned on changes nothing; the paused Watch link
    /// hears Siri's locked answer for the same refusal.
    func testALockedTickIsReportedAsLocked() {
        XCTAssertEqual(WatchReply(.locked), .notSaved(reason: AppLockPolicy.lockedAnswer))
        XCTAssertNotEqual(WidgetTick.locked, .notFound)
    }

    // MARK: Shortcuts and Siri looking lists up

    func testListLookupsWithTheLockOffAreUnchanged() {
        for lookup in AppLockListLookup.allCases {
            XCTAssertEqual(AppLockPolicy.listLookup(lookup, lockOn: false, isLocked: false), .lists, "\(lookup)")
        }
    }

    func testWhileDoddyIsLockedNoListNameReachesShortcutsOrSiri() {
        XCTAssertEqual(AppLockPolicy.listLookup(.suggestions, lockOn: true, isLocked: true), .nothing)
        // A typed or spoken name, or a list a shortcut already holds, comes back under a neutral name,
        // so the intent still runs and says that Doddy is locked.
        XCTAssertEqual(AppLockPolicy.listLookup(.byName, lockOn: true, isLocked: true), .lockedPlaceholder)
        XCTAssertEqual(AppLockPolicy.listLookup(.byID, lockOn: true, isLocked: true), .lockedPlaceholder)
    }

    /// iOS keeps suggested names for Siri's list phrases and shows them in Shortcuts, outside Doddy's
    /// lock, so with the lock on they are never handed over, even in the minute Doddy is unlocked.
    func testWithTheLockOnTheNamesAreNeverHandedOverToKeep() {
        XCTAssertEqual(AppLockPolicy.listLookup(.suggestions, lockOn: true, isLocked: false), .nothing)
        XCTAssertEqual(AppLockPolicy.listLookup(.byName, lockOn: true, isLocked: false), .lists)
        XCTAssertEqual(AppLockPolicy.listLookup(.byID, lockOn: true, isLocked: false), .lists)
    }

    func testTheLockedPlaceholderIsNoListOfThePersons() {
        XCTAssertEqual(AppLockPolicy.lockedListID, UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    // MARK: the island's Mute and Unmute

    func testMutingStaysOpenOnALockedIPhone() {
        XCTAssertFalse(IslandMute.needsUnlockedIPhone(.mute))
        for unlocked in [true, false] {
            XCTAssertEqual(IslandMute.decide(.mute, shownMuted: false, iPhoneUnlocked: unlocked), .toggle, "unlocked=\(unlocked)")
        }
    }

    func testUnmutingNeedsTheIPhoneUnlocked() {
        XCTAssertTrue(IslandMute.needsUnlockedIPhone(.unmute))
        XCTAssertEqual(IslandMute.decide(.unmute, shownMuted: true, iPhoneUnlocked: true), .toggle)
        XCTAssertEqual(IslandMute.decide(.unmute, shownMuted: true, iPhoneUnlocked: false), .refusedLocked)
        XCTAssertEqual(IslandMute.decide(.unmute, shownMuted: nil, iPhoneUnlocked: false), .refusedLocked)
    }

    /// The conversation's switch is a toggle, so each button flips it only when the island shows the
    /// state it is meant to change: Mute can never unmute, and Unmute can never mute.
    func testNeitherButtonDoesTheOthersJob() {
        for unlocked in [true, false] {
            XCTAssertEqual(IslandMute.decide(.mute, shownMuted: true, iPhoneUnlocked: unlocked), .nothing)
            XCTAssertEqual(IslandMute.decide(.mute, shownMuted: nil, iPhoneUnlocked: unlocked), .nothing)
        }
        XCTAssertEqual(IslandMute.decide(.unmute, shownMuted: false, iPhoneUnlocked: true), .nothing)
        XCTAssertEqual(IslandMute.decide(.unmute, shownMuted: nil, iPhoneUnlocked: true), .nothing)
    }

    // MARK: voice tools while the iPhone is locked

    private let theirThings = [
        VoiceToolName.searchMemories, VoiceToolName.saveMemory, VoiceToolName.remindAboutNote,
        VoiceToolName.addToList, VoiceToolName.readList, VoiceToolName.checkOff, VoiceToolName.removeFromList, VoiceToolName.createList,
        VoiceToolName.addIngredients, VoiceToolName.parkingSpot, VoiceToolName.undoLast, VoiceToolName.proposePlan,
        VoiceToolName.lookupContact, VoiceToolName.upcomingBirthdays, VoiceToolName.draftMessage,
        VoiceToolName.readCalendar, VoiceToolName.findFreeTime, VoiceToolName.createCalendarEvent, VoiceToolName.changeCalendarEvent,
        VoiceToolName.deleteCalendarEvent, VoiceToolName.deleteCalendarEvents,
        VoiceToolName.createReminder, VoiceToolName.changeReminder, VoiceToolName.deleteReminder, VoiceToolName.moveReminders,
        VoiceToolName.findPhotos, VoiceToolName.readSteps, VoiceToolName.readHealthWeek, VoiceToolName.checkErrands,
        VoiceToolName.lookAtScreen, VoiceToolName.listAlarms, VoiceToolName.cancelAlarm,
        "read_email", "check_email", "read_google_calendar", "read_outlook_calendar",
    ]

    func testWithTheLockOffEveryToolRunsAsBefore() {
        for tool in theirThings + Array(ProtectedDataPolicy.openTools) + ["a_tool_added_later"] {
            XCTAssertTrue(ProtectedDataPolicy.allows(tool: tool, protectedDataAvailable: false, appLockOn: false), tool)
        }
    }

    func testWithTheIPhoneUnlockedEveryToolRuns() {
        for tool in theirThings + ["a_tool_added_later"] {
            XCTAssertTrue(ProtectedDataPolicy.allows(tool: tool, protectedDataAvailable: true, appLockOn: true), tool)
        }
    }

    func testMemoryContactsAndCalendarStopWhenTheIPhoneLocksWithTheLockOn() {
        for tool in theirThings {
            XCTAssertFalse(ProtectedDataPolicy.allows(tool: tool, protectedDataAvailable: false, appLockOn: true), tool)
        }
    }

    /// Fail closed: a tool nobody has decided about is treated as one that reaches the person's things.
    func testAToolNobodyDecidedAboutStopsToo() {
        XCTAssertFalse(ProtectedDataPolicy.allows(tool: "a_tool_added_later", protectedDataAvailable: false, appLockOn: true))
        XCTAssertFalse(ProtectedDataPolicy.allows(tool: "", protectedDataAvailable: false, appLockOn: true))
    }

    func testSumsAndDoddysOwnTimersKeepWorkingAndCanAlwaysBeStopped() {
        for tool in [VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.convertCurrency, VoiceToolName.setTimer,
                     VoiceToolName.stopStopwatch, VoiceToolName.stopFocus, VoiceToolName.stopWindDown, VoiceToolName.stopTranslator,
                     VoiceToolName.lostWallet] {
            XCTAssertTrue(ProtectedDataPolicy.allows(tool: tool, protectedDataAvailable: false, appLockOn: true), tool)
        }
        XCTAssertTrue(ProtectedDataPolicy.openTools.isDisjoint(with: theirThings))
    }

    func testTheAgentIsToldNothingWasDoneAndHowToGetOn() {
        XCTAssertTrue(ProtectedDataPolicy.reply.hasPrefix("locked:"))
        XCTAssertTrue(ProtectedDataPolicy.reply.contains("Nothing was looked up, saved or changed."))
        XCTAssertTrue(ProtectedDataPolicy.reply.contains("unlock"))
    }
}
