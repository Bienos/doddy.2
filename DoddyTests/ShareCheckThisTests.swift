import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// "Check the price" from the Share Sheet (docs/implementation/SHOPPING.md "Check this"): the product link has a file
/// of its own, and the router keeps only a link and gives it once. App-target tests: NOT RUN in the authoring
/// environment (no Xcode); the hosted Mac job runs them.
@MainActor
final class ShareCheckThisTests: XCTestCase {
    private func makeRouter() -> ShortcutRouter {
        let defaults = UserDefaults(suiteName: "ShareCheckThisTests.\(UUID().uuidString)")!
        return ShortcutRouter(setup: BackTapSetupModel(defaults: defaults))
    }

    func testEverySlotHasItsOwnFileAndTheNoteKeepsTheOldOne() {
        let names = ShareInboxFile.Slot.allCases.map(\.fileName)
        XCTAssertEqual(Set(names).count, names.count, "a price check must never replace a note, or the other way round")
        XCTAssertEqual(ShareInboxFile.Slot.note.fileName, "share-inbox.json", "an older app still reads the note's file")
        XCTAssertEqual(ShareInboxFile.fileName, "share-inbox.json")
    }

    func testTheRouterKeepsOnlyATextWithAWebAddress() {
        let router = makeRouter()
        router.priceCheckInvoked(text: "no link here")
        XCTAssertNil(router.priceCheckLink)
        router.priceCheckInvoked(text: "http://sklep.pl/p/1")
        XCTAssertNil(router.priceCheckLink, "plain http is not a page Doddy reads")
    }

    func testTheLinkIsGivenOnce() {
        let router = makeRouter()
        router.priceCheckInvoked(text: "Zmywarka\nhttps://sklep.pl/p/1")
        XCTAssertEqual(router.priceCheckLink, "Zmywarka\nhttps://sklep.pl/p/1")
        XCTAssertEqual(router.takePriceCheckLink(), "Zmywarka\nhttps://sklep.pl/p/1")
        XCTAssertNil(router.takePriceCheckLink())
        XCTAssertNil(router.priceCheckLink)
    }

    func testTheLockForgetsAWaitingLink() {
        let router = makeRouter()
        router.priceCheckInvoked(text: "https://sklep.pl/p/1")
        router.dismissForLock()
        XCTAssertNil(router.priceCheckLink)
    }
}
