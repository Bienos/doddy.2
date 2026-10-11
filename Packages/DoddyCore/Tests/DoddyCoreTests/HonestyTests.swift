import XCTest
@testable import DoddyCore

/// M0 must never claim a capability it does not have.
final class HonestyTests: XCTestCase {
    func testNoCapabilityIsAvailableInM0() {
        for capability in Capability.allCases {
            XCTAssertFalse(CapabilityCatalog.m0.isAvailable(capability), "\(capability) must not be claimed in M0")
            guard case .notImplemented = CapabilityCatalog.m0.status(of: capability) else {
                return XCTFail("\(capability) needs an explicit not-implemented status")
            }
        }
        XCTAssertEqual(CapabilityCatalog.m0.statuses.count, Capability.allCases.count, "catalog must list every capability")
    }

    func testMilestoneAssignments() {
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .memoryStorage), .notImplemented(plannedMilestone: "M1"))
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .cloudAssistant), .notImplemented(plannedMilestone: "M2"))
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .voiceInput), .notImplemented(plannedMilestone: "M3"))
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .reminders), .notImplemented(plannedMilestone: "M4"))
    }

    func testTextAssistantIsClaimedOnlyFromM2() {
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .textAssistant), .notImplemented(plannedMilestone: "M2"))
        XCTAssertFalse(CapabilityCatalog.m1.isAvailable(.textAssistant))
        XCTAssertFalse(CapabilityCatalog.v1Voice.isAvailable(.textAssistant))
        XCTAssertTrue(CapabilityCatalog.m2.isAvailable(.textAssistant))
        XCTAssertFalse(CapabilityCatalog.v2WithConnectedApps.isAvailable(.textAssistant))
        // M2 adds exactly one claim on top of what it builds on.
        for capability in Capability.allCases where capability != .textAssistant {
            XCTAssertEqual(CapabilityCatalog.m2.status(of: capability), CapabilityCatalog.v1Voice.status(of: capability), "\(capability)")
            XCTAssertEqual(CapabilityCatalog.v2WithAssistant.status(of: capability), CapabilityCatalog.v2WithConnectedApps.status(of: capability), "\(capability)")
        }
        XCTAssertTrue(CapabilityCatalog.v2WithAssistant.isAvailable(.textAssistant))
    }

    func testPrivacyDefaultsAreFullyLocal() {
        XCTAssertTrue(PrivacyDefaults.m0.isFullyLocal)
        XCTAssertFalse(PrivacyDefaults.m0.accountRequired)
        XCTAssertFalse(PrivacyDefaults.m0.microphoneUsed)
        XCTAssertFalse(PrivacyDefaults.m0.cloudAIEnabled)
    }

    func testSyncIsNotCalledUnbuiltWhileSharedListsShip() {
        // Lists the user shares do go to iCloud; notes don't sync. "Off (not built)" hid the first.
        XCTAssertEqual(PrivacyDefaults.m0.syncText, "Off (not built)")
        XCTAssertFalse(PrivacyDefaults.v1Voice.syncText.contains("not built"))
        XCTAssertTrue(PrivacyDefaults.v1Voice.syncText.contains("iCloud"))
        for configured in [false, true] {
            guard case .limited(let note) = CapabilityCatalog.shipping(serverConfigured: configured).status(of: .cloudSync) else {
                return XCTFail("shared lists must be described, not called not implemented")
            }
            XCTAssertTrue(note.contains("iCloud"))
        }
    }

    func testUnavailableAdaptersThrowAndNeverFabricateResults() async throws {
        let new = try NewMemory(text: "x", capturedAt: Date(timeIntervalSince1970: 0))
        let repo = UnavailableMemoryRepository()
        await assertUnavailable(.memoryStorage) { _ = try await repo.save(new) }
        await assertUnavailable(.memoryStorage) { _ = try await repo.query("x", limit: 5) }
        await assertUnavailable(.memoryStorage) { _ = try await repo.update(id: UUID(), currentText: "y") }
        await assertUnavailable(.memoryStorage) { try await repo.delete(id: UUID()) }
        await assertUnavailable(.memoryStorage) { _ = try await repo.export() }
        await assertUnavailable(.memoryRecall) { _ = try await UnavailableRecallService().recall("x", limit: 5) }
        await assertUnavailable(.cloudAssistant) {
            _ = try await UnavailableAssistantClient().respond(AssistantRequest(sessionID: UUID(), userText: "hi"))
        }
        let proposal = ToolProposal(operationID: UUID(), kind: .createReminder, summary: "x")
        await assertUnavailable(.reminders) {
            _ = try await UnavailableToolExecutor().execute(ToolConfirmation(proposal: proposal, confirmedAt: Date(timeIntervalSince1970: 0)))
        }
    }

    func testNoMatchCopyDoesNotInventAnAnswer() {
        XCTAssertEqual(RecallCopy.noMatch, "I couldn't find that in your saved memories.")
    }

    func testCandidatesAlwaysReferToARealRecord() throws {
        let record = try MemoryRecord(id: UUID(), rawText: "x", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(MemoryCandidate(record: record, matchedTerms: ["x"]).memoryID, record.id)
    }

    private func assertUnavailable(
        _ capability: Capability, _ body: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected capabilityUnavailable(\(capability))", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? DoddyError, .capabilityUnavailable(capability), file: file, line: line)
        }
    }
}
