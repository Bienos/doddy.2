import XCTest
@testable import DoddyCore

final class LocalMessageActionTests: XCTestCase {
    func testAllowlistRejectsExtraKeysTypesAndOversizedPayloads() throws {
        for (name, json) in [
            ("delete_memory", #"{"id":"x"}"#), ("save_memory", #"{"text":"hello","send":true}"#),
            ("save_memory", #"{"text":["hello"]}"#), ("add_to_list", #"{"list":"Shop","items":"milk"}"#),
            ("create_list", #"{"name":"Shop","items":[""]}"#), ("save_memory", String(repeating: "x", count: 12_001))
        ] { XCTAssertNil(LocalMessageAction.make(name: name, parametersJSON: json)) }
        let action = try XCTUnwrap(LocalMessageAction.make(name: "save_memory", parametersJSON: #"{"text":"Exact original note"}"#))
        XCTAssertEqual(action.request, .saveMemory(text: "Exact original note"))
        XCTAssertEqual(action.card(polish: false).lines, ["Exact original note"])
    }

    func testEachAllowedActionUsesTheVoiceParserAndPayloadCard() throws {
        let payloads = ["save_memory": #"{"text":"My note"}"#, "search_memories": #"{"query":"dentist"}"#,
            "create_list": #"{"name":"Shop","items":["milk"]}"#, "read_list": #"{"list":"Shop"}"#,
            "add_to_list": #"{"list":"Shop","items":["milk"]}"#, "check_off": #"{"list":"Shop","items":["milk"]}"#,
            "remove_from_list": #"{"list":"Shop","items":["milk"]}"#, "create_reminder": #"{"title":"Call Mum"}"#]
        for name in LocalMessageAction.Name.allCases {
            let payload = try XCTUnwrap(payloads[name.rawValue])
            let action = try XCTUnwrap(LocalMessageAction.make(name: name.rawValue, parametersJSON: payload))
            XCTAssertEqual(action.request, VoiceToolRequest.parse(name: name.rawValue, parametersJSON: Data(payload.utf8)))
            XCTAssertFalse(action.card(polish: false).confirmLabel.isEmpty)
            XCTAssertTrue(action.canExecute)
        }
    }

    func testOfferTextNamesTheOfferAndNeverClaimsItWasDone() throws {
        let list = try XCTUnwrap(LocalMessageAction.make(name: "create_list", parametersJSON: #"{"name":"Weekend shopping","items":["Oat milk","Eggs"]}"#))
        XCTAssertEqual(list.offerText(polish: false),
                       "Create this list?\nWeekend shopping\n\nNothing changes until you confirm it on the card. The card lasts 5 minutes and is gone once Messages closes.")
        let polish = list.offerText(polish: true)
        XCTAssertTrue(polish.hasPrefix("Utworzyć listę?\nWeekend shopping"))
        XCTAssertTrue(polish.contains("Nic się nie zmieni"))
        for name in LocalMessageAction.Name.allCases {
            let text = try XCTUnwrap(LocalMessageAction.make(name: name.rawValue, parametersJSON: name == .createReminder
                ? #"{"title":"Call Mum"}"# : name == .saveMemory ? #"{"text":"x"}"# : name == .searchMemories ? #"{"query":"x"}"#
                : name == .readList ? #"{"list":"x"}"# : name == .createList ? #"{"name":"x","items":["y"]}"# : #"{"list":"x","items":["y"]}"#))
                .offerText(polish: false).lowercased()
            for claim in ["has been", "was ", "done", " added", "created", "removed", "checked off", "saved note"] {
                XCTAssertFalse(text.contains(claim), "\(name.rawValue) offer must not say '\(claim)'")
            }
        }
    }

    func testActionRepliesRequireOptInAndInvalidProposalsAreDropped() throws {
        let id = UUID()
        let body = try JSONSerialization.data(withJSONObject: ["schemaVersion":1, "requestId":id.uuidString.lowercased(), "text":"Offer", "citedMemoryIDs":[],
            "localAction":["name":"save_memory", "parametersJSON":#"{"text":"Exact note"}"#]])
        let response = GatewayHTTPResponse(status: 200, body: body)
        let plain = AssistantRequest(sessionID: UUID(), userText: "Save note", requestID: id)
        XCTAssertNil(try GatewayAssistantClient.interpret(response, for: plain).localAction)
        let optedIn = AssistantRequest(sessionID: UUID(), userText: "Save note", requestID: id, localActions: .init())
        XCTAssertEqual(try GatewayAssistantClient.interpret(response, for: optedIn).localAction?.name, .saveMemory)
    }
}
