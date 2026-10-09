import XCTest
import DoddyCore
@testable import Doddy

/// App-target tests. NOT RUN in the authoring environment (no Xcode); see BUILD_AND_TEST.md.
final class AppEnvironmentTests: XCTestCase {
    func testUnavailableEnvironmentWiresOnlyUnavailableAdapters() {
        let env = AppEnvironment.unavailable
        XCTAssertTrue(env.memoryRepository is UnavailableMemoryRepository)
        XCTAssertTrue(env.profileRepository is UnavailableProfileRepository)
        XCTAssertTrue(env.recallService is UnavailableRecallService)
        XCTAssertTrue(env.assistantClient is UnavailableAssistantClient)
        XCTAssertTrue(env.toolExecutor is UnavailableToolExecutor)
    }

    func testEveryCapabilityHasHonestDisplayCopy() {
        for capability in Capability.allCases {
            XCTAssertFalse(capability.displayName.isEmpty)
            let text = StatusCopy.text(for: AppEnvironment.unavailable.capabilities.status(of: capability))
            XCTAssertTrue(text.hasPrefix("Not built"), "\(capability): \(text)")
        }
    }

    @MainActor
    func testUnreadableProfileStorageNeverBlocksTheApp() async {
        let profiles = ProfileStore(environment: .unavailable, arguments: [])
        await profiles.load()
        XCTAssertTrue(profiles.hasLoaded)
        XCTAssertEqual(profiles.route, .home)
    }

    @MainActor
    func testFreshInstallRoutesToSetupAndSkipFlagOnlyWorksInMemory() async {
        let fresh = ProfileStore(environment: .live(arguments: ["-inMemoryStore"]), arguments: ["-inMemoryStore"])
        await fresh.load()
        XCTAssertEqual(fresh.route, .setup(.welcome))

        let skipped = ProfileStore(
            environment: .live(arguments: ["-inMemoryStore"]), arguments: ["-inMemoryStore", "-onboardingDone"])
        await skipped.load()
        XCTAssertEqual(skipped.route, .home)
    }

    func testEveryProfileFieldHasCopyAndNoSetupStatusClaimsVerification() {
        for key in ProfileKey.allCases {
            XCTAssertFalse(key.label.isEmpty)
            XCTAssertTrue(key.question.hasSuffix("?"), key.question)
        }
        for decision in SetupDecision.allCases {
            XCTAssertFalse(decision.statusText.lowercased().contains("verified"))
        }
    }

    func testAvailableStatusCopy() {
        XCTAssertEqual(StatusCopy.text(for: .available), "Available")
        XCTAssertEqual(StatusCopy.text(for: .notImplemented(plannedMilestone: "M1")), "Not built yet · planned M1")
        XCTAssertEqual(StatusCopy.text(for: .limited("read-only")), "Limited · read-only")
    }
}
