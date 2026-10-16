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
    func testFreshInstallStartsOnHomeAndOptionalIntroductionIsExplicit() async {
        let fresh = ProfileStore(environment: .live(arguments: ["-inMemoryStore"]), arguments: ["-inMemoryStore"])
        await fresh.load()
        XCTAssertEqual(fresh.route, .home)
        XCTAssertTrue(fresh.shouldOfferIntroduction)

        await fresh.reopenIntroduction()
        XCTAssertEqual(fresh.route, .introduction)
        await fresh.finishIntroduction(saved: false)
        XCTAssertEqual(fresh.route, .home)
        XCTAssertFalse(fresh.shouldOfferIntroduction)

        let skipped = ProfileStore(
            environment: .live(arguments: ["-inMemoryStore"]), arguments: ["-inMemoryStore", "-onboardingDone"])
        await skipped.load()
        XCTAssertEqual(skipped.route, .home)
    }

    @MainActor
    func testIntroductionEditsOnlyItsReviewedFieldsAndPreservesOtherLocalProfileData() async throws {
        let environment = AppEnvironment.live(arguments: ["-inMemoryStore"])
        var oldProfile = ProfileDraft()
        oldProfile[.name] = "Mika"
        oldProfile[.help] = "Keep useful details"
        _ = try await environment.profileRepository.commit(oldProfile, basedOn: .empty)

        let profiles = ProfileStore(environment: environment, arguments: ["-inMemoryStore"])
        await profiles.load()
        XCTAssertEqual(Set(profiles.introductionDraft.values.keys), Set(ProfileKey.introductionQuestions))

        var intro = profiles.introductionDraft
        intro[.name] = "M"
        _ = try await profiles.commitIntroduction(intro)
        XCTAssertEqual(profiles.profile.value(.name), "M")
        XCTAssertEqual(profiles.profile.value(.help), "Keep useful details")
    }

    func testEveryProfileFieldHasCopy() {
        for key in ProfileKey.allCases {
            XCTAssertFalse(key.label.isEmpty)
            XCTAssertTrue(key.question.hasSuffix("?"), key.question)
        }
    }

    func testFirstLaunchAnimationIsRememberedAndOlderInstallationsDoNotReplayIt() {
        let suite = "doddy-opening-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(OpeningPreferences.firstLaunchIntroSeen(defaults))
        defaults.set(true, forKey: PreferenceKey.quickStartOffered)
        XCTAssertTrue(OpeningPreferences.firstLaunchIntroSeen(defaults))
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.firstLaunchIntroSeen))

        OpeningPreferences.markFirstLaunchIntroSeen(defaults)
        XCTAssertTrue(OpeningPreferences.firstLaunchIntroSeen(defaults))
    }

    func testVoiceDoesNotStartOnOpenByDefault() {
        let suite = "doddy-listen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(OpeningPreferences.listenOnOpen(defaults))
    }

    func testAvailableStatusCopy() {
        XCTAssertEqual(StatusCopy.text(for: .available), "Available")
        XCTAssertEqual(StatusCopy.text(for: .notImplemented(plannedMilestone: "M1")), "Not built yet · planned M1")
        XCTAssertEqual(StatusCopy.text(for: .limited("read-only")), "Limited · read-only")
        XCTAssertEqual(StatusCopy.text(for: .needsSetup("server")), "Needs setup · server")
    }
}
