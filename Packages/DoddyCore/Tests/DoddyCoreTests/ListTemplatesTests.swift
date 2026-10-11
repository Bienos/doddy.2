import XCTest
@testable import DoddyCore

/// List templates (ADR-334).
final class ListTemplatesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func list(_ name: String, open: [String], done: [String] = []) throws -> DoddyList {
        let record = try MemoryRecord(id: UUID(), rawText: name, source: .explicitText, category: .list, capturedAt: now)
        var items: [ListItem] = []
        for (position, text) in (open + done).enumerated() {
            items.append(ListItem(id: UUID(), listID: record.id, text: text, source: .typed, addedAt: now,
                                  doneAt: position >= open.count ? now : nil, position: position))
        }
        return DoddyList(record: record, items: items)
    }

    func testSaveKeepsItemsWithoutTicksAndReplacesBySameName() throws {
        var templates = ListTemplates()
        let packing = try list("Packing", open: ["Charger", "Passport"], done: ["Toothbrush"])
        guard case .saved(let first) = templates.save(packing) else { return XCTFail("not saved") }
        XCTAssertEqual(first.items, ["Charger", "Passport", "Toothbrush"])
        let again = try list("packing", open: ["Charger", "Sunglasses"])
        guard case .replaced(let second) = templates.save(again) else { return XCTFail("not replaced") }
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(templates.all.count, 1)
        XCTAssertEqual(templates.save(try list("Empty", open: [])), .empty)
        // Round trip through storage.
        XCTAssertEqual(ListTemplates(stored: templates.stored), templates)
        XCTAssertEqual(ListTemplates(stored: Data("nope".utf8)).all, [])
    }

    func testFindingAndStartingFromATemplate() throws {
        var templates = ListTemplates()
        _ = templates.save(try list("Packing", open: ["Charger", "Passport"]))
        _ = templates.save(try list("Weekly shop", open: ["Milk"]))
        XCTAssertEqual(templates.named("packing list")?.name, "Packing")
        XCTAssertEqual(templates.named("weekly shop")?.name, "Weekly shop")
        XCTAssertNil(templates.named("camping"))
        let packing = try XCTUnwrap(templates.named("Packing"))
        XCTAssertEqual(ListTemplates.items(from: packing, plus: ["passport", "Swimsuit"]), ["Charger", "Passport", "Swimsuit"])
        XCTAssertTrue(VoiceToolReply.templateNotFound("camping", templates: templates).contains("\"Packing\""))
        XCTAssertEqual(templates.promptLine, "List templates (start one with create_list and template): Packing, Weekly shop")
    }

    func testCreateListTakesATemplateName() {
        let json = #"{"name": "Packing for Kraków", "template": " Packing "}"#
        guard case .createList(let request) = VoiceToolRequest.parse(name: "create_list", parametersJSON: Data(json.utf8)) else {
            return XCTFail("not a create_list request")
        }
        XCTAssertEqual(request.template, "Packing")
        XCTAssertEqual(request.list, "Packing for Kraków")
    }
}
