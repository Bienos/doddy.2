import DoddyCore
import Foundation
import Observation

/// Main-actor view state for the reviewed profile and first-use progress. The profile shown is
/// only ever what the repository returned after a committed write.
@MainActor
@Observable
final class ProfileStore {
    private let repository: any ProfileRepository
    /// UI tests: start straight on Home (`-onboardingDone`, in-memory store only).
    private let skipOnboarding: Bool
    private(set) var profile: ApprovedProfile = .empty
    private(set) var progress: OnboardingProgress?
    private(set) var hasLoaded = false
    /// Set when setup progress couldn't be saved. The flow still moves on, so nobody is stuck.
    private(set) var progressSaveProblem: String?

    init(environment: AppEnvironment, arguments: [String] = ProcessInfo.processInfo.arguments) {
        repository = environment.profileRepository
        skipOnboarding = arguments.contains("-onboardingDone") && arguments.contains("-inMemoryStore")
    }

    /// Without readable storage the onboarding is skipped: the app must stay usable, and Home
    /// already explains the storage problem.
    var route: OnboardingRoute {
        guard hasLoaded, let progress else { return .home }
        return progress.route
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
            progress = try await repository.saveOnboarding(next)
            progressSaveProblem = nil
        } catch {
            progressSaveProblem = "Doddy couldn't save your place in setup, so you may see these steps again next time. (\(error.localizedDescription))"
        }
    }

    func reopenSetup() async {
        await updateProgress { $0.guiding(to: .welcome, at: .now) }
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
                return "Your preferences changed somewhere else while you were editing. Nothing was saved; your edits are still here. Check them and save again."
            case .verificationFailed:
                return "The save couldn't be confirmed, so it wasn't counted as saved. Your answers are still here."
            case .corruptRecord:
                return "A saved preference couldn't be read. Nothing was deleted."
            }
        }
        if error is DoddyError {
            return "Preferences can't be saved on this iPhone right now."
        }
        return "Something went wrong and nothing was saved. (\(error.localizedDescription))"
    }
}

extension ProfileKey {
    var label: String {
        switch self {
        case .name: "What to call you"
        case .help: "Useful help"
        case .style: "Answer style"
        case .language: "Language"
        case .humor: "Humor"
        case .context: "Current focus"
        }
    }

    var question: String {
        switch self {
        case .name: "First things first. What should I call you?"
        case .help: "What would make me useful in your day?"
        case .style: "And how do you like your answers?"
        case .language: "Which language feels natural to you?"
        case .humor: "A little dry humor, or straight to the useful bit?"
        case .context: "Anything you'd like a hand with these days?"
        }
    }

    var hint: String {
        switch self {
        case .name: "A name or nickname is enough. It doesn't verify who you are."
        case .help: "Pick a starting point, or say it in your own words."
        case .style: "You can change this whenever you want."
        case .language: "Doddy's screens are in English for now. This is for replies later on."
        case .humor: "No jokes when something matters."
        case .context: "A project, hobby or routine. Share only what would help."
        }
    }
}

extension SetupDecision {
    var statusText: String {
        switch self {
        case .notStarted, .deferred: "Not set up"
        case .guiding: "In progress"
        case .userReportedDone: "You said it's set up"
        case .userReportedTestPassed: "You said it works"
        }
    }
}
