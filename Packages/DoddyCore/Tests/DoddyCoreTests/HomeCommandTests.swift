import XCTest
@testable import DoddyCore

final class HomeCommandTests: XCTestCase {
    private let home = HomeSnapshot(
        accessories: [
            HomeAccessory(id: "a1", name: "Lamp", room: "Living room", kind: .light, reachable: true),
            HomeAccessory(id: "a2", name: "Lamp", room: "Bedroom", kind: .light, reachable: true),
            HomeAccessory(id: "a3", name: "Front door", room: "Hall", kind: .lock, reachable: true),
            HomeAccessory(id: "a4", name: "Heater plug", room: "Study", kind: .outlet, reachable: false),
            HomeAccessory(id: "a5", name: "Fan", room: nil, kind: .fan, reachable: true),
        ],
        scenes: [HomeScene(id: "s1", name: "Good night")])

    func testResolvesByNameAndRoom() {
        let result = HomeCommandRules.resolve(.power(on: false, name: "lamp", room: "living room"), in: home)
        XCTAssertEqual(result, .ready(.power(on: false, accessoryID: "a1", accessoryName: "Lamp", room: "Living room")))
    }

    func testSameNameInTwoRoomsIsAmbiguousNeverPicked() {
        guard case let .ambiguous(names) = HomeCommandRules.resolve(.power(on: true, name: "Lamp", room: nil), in: home) else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(names.count, 2)
    }

    func testLocksAreRefused() {
        guard case .refused = HomeCommandRules.resolve(.power(on: false, name: "Front door", room: nil), in: home) else {
            return XCTFail("expected refused")
        }
    }

    func testUnreachableAndUnknown() {
        XCTAssertEqual(HomeCommandRules.resolve(.power(on: true, name: "Heater plug", room: nil), in: home), .unreachable(name: "Heater plug"))
        XCTAssertEqual(HomeCommandRules.resolve(.power(on: true, name: "Toaster", room: nil), in: home), .notFound)
        XCTAssertEqual(HomeCommandRules.resolve(.scene(name: "Party"), in: home), .notFound)
    }

    func testSceneIsFoundIgnoringCaseAndAccents() {
        XCTAssertEqual(HomeCommandRules.resolve(.scene(name: "GOOD NIGHT"), in: home),
                       .ready(.runScene(sceneID: "s1", sceneName: "Good night")))
    }

    func testApprovalIsBoundToTheExactCommand() {
        let off = HomeCommand.power(on: false, accessoryID: "a1", accessoryName: "Lamp", room: nil)
        let on = HomeCommand.power(on: true, accessoryID: "a1", accessoryName: "Lamp", room: nil)
        XCTAssertTrue(HomeCommandRules.isApproved(off, approvedDigest: off.digest))
        XCTAssertFalse(HomeCommandRules.isApproved(on, approvedDigest: off.digest))
        XCTAssertFalse(HomeCommandRules.isApproved(off, approvedDigest: nil))
    }

    func testOnlyConfirmedCountsAsDone() {
        let command = HomeCommand.runScene(sceneID: "s1", sceneName: "Good night")
        XCTAssertTrue(VoiceToolReply.home(command, outcome: .confirmed).hasPrefix("changed:"))
        XCTAssertTrue(VoiceToolReply.home(command, outcome: .unknown).hasPrefix("unknown"))
        XCTAssertTrue(VoiceToolReply.home(command, outcome: .unknown).contains("don't try again"))
        XCTAssertTrue(VoiceToolReply.home(command, outcome: .failed("timeout")).hasPrefix("failed"))
    }

    func testCardTextUsesHomeKitNames() {
        XCTAssertEqual(HomeCommand.power(on: false, accessoryID: "a1", accessoryName: "Lamp", room: "Bedroom").cardText,
                       "Turn off Lamp in Bedroom?")
    }

    func testRepliesReadBackAsTheRightActivityOutcome() {
        let command = HomeCommand.runScene(sceneID: "s1", sceneName: "Good night")
        func outcome(_ reply: String) -> ActivityOutcome { ActivityLog.outcome(of: reply, isLookup: false).0 }
        XCTAssertEqual(outcome(VoiceToolReply.home(command, outcome: .confirmed)), .done)
        XCTAssertEqual(outcome(VoiceToolReply.home(command, outcome: .unknown)), .notSure)
        XCTAssertEqual(outcome(VoiceToolReply.home(command, outcome: .failed("x"))), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.homeDeclined), .declined)
        XCTAssertEqual(outcome(VoiceToolReply.homeNotFound), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.homeAmbiguous(["a", "b"])), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.homeRefused("no")), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.homeUnreachable("Lamp")), .notDone)
    }

    // MARK: The voice tool

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.controlHome, parametersJSON: Data(json.utf8), now: Date(), calendar: .current)
    }

    func testParsesPowerAndSceneRequests() {
        XCTAssertEqual(parse(#"{"action":"off","name":"lamp","room":"Bedroom"}"#), .controlHome(.power(on: false, name: "lamp", room: "Bedroom")))
        XCTAssertEqual(parse(#"{"action":"ON","name":"Fan"}"#), .controlHome(.power(on: true, name: "Fan", room: nil)))
        XCTAssertEqual(parse(#"{"action":"scene","name":"Good night"}"#), .controlHome(.scene(name: "Good night")))
    }

    func testBadArgumentsRunNothing() {
        for json in ["{}", #"{"action":"on"}"#, #"{"action":"unlock","name":"Front door"}"#, #"{"action":"on","name":"  "}"#] {
            guard case .invalid = parse(json) else { return XCTFail("expected invalid for \(json)") }
        }
    }

    func testTheToolNeedsAnExactCardAndTheHomeConnection() {
        let request = VoiceToolRequest.controlHome(.scene(name: "Good night"))
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.controlHome), .home)
        XCTAssertEqual(AskFirst.need(for: request), .ownPayloadCard)
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.controlHome)?.approval, .card)
        XCTAssertEqual(ActivityRequest.describe(request, calendar: .current)?.app, .home)
    }
}
