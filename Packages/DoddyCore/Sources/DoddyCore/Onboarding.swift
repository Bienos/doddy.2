import Foundation

// First-use flow (design/interface-v1.2/docs/GUIDED-BACK-TAP-AND-VOICE-SETUP.md):
// optional guided Back Tap setup → optional introduction → Home.
//
// Doddy cannot read the iPhone's Back Tap setting, and no public API reports it. Every
// "done" state here is what the user told us, never a verified system setting.

/// One step of first-use setup, in order, as stored with `OnboardingProgress`. The words the
/// user sees are `BackTapGuide`'s.
public enum SetupStep: String, CaseIterable, Codable, Sendable {
    /// "Two taps. A little help." Start or set up later.
    case welcome
    /// Create the personal Open Doddy shortcut in Shortcuts.
    case shortcut
    /// The Settings walkthrough, keyed by the page the user says they are on.
    case openSettings, settings, accessibility, touch, backTap, doubleTap
    /// Go to the Home Screen and double-tap the back of the iPhone.
    case test

    public var next: SetupStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    public var previous: SetupStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index > 0 else { return nil }
        return all[index - 1]
    }
}

public enum SetupGuideCopy {
    /// Version of the step map, stored with `OnboardingProgress`. A guide saved under another
    /// version restarts from the beginning instead of resuming on a page that may no longer exist.
    /// The guide's words and steps are `BackTapGuide` (BackTapSetup.swift).
    public static let version = "backtap-written-1"
}

public enum SetupDecision: String, CaseIterable, Codable, Sendable {
    case notStarted
    /// The written guide is open at `OnboardingProgress.setupStep`.
    case guiding
    /// "Set this up later." The app is fully usable; Settings can reopen the guide.
    case deferred
    /// The user said they chose Open Doddy but skipped the tap test or it didn't work.
    case userReportedDone
    /// The user said a double tap opened Doddy. Still a self-report: Doddy can't tell how
    /// it was opened and can't read the setting.
    case userReportedTestPassed
}

public enum IntroDecision: String, CaseIterable, Codable, Sendable {
    case notDecided
    /// "Start without the chat" or finished without saving. Not asked again; Settings can
    /// reopen it.
    case skipped
    /// At least one reviewed field was saved.
    case saved
}

public enum OnboardingRoute: Equatable, Sendable {
    case setup(SetupStep)
    case introduction
    case home
}

/// What has been decided about first use. Stores task state only: no answers, no speech,
/// no claim about the iPhone's settings.
public struct OnboardingProgress: Equatable, Sendable {
    public private(set) var walkthroughVersion: String
    public private(set) var setupDecision: SetupDecision
    /// Only meaningful while `guiding`.
    public private(set) var setupStep: SetupStep?
    public private(set) var introDecision: IntroDecision
    public var updatedAt: Date

    public init(
        walkthroughVersion: String = SetupGuideCopy.version, setupDecision: SetupDecision = .notStarted,
        setupStep: SetupStep? = nil, introDecision: IntroDecision = .notDecided, updatedAt: Date
    ) {
        self.walkthroughVersion = walkthroughVersion
        self.setupDecision = setupDecision
        self.setupStep = setupDecision == .guiding ? setupStep : nil
        self.introDecision = introDecision
        self.updatedAt = updatedAt
    }

    /// Fresh install: nothing decided.
    public static func initial(at date: Date) -> OnboardingProgress { OnboardingProgress(updatedAt: date) }

    /// Setup comes first, then the introduction, then Home. A deferred or finished setup
    /// never blocks the app.
    public var route: OnboardingRoute {
        switch setupDecision {
        case .notStarted:
            return .setup(.welcome)
        case .guiding:
            guard walkthroughVersion == SetupGuideCopy.version, let setupStep else { return .setup(.welcome) }
            return .setup(setupStep)
        case .deferred, .userReportedDone, .userReportedTestPassed:
            return introDecision == .notDecided ? .introduction : .home
        }
    }

    public var setupFinished: Bool { setupDecision == .userReportedDone || setupDecision == .userReportedTestPassed }

    // MARK: Transitions (pure; the caller persists the result)

    /// Open the guide at `step` (Start, Next, Previous, a reported page, or reopening it
    /// from Settings).
    public func guiding(to step: SetupStep, at date: Date) -> OnboardingProgress {
        OnboardingProgress(
            walkthroughVersion: SetupGuideCopy.version, setupDecision: .guiding, setupStep: step,
            introDecision: introDecision, updatedAt: date)
    }

    public func deferringSetup(at date: Date) -> OnboardingProgress {
        OnboardingProgress(
            walkthroughVersion: walkthroughVersion, setupDecision: .deferred, introDecision: introDecision,
            updatedAt: date)
    }

    /// Ends the guide with the user's own report.
    public func finishingSetup(testPassed: Bool, at date: Date) -> OnboardingProgress {
        OnboardingProgress(
            walkthroughVersion: SetupGuideCopy.version,
            setupDecision: testPassed ? .userReportedTestPassed : .userReportedDone,
            introDecision: introDecision, updatedAt: date)
    }

    public func decidingIntro(_ decision: IntroDecision, at date: Date) -> OnboardingProgress {
        OnboardingProgress(
            walkthroughVersion: walkthroughVersion, setupDecision: setupDecision, setupStep: setupStep,
            introDecision: decision, updatedAt: date)
    }
}
