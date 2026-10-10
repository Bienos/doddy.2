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
        guard hasLoaded, let progress else { return .home }
        // The core's setup step is skipped: the Back Tap guide is V2's `BackTapSetupView` (Home
        // card and Settings), not a first-use step (DECISIONS.md ADR-089).
        return progress.introDecision == .notDecided ? .introduction : .home
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

    /// Leaving the introduction without saving. If a profile is already stored (the intro was
    /// reopened from Settings), it still counts as saved.
    func finishIntroduction(saved: Bool) async {
        let decision: IntroDecision = saved || !profile.isEmpty ? .saved : .skipped
        await updateProgress { $0.decidingIntro(decision, at: .now) }
    }

    func reopenIntroduction() async {
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
        case .name: NSLocalizedString("First things first. What should I call you?", comment: "")
        case .help: NSLocalizedString("What would make me useful in your day?", comment: "")
        case .style: NSLocalizedString("And how do you like your answers?", comment: "")
        case .language: NSLocalizedString("Which language feels natural to you?", comment: "")
        case .humor: NSLocalizedString("A little dry humor, or straight to the useful bit?", comment: "")
        case .context: NSLocalizedString("Anything you'd like a hand with these days?", comment: "")
        }
    }

    var hint: String {
        switch self {
        case .name: NSLocalizedString("A name or nickname is enough. It doesn't verify who you are.", comment: "")
        case .help: NSLocalizedString("Pick a starting point, or say it in your own words.", comment: "")
        case .style: NSLocalizedString("You can change this whenever you want.", comment: "")
        case .language: NSLocalizedString("Doddy's screens follow your iPhone's language. This is for Doddy's replies.", comment: "")
        case .humor: NSLocalizedString("No jokes when something matters.", comment: "")
        case .context: NSLocalizedString("A project, hobby or routine. Share only what would help.", comment: "")
        }
    }
}
