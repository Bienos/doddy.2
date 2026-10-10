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
        XCTAssertNil(env.assistant)
        XCTAssertTrue(env.toolExecutor is UnavailableToolExecutor)
        XCTAssertNil(env.noteReminders)
    }

    func testUITestLaunchNeverTouchesIOSNotifications() async {
        let env = AppEnvironment.live(arguments: ["-inMemoryStore"])
        XCTAssertTrue(env.capabilities.isAvailable(.noteReminders))
        let status = await env.noteReminders?.authorization()
        XCTAssertEqual(status, .denied, "UI-test launches use DisabledNoteNotifications")
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
    func testFreshInstallRoutesToIntroductionAndSkipFlagOnlyWorksInMemory() async {
        let fresh = ProfileStore(environment: .live(arguments: ["-inMemoryStore"]), arguments: ["-inMemoryStore"])
        await fresh.load()
        // The Back Tap guide is not a first-use step (ADR-089), so a fresh install starts on the introduction.
        XCTAssertEqual(fresh.route, .introduction)

        let skipped = ProfileStore(
            environment: .live(arguments: ["-inMemoryStore"]), arguments: ["-inMemoryStore", "-onboardingDone"])
        await skipped.load()
        XCTAssertEqual(skipped.route, .home)
    }

    func testEveryProfileFieldHasCopy() {
        for key in ProfileKey.allCases {
            XCTAssertFalse(key.label.isEmpty)
            XCTAssertTrue(key.question.hasSuffix("?"), key.question)
        }
    }

    func testAvailableStatusCopy() {
        XCTAssertEqual(StatusCopy.text(for: .available), "Available")
        XCTAssertEqual(StatusCopy.text(for: .notImplemented(plannedMilestone: "M1")), "Not built yet · planned M1")
        XCTAssertEqual(StatusCopy.text(for: .limited("read-only")), "Limited · read-only")
        XCTAssertEqual(StatusCopy.text(for: .needsSetup("server")), "Needs setup · server")
    }
}
