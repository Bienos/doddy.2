import XCTest
@testable import DoddyCore

/// Recipe to shopping list (ADR-305) and the "What Doddy did" rows of round 4's replies.
final class IngredientsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func list(open: [String], done: [String] = []) throws -> DoddyList {
        let record = try MemoryRecord(id: UUID(), rawText: "Shopping", source: .explicitText, category: .list, capturedAt: now)
        var items: [ListItem] = []
        for (position, text) in (open + done).enumerated() {
            items.append(ListItem(id: UUID(), listID: record.id, text: text, source: .typed, addedAt: now,
                                  doneAt: position >= open.count ? now : nil, position: position))
        }
        return DoddyList(record: record, items: items)
    }

    func testToolCallCleansAndDropsRepeats() {
        let json = #"{"list": "Shopping", "dish": "lasagne", "items": ["Pasta sheets", "pasta sheets", "  mince ", "", "Tomatoes"]}"#
        XCTAssertEqual(VoiceToolRequest.parse(name: "add_ingredients", parametersJSON: Data(json.utf8)),
                       .addIngredients(IngredientsProposal(list: "Shopping", dish: "lasagne", items: ["Pasta sheets", "mince", "Tomatoes"])))
        if case .invalid = VoiceToolRequest.parse(name: "add_ingredients", parametersJSON: Data(#"{"list": "Shopping", "dish": "x", "items": []}"#.utf8)) {} else {
            XCTFail("no items, no card")
        }
        XCTAssertEqual(IngredientsProposal.cleanedItems((1...40).map { "item \($0)" }).count, IngredientsProposal.maxItems)
        XCTAssertFalse(ConnectionPause.applies(to: .addIngredients(IngredientsProposal(list: "a", dish: "b", items: ["c"]))))
    }

    func testWhatIsAlreadyOpenStartsUnticked() throws {
        let shopping = try list(open: ["milk", "Mince"], done: ["tomatoes"])
        XCTAssertEqual(IngredientsProposal.alreadyOpen(["pasta", "mince", "tomatoes"], on: shopping), [1], "a ticked-off item isn't 'already there'")
    }

    func testTheReplySaysTheyWereSuggestions() {
        let item = ListItem(id: UUID(), listID: UUID(), text: "pasta", source: .voice, addedAt: now, doneAt: nil, position: 0)
        let reply = VoiceToolReply.ingredientsAdded(ListAddResult(added: [item], alreadyThere: [], tooLong: [], noRoom: []), list: "Shopping", dish: "lasagne", leftOut: ["salt"])
        // The list name and items sit between the data markers (review C4).
        XCTAssertTrue(reply.contains(ToolData.block(["Name: \"Shopping\"", "- pasta"])), reply)
        XCTAssertTrue(reply.hasPrefix("added to the list: 1 item."))
        XCTAssertTrue(reply.contains("unticked these (has them already)"))
        XCTAssertTrue(reply.contains("- salt"))
        XCTAssertTrue(reply.contains("Doddy's suggestions for this dish"))
        XCTAssertTrue(reply.contains("Dish: \"lasagne\""))
    }

    func testRoundFourRepliesLandOnHonestRows() {
        func outcome(_ reply: String, lookup: Bool = false) -> ActivityOutcome { ActivityEntry.outcome(of: reply, isLookup: lookup).0 }
        let item = ListItem(id: UUID(), listID: UUID(), text: "pasta", source: .voice, addedAt: now, doneAt: nil, position: 0)
        XCTAssertEqual(outcome(VoiceToolReply.ingredientsAdded(ListAddResult(added: [item], alreadyThere: [], tooLong: [], noRoom: []), list: "S", dish: "d", leftOut: [])), .done)
        XCTAssertEqual(outcome(VoiceToolReply.ingredientsDeclined), .declined)
        XCTAssertEqual(outcome(VoiceToolReply.ingredientsNoneTicked), .notDone)
        let spot = ParkingSpot(latitude: 1, longitude: 2, accuracyMeters: 10, savedAt: now, note: nil)
        XCTAssertEqual(outcome(VoiceToolReply.parkingSaved(spot, now: now, calendar: Calendar(identifier: .gregorian))), .done)
        XCTAssertEqual(outcome(VoiceToolReply.parkingCleared), .done)
        XCTAssertEqual(outcome(VoiceToolReply.parkingNothingToClear), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.parkingNotSaved), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.parkingDeclined), .declined)
        XCTAssertEqual(outcome(VoiceToolReply.reminderDetailsChanged("x", change: ReminderDetailsChange(priority: .high), due: nil)), .done)
        XCTAssertEqual(outcome(VoiceToolReply.reminderListNotFound("x", lists: [])), .notDone)
        XCTAssertEqual(outcome("completed: Todoist task \"Buy milk\" is done."), .done)
        XCTAssertEqual(outcome("moved: Todoist task \"Buy milk\" is now due tomorrow."), .done)
        XCTAssertEqual(outcome(VoiceToolReply.currency(CurrencyConversionRequest(amount: 1, from: "EUR", to: "PLN"), rates: nil, isLastKnown: false), lookup: true), .notDone)
    }
}
