import XCTest
@testable import DoddyCore

/// Doddy in the car (ADR-338): look-ups run, two local writes wait for a spoken yes, the rest waits.
final class CarProfileTests: XCTestCase {
    private func request(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    func testLookUpsRun() {
        XCTAssertEqual(CarProfile.decision(for: request("search_memories", #"{"query": "gate code"}"#)), .run)
        XCTAssertEqual(CarProfile.decision(for: request("read_calendar", #"{"range": "today"}"#)), .run)
        XCTAssertEqual(CarProfile.decision(for: request("parking_spot", #"{"action": "find"}"#)), .run)
        XCTAssertEqual(CarProfile.decision(for: request("check_email", #"{}"#)), .run)
        // ADR-440: writing down a category of what Doddy can't do touches none of the user's data.
        XCTAssertEqual(CarProfile.decision(for: request("note_capability_gap", #"{"category": "music"}"#)), .run)
    }

    func testOnlyNotesAndListItemsAskAloud() {
        XCTAssertEqual(CarProfile.decision(for: request("save_memory", #"{"text": "Gate code 4512"}"#)),
                       .askAloud(readBack: "I'll save this note: \u{201C}Gate code 4512\u{201D}. Say yes to save it, or no."))
        guard case .askAloud(let readBack) = CarProfile.decision(for: request("add_to_list", #"{"list": "Shopping", "items": ["milk", "eggs"]}"#)) else {
            return XCTFail("list add should ask aloud")
        }
        XCTAssertTrue(readBack.contains("\u{201C}milk\u{201D}, \u{201C}eggs\u{201D}") && readBack.contains("\u{201C}Shopping\u{201D}"))
    }

    func testEverythingElseThatChangesSomethingWaits() {
        for (name, json) in [
            ("create_reminder", #"{"title": "Call mum", "due": "2030-01-01T09:00"}"#),
            ("set_timer", #"{"minutes": 5}"#),
            ("draft_email", #"{"to": "a@b.example", "subject": "Hi", "body": "Hello"}"#),
            ("parking_spot", #"{"action": "save"}"#),
            ("check_off", #"{"list": "Shopping", "items": ["milk"]}"#),
            ("draft_message", #"{"to": "Marta", "body": "On my way", "channel": "text"}"#),
        ] {
            guard case .refuse = CarProfile.decision(for: request(name, json)) else {
                return XCTFail("\(name) should wait until the user isn't driving")
            }
        }
        XCTAssertTrue(VoiceToolReply.notInTheCar("x").hasPrefix("not in the car:"))
    }

    func testOnlyAPlainYesCounts() {
        for yes in ["Yes", "yes.", " Yes please! ", "tak", "Tak, proszę", "zapisz"] {
            XCTAssertTrue(CarConfirmation.isYes(yes), yes)
        }
        for no in ["no", "", "yes but change it to 4513", "maybe", "nie", "yes no", "uh"] {
            XCTAssertFalse(CarConfirmation.isYes(no), no)
        }
    }
}

/// Home Screen quick actions (ADR-339).
final class QuickActionTests: XCTestCase {
    func testParkingOnlyWithASpotAndTypesRoundTrip() {
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: false), [.talk, .newNote, .find])
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: true).last, .parking)
        for action in QuickAction.allCases { XCTAssertEqual(QuickAction(rawValue: action.rawValue), action) }
        XCTAssertNil(QuickAction(rawValue: "doddy.quick.deleteEverything"))
    }
}
