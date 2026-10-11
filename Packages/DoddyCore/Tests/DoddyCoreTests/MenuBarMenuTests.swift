import Foundation
import XCTest
@testable import DoddyCore

/// ADR-450: the Mac menu-bar menu never offers what the Mac app can't do.
final class MenuBarMenuTests: XCTestCase {
    func testMenuListsEverySixRowsInTheReferenceOrder() {
        let menu = MenuBarMenu(memoryIsOpen: true)
        XCTAssertEqual(
            menu.entries.map(\.title),
            ["Open Doddy", "Talk to Doddy", "Remember something", "Find in my memories", "Translate", "Settings"])
    }

    func testVoiceAndTranslateAreNeverAvailableOnTheMac() {
        for open in [true, false] {
            let menu = MenuBarMenu(memoryIsOpen: open)
            for action in [MenuBarAction.talk, .translate] {
                guard case .unavailable(let reason) = menu.entry(action).availability else {
                    return XCTFail("\(action) must not look available on the Mac")
                }
                XCTAssertTrue(reason.contains("iPhone"), "the reason points to where it does work")
            }
        }
    }

    func testRememberAndFindNeedTheMemoryStore() {
        let open = MenuBarMenu(memoryIsOpen: true)
        XCTAssertTrue(open.entry(.remember).availability.isAvailable)
        XCTAssertTrue(open.entry(.find).availability.isAvailable)
        XCTAssertEqual(open.status, .ready)

        let closed = MenuBarMenu(memoryIsOpen: false)
        XCTAssertFalse(closed.entry(.remember).availability.isAvailable)
        XCTAssertFalse(closed.entry(.find).availability.isAvailable)
        XCTAssertEqual(closed.status, .memoryUnavailable)
    }

    func testWindowsOpenEvenWhenMemoryIsUnavailable() {
        let closed = MenuBarMenu(memoryIsOpen: false)
        XCTAssertTrue(closed.entry(.openDoddy).availability.isAvailable)
        XCTAssertTrue(closed.entry(.settings).availability.isAvailable)
    }

    func testStatusNeverClaimsListening() {
        for status in [MenuBarStatus.ready, .memoryUnavailable] {
            XCTAssertFalse(status.text.lowercased().contains("listening…"))
        }
        XCTAssertTrue(MenuBarStatus.ready.text.contains("Not listening"))
    }
}
