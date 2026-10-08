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

    func testPrivacyDefaultsAreFullyLocal() {
        XCTAssertTrue(PrivacyDefaults.m0.isFullyLocal)
        XCTAssertFalse(PrivacyDefaults.m0.accountRequired)
        XCTAssertFalse(PrivacyDefaults.m0.microphoneUsed)
        XCTAssertFalse(PrivacyDefaults.m0.cloudAIEnabled)
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
