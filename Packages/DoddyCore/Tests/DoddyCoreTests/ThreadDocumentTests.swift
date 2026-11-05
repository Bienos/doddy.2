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

    func testOnlyAWorkingOrReadyFileOnAnHTTPSLinkBecomesABubble() {
        XCTAssertNotNil(ThreadDocument(RunDocument(url: link, name: "a", kind: "doc", status: .ready)))
        XCTAssertNotNil(ThreadDocument(RunDocument(url: link, name: "a", kind: "doc", status: .working)))
        XCTAssertNil(ThreadDocument(RunDocument(url: link, name: "a", kind: "doc", status: .failed)))
        XCTAssertNil(ThreadDocument(RunDocument(url: URL(string: "http://doddy.example.com/d/abc")!, name: "a", kind: "doc", status: .ready)))
        XCTAssertNil(ThreadDocument(RunDocument(url: URL(string: "javascript:alert(1)")!, name: "a", kind: "doc", status: .ready)))
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
