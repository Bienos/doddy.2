import DoddyCore
import XCTest

final class ListsTests: XCTestCase {
    private let listID = UUID()

    private func item(_ text: String, done: Bool = false, position: Int = 0) -> ListItem {
        ListItem(id: UUID(), listID: listID, text: text, source: .voice, addedAt: Date(timeIntervalSince1970: 0),
                 doneAt: done ? Date(timeIntervalSince1970: 60) : nil, position: position)
    }

    private func list(_ name: String, _ items: [ListItem] = []) throws -> DoddyList {
        DoddyList(record: try MemoryRecord(id: UUID(), rawText: name, source: .explicitVoice, category: .list,
                                           capturedAt: Date(timeIntervalSince1970: 0)), items: items)
    }

    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    // MARK: Matching

    func testListNamesMatchIgnoringCaseAccentsAndTheWordList() throws {
        let lists = [try list("Shopping"), try list("Wyjazd do Krakowa"), try list("Gift ideas")]
        XCTAssertEqual(ListMatch.list(named: "shopping", in: lists), .one(lists[0]))
        XCTAssertEqual(ListMatch.list(named: "my shopping list", in: lists), .one(lists[0]))
        XCTAssertEqual(ListMatch.list(named: "wyjazd do krakowa", in: lists), .one(lists[1]))
        XCTAssertEqual(ListMatch.list(named: "Wyjazd do Krakowa!", in: lists), .one(lists[1]))
        XCTAssertEqual(ListMatch.list(named: "groceries", in: lists), .none)
        // Never "the closest": a part of a name is not a match.
        XCTAssertEqual(ListMatch.list(named: "gift", in: lists), .none)
    }

    func testItemsMatchExactlyThenByAllWordsAndNeverGuess() {
        let items = [item("mleko 2 l"), item("oat milk"), item("milk chocolate"), item("eggs"), item("Żółty ser")]
        XCTAssertEqual(ListMatch.item("Eggs", in: items), .one(items[3]))
        XCTAssertEqual(ListMatch.item("the eggs", in: items), .one(items[3]))
        XCTAssertEqual(ListMatch.item("zolty ser", in: items), .one(items[4]))
        XCTAssertEqual(ListMatch.item("mleko", in: items), .one(items[0]))
        XCTAssertEqual(ListMatch.item("milk", in: items), .several([items[1], items[2]]))
        XCTAssertEqual(ListMatch.item("oat milk", in: items), .one(items[1]))
        XCTAssertEqual(ListMatch.item("bread", in: items), .none)
        // Different languages don't match: "milk" is not "mleko".
        XCTAssertFalse(ListMatch.item("milk", in: [items[0]]) == .one(items[0]))
    }

    func testDuplicates() {
        XCTAssertTrue(ListMatch.isDuplicate("Milk", of: ["milk"]))
        XCTAssertTrue(ListMatch.isDuplicate("the milk", of: ["milk"]))
        XCTAssertFalse(ListMatch.isDuplicate("oat milk", of: ["milk"]))
    }

    // MARK: List text

    func testSummaryTextAndShareText() throws {
        let shopping = try list("Shopping", [item("milk", position: 0), item("eggs", position: 1), item("bread", done: true, position: 2)])
        XCTAssertEqual(shopping.summary, "2 left · 1 done")
        XCTAssertEqual(shopping.text, "Shopping: milk, eggs")
        XCTAssertEqual(shopping.shareText, "Shopping\n- milk\n- eggs")
        XCTAssertEqual(try list("Empty").summary, "Empty")
        XCTAssertEqual(try list("Done", [item("x", done: true)]).text, "Done: nothing left")
        XCTAssertEqual(try ListText.checkedName("  Packing  "), "Packing")
        XCTAssertThrowsError(try ListText.checkedName("   "))
        XCTAssertThrowsError(try ListText.checkedName(String(repeating: "x", count: ListLimits.nameLength + 1)))
    }

    // MARK: Voice tools

    func testParsesTheListTools() {
        XCTAssertEqual(parse(VoiceToolName.addToList, #"{"list":"Shopping","items":["milk"," eggs ",""]}"#),
                       .addToList(ListVoiceRequest(list: "Shopping", items: ["milk", "eggs"])))
        XCTAssertEqual(parse(VoiceToolName.addToList, #"{"list":"Shopping","items":"milk"}"#),
                       .addToList(ListVoiceRequest(list: "Shopping", items: ["milk"])))
        XCTAssertEqual(parse(VoiceToolName.readList, #"{"list":"Shopping"}"#), .readList(name: "Shopping"))
        XCTAssertEqual(parse(VoiceToolName.checkOff, #"{"list":"Shopping","items":["eggs"]}"#),
                       .checkOff(ListVoiceRequest(list: "Shopping", items: ["eggs"])))
        XCTAssertEqual(parse(VoiceToolName.removeFromList, #"{"list":"Shopping","items":["eggs"]}"#),
                       .removeFromList(ListVoiceRequest(list: "Shopping", items: ["eggs"])))
        XCTAssertEqual(parse(VoiceToolName.createList, #"{"name":"Kraków","items":["paszport"]}"#),
                       .createList(ListVoiceRequest(list: "Kraków", items: ["paszport"])))
        XCTAssertEqual(parse(VoiceToolName.createList, #"{"name":"Kraków"}"#),
                       .createList(ListVoiceRequest(list: "Kraków", items: [])))
        for (name, json) in [(VoiceToolName.addToList, #"{"list":"Shopping"}"#), (VoiceToolName.addToList, #"{"items":["x"]}"#),
                             (VoiceToolName.checkOff, #"{"list":"Shopping","items":[]}"#), (VoiceToolName.readList, "{}")] {
            guard case .invalid = parse(name, json) else { return XCTFail("expected invalid: \(name) \(json)") }
        }
        // Lists never touch another app, so "Pause all connections" doesn't stop them.
        XCTAssertFalse(ConnectionPause.applies(to: .readList(name: "x")))
        // Translator mode refuses them like any other tool.
        XCTAssertFalse(TranslatorPolicy.allows(.addToList(ListVoiceRequest(list: "x", items: ["y"]))))
        XCTAssertEqual(ActivityRequest.describe(.addToList(ListVoiceRequest(list: "Shopping", items: ["milk"])), calendar: .current)?.title, "Add to a list")
    }

    func testRepliesUseTheVerifiedPrefixes() throws {
        let added = item("eggs")
        let reply = VoiceToolReply.listAdded(
            ListAddResult(added: [added], alreadyThere: ["milk"], tooLong: [], noRoom: []), list: "Shopping")
        XCTAssertEqual(reply, "added to \"Shopping\": eggs. Already on the list, not added again: milk.")
        XCTAssertTrue(VoiceToolReply.listAdded(ListAddResult(added: [], alreadyThere: ["milk"], tooLong: [], noRoom: []), list: "S").hasPrefix("not added:"))
        XCTAssertTrue(VoiceToolReply.listNotFound("groceries", lists: [try list("Shopping")]).contains("\"Shopping\""))
        let changed = VoiceToolReply.listChanged(
            verb: "ticked", changed: [item("eggs")], list: "Shopping", notFound: ["bread"],
            ambiguous: [(said: "milk", options: [item("oat milk"), item("milk chocolate")])])
        XCTAssertTrue(changed.hasPrefix("ticked on \"Shopping\": eggs."))
        XCTAssertTrue(changed.contains("\"milk\" matches several items (\"oat milk\", \"milk chocolate\"): not ticked; ask the user which one."))
        XCTAssertTrue(changed.contains("Not on the list: bread."))

        let long = try list("Long", (0..<12).map { item("item \($0)", position: $0) })
        let read = VoiceToolReply.listRead(long)
        XCTAssertTrue(read.contains("12 open"))
        XCTAssertTrue(read.contains("and 2 more"))
        XCTAssertFalse(read.contains("item 10"))
    }

    func testListsPromptHasNamesAndCountsOnly() throws {
        XCTAssertEqual(ListsPrompt.render([]), "(no lists yet)")
        let text = ListsPrompt.render([try list("Shopping", [item("secret code 1234"), item("x", done: true)])])
        XCTAssertEqual(text, "- Shopping (1 open, 1 ticked)")
        XCTAssertFalse(text.contains("1234"))
    }

    func testListIsNeverANoteType() {
        XCTAssertFalse(MemoryCategory.noteCategories.contains(.list))
        XCTAssertTrue(MemoryCategory.allCases.contains(.list))
    }

    func testPlainTextExportIncludesItems() throws {
        let shopping = try list("Shopping", [item("milk"), item("bread", done: true, position: 1)])
        let text = MemoryExport.plainText([], lists: [shopping], exportedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.contains("## Shopping\n[ ] milk\n[x] bread"))
    }
}

extension ListsTests {
    func testMarkdownExportAddsListsAsTaskLists() throws {
        let shopping = DoddyList(
            record: try MemoryRecord(id: UUID(), rawText: "Shopping", source: .explicitText, category: .list, capturedAt: Date(timeIntervalSince1970: 0)),
            items: [ListItem(id: UUID(), listID: UUID(), text: "milk", source: .typed, addedAt: Date(timeIntervalSince1970: 0), doneAt: nil, position: 0),
                    ListItem(id: UUID(), listID: UUID(), text: "bread", source: .typed, addedAt: Date(timeIntervalSince1970: 0), doneAt: Date(timeIntervalSince1970: 9), position: 1)])
        let text = MarkdownExport.markdown([], lists: [shopping], exportedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.contains("# Lists\n\n## Shopping\n\n- [ ] milk\n- [x] bread"))
        XCTAssertFalse(MarkdownExport.markdown([], exportedAt: Date()).contains("# Lists"))
    }
}
