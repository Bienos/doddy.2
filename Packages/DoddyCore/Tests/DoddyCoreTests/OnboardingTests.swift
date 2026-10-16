import DoddyCore
import Foundation
import XCTest

final class ProfileDraftTests: XCTestCase {
    /// The first-meet conversation asks only these two questions; other profile fields stay
    /// available in Settings and are not added to this first-run flow.
    func testTheIntroductionAsksOnlyNameAndStyle() {
        XCTAssertEqual(ProfileKey.introductionQuestions, [.name, .style])
        XCTAssertEqual(Set(ProfileKey.allCases), [.name, .help, .style, .language, .humor, .context])
        XCTAssertTrue(Set(ProfileKey.introductionQuestions).isSubset(of: Set(ProfileKey.allCases)))
    }

    func testBlankAnswersMeanSkippedAndValuesAreTrimmed() throws {
        var draft = ProfileDraft()
        draft[.name] = "  Ola \n"
        draft[.help] = "   "
        draft[.context] = "Learning\nthe guitar"
        XCTAssertEqual(try draft.validated(), [.name: "Ola", .context: "Learning the guitar"])
    }

    func testOverLongAnswerIsRejectedNotCut() {
        var draft = ProfileDraft()
        draft[.name] = String(repeating: "a", count: ProfileKey.name.maxLength + 1)
        XCTAssertThrowsError(try draft.validated()) { error in
            XCTAssertEqual(error as? ProfileValidationError, .tooLong(.name, length: 61, maximum: 60))
        }
        draft[.name] = String(repeating: "ż", count: ProfileKey.name.maxLength)
        XCTAssertEqual(try draft.validated()[.name]?.unicodeScalars.count, 60)
    }

    func testEffectivelyEmptyDraft() {
        var draft = ProfileDraft()
        XCTAssertTrue(draft.isEffectivelyEmpty)
        draft[.humor] = " "
        XCTAssertTrue(draft.isEffectivelyEmpty)
        draft[.humor] = "Just the useful bit"
        XCTAssertFalse(draft.isEffectivelyEmpty)
        draft.remove(.humor)
        XCTAssertTrue(draft.isEffectivelyEmpty)
    }

    func testPresetChoicesFitTheirLimits() {
        for key in ProfileKey.allCases {
            for choice in ProfileChoices.options(for: key) {
                XCTAssertLessThanOrEqual(choice.unicodeScalars.count, key.maxLength, "\(key): \(choice)")
            }
        }
    }
}

final class OnboardingProgressTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testFreshInstallSetupCanBeDeferredAndIntroductionIsOptional() {
        var progress = OnboardingProgress.initial(at: t0)
        XCTAssertEqual(progress.route, .setup(.welcome))

        progress = progress.guiding(to: .shortcut, at: t0)
        XCTAssertEqual(progress.route, .setup(.shortcut))

        progress = progress.finishingSetup(testPassed: true, at: t0)
        XCTAssertEqual(progress.setupDecision, .userReportedTestPassed)
        XCTAssertNil(progress.setupStep)
        XCTAssertEqual(progress.route, .introduction)

        progress = progress.decidingIntro(.saved, at: t0)
        XCTAssertEqual(progress.route, .home)
    }

    func testDeferringSetupNeverBlocksTheApp() {
        let deferred = OnboardingProgress.initial(at: t0).deferringSetup(at: t0)
        XCTAssertEqual(deferred.route, .introduction)
        XCTAssertEqual(deferred.decidingIntro(.skipped, at: t0).route, .home)
    }

    func testUnfinishedGuideResumesOnTheReportedPage() {
        let progress = OnboardingProgress.initial(at: t0).guiding(to: .touch, at: t0)
        XCTAssertEqual(progress.route, .setup(.touch))
    }

    func testGuideFromAnOlderStepMapRestartsAtTheBeginning() {
        let old = OnboardingProgress(walkthroughVersion: "older", setupDecision: .guiding, setupStep: .backTap, updatedAt: t0)
        XCTAssertEqual(old.route, .setup(.welcome))
    }

    func testReopeningSetupFromSettingsKeepsTheIntroDecision() {
        let done = OnboardingProgress.initial(at: t0).deferringSetup(at: t0).decidingIntro(.saved, at: t0)
        let reopened = done.guiding(to: .welcome, at: t0)
        XCTAssertEqual(reopened.route, .setup(.welcome))
        XCTAssertEqual(reopened.deferringSetup(at: t0).route, .home, "the introduction is not asked again")
    }

    func testStepIsOnlyKeptWhileGuiding() {
        let progress = OnboardingProgress(setupDecision: .deferred, setupStep: .touch, updatedAt: t0)
        XCTAssertNil(progress.setupStep)
    }

    func testNoStateClaimsTheSystemSettingWasVerified() {
        for decision in SetupDecision.allCases {
            XCTAssertFalse(decision.rawValue.lowercased().contains("verified"), decision.rawValue)
        }
    }

    func testStepOrder() {
        XCTAssertEqual(SetupStep.welcome.next, .shortcut)
        XCTAssertEqual(SetupStep.doubleTap.next, .test)
        XCTAssertNil(SetupStep.test.next)
        XCTAssertNil(SetupStep.welcome.previous)
    }
}
