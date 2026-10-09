import Foundation

// MARK: - Step map

/// One card of the guided Double Back Tap setup. Pure data the app shows; nothing here reads
/// iOS Settings, detects a gesture or knows what Back Tap is set to.
public struct BackTapGuideStep: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Where the user is, e.g. "Settings → Accessibility → Touch".
    public let route: String
    /// What Doddy says or shows for this step.
    public let instruction: String
    /// The button the user taps to report being on this page, e.g. "I'm in Touch".
    public let reportLabel: String

    public init(id: String, title: String, route: String, instruction: String, reportLabel: String) {
        self.id = id
        self.title = title
        self.route = route
        self.instruction = instruction
        self.reportLabel = reportLabel
    }
}

/// The versioned walkthrough (design/interface-v1.2, GUIDED-BACK-TAP-AND-VOICE-SETUP.md).
/// Guidance follows the page the user *reports*; the app never claims to see their screen.
public enum BackTapGuide {
    /// Bump when the step text or order changes. Stored next to the user's completion marker.
    public static let version = 1
    /// The personal shortcut the user creates in the Shortcuts app.
    public static let shortcutName = "Open Doddy"
    /// The manual path. There is no public API to assign Back Tap or to read its assignment.
    public static let settingsPath = ["Settings", "Accessibility", "Touch", "Back Tap", "Double Tap", shortcutName]

    public static let steps: [BackTapGuideStep] = [
        BackTapGuideStep(
            id: "settings", title: "Open Settings", route: "Settings",
            instruction: "Open the Settings app. On its main list, choose Accessibility.",
            reportLabel: "I'm in Settings"),
        BackTapGuideStep(
            id: "accessibility", title: "Choose Touch", route: "Settings → Accessibility",
            instruction: "In Accessibility, find the Physical and Motor section, then choose Touch.",
            reportLabel: "I'm in Accessibility"),
        BackTapGuideStep(
            id: "touch", title: "Find Back Tap", route: "Settings → Accessibility → Touch",
            instruction: "Scroll down in Touch and choose Back Tap.",
            reportLabel: "I'm in Touch"),
        BackTapGuideStep(
            id: "back-tap", title: "Choose Double Tap", route: "Settings → Accessibility → Touch → Back Tap",
            instruction: "Choose Double Tap. If it already has an action you want to keep, you can leave this for later.",
            reportLabel: "I'm in Back Tap"),
        BackTapGuideStep(
            id: "double-tap", title: "Choose your shortcut", route: "Back Tap → Double Tap",
            instruction: "Scroll to the Shortcuts section and choose Open Doddy. Then go back.",
            reportLabel: "I'm in Double Tap"),
        BackTapGuideStep(
            id: "assigned", title: "Let's try it", route: "Double Tap → Open Doddy",
            instruction: "With the shortcut chosen, come back to Doddy and start the test. Then double-tap the back of your iPhone.",
            reportLabel: "I chose Open Doddy"),
    ]

    /// Index of the step the user can be sent back to when the shortcut arrived some other way.
    public static let chooseShortcutStepIndex = 4

    /// Steps on which the user can report a Settings page (the last step is the test intro).
    public static var reportableSteps: ArraySlice<BackTapGuideStep> { steps.dropLast() }

    /// The step matching a reported page: its id, title, report label or bare page name
    /// ("Touch", "Back Tap"), ignoring case and curly apostrophes. Nil when unknown, in which
    /// case the app asks which page the user is on instead of guessing.
    public static func stepIndex(reportedPage: String) -> Int? {
        let wanted = normalize(reportedPage)
        guard !wanted.isEmpty else { return nil }
        return steps.firstIndex { step in
            let page = step.route.components(separatedBy: "→").last ?? ""
            return [step.id, step.title, step.reportLabel, page].map(normalize).contains(wanted)
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
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
    /// "First, the shortcut": create and run the personal Open Doddy shortcut.
    case shortcutPreparation
    /// Settings walkthrough, by step index into `BackTapGuide.steps`.
    case guiding(step: Int)
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
    case start
    case shortcutReady
    /// The user reports which Settings page they are on (a report label, step id or page name).
    case report(page: String)
    case next
    case previous
    case startTest(now: Date)
    case receipt(ShortcutReceipt)
    /// "Yes, I used Double Back Tap."
    case confirmDoubleTap(now: Date)
    /// "I ran it another way": the receipt is discarded and the guide resumes.
    case otherTrigger
    case deferSetup
    /// Reopen the guide from Settings after it was deferred or completed.
    case revisit
}

public enum BackTapSetupOutcome: Equatable, Sendable {
    case accepted
    case ignored(String)
}

/// Deterministic guided-setup state. It stores what the user reported and whether Doddy's
/// intent ran during an active test window. It never stores a system-verified assignment,
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

    public var currentStep: BackTapGuideStep? {
        if case .guiding(let index) = phase, BackTapGuide.steps.indices.contains(index) {
            return BackTapGuide.steps[index]
        }
        return nil
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
        case .notStarted, .shortcutPreparation, .guiding:
            BackTapSetupSummary(status: .notStarted, testedAt: nil, guideVersion: BackTapGuide.version, activeTest: nil)
        }
    }

    @discardableResult
    public mutating func handle(_ event: BackTapSetupEvent) -> BackTapSetupOutcome {
        switch (event, phase) {
        case (.start, .notStarted), (.start, .deferred), (.revisit, .deferred), (.revisit, .userReportedTested):
            phase = .shortcutPreparation
            return .accepted
        case (.start, _):
            return .ignored("already started")
        case (.revisit, _):
            return .ignored("setup is in progress")

        case (.shortcutReady, .shortcutPreparation):
            phase = .guiding(step: 0)
            return .accepted
        case (.shortcutReady, _):
            return .ignored("not at the shortcut step")

        case (.report(let page), .shortcutPreparation), (.report(let page), .guiding),
             (.report(let page), .testing), (.report(let page), .receiptReceived):
            guard let index = BackTapGuide.stepIndex(reportedPage: page) else {
                return .ignored("unknown page")
            }
            phase = .guiding(step: index)
            return .accepted
        case (.report, _):
            return .ignored("not guiding")

        case (.next, .guiding(let index)):
            guard index + 1 < BackTapGuide.steps.count else { return .ignored("last step; start the test") }
            phase = .guiding(step: index + 1)
            return .accepted
        case (.next, _):
            return .ignored("not guiding")

        case (.previous, .guiding(let index)):
            phase = index == 0 ? .shortcutPreparation : .guiding(step: index - 1)
            return .accepted
        case (.previous, _):
            return .ignored("not guiding")

        case (.startTest(let now), .shortcutPreparation), (.startTest(let now), .guiding), (.startTest(let now), .testing):
            phase = .testing(BackTapTestWindow(startedAt: now, duration: Self.testWindowDuration))
            return .accepted
        case (.startTest, _):
            return .ignored("start the guide first")

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
            phase = .guiding(step: BackTapGuide.chooseShortcutStepIndex)
            return .accepted
        case (.otherTrigger, _):
            return .ignored("no receipt to discard")

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
