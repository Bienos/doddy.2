import DoddyCore
import Foundation
import Observation

/// Main-actor view state for the reviewed profile and first-use progress. The profile shown is
/// only ever what the repository returned after a committed write.
@MainActor
@Observable
final class ProfileStore {
    private let repository: any ProfileRepository
    /// UI tests: start straight on Home (`-onboardingDone`, only with a test store: in-memory,
    /// or the per-test `-memoryTestID` database, which is a DEBUG-only fixture).
    private let skipOnboarding: Bool
    private(set) var profile: ApprovedProfile = .empty
    private(set) var progress: OnboardingProgress?
    private(set) var hasLoaded = false
    /// The introduction is opened only by an explicit Home or Settings action. A fresh install
    /// always starts on Home; the launch animation is owned separately by `OpeningModel`.
    private(set) var isIntroductionPresented = false
    /// Set when setup progress couldn't be saved. The flow still moves on, so nobody is stuck.
    private(set) var progressSaveProblem: String?

    init(environment: AppEnvironment, arguments: [String] = ProcessInfo.processInfo.arguments) {
        repository = environment.profileRepository
        skipOnboarding = arguments.contains("-onboardingDone")
            && (arguments.contains("-inMemoryStore") || Self.usesTestDatabase(arguments))
    }

    private static func usesTestDatabase(_ arguments: [String]) -> Bool {
        #if DEBUG
        return arguments.contains("-memoryTestID")
        #else
        return false
        #endif
    }

    /// Without readable storage the onboarding is skipped: the app must stay usable, and Home
    /// already explains the storage problem.
    var route: OnboardingRoute {
        isIntroductionPresented ? .introduction : .home
    }

    var shouldOfferIntroduction: Bool {
        !isIntroductionPresented && (progress?.introDecision == .notDecided || progressSaveProblem != nil)
    }

    /// Only a genuinely new installation gets the one-time basketball opening. Completed or
    /// previously used installations from before this flow are not surprised with it on upgrade.
    var isFirstInstallation: Bool {
        guard hasLoaded, let progress else { return false }
        return progress.introDecision == .notDecided && profile.isEmpty
            && !UserDefaults.standard.bool(forKey: PreferenceKey.quickStartOffered)
            && !UserDefaults.standard.bool(forKey: PreferenceKey.hadFirstConversation)
    }

    func load() async {
        do {
            profile = try await repository.profile()
            var loaded = try await repository.onboarding()
            if skipOnboarding, loaded.route != .home {
                loaded = try await repository.saveOnboarding(
                    loaded.deferringSetup(at: .now).decidingIntro(.skipped, at: .now))
            }
            progress = loaded
        } catch {
            progress = nil
        }
        hasLoaded = true
    }

    /// Applies one onboarding transition and saves it. If saving fails the new state is still
    /// used for this session and the problem is shown, rather than trapping the user.
    func updateProgress(_ transition: (OnboardingProgress) -> OnboardingProgress) async {
        let next = transition(progress ?? .initial(at: .now))
        progress = next
        do {
            let saved = try await repository.saveOnboarding(next)
            // A newer tap may have moved on while this save was in flight; keep the newest.
            if progress == next { progress = saved }
            progressSaveProblem = nil
        } catch {
            progressSaveProblem = "Doddy couldn't save your place in the introduction, so you may see it again next time. (\(error.localizedDescription))"
        }
    }

    /// Leaving the optional introduction without saving. A prior saved profile remains intact.
    func finishIntroduction(saved: Bool) async {
        isIntroductionPresented = false
        let decision: IntroDecision = saved ? .saved : .skipped
        await updateProgress { $0.decidingIntro(decision, at: .now) }
    }

    func reopenIntroduction() async {
        isIntroductionPresented = true
        await updateProgress { $0.decidingIntro(.notDecided, at: .now) }
    }

    /// Returns only after the repository confirmed a committed, read-back write.
    @discardableResult
    func commit(_ draft: ProfileDraft) async throws -> ApprovedProfile {
        do {
            profile = try await repository.commit(draft, basedOn: profile)
            return profile
        } catch ProfileStoreError.revisionConflict {
            // Show what is stored now; the caller keeps the user's draft.
            profile = (try? await repository.profile()) ?? profile
            throw ProfileStoreError.revisionConflict
        }
    }

    func forget() async throws {
        try await repository.forgetProfile()
        profile = try await repository.profile()
    }

    /// The optional first-meet flow edits only its two reviewed fields. Existing Settings profile
    /// fields are preserved locally but never exposed as hidden edits in this conversation.
    var introductionDraft: ProfileDraft {
        var values: [ProfileKey: String] = [:]
        for key in ProfileKey.introductionQuestions {
            if let value = profile.value(key) { values[key] = value }
        }
        return ProfileDraft(values: values)
    }

    func commitIntroduction(_ draft: ProfileDraft) async throws -> ApprovedProfile {
        var merged = profile.draft
        for key in ProfileKey.introductionQuestions {
            merged[key] = draft[key]
        }
        return try await commit(merged)
    }
}

enum ProfileErrorText {
    static func message(for error: any Error) -> String {
        if let error = error as? ProfileValidationError {
            switch error {
            case .tooLong(let key, let length, let maximum):
                return "\(key.label) is \(length) characters; the limit is \(maximum). Nothing was cut and nothing was saved."
            }
        }
        if let error = error as? ProfileStoreError {
            switch error {
            case .revisionConflict:
                return NSLocalizedString("Your preferences changed somewhere else while you were editing. Nothing was saved; your edits are still here. Check them and save again.", comment: "")
            case .verificationFailed:
                return NSLocalizedString("The save couldn't be confirmed, so it wasn't counted as saved. Your answers are still here.", comment: "")
            case .corruptRecord:
                return NSLocalizedString("A saved preference couldn't be read. Nothing was deleted.", comment: "")
            }
        }
        if error is DoddyError {
            return NSLocalizedString("Preferences can't be saved on this iPhone right now.", comment: "")
        }
        return "Something went wrong and nothing was saved. (\(error.localizedDescription))"
    }
}

extension ProfileKey {
    var question: String {
        switch self {
        case .name: NSLocalizedString("What should I call you?", comment: "")
        case .help: NSLocalizedString("What would make me useful in your day?", comment: "")
        case .style: NSLocalizedString("How should I show up?", comment: "")
        case .language: NSLocalizedString("Which language feels natural to you?", comment: "")
        case .humor: NSLocalizedString("A little dry humor, or straight to the useful bit?", comment: "")
        case .context: NSLocalizedString("Anything you'd like a hand with these days?", comment: "")
        }
    }

    var hint: String {
        switch self {
        case .name: NSLocalizedString("A name or nickname is enough. It doesn't verify who you are.", comment: "")
        case .help: NSLocalizedString("Pick a starting point, or say it in your own words.", comment: "")
        case .style: NSLocalizedString("Pick a starting vibe. You can change it whenever you want.", comment: "")
        case .language: NSLocalizedString("Doddy's screens follow your iPhone's language. This is for Doddy's replies.", comment: "")
        case .humor: NSLocalizedString("No jokes when something matters.", comment: "")
        case .context: NSLocalizedString("A project, hobby or routine. Share only what would help.", comment: "")
        }
    }
}
