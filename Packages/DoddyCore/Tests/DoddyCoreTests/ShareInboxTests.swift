import Foundation
import XCTest
@testable import DoddyCore

final class ShareInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTextAndLinkBecomeOneNote() throws {
        let item = try XCTUnwrap(ShareInboxItem.compose(text: "  Recipe for pierogi \n", link: "https://example.com/pierogi", sharedAt: now))
        XCTAssertEqual(item.text, "Recipe for pierogi\nhttps://example.com/pierogi")
        // A link already in the text isn't added twice.
        XCTAssertEqual(ShareInboxItem.compose(text: "See https://example.com/a", link: "https://example.com/a", sharedAt: now)?.text,
                       "See https://example.com/a")
        XCTAssertEqual(ShareInboxItem.compose(text: nil, link: "https://example.com/a", sharedAt: now)?.text, "https://example.com/a")
    }

    func testNothingToKeepAndNonWebLinks() {
        XCTAssertNil(ShareInboxItem.compose(text: "   \n", link: nil, sharedAt: now))
        XCTAssertNil(ShareInboxItem.compose(text: nil, link: "file:///private/var/secret.txt", sharedAt: now))
        XCTAssertNil(ShareInboxItem.compose(text: nil, link: "javascript:alert(1)", sharedAt: now))
        XCTAssertEqual(ShareInboxItem.compose(text: "a\u{0007}b\tc", link: nil, sharedAt: now)?.text, "ab\tc")
    }

    func testLongTextIsCutAndOldItemsAreStale() throws {
        let long = String(repeating: "x", count: ShareInboxItem.maxLength + 50)
        XCTAssertEqual(ShareInboxItem.compose(text: long, link: nil, sharedAt: now)?.text.count, ShareInboxItem.maxLength)
        let item = try XCTUnwrap(ShareInboxItem.compose(text: "milk", link: nil, sharedAt: now))
        XCTAssertFalse(item.isStale(now: now.addingTimeInterval(3600)))
        XCTAssertTrue(item.isStale(now: now.addingTimeInterval(ShareInboxItem.keptFor + 1)))
        XCTAssertTrue(item.isStale(now: now.addingTimeInterval(-3600)), "a date in the future isn't trusted")
    }

    func testRoundTripAndBadFiles() throws {
        let item = try XCTUnwrap(ShareInboxItem.compose(text: "milk", link: nil, sharedAt: now))
        XCTAssertEqual(ShareInboxItem.decoded(try item.encoded()), item)
        XCTAssertNil(ShareInboxItem.decoded(Data("{}".utf8)))
        XCTAssertNil(ShareInboxItem.decoded(Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"","sharedAt":"2027-01-15T08:00:00Z"}"#.utf8)))
    }
}
