import Foundation
import XCTest
@testable import DoddyCore

final class SidebarNavigationTests: XCTestCase {
    private let shopping = UUID()
    private let note = UUID()

    func testAListRowIsHighlightedOnlyWhileHomeShowsThatList() {
        let lists: Set<UUID> = [shopping]
        XCTAssertEqual(SidebarNavigation(section: .home, homePath: [shopping]).selection(listIDs: lists), .list(shopping))
        // Something opened from the list keeps the list's row.
        XCTAssertEqual(SidebarNavigation(section: .home, homePath: [shopping, note]).selection(listIDs: lists), .list(shopping))
        // A note on Home is Home.
        XCTAssertEqual(SidebarNavigation(section: .home, homePath: [note]).selection(listIDs: lists), .section(.home))
        // Another section wins even if Home's path still holds the list.
        XCTAssertEqual(SidebarNavigation(section: .memories, homePath: [shopping]).selection(listIDs: lists), .section(.memories))
    }

    func testADeletedListHighlightsHome() {
        let nav = SidebarNavigation(section: .home, homePath: [shopping])
        XCTAssertEqual(nav.selection(listIDs: []), .section(.home))
    }

    func testChoosingAListOpensItOnHomeInPlaceOfWhatWasThere() {
        var nav = SidebarNavigation(section: .settings, homePath: [note])
        nav.choose(.list(shopping), listIDs: [shopping])
        XCTAssertEqual(nav, SidebarNavigation(section: .home, homePath: [shopping]))
    }

    func testChoosingHomeFromAListGoesBackToHomeItself() {
        var nav = SidebarNavigation(section: .home, homePath: [shopping])
        nav.choose(.section(.home), listIDs: [shopping])
        XCTAssertEqual(nav, SidebarNavigation(section: .home, homePath: []))
    }

    func testOtherwiseHomeKeepsItsPlaceLikeATab() {
        var nav = SidebarNavigation(section: .memories, homePath: [note])
        nav.choose(.section(.home), listIDs: [shopping])
        XCTAssertEqual(nav, SidebarNavigation(section: .home, homePath: [note]))

        // Leaving Home for Settings keeps Home's path for when the user comes back.
        nav.choose(.section(.settings), listIDs: [shopping])
        XCTAssertEqual(nav, SidebarNavigation(section: .settings, homePath: [note]))
    }
}
