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
            // ASK-01: the spec says how the user answers, and it matches what the app asks for. Since
            // decision 2026-11-11-asked-for-runs-at-once a tool either waits for a tap or runs at once:
            // no approval and no spec entry is left that a spoken yes answers.
            XCTAssertTrue(tap || approval == .runsNow, "\(tool.name): \(approval) is neither a tap nor at once")
            XCTAssertEqual(tool.ask, tap ? .tap : .runsNow, tool.name)
            XCTAssertEqual(tool.ask == .runsNow, AskFirst.runsAtOnce(tool.name), tool.name)
        }
        XCTAssertEqual(try spec().filter { $0.ask == .yesOrTap }.map(\.name), [], "no tool is yes_or_tap any more")
    }

    func testACardHasTimeToBeTapped() throws {
        // The agent's wait covers the user reading the card; a short timeout would end the call
        // before the tap and leave the change unanswered. Every tool that doesn't run at once waits.
        for tool in try spec() where tool.ask != .runsNow {
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

    func testOnlyDoddysOwnSmallActionsRunWithoutACard() {
        // Everything that is not a lookup shows a card, except: Doddy's own small things that are undone
        // in one step (`AskFirst.ownSmallActions`: his stopwatch, focus timer and wind-down, adding to or
        // ticking off one of his lists, following a topic, opening the training plan screen and the
        // capability-gap category; decision 2026-11-11-asked-for-runs-at-once); translator mode, which
        // changes no data and starts and stops at once since ADR-619 (owner, 24 Oct 2026); and text_me,
        // which can reach only the user's own verified number, while Texts from Doddy is on (owner,
        // 9 Nov 2026, decision 2026-11-09-restaurant-calls-one-tap).
        let withoutCard = Set(ToolCatalog.all.filter { $0.effect != .lookup && $0.approval != .card && $0.approval != .serverApproval }.map(\.name))
        XCTAssertEqual(withoutCard, [
            "start_stopwatch", "stop_stopwatch", "start_focus", "stop_focus", "start_wind_down", "stop_wind_down",
            "add_to_list", "check_off", "follow_news", "open_training_plan", "note_capability_gap",
            VoiceToolName.startTranslator, VoiceToolName.stopTranslator, VoiceToolName.textMe,
        ])
        XCTAssertEqual(withoutCard, AskFirst.ownSmallActions.union([VoiceToolName.startTranslator, VoiceToolName.stopTranslator, VoiceToolName.textMe]))
        for name in withoutCard { XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .runsNow, name) }
        // What takes something away, reaches past Doddy's own lists and timers, or starts paid
        // background work keeps its card.
        for name in [VoiceToolName.removeFromList, VoiceToolName.parkingSpot, VoiceToolName.saveMemory, VoiceToolName.createList,
                     VoiceToolName.createCalendarEvent, VoiceToolName.deleteCalendarEvent, VoiceToolName.setTimer, VoiceToolName.setAlarm,
                     VoiceToolName.remindWhenToLeave, VoiceToolName.handOverErrand, VoiceToolName.makeSomething, VoiceToolName.callPlaces] {
            XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .card, name)
        }
    }

    func testEveryLookupRunsAtOnce() {
        // Decision 2026-11-11-asked-for-runs-at-once: what the user asks for is the yes, so every lookup
        // runs at once: the public ones (ADR-575), the looks at the user's own things on this iPhone, and
        // every read through Doddy's server. No descriptor is left that asks for a spoken yes.
        for tool in ToolCatalog.all where tool.effect == .lookup {
            XCTAssertEqual(tool.approval, .runsNow, tool.name)
        }
        XCTAssertEqual(ToolCatalog.all.filter { $0.approval == .askFirst || $0.approval == .serverAsk }.map(\.name), [])
        let runsNow = Set(ToolCatalog.all.filter { $0.approval == .runsNow }.map(\.name))
        XCTAssertEqual(runsNow, Set(ToolCatalog.all.map(\.name).filter(AskFirst.runsAtOnce)), "the catalog and AskFirst.runsAtOnce name the same tools")
        XCTAssertEqual(runsNow,
                       AskFirst.publicLookups.union(AskFirst.ownLooks).union(AskFirst.ownSmallActions)
                           .union([VoiceToolName.startTranslator, VoiceToolName.stopTranslator, VoiceToolName.textMe])
                           .union(CloudToolName.all.subtracting(CloudToolName.writes)),
                       "public lookups, looks at the user's own things, Doddy's own small actions, every read through Doddy's server, translator start and stop (ADR-619), and text_me to the user's own number (decision 2026-11-09-restaurant-calls-one-tap)")
        XCTAssertEqual(AskFirst.publicLookups, ["calculate", "convert_units", "convert_currency", "web_search", "news_search", "find_places",
                                                "geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"])
        for name in AskFirst.publicLookups { XCTAssertEqual(ToolCatalog.descriptor(name)?.effect, .lookup, name) }
        XCTAssertEqual(AskFirst.ownLooks, ["search_memories", "read_list", "read_calendar", "find_free_time", "lookup_contact", "upcoming_birthdays",
                                           "find_photos", "look_at_screen", "read_steps", "read_health_week", "list_alarms", "check_stopwatch",
                                           "check_focus", "check_errands", "find_deals"])
        for name in AskFirst.ownLooks {
            XCTAssertEqual(ToolCatalog.descriptor(name)?.effect, .lookup, name)
            XCTAssertEqual(ToolCatalog.descriptor(name)?.isCloud, false, "\(name) is the app's own look")
        }
        // The one lookup that hides inside a change tool: `parking_spot` keeps the card of its strictest
        // action in the catalog, and only its "find" runs at once.
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.parkingSpot)?.approval, .card)
        XCTAssertEqual(AskFirst.need(for: .parkingSpot(.find)), .runsNow)
        guard case .yesFirst = AskFirst.need(for: .parkingSpot(.clear)) else { return XCTFail("forgetting the spot shows a card") }
        XCTAssertEqual(AskFirst.need(for: .parkingSpot(.save(note: nil))), .ownPayloadCard)
    }

    func testEveryToolThatAsksRunsOnThePhoneWhereTheAppCanAsk() throws {
        // ElevenLabs runs web tools itself, so the app could never show a card before them (ASK-01). Only
        // the public lookups may run there (ADR-575); the other tools that run at once stay on the phone.
        for tool in try spec() where tool.runsOn != .phone {
            XCTAssertEqual(tool.runsOn, .web, tool.name)
            XCTAssertEqual(tool.ask, .runsNow, tool.name)
            XCTAssertTrue(ToolCatalog.webLookups.contains(tool.name), tool.name)
        }
        XCTAssertEqual(Set(try spec().filter { $0.runsOn == .web }.map(\.name)), ToolCatalog.webLookups)
    }

    func testAccountWritesAreExactlyTheServerApprovedOnes() {
        let writes = Set(ToolCatalog.all.filter { $0.effect == .accountWrite }.map(\.name))
        let serverApproved = Set(ToolCatalog.all.filter { $0.approval == .serverApproval }.map(\.name))
        XCTAssertEqual(writes, CloudToolName.writes)
        XCTAssertEqual(serverApproved, CloudToolName.writes)
    }

    func testHandoffsShowACardExceptOpeningThePlanScreen() {
        // A handoff sends something out of the app or to Doddy's server, so it shows a card. The one
        // exception since 11 Nov 2026: `open_training_plan` only opens Doddy's own screen, which the
        // person closes again (`AskFirst.ownSmallActions`).
        let handoffs = ToolCatalog.all.filter { $0.effect == .handoff }
        for tool in handoffs {
            XCTAssertEqual(tool.approval, tool.name == VoiceToolName.openTrainingPlan ? .runsNow : .card, tool.name)
        }
        XCTAssertEqual(Set(handoffs.filter { $0.approval == .runsNow }.map(\.name)), [VoiceToolName.openTrainingPlan])
        for name in [VoiceToolName.handOverErrand, VoiceToolName.makeSomething] {
            XCTAssertEqual(ToolCatalog.descriptor(name)?.effect, .handoff, name)
            XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .card, name)
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
        // websearch.ts also holds the fixed Monid tools (ADR-489); claude.ts the Claude tools (ADR-564).
        XCTAssertEqual(
            Set(server.keys).union([CloudToolName.webSearch, "news_search", "find_places", CloudToolName.askClaude, CloudToolName.makeDocument])
                .union(CloudToolName.flightTools),
            CloudToolName.all)
        let claude = try String(contentsOf: repoRoot.appendingPathComponent("backend/src/tools/claude.ts"), encoding: .utf8)
        for name in [CloudToolName.askClaude, CloudToolName.makeDocument] {
            XCTAssertTrue(claude.contains("\"\(name)\""), "\(name) not in claude.ts")
            XCTAssertFalse(CloudToolName.isWrite(name), "\(name) changes nothing outside Doddy")
            XCTAssertFalse(CloudToolName.needsAccount(name), name)
        }
        // Flights live in backend/src/flights (decision 2026-11-11-flights-kiwi-search-duffel-booking); booking is their one write.
        XCTAssertEqual(Set(server.filter { $0.value == "write" }.keys), CloudToolName.writes.subtracting([CloudToolName.bookFlight]))
        XCTAssertTrue(CloudToolName.isWrite(CloudToolName.bookFlight))
        let flights = try ["kiwi.ts", "duffel.ts", "service.ts"].map {
            try String(contentsOf: repoRoot.appendingPathComponent("backend/src/flights/\($0)"), encoding: .utf8)
        }.joined()
        for name in CloudToolName.flightTools {
            XCTAssertTrue(flights.contains("\"\(name)\""), "\(name) not in backend/src/flights")
            XCTAssertFalse(CloudToolName.needsAccount(name), name)
        }
        let websearch = try String(contentsOf: repoRoot.appendingPathComponent("backend/src/tools/websearch.ts"), encoding: .utf8)
        XCTAssertTrue(websearch.contains("\"\(CloudToolName.webSearch)\""), "web_search not found in websearch.ts")
        for name in ["news_search", "find_places"] { XCTAssertTrue(websearch.contains("\(name): {"), "\(name) not in MONID_TOOLS") }
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
