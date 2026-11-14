import XCTest
@testable import DoddyCore

/// A file Doddy made from a Messages card, kept in the thread (ADR-606).
final class ThreadDocumentTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)
    private let link = URL(string: "https://doddy.example.com/d/abc")!

    func testAFileBubbleIsADoddyMessageNamedAfterTheFileAndNotFromTheNotes() throws {
        let document = try XCTUnwrap(ThreadDocument(RunDocument(url: link, name: "Plan bety.pptx", kind: "deck", status: .working)))
        let message = ThreadMessage.file(document, now: t0)
        XCTAssertEqual(message.sender, .doddy)
        XCTAssertEqual(message.text, "Plan bety.pptx")
        XCTAssertEqual(message.delivery, .sent)
        XCTAssertEqual(message.basis, .general)
        XCTAssertEqual(message.document, document)
        XCTAssertEqual(document.label, "Deck")
        let unnamed = ThreadMessage.file(ThreadDocument(url: link, name: "  ", kind: "pdf"), now: t0)
        XCTAssertEqual(unnamed.text, "PDF", "never an empty text")
    }

    func testAFileBubbleSaysWhatTheFileIsWhenItIsKnown() throws {
        // 12 Nov 2026: the brief the person said yes to becomes the bubble's words; the name stays on the file's card.
        let document = ThreadDocument(url: link, name: "Kraków.pptx", kind: "deck")
        let message = ThreadMessage.file(document, about: "  Six slides on\nKraków's history\tfor a school talk. ", now: t0)
        XCTAssertEqual(message.text, "Six slides on Kraków's history for a school talk.")
        XCTAssertEqual(ThreadDelivery.caption(of: message), "Six slides on Kraków's history for a school talk.", "shown above the file's card")
        XCTAssertEqual(ThreadMessage.file(document, about: "   ", now: t0).text, "Kraków.pptx", "nothing to say: the name, as before")
        XCTAssertNil(ThreadDelivery.caption(of: ThreadMessage.file(document, now: t0)))

        let long = String(repeating: "słowo ", count: 100)
        let clipped = try XCTUnwrap(ThreadMessage.fileAbout(long))
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertLessThanOrEqual(clipped.count, ThreadMessage.fileAboutLimit + 1)
        XCTAssertFalse(clipped.dropLast().hasSuffix(" "), "cut at a word")
    }

    func testOnlyAWorkingOrReadyFileOnAnHTTPSLinkBecomesABubble() {
        XCTAssertNotNil(ThreadDocument(RunDocument(url: link, name: "a", kind: "doc", status: .ready)))
        XCTAssertNotNil(ThreadDocument(RunDocument(url: link, name: "a", kind: "doc", status: .working)))
        XCTAssertNil(ThreadDocument(RunDocument(url: link, name: "a", kind: "doc", status: .failed)))
        XCTAssertNil(ThreadDocument(RunDocument(url: URL(string: "http://doddy.example.com/d/abc")!, name: "a", kind: "doc", status: .ready)))
        XCTAssertNil(ThreadDocument(RunDocument(url: URL(string: "javascript:alert(1)")!, name: "a", kind: "doc", status: .ready)))
    }

    func testTheFilesIDIsReadFromItsLinkAndNothingElseCounts() {
        let id = "Abcdefghijklmnopqrstuv-_"
        XCTAssertEqual(id.count, 24)
        let signed = URL(string: "https://doddy.example.com/v1/documents/\(id)?exp=1792000000&sig=abc")!
        XCTAssertEqual(ThreadDocument(url: signed, name: "a", kind: "doc").documentID, id)
        XCTAssertNil(ThreadDocument(url: link, name: "a", kind: "doc").documentID, "not a documents link")
        let short = URL(string: "https://doddy.example.com/v1/documents/abc")!
        XCTAssertNil(ThreadDocument(url: short, name: "a", kind: "doc").documentID)
        let elsewhere = URL(string: "https://doddy.example.com/v1/other/\(id)")!
        XCTAssertNil(ThreadDocument(url: elsewhere, name: "a", kind: "doc").documentID)
        let odd = URL(string: "https://doddy.example.com/v1/documents/Abcdefghijklmnopqrstu%2F%2E")!
        XCTAssertNil(ThreadDocument(url: odd, name: "a", kind: "doc").documentID, "a path trick is not an id")
    }

    func testAFileBubbleIsNotSentToTheModelAsSomethingDoddySaid() {
        let doc = ThreadMessage.file(ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck"), now: t0.addingTimeInterval(1))
        let question = ThreadMessage(sender: .user, text: "Zrób prezentację", createdAt: t0, delivery: .sent)
        let turns = ThreadRules.history(from: [question, doc], before: t0.addingTimeInterval(60))
        XCTAssertEqual(turns.map(\.text), ["Zrób prezentację"])
    }

    func testTheThreadExportAndAnOlderExportBothRead() throws {
        let document = ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck")
        let message = ThreadMessage.file(document, now: t0)
        let decoded = try JSONDecoder().decode(ThreadMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.document, document)
        let older = #"{"id":"\#(UUID().uuidString)","sender":"doddy","text":"x","createdAt":0,"delivery":"sent","basis":"general","noteIDs":[],"notesSent":0,"notesSearchFailed":false}"#
        XCTAssertNil(try JSONDecoder().decode(ThreadMessage.self, from: Data(older.utf8)).document)
    }
}
