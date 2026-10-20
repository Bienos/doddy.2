import Foundation

// MARK: - The guide

/// The Double Back Tap guide (design v1.2, "Two taps. A little help."). It is one screen with three
/// steps, not a card per Settings page: Doddy can't see Settings, so asking people to report which
/// page they are on only added taps. Nothing here reads iOS Settings, detects a gesture or knows
/// what Back Tap is set to.
public enum BackTapGuide {
    /// Bump when the guide's steps change. Stored next to the user's completion marker.
    /// 2: one screen with three steps instead of six cards (the Ways to open Doddy screen).
    public static let version = 2
    /// The built-in App Shortcut. Observed 2026-10-09 on the owner's iPhone: Back Tap's Shortcuts
    /// section lists it directly, so nothing has to be created first.
    public static let appShortcutTitle = "Talk to Doddy"
    /// Fallback: the personal shortcut the user creates in the Shortcuts app if their iOS version
    /// does not list the App Shortcut under Back Tap.
    public static let fallbackShortcutName = "Open Doddy"
    /// The manual path. There is no public API to assign Back Tap or to read its assignment.
    public static let settingsPath = ["Settings", "Accessibility", "Touch", "Back Tap", "Double Tap", appShortcutTitle]
}

// MARK: - Test evidence

/// The period during which a shortcut invocation counts as *this* test's receipt.
public struct BackTapTestWindow: Equatable, Sendable, Codable {
    public let id: UUID
    public let startedAt: Date
    public let expiresAt: Date

    public init(id: UUID = UUID(), startedAt: Date, duration: TimeInterval) {
        self.id = id
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(duration)
    }

    public func isActive(at date: Date) -> Bool { date >= startedAt && date <= expiresAt }
}

/// Proof that Doddy's own intent ran. It proves the shortcut reached the app, not that a
/// Double Back Tap triggered it; the user says that part themselves.
public struct ShortcutReceipt: Equatable, Sendable {
    public enum Source: String, Sendable {
        case talkToDoddyIntent
    }

    public let source: Source
    public let receivedAt: Date

    public init(source: Source = .talkToDoddyIntent, receivedAt: Date) {
        self.source = source
        self.receivedAt = receivedAt
    }
}

// MARK: - State machine

public enum BackTapSetupPhase: Equatable, Sendable {
    case notStarted
    /// The three steps are on screen.
    case guiding
    /// Waiting for the shortcut to open Doddy.
    case testing(BackTapTestWindow)
    /// The shortcut arrived during the test; waiting for the user to say how they triggered it.
    case receiptReceived(BackTapTestWindow, receivedAt: Date)
    /// The only finished state. It is the user's report plus an intent receipt, never an iOS
    /// confirmation, so it is deliberately not called "verified".
    case userReportedTested(at: Date)
    case deferred
}

public enum BackTapSetupEvent: Equatable, Sendable {
    /// Show the steps (first time, or again after "later").
    case start
    case startTest(now: Date)
    case receipt(ShortcutReceipt)
    /// "Yes, I used Double Back Tap."
    case confirmDoubleTap(now: Date)
    /// "I ran it another way": the receipt is discarded and the steps come back.
    case otherTrigger
    /// "It didn't work, show me the steps."
    case backToSteps
    case deferSetup
    /// Show the steps again after they were deferred or completed.
    case revisit
}

public enum BackTapSetupOutcome: Equatable, Sendable {
    case accepted
    case ignored(String)
}

/// Deterministic guided-setup state. It stores whether Doddy's intent ran during an active test
/// window and what the user said about it. It never stores a system-verified assignment,
/// because iOS offers no API for that; and it cannot reach a finished state without a receipt.
public struct BackTapSetupCoordinator: Equatable, Sendable {
    /// How long a started test accepts a shortcut receipt.
    public static let testWindowDuration: TimeInterval = 120

    public private(set) var phase: BackTapSetupPhase

    public init(phase: BackTapSetupPhase = .notStarted) {
        self.phase = phase
    }

    /// Restores a persisted summary. An unexpired test window is resumed so that a shortcut
    /// arriving after iOS relaunched the app in the background still counts.
    public init(summary: BackTapSetupSummary, now: Date) {
        if let window = summary.activeTest, window.isActive(at: now) {
            phase = .testing(window)
            return
        }
        switch summary.status {
        case .notStarted: phase = .notStarted
        case .deferred: phase = .deferred
        case .userReportedTested: phase = .userReportedTested(at: summary.testedAt ?? now)
        }
    }

    public var isDone: Bool {
        if case .userReportedTested = phase { return true }
        return false
    }

    public var activeTest: BackTapTestWindow? {
        switch phase {
        case .testing(let window), .receiptReceived(let window, _): window
        default: nil
        }
    }

    public var summary: BackTapSetupSummary {
        switch phase {
        case .userReportedTested(let at):
            BackTapSetupSummary(status: .userReportedTested, testedAt: at, guideVersion: BackTapGuide.version, activeTest: nil)
        case .deferred:
            BackTapSetupSummary(status: .deferred, testedAt: nil, guideVersion: BackTapGuide.version, activeTest: nil)
        case .testing(let window), .receiptReceived(let window, _):
            BackTapSetupSummary(status: .notStarted, testedAt: nil, guideVersion: BackTapGuide.version, activeTest: window)
        case .notStarted, .guiding:
            BackTapSetupSummary(status: .notStarted, testedAt: nil, guideVersion: BackTapGuide.version, activeTest: nil)
        }
    }

    @discardableResult
    public mutating func handle(_ event: BackTapSetupEvent) -> BackTapSetupOutcome {
        switch (event, phase) {
        case (.start, .notStarted), (.start, .deferred), (.revisit, .deferred), (.revisit, .userReportedTested):
            phase = .guiding
            return .accepted
        case (.start, _):
            return .ignored("already started")
        case (.revisit, _):
            return .ignored("setup is in progress")

        case (.startTest(let now), .guiding), (.startTest(let now), .testing):
            phase = .testing(BackTapTestWindow(startedAt: now, duration: Self.testWindowDuration))
            return .accepted
        case (.startTest, _):
            return .ignored("show the steps first")

        case (.receipt(let receipt), .testing(let window)):
            guard receipt.receivedAt >= window.startedAt else { return .ignored("receipt predates the test") }
            guard receipt.receivedAt <= window.expiresAt else { return .ignored("test window expired") }
            phase = .receiptReceived(window, receivedAt: receipt.receivedAt)
            return .accepted
        case (.receipt, .receiptReceived):
            return .ignored("duplicate receipt")
        case (.receipt, _):
            return .ignored("no active test")

        case (.confirmDoubleTap(let now), .receiptReceived):
            phase = .userReportedTested(at: now)
            return .accepted
        case (.confirmDoubleTap, .testing):
            return .ignored("no shortcut received yet")
        case (.confirmDoubleTap, _):
            return .ignored("no test to confirm")

        case (.otherTrigger, .receiptReceived):
            phase = .guiding
            return .accepted
        case (.otherTrigger, _):
            return .ignored("no receipt to discard")

        case (.backToSteps, .testing), (.backToSteps, .receiptReceived):
            phase = .guiding
            return .accepted
        case (.backToSteps, _):
            return .ignored("no test to leave")

        case (.deferSetup, .userReportedTested):
            return .ignored("already tested")
        case (.deferSetup, _):
            phase = .deferred
            return .accepted
        }
    }
}

/// What the app persists: the outcome and, while a test runs, its window. Utterances, reported
/// pages and anything personal are never stored (design rule: setup is not memory).
public struct BackTapSetupSummary: Equatable, Sendable, Codable {
    public enum Status: String, Sendable, Codable {
        case notStarted, deferred, userReportedTested
    }

    public var status: Status
    public var testedAt: Date?
    public var guideVersion: Int
    public var activeTest: BackTapTestWindow?

    public init(status: Status = .notStarted, testedAt: Date? = nil, guideVersion: Int = BackTapGuide.version, activeTest: BackTapTestWindow? = nil) {
        self.status = status
        self.testedAt = testedAt
        self.guideVersion = guideVersion
        self.activeTest = activeTest
    }
}
