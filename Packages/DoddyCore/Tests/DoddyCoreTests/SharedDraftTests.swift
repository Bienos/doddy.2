import DoddyCore
import XCTest

final class SharedDraftTests: XCTestCase {
    func testTextIsKeptExactlyUnlessItIsOnlyWhitespace() {
        XCTAssertEqual(SharedDraft(text: "  Gate code 4821\n").text, "  Gate code 4821\n")
        XCTAssertEqual(SharedDraft(text: " \n\t ").text, "")
        let long = String(repeating: "a", count: MemoryLimits.maxTextLength + 10)
        XCTAssertEqual(SharedDraft(text: long).text, long, "not cut; the capture screen reports the length")
    }

    func testDraftShowsAtOnceWhenNothingIsOpen() {
        var queue = SharedDraftQueue()
        let draft = SharedDraft(text: "Parcel locker 12")
        queue.receive(draft, blocked: false)
        XCTAssertEqual(queue.shown, draft)
        XCTAssertNil(queue.waiting)
    }

    func testDraftWaitsForAConversationThenShows() {
        var queue = SharedDraftQueue()
        let draft = SharedDraft(text: "Parcel locker 12")
        queue.receive(draft, blocked: true)
        XCTAssertNil(queue.shown)
        queue.unblocked(stillBlocked: true)
        XCTAssertNil(queue.shown, "still blocked, e.g. a capture screen is also open")
        queue.unblocked(stillBlocked: false)
        XCTAssertEqual(queue.shown, draft)
        XCTAssertNil(queue.waiting)
    }

    func testOnlyTheNewestWaitsAndOneShownDraftIsNeverReplaced() {
        var queue = SharedDraftQueue()
        let first = SharedDraft(text: "first"), second = SharedDraft(text: "second"), third = SharedDraft(text: "third")
        queue.receive(first, blocked: false)
        queue.receive(second, blocked: false)
        queue.receive(third, blocked: false)
        XCTAssertEqual(queue.shown, first, "the draft on screen is not swapped under the user")
        XCTAssertEqual(queue.waiting, third)
        queue.unblocked(stillBlocked: false)
        XCTAssertEqual(queue.shown, first, "nothing moves while a draft is still shown")
        queue.shownClosed()
        queue.unblocked(stillBlocked: false)
        XCTAssertEqual(queue.shown, third)
    }

    func testNewNoteIsAnEmptyTypedNoteNotSharedText() {
        let blank = SharedDraft.newNote()
        XCTAssertEqual(blank.text, "")
        XCTAssertFalse(blank.isSharedText)
        XCTAssertFalse(SharedDraft(text: " \n").isSharedText, "nothing was shared, so what the user types is a typed note")
        XCTAssertTrue(SharedDraft(text: "Locker 12").isSharedText)
    }
}
