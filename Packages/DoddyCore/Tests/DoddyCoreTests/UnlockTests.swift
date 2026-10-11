import Foundation
import XCTest
@testable import DoddyCore

/// Unlock as you go (ADR-324): the card asks for exactly what a request needs, from typed codes
/// and the server's catalog, never from the agent's words; nothing is unlocked without a tap.
final class UnlockTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("contracts/online-accounts/\(name).json"))
    }

    private func catalog(_ name: String) throws -> ToolsCatalog {
        try JSONDecoder().decode(ToolsCatalog.self, from: fixture(name))
    }

    private func serverError(_ code: String, receiptCode: String? = nil) -> OnlineAccountsError {
        let receipt = receiptCode.map {
            OnlineToolReceipt(
                operationId: UUID(), operation: .read, toolkit: "gmail", tool: "check_email",
                timestamp: "2026-10-11T10:00:00.000Z", mode: .mock, status: .blocked, summary: "x", errorCode: $0, providerReference: nil)
        }
        return .server(code: code, message: "x", retryAfterSeconds: nil, receipt: receipt)
    }

    // MARK: Which refusals the user can resolve on the card

    func testOnlyUnlockableServerCodesRaiseACard() throws {
        XCTAssertEqual(UnlockNeed.from(serverError("capability_disabled"), tool: "check_email"), .onlineTool("check_email"))
        XCTAssertEqual(UnlockNeed.from(serverError("not_connected"), tool: "check_email"), .onlineTool("check_email"))
        XCTAssertEqual(UnlockNeed.from(serverError("connection_expired"), tool: "list_todoist_tasks"), .onlineTool("list_todoist_tasks"))
        XCTAssertEqual(UnlockNeed.from(serverError("permission_insufficient"), tool: "find_drive_file"), .onlineTool("find_drive_file"))
        // The switch was on; the approval simply expired while the card waited.
        XCTAssertNil(UnlockNeed.from(serverError("capability_disabled", receiptCode: "confirmation_required"), tool: "draft_email"))
        // Web search has no account to connect.
        XCTAssertNil(UnlockNeed.from(serverError("not_connected"), tool: "web_search"))
        XCTAssertEqual(UnlockNeed.from(serverError("capability_disabled"), tool: "web_search"), .onlineTool("web_search"))
        // Everything else stays a plain failure: nothing for the user to allow.
        for code in ["rate_limited", "quota_exceeded", "provider_timeout", "not_found", "invalid_request", "live_not_configured"] {
            XCTAssertNil(UnlockNeed.from(serverError(code), tool: "check_email"), code)
        }
        XCTAssertNil(UnlockNeed.from(.transport("x"), tool: "check_email"))
        XCTAssertNil(UnlockNeed.from(.unauthenticated, tool: "check_email"))
        XCTAssertNil(UnlockNeed.from(.notConfigured, tool: "check_email"))
    }

    // MARK: Steps come from the catalog

    func testDisconnectedAccountNeedsConnectThenTheOneSwitch() throws {
        let steps = UnlockPlan.onlineSteps(for: "check_email", catalog: try catalog("catalog-disconnected"), accountNotConnected: true)
        XCTAssertEqual(steps, [.connectAccount(toolkit: "gmail", title: "Gmail"), .switchOnTool(tool: "check_email", title: "Check my email")])
    }

    func testConnectedAccountWithToolOffNeedsOnlyThatSwitch() throws {
        let steps = UnlockPlan.onlineSteps(for: "read_email", catalog: try catalog("catalog-gmail-on"), accountNotConnected: false)
        XCTAssertEqual(steps, [.switchOnTool(tool: "read_email", title: "Read an email")], "connecting never switches tools on (ADR-097), and one tool never unlocks another")
    }

    func testNothingToUnlockWhenTheCatalogSaysItIsAllowed() throws {
        XCTAssertEqual(UnlockPlan.onlineSteps(for: "check_email", catalog: try catalog("catalog-gmail-on"), accountNotConnected: false), [])
    }

    func testWebSearchNeverAsksToConnect() throws {
        for name in ["catalog-disconnected", "catalog-gmail-on"] {
            let steps = UnlockPlan.onlineSteps(for: "web_search", catalog: try catalog(name), accountNotConnected: true)
            XCTAssertEqual(steps, [.switchOnTool(tool: "web_search", title: "Search the web")], name)
        }
    }

    func testUnknownToolHasNoSteps() throws {
        XCTAssertEqual(UnlockPlan.onlineSteps(for: "send_email", catalog: try catalog("catalog-gmail-on"), accountNotConnected: true), [])
    }

    func testWithoutACatalogTheErrorCodeDecidesTheFirstStep() {
        XCTAssertEqual(
            UnlockPlan.onlineSteps(for: "list_todoist_tasks", catalog: nil, accountNotConnected: true),
            [.connectAccount(toolkit: "todoist", title: "Todoist"), .switchOnTool(tool: "list_todoist_tasks", title: "List my tasks")])
        XCTAssertEqual(
            UnlockPlan.onlineSteps(for: "search_notion", catalog: nil, accountNotConnected: false),
            [.switchOnTool(tool: "search_notion", title: "Search Notion")])
        XCTAssertEqual(
            UnlockPlan.onlineSteps(for: "web_search", catalog: nil, accountNotConnected: true),
            [.switchOnTool(tool: "web_search", title: "Search the web")])
    }

    func testGuessedToolkitsMatchTheServersIds() throws {
        let ids = try catalog("catalog-disconnected").toolkits.map(\.id)
        for tool in CloudToolName.all {
            XCTAssertTrue(ids.contains(UnlockPlan.guessedToolkit(for: tool)), tool)
        }
    }

    // MARK: Two taps, in order

    func testPlanAdvancesOneTapAtATime() {
        var plan = UnlockPlan(need: .onlineTool("check_email"), steps: [.connectAccount(toolkit: "gmail", title: "Gmail"), .switchOnTool(tool: "check_email", title: "Check my email")])
        XCTAssertEqual(plan.current, .connectAccount(toolkit: "gmail", title: "Gmail"))
        XCTAssertFalse(plan.isComplete)
        XCTAssertFalse(plan.isDone(.connectAccount(toolkit: "gmail", title: "Gmail")))
        plan.advance()
        XCTAssertTrue(plan.isDone(.connectAccount(toolkit: "gmail", title: "Gmail")))
        XCTAssertEqual(plan.current, .switchOnTool(tool: "check_email", title: "Check my email"))
        plan.advance()
        XCTAssertTrue(plan.isComplete)
        XCTAssertNil(plan.current)
        plan.advance()
        XCTAssertEqual(plan.completed, 2, "advancing past the end does nothing")
    }

    func testConnectionPlanIsOneTap() {
        var plan = UnlockPlan(need: .connection(.reminders), steps: [.allowConnection(.reminders)])
        XCTAssertEqual(plan.need.title, "Reminders")
        XCTAssertEqual(plan.current?.action, "Allow Reminders")
        plan.advance()
        XCTAssertTrue(plan.isComplete)
    }

    // MARK: What the agent hears

    func testRepliesNeverClaimAccessWasGiven() {
        let declined = VoiceToolReply.unlockDeclined(.onlineTool("check_email"))
        XCTAssertTrue(declined.hasPrefix("declined:") && declined.contains("Gmail") && declined.contains("Nothing was switched on"))
        let blocked = VoiceToolReply.unlockBlocked(.calendar)
        XCTAssertTrue(blocked.hasPrefix("failed:") && blocked.contains("iPhone Settings") && blocked.contains("Nothing was done"))
        let notConnected = VoiceToolReply.unlockFailed(.connectAccount(toolkit: "gmail", title: "Gmail"), reason: "Connecting was canceled.")
        XCTAssertTrue(notConnected.hasPrefix("failed:") && notConnected.contains("Gmail wasn't connected") && notConnected.contains("Connecting was canceled."))
        let notOn = VoiceToolReply.unlockFailed(.switchOnTool(tool: "read_email", title: "Read an email"), reason: nil)
        XCTAssertTrue(notOn.contains("\"Read an email\" wasn't switched on") && notOn.contains("Nothing was done"))
        for text in [declined, blocked, notConnected, notOn] {
            XCTAssertFalse(text.lowercased().contains("is now on") || text.lowercased().contains("connected."), text)
        }
    }
}
