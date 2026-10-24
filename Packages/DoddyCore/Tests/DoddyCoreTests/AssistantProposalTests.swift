import XCTest
@testable import DoddyCore

/// A file Doddy offers in Messages (ADR-606): offered as a card, made only after a tap, with exactly the words shown.
final class AssistantProposalTests: XCTestCase {
    private let request = AssistantRequest(sessionID: UUID(), userText: "Zrób mi prezentację")

    private func body(_ proposal: String?) -> GatewayHTTPResponse {
        let id = request.requestID.uuidString.lowercased()
        let extra = proposal.map { #","proposal":\#($0)"# } ?? ""
        return GatewayHTTPResponse(status: 200, body: Data(#"{"schemaVersion":1,"requestId":"\#(id)","text":"Mogę to zrobić jako prezentację.","citedMemoryIDs":[]\#(extra)}"#.utf8))
    }

    func testAProposalNeedsARealKindATitleAndARequestInsideTheLimits() {
        XCTAssertEqual(AssistantProposal.make(kind: "deck", title: "  Plan bety ", request: " Dziesięć slajdów "),
                       AssistantProposal(kind: .deck, title: "Plan bety", request: "Dziesięć slajdów"))
        for kind in ["doc", "spreadsheet", "pdf", "text"] {
            XCTAssertNotNil(AssistantProposal.make(kind: kind, title: "t", request: "r"), kind)
        }
        XCTAssertNil(AssistantProposal.make(kind: "none", title: "", request: ""))
        XCTAssertNil(AssistantProposal.make(kind: "video", title: "t", request: "r"), "only the kinds make_document knows")
        XCTAssertNil(AssistantProposal.make(kind: "deck", title: "", request: "r"))
        XCTAssertNil(AssistantProposal.make(kind: "deck", title: "t", request: "   "))
        XCTAssertNotNil(AssistantProposal.make(kind: "deck", title: String(repeating: "t", count: 120), request: String(repeating: "r", count: 1_500)))
        XCTAssertNil(AssistantProposal.make(kind: "deck", title: String(repeating: "t", count: 121), request: "r"))
        XCTAssertNil(AssistantProposal.make(kind: "deck", title: "t", request: String(repeating: "r", count: 1_501)))
        // Unicode scalars, as the tool counts them.
        XCTAssertNotNil(AssistantProposal.make(kind: "deck", title: String(repeating: "😀", count: 120), request: "r"))
        XCTAssertNil(AssistantProposal.make(kind: "deck", title: String(repeating: "😀", count: 121), request: "r"))
    }

    func testItRunsTheMakeDocumentToolWithExactlyTheWordsOnTheCard() throws {
        let proposal = try XCTUnwrap(AssistantProposal.make(kind: "deck", title: "Plan bety", request: "Dziesięć slajdów o becie."))
        let call = proposal.toolCall
        XCTAssertEqual(call.name, "make_document")
        XCTAssertEqual(call.arguments, ["kind": .string("deck"), "title": .string("Plan bety"), "request": .string("Dziesięć slajdów o becie.")])
        XCTAssertFalse(call.isWrite, "like the voice: nothing outside Doddy changes, so a card and a tap")
        XCTAssertEqual(proposal.label, "Deck")
    }

    func testTheWireProposalIsReadAndABadOneIsDroppedWhileTheAnswerStays() throws {
        let offered = try GatewayAssistantClient.interpret(body(#"{"kind":"pdf","title":"Umowa","request":"Jedna strona."}"#), for: request)
        XCTAssertEqual(offered.proposal, AssistantProposal(kind: .pdf, title: "Umowa", request: "Jedna strona."))
        XCTAssertEqual(offered.text, "Mogę to zrobić jako prezentację.")

        for bad in [#"{"kind":"video","title":"t","request":"r"}"#, #"{"kind":"deck","title":"","request":"r"}"#,
                    #"{"kind":"deck","title":"t","request":"\#(String(repeating: "r", count: 1_501))"}"#] {
            let reply = try GatewayAssistantClient.interpret(body(bad), for: request)
            XCTAssertNil(reply.proposal, bad)
            XCTAssertEqual(reply.text, "Mogę to zrobić jako prezentację.", "the answer is still shown")
        }
        XCTAssertNil(try GatewayAssistantClient.interpret(body(nil), for: request).proposal, "an older server sends none")
    }

    func testTheVerifiedAnswerKeepsTheProposalAndNoteCitationsStillWork() throws {
        let proposal = AssistantProposal(kind: .doc, title: "List", request: "Krótki list.")
        let verified = try CitationVerifier.verify(AssistantReply(text: "Mogę to zrobić.", proposal: proposal), for: request)
        XCTAssertEqual(verified.proposal, proposal)
        XCTAssertEqual(verified.basis, .general)
        XCTAssertNil(try CitationVerifier.verify(AssistantReply(text: "Cześć."), for: request).proposal)
    }
}
