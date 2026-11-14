import XCTest
@testable import DoddyCore

/// Messages as one timeline, and a file bubble that follows the server (owner, 11 Nov 2026).
final class ThreadTimelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_794_000_000)
    private let docID = "abcdefghijklmnopqrstuvwx"

    private func message(_ minutes: Double, _ text: String, sender: ThreadMessage.Sender = .user, document: ThreadDocument? = nil) -> ThreadMessage {
        ThreadMessage(id: UUID(), sender: sender, text: text, createdAt: t0.addingTimeInterval(minutes * 60), delivery: .sent, basis: .general, document: document)
    }

    private func made(_ minutes: Double, id: String, status: MadeDocument.Status) -> MadeDocument {
        MadeDocument(id: id, name: "Marsz Niepodległości.pptx", kind: .deck, status: status, createdAt: t0.addingTimeInterval(minutes * 60),
                     deleteAfter: t0.addingTimeInterval(7 * 24 * 3600), sizeBytes: status == .ready ? 1000 : nil)
    }

    func testAFileTakesItsPlaceByTimeInsteadOfStayingUnderTheNewestMessage() {
        let messages = [message(0, "hej"), message(1, "cześć", sender: .doddy), message(60, "zrób prezentację"), message(61, "jasne", sender: .doddy)]
        let deck = LocalMadeFile(name: "Iława.pptx", title: "Iława", kind: "deck", createdAt: t0.addingTimeInterval(30 * 60))
        let server = made(2, id: docID, status: .ready)
        let items = ThreadTimeline.items(messages: messages, local: [deck], server: [server])
        XCTAssertEqual(items.map(\.id), [
            "m-\(messages[0].id.uuidString)", "m-\(messages[1].id.uuidString)", "s-\(docID)", "l-\(deck.id.uuidString)",
            "m-\(messages[2].id.uuidString)", "m-\(messages[3].id.uuidString)",
        ])
        guard case .message(let index, _) = items[4] else { return XCTFail("a message") }
        XCTAssertEqual(index, 2, "a bubble keeps its place in the thread for its run and day heading")
        XCTAssertEqual(items.last?.id, "m-\(messages[3].id.uuidString)", "the newest message is last, not an old file")
    }

    func testMessagesWithTheSameTimeKeepTheirOrderAndComeBeforeAFile() {
        let a = message(5, "a"), b = message(5, "b", sender: .doddy)
        let deck = LocalMadeFile(name: "x.pptx", title: "x", kind: "deck", createdAt: t0.addingTimeInterval(5 * 60))
        let items = ThreadTimeline.items(messages: [a, b], local: [deck], server: [])
        XCTAssertEqual(items.map(\.id), ["m-\(a.id.uuidString)", "m-\(b.id.uuidString)", "l-\(deck.id.uuidString)"])
        XCTAssertEqual(ThreadTimeline.items(messages: [], local: [], server: []), [])
    }

    func testTheBubbleFollowsWhatTheServerSays() throws {
        let url = try XCTUnwrap(URL(string: "https://doddy.example/v1/documents/\(docID)?exp=1&sig=x"))
        let file = ThreadDocument(url: url, name: "Marsz Niepodległości.pptx", kind: "deck")
        let saved = message(0, "Robię to dla ciebie: „Marsz Niepodległości.pptx”. Zajmie minutę lub dwie; otworzysz to tutaj.", sender: .doddy, document: file)

        XCTAssertEqual(ThreadFileState.of(file, in: []), .unknown)
        XCTAssertEqual(ThreadFileState.of(file, in: [made(0, id: "zzzzzzzzzzzzzzzzzzzzzzzz", status: .failed)]), .unknown)
        XCTAssertEqual(ThreadFileState.of(file, in: [made(0, id: docID, status: .working)]), .making)
        XCTAssertEqual(ThreadFileState.of(file, in: [made(0, id: docID, status: .ready)]), .ready)
        XCTAssertEqual(ThreadFileState.of(file, in: [made(0, id: docID, status: .failed)]), .failed)
        XCTAssertEqual(ThreadFileState.of(file, in: [made(0, id: docID, status: .interrupted)]), .failed)

        XCTAssertEqual(ThreadFileState.making.caption(for: saved, polish: true), saved.text, "while it is made: the words it was saved with")
        XCTAssertEqual(ThreadFileState.unknown.caption(for: saved, polish: true), saved.text)
        XCTAssertEqual(ThreadFileState.ready.caption(for: saved, polish: true), "Proszę, gotowe: „Marsz Niepodległości.pptx”.")
        XCTAssertEqual(ThreadFileState.ready.caption(for: saved, polish: false), "Here it is: “Marsz Niepodległości.pptx”.")
        let failed = try XCTUnwrap(ThreadFileState.failed.caption(for: saved, polish: true))
        XCTAssertTrue(failed.hasPrefix("Nie udało mi się zrobić „Marsz Niepodległości.pptx”."), failed)
        XCTAssertFalse(failed.contains("gotowe"), "a failed file is never called ready")
    }

    func testAFileFromTheMakeItCardKeepsNoCaption() throws {
        let url = try XCTUnwrap(URL(string: "https://doddy.example/v1/documents/\(docID)"))
        let file = ThreadDocument(url: url, name: "Plan.pdf", kind: "pdf")
        let card = message(0, "Plan.pdf", sender: .doddy, document: file)
        XCTAssertNil(ThreadFileState.ready.caption(for: card, polish: true))
        XCTAssertNotNil(ThreadFileState.failed.caption(for: card, polish: true), "a failure is said even there")
    }
}
