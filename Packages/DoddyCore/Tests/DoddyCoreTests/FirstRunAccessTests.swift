import XCTest
@testable import DoddyCore

final class FirstRunAccessTests: XCTestCase {
    func testShowsOnlyOnAFreshInstallationNotYetSeen() {
        XCTAssertTrue(FirstRunAccessRule.shouldShow(seen: false, firstInstallation: true, override: nil))
        XCTAssertFalse(FirstRunAccessRule.shouldShow(seen: true, firstInstallation: true, override: nil))
        XCTAssertFalse(FirstRunAccessRule.shouldShow(seen: false, firstInstallation: false, override: nil),
                       "someone updating from an older version is not asked for everything at once")
    }

    func testATestOverrideForcesItOnOnlyUntilItIsAnswered() {
        XCTAssertTrue(FirstRunAccessRule.shouldShow(seen: false, firstInstallation: false, override: true))
        XCTAssertFalse(FirstRunAccessRule.shouldShow(seen: true, firstInstallation: false, override: true),
                       "or a test could never get past it")
        XCTAssertFalse(FirstRunAccessRule.shouldShow(seen: false, firstInstallation: true, override: false))
    }

    func testTheLaunchArgumentIsReadAsTheStringItArrivesAs() {
        // `-firstRunAccess NO` is stored by iOS as the string "NO". `as? Bool` on it is nil, which is how the
        // step came to show over Home in every fresh-install UI test.
        let name = "FirstRunAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertNil(FirstRunAccessRule.override(in: defaults), "no argument, no override")
        for (value, expected) in [("NO", false), ("no", false), ("0", false), ("false", false),
                                  ("YES", true), ("yes", true), ("1", true), ("true", true)] {
            defaults.set(value, forKey: "firstRunAccess")
            XCTAssertEqual(FirstRunAccessRule.override(in: defaults), expected, value)
        }
        defaults.set("maybe", forKey: "firstRunAccess")
        XCTAssertNil(FirstRunAccessRule.override(in: defaults), "a value that is not yes or no is no override")
        defaults.set(false, forKey: "firstRunAccess")
        XCTAssertEqual(FirstRunAccessRule.override(in: defaults), false)
        defaults.set(true, forKey: "firstRunAccess")
        XCTAssertEqual(FirstRunAccessRule.override(in: defaults), true)
    }

    func testEveryItemStartsTickedAndTheOrderIsFixed() {
        XCTAssertEqual(FirstRunAccessItem.allCases.count, 9)
        XCTAssertTrue(FirstRunAccessItem.allCases.allSatisfy(\.tickedAtStart))
        // The microphone first (the reason Doddy exists), notifications next.
        XCTAssertEqual(FirstRunAccessItem.allCases.prefix(2), [.microphone, .notifications])
        let ticked = Set(FirstRunAccessItem.allCases)
        XCTAssertEqual(FirstRunAccessRule.itemsToAsk(ticked: ticked), FirstRunAccessItem.allCases)
        XCTAssertEqual(FirstRunAccessRule.itemsToAsk(ticked: [.camera, .contacts]), [.contacts, .camera],
                       "asked in the fixed order, whatever order they were ticked in")
        XCTAssertEqual(FirstRunAccessRule.itemsToAsk(ticked: []), [])
    }

    func testEachItemTurnsOnTheConnectionThatUsesItAndNothingElse() {
        XCTAssertNil(FirstRunAccessItem.microphone.connection)
        XCTAssertNil(FirstRunAccessItem.location.connection)
        XCTAssertEqual(FirstRunAccessItem.notifications.connection, .timers)
        XCTAssertEqual(FirstRunAccessItem.contacts.connection, .contacts)
        XCTAssertEqual(FirstRunAccessItem.calendar.connection, .calendar)
        XCTAssertEqual(FirstRunAccessItem.reminders.connection, .reminders)
        XCTAssertEqual(FirstRunAccessItem.motion.connection, .steps)
        XCTAssertEqual(FirstRunAccessItem.photos.connection, .photos)
        XCTAssertEqual(FirstRunAccessItem.camera.connection, .camera)
        // No two items share a switch, and none of the no-permission ones (they start on already).
        let connections = FirstRunAccessItem.allCases.compactMap(\.connection)
        XCTAssertEqual(Set(connections).count, connections.count)
        XCTAssertTrue(connections.allSatisfy { !$0.startsOn })
    }

    func testSummaryCountsAllowedAndRefusedButNotSkipped() {
        let outcomes: [FirstRunAccessItem: FirstRunAccessOutcome] = [
            .microphone: .allowed, .contacts: .refused, .camera: .skipped, .photos: .allowed,
        ]
        let summary = FirstRunAccessRule.summary(outcomes)
        XCTAssertEqual(summary.allowed, 2)
        XCTAssertEqual(summary.refused, 1)
    }
}
