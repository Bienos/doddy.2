import XCTest
@testable import DoddyCore

/// ADR-445: the typed tool table agrees with the voice spec (`voice-agent/tools.json`), with the
/// server's own read/write list (`backend/src/tools/catalog.ts`, `websearch.ts`) and with the plan
/// rules. A tool added or changed in one place and not the others fails here.
final class ToolCatalogTests: XCTestCase {
    private func spec() throws -> [RealtimeToolSpec] {
        try RealtimeToolCatalog.decode(Data(contentsOf: Fixtures.root.appendingPathComponent("voice-agent/tools.json")))
    }

    // MARK: Against the voice spec

    func testEverySpecToolIsInTheCatalogAndNothingElse() throws {
        let names = Set(try spec().map(\.name))
        XCTAssertEqual(Set(ToolCatalog.all.keys).subtracting(names), [], "in the catalog but not in tools.json")
        XCTAssertEqual(names.subtracting(ToolCatalog.all.keys), [], "in tools.json but not in the catalog")
    }

    func testWhereEachToolRunsMatchesTheSpec() throws {
        for tool in try spec() {
            XCTAssertEqual(ToolCatalog.descriptor(tool.name)?.runsOn, tool.runsOn, tool.name)
        }
    }

    func testOnScreenConfirmationMatchesTheSpecForEveryTool() throws {
        for tool in try spec() {
            let approval = try XCTUnwrap(ToolCatalog.descriptor(tool.name)?.approval, tool.name)
            XCTAssertEqual(approval != .none, tool.confirmOnScreen,
                           "\(tool.name): tools.json confirm_on_screen=\(tool.confirmOnScreen), catalog \(approval)")
        }
    }

    // MARK: Approval rules (DOD-07)

    func testEveryChangeHasACardUnlessItsExemptionIsRecorded() {
        for tool in ToolCatalog.all.values where tool.changesSomething && tool.approval == .none {
            let reason = ToolCatalog.changesWithoutCard[tool.name]
            XCTAssertNotNil(reason, "\(tool.name) changes something without a card and has no recorded decision")
            XCTAssertFalse(reason?.isEmpty ?? true)
        }
        // The exemptions are local changes only: never an account write or a hand-over.
        for name in ToolCatalog.changesWithoutCard.keys {
            XCTAssertEqual(ToolCatalog.descriptor(name)?.effect, .localChange, name)
            XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, ToolApproval.none, name)
        }
    }

    func testAccountWritesAlwaysNeedTheServersApprovalAndOnlyThey() {
        for tool in ToolCatalog.all.values {
            XCTAssertEqual(tool.effect == .accountWrite, CloudToolName.writes.contains(tool.name), tool.name)
            XCTAssertEqual(tool.approval == .serverApprovedCard, tool.effect == .accountWrite, tool.name)
        }
    }

    func testHandOversAlwaysShowACardAndLookupsNever() {
        for tool in ToolCatalog.all.values {
            if tool.effect == .handoff { XCTAssertEqual(tool.approval, .card, tool.name) }
            if tool.effect == .lookup { XCTAssertEqual(tool.approval, ToolApproval.none, tool.name) }
        }
    }

    func testPlanStepsAreChangesThatFinishInsideDoddy() {
        XCTAssertFalse(PlanTool.allowed.contains(VoiceToolName.proposePlan))
        for name in PlanTool.allowed {
            let tool = ToolCatalog.descriptor(name)
            XCTAssertNotNil(tool, name)
            XCTAssertTrue(tool?.effect == .localChange || tool?.effect == .accountWrite, "\(name): \(String(describing: tool?.effect))")
            XCTAssertTrue(tool?.canBePlanStep ?? false)
        }
    }

    // MARK: Against the server's own list

    /// `name: "x"` followed within a few lines by `risk: "read"|"write"` in backend/src/tools/catalog.ts.
    private func backendRisks() throws -> [String: String] {
        let text = try String(contentsOf: Fixtures.root.appendingPathComponent("backend/src/tools/catalog.ts"), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        var risks: [String: String] = [:]
        func quoted(_ line: String, key: String) -> String? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key): \"") else { return nil }
            let rest = trimmed.dropFirst(key.count + 3)
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        for (i, line) in lines.enumerated() {
            guard let name = quoted(line, key: "name") else { continue }
            for next in lines[(i + 1)..<min(i + 8, lines.count)] {
                if quoted(next, key: "name") != nil { break }
                if let risk = quoted(next, key: "risk") { risks[name] = risk; break }
            }
        }
        return risks
    }

    func testTheServerAgreesWhichOnlineToolsWrite() throws {
        let risks = try backendRisks()
        XCTAssertEqual(risks.count, CloudToolName.all.count - 1, "every online-account tool but web_search is in catalog.ts")
        for (name, risk) in risks {
            let tool = try XCTUnwrap(ToolCatalog.descriptor(name), name)
            XCTAssertEqual(risk == "write", tool.effect == .accountWrite, "\(name): server says \(risk), catalog \(tool.effect)")
        }
        // Web search lives in websearch.ts and only reads.
        let web = try String(contentsOf: Fixtures.root.appendingPathComponent("backend/src/tools/websearch.ts"), encoding: .utf8)
        XCTAssertTrue(web.contains(CloudToolName.webSearch))
        XCTAssertEqual(ToolCatalog.descriptor(CloudToolName.webSearch)?.effect, .lookup)
    }

    // MARK: Derived facts stay derived

    func testConnectionsAndPlanEligibilityComeFromTheExistingConstants() {
        for tool in ToolCatalog.all.values {
            XCTAssertEqual(tool.connection, VoiceConnection.serving(tool.name), tool.name)
            XCTAssertEqual(tool.canBePlanStep, PlanTool.allowed.contains(tool.name), tool.name)
            XCTAssertEqual(tool.isOnlineAccountTool, CloudToolName.all.contains(tool.name), tool.name)
        }
        XCTAssertNil(ToolCatalog.descriptor("fly_a_drone"))
    }
}
