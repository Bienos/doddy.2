import Foundation
import XCTest
@testable import DoddyCore

/// The tool catalog against the spec the live agent is built from (`voice-agent/tools.json`) and
/// the server's tool list (`backend/src/tools/catalog.ts`), ADR-444. A tool added, renamed or
/// changed in one place and not the others fails here.
final class ToolCatalogTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func spec() throws -> [RealtimeToolSpec] {
        try RealtimeToolCatalog.decode(Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/tools.json")))
    }

    // MARK: The spec and the catalog

    func testEverySpecToolHasADescriptorAndTheReverse() throws {
        let specNames = try spec().map(\.name)
        XCTAssertEqual(Set(specNames).count, specNames.count, "a tool is listed twice in tools.json")
        XCTAssertEqual(Set(ToolCatalog.all.map(\.name)).count, ToolCatalog.all.count, "a tool is listed twice in the catalog")
        XCTAssertEqual(Set(ToolCatalog.all.map(\.name)).subtracting(specNames), [], "in the app, not in tools.json")
        XCTAssertEqual(Set(specNames).subtracting(ToolCatalog.all.map(\.name)), [], "in tools.json, not in the app")
    }

    func testRunsOnMatchesTheSpec() throws {
        for tool in try spec() {
            XCTAssertEqual(ToolCatalog.descriptor(tool.name)?.runsOn, tool.runsOn, tool.name)
        }
    }

    func testConfirmOnScreenMatchesTheApproval() throws {
        // The spec tells the agent to wait for a tap; the app must show a card for exactly those.
        for tool in try spec() {
            let approval = try XCTUnwrap(ToolCatalog.descriptor(tool.name)?.approval, tool.name)
            let tap = approval == .card || approval == .serverApproval
            XCTAssertEqual(tool.confirmOnScreen, tap, "\(tool.name): confirm_on_screen vs \(approval)")
            // ASK-01: the spec says how the user answers, and it matches what the app asks for.
            XCTAssertEqual(tool.ask, tap ? .tap : .yesOrTap, tool.name)
        }
    }

    func testACardHasTimeToBeTapped() throws {
        // The agent's wait covers the user reading the card; a short timeout would end the call
        // before the tap and leave the change unanswered.
        // ASK-01: every tool waits for an answer now, reads included.
        for tool in try spec() {
            XCTAssertGreaterThanOrEqual(tool.timeoutSeconds, 60, tool.name)
        }
    }

    func testEveryPhoneToolIsRouted() throws {
        // A phone tool the app can't parse would leave the agent waiting until its timeout.
        for tool in ToolCatalog.all where tool.runsOn == .phone && tool.name != VoiceToolName.proposePlan {
            if case .unsupported = VoiceToolRequest.parse(name: tool.name, parametersJSON: Data("{}".utf8)) {
                XCTFail("\(tool.name) is in the catalog but VoiceToolRequest.parse doesn't know it")
            }
        }
    }

    // MARK: Rules between effect and approval

    func testNoChangeRunsWithoutACard() {
        // ASK-01: since 2026-10-18 list changes and the capability-gap row show a card too. Only
        // translator mode, which changes no data, may start on a spoken yes.
        let withoutCard = Set(ToolCatalog.all.filter { $0.effect != .lookup && $0.approval != .card && $0.approval != .serverApproval }.map(\.name))
        XCTAssertEqual(withoutCard, [VoiceToolName.startTranslator, VoiceToolName.stopTranslator])
        for name in withoutCard { XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .askFirst, name) }
    }

    func testLookupsAskFirst() {
        // ASK-01: reads ask too (a spoken yes or a tap). There is no approval that means "runs at once".
        for tool in ToolCatalog.all where tool.effect == .lookup {
            XCTAssertEqual(tool.approval, tool.isCloud ? .serverAsk : .askFirst, tool.name)
        }
    }

    func testEveryToolRunsOnThePhoneWhereTheAppCanAsk() throws {
        // ElevenLabs runs web tools itself, so the app could never ask before them (ASK-01).
        for tool in try spec() { XCTAssertEqual(tool.runsOn, .phone, tool.name) }
    }

    func testAccountWritesAreExactlyTheServerApprovedOnes() {
        let writes = Set(ToolCatalog.all.filter { $0.effect == .accountWrite }.map(\.name))
        let serverApproved = Set(ToolCatalog.all.filter { $0.approval == .serverApproval }.map(\.name))
        XCTAssertEqual(writes, CloudToolName.writes)
        XCTAssertEqual(serverApproved, CloudToolName.writes)
    }

    func testHandoffsShowACard() {
        for tool in ToolCatalog.all where tool.effect == .handoff {
            XCTAssertEqual(tool.approval, .card, tool.name)
        }
    }

    // MARK: The other registries

    func testPlanStepsAreChangesOnThePhoneOrAnAccount() {
        // The plan card approves its steps, so a step needs no card of its own; but only tools that
        // change something belong in a plan, and every one must be a known tool.
        for name in PlanTool.allowed {
            let tool = ToolCatalog.descriptor(name)
            XCTAssertNotNil(tool, "\(name) is allowed in plans but not in the catalog")
            XCTAssertEqual(tool?.runsOn, .phone, name)
            XCTAssertTrue(tool?.effect == .localChange || tool?.effect == .accountWrite, name)
        }
        XCTAssertEqual(Set(ToolCatalog.all.filter(\.planEligible).map(\.name)), Set(PlanTool.allowed))
    }

    func testEveryConnectionServesCatalogTools() {
        for connection in VoiceConnection.allCases {
            let tools = ToolCatalog.all.filter { $0.connection == connection }
            XCTAssertFalse(tools.isEmpty, "\(connection) serves no tool in the catalog")
            XCTAssertTrue(tools.allSatisfy { $0.runsOn == .phone && !$0.isCloud }, "\(connection)")
        }
    }

    func testCloudToolsMatchTheServer() throws {
        // backend/src/tools/catalog.ts is the server's authority on read and write; the iPhone only
        // mirrors it (CloudToolName). web_search lives in websearch.ts and is a read.
        let source = try String(contentsOf: repoRoot.appendingPathComponent("backend/src/tools/catalog.ts"), encoding: .utf8)
        let server = Self.serverRisks(source)
        XCTAssertFalse(server.isEmpty, "couldn't read CLOUD_TOOLS from catalog.ts")
        XCTAssertEqual(Set(server.keys).union([CloudToolName.webSearch]), CloudToolName.all)
        XCTAssertEqual(Set(server.filter { $0.value == "write" }.keys), CloudToolName.writes)
        let websearch = try String(contentsOf: repoRoot.appendingPathComponent("backend/src/tools/websearch.ts"), encoding: .utf8)
        XCTAssertTrue(websearch.contains("\"\(CloudToolName.webSearch)\""), "web_search not found in websearch.ts")
        for name in CloudToolName.all {
            XCTAssertEqual(ToolCatalog.descriptor(name)?.isCloud, true, name)
        }
    }

    func testTheReaderFindsNameRiskPairs() {
        let source = """
        const A: CloudToolDefinition = {
          name: "check_email",
          toolkit: "gmail",
          composioSlug: "X",
          risk: "read",
        };
        const B: CloudToolDefinition = {
          name: "draft_email",
          risk: "write",
        };
        """
        XCTAssertEqual(Self.serverRisks(source), ["check_email": "read", "draft_email": "write"])
    }

    /// `name` and `risk` of each top-level tool definition in catalog.ts (two-space indent).
    private static func serverRisks(_ source: String) -> [String: String] {
        var risks: [String: String] = [:]
        var name: String?
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: #/  name: "([a-z_]+)",/#) {
                name = String(match.1)
            } else if let match = line.wholeMatch(of: #/  risk: "(read|write)",/#), let current = name {
                risks[current] = String(match.1)
                name = nil
            }
        }
        return risks
    }
}
