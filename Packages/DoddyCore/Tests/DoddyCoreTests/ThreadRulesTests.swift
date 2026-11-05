@testable import DoddyCore
import XCTest

/// The thread with Doddy (ADR-585): what goes to the model as earlier turns, when a date heading shows,
/// and what the delivery line says.
final class ThreadRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func message(_ sender: ThreadMessage.Sender, _ text: String, minutesAgo: Double, _ delivery: ThreadMessage.Delivery = .sent) -> ThreadMessage {
        ThreadMessage(
            id: UUID(), sender: sender, text: text, createdAt: now.addingTimeInterval(-minutesAgo * 60), delivery: delivery,
            basis: sender == .doddy ? .general : nil)
    }

    func testHistoryKeepsOnlyDeliveredRecentMessagesInOrder() {
        let thread = [
            message(.user, "very old question", minutesAgo: 13 * 60),
            message(.doddy, "very old answer", minutesAgo: 13 * 60 - 1),
            message(.user, "did it arrive?", minutesAgo: 30, .failed),
            message(.user, "still going", minutesAgo: 20, .sending),
            message(.user, "what is on Friday?", minutesAgo: 10),
            message(.doddy, "A dentist at 9.", minutesAgo: 9),
        ]
        let turns = ThreadRules.history(from: thread, before: now)
        XCTAssertEqual(turns.map(\.text), ["what is on Friday?", "A dentist at 9."])
        XCTAssertEqual(turns.map(\.role), [.user, .assistant])
    }

    func testHistoryExcludesTheQuestionBeingAskedAndAnythingLater() {
        let asking = message(.user, "now", minutesAgo: 0)
        let thread = [message(.user, "before", minutesAgo: 5), message(.doddy, "reply", minutesAgo: 4), asking]
        XCTAssertEqual(ThreadRules.history(from: thread, before: asking.createdAt).map(\.text), ["before", "reply"])
    }

    func testHistoryAtTheEdgeOfTheWindow() {
        let edge = message(.doddy, "edge", minutesAgo: 12 * 60)
        let past = message(.doddy, "past", minutesAgo: 12 * 60 + 1)
        XCTAssertEqual(ThreadRules.history(from: [past, edge], before: now).map(\.text), ["edge"])
    }

    func testHeadingShowsForTheFirstMessageAndAfterAnHourOfSilence() {
        let first = message(.user, "a", minutesAgo: 200)
        let soon = message(.doddy, "b", minutesAgo: 190)
        let later = message(.user, "c", minutesAgo: 100)
        XCTAssertTrue(ThreadRules.showsHeading(first, after: nil))
        XCTAssertFalse(ThreadRules.showsHeading(soon, after: first))
        XCTAssertTrue(ThreadRules.showsHeading(later, after: soon))
    }

    func testBlankDraftsAndABusyThreadCannotSend() {
        XCTAssertFalse(ThreadRules.canSend(draft: "", isSending: false))
        XCTAssertFalse(ThreadRules.canSend(draft: " \n\t ", isSending: false))
        XCTAssertFalse(ThreadRules.canSend(draft: "hello", isSending: true))
        XCTAssertTrue(ThreadRules.canSend(draft: " hello ", isSending: false))
    }

    func testOnlyANotDeliveredUserMessageCanBeSentAgain() {
        XCTAssertTrue(ThreadRules.canRetry(message(.user, "x", minutesAgo: 1, .failed)))
        XCTAssertFalse(ThreadRules.canRetry(message(.user, "x", minutesAgo: 1, .sending)))
        XCTAssertFalse(ThreadRules.canRetry(message(.user, "x", minutesAgo: 1, .sent)))
        XCTAssertFalse(ThreadRules.canRetry(message(.doddy, "x", minutesAgo: 1)))
    }

    func testDeliveryLineNeverClaimsMoreThanIsKnown() {
        XCTAssertEqual(ThreadRules.deliveryLine(for: message(.user, "x", minutesAgo: 1, .sending)), .sending)
        XCTAssertEqual(ThreadRules.deliveryLine(for: message(.user, "x", minutesAgo: 1, .failed)), .notDelivered)
        XCTAssertNil(ThreadRules.deliveryLine(for: message(.user, "x", minutesAgo: 1, .sent)), "answered: nothing to say, and never 'read'")
        XCTAssertNil(ThreadRules.deliveryLine(for: message(.doddy, "x", minutesAgo: 1)))
    }

    func testANewUserMessageIsSendingAndADoddyAnswerCarriesWhereItCameFrom() throws {
        XCTAssertEqual(ThreadMessage.user("hi", now: now).delivery, .sending)

        let note = try MemoryRecord(id: UUID(), rawText: "Dentist Friday at 9", source: .explicitVoice, capturedAt: now)
        let grounded = AssistantAnswer(answer: VerifiedAnswer(text: "Friday at 9.", sources: [note]), notesSent: [note], notesSearchFailed: false)
        let fromNotes = ThreadMessage.doddy(grounded, now: now)
        XCTAssertEqual(fromNotes.basis, .savedNotes)
        XCTAssertEqual(fromNotes.noteIDs, [note.id])
        XCTAssertEqual(fromNotes.notesSent, 1)
        XCTAssertEqual(fromNotes.delivery, .sent)

        let general = AssistantAnswer(answer: VerifiedAnswer(text: "Probably.", sources: []), notesSent: [], notesSearchFailed: true)
        let fromNowhere = ThreadMessage.doddy(general, now: now)
        XCTAssertEqual(fromNowhere.basis, .general)
        XCTAssertTrue(fromNowhere.notesSearchFailed)
        XCTAssertTrue(fromNowhere.noteIDs.isEmpty)
    }
}
