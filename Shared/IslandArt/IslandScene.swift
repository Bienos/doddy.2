import Foundation

/// The looks the voice island can take (ADR-211): the owner's V4 boards that have a voice
/// conversation state. Chosen in Settings → Voice → Dynamic Island style; Lean In by default.
enum IslandStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case leanIn, orbit, inkRipple, negativeSpace, editorial, abstractHorizon, hereWithYou

    var board: IslandBoard {
        switch self {
        case .leanIn: .leanIn
        case .orbit: .orbit
        case .inkRipple: .inkRipple
        case .negativeSpace: .negativeSpace
        case .editorial: .editorial
        case .abstractHorizon: .abstractHorizon
        case .hereWithYou: .hereWithYou
        }
    }

    /// The pack's names (Design-notes.md).
    var displayName: String {
        switch self {
        case .leanIn: "Lean In"
        case .orbit: "Orbit"
        case .inkRipple: "Ink Ripple"
        case .negativeSpace: "Negative Space"
        case .editorial: "Editorial"
        case .abstractHorizon: "Abstract Horizon"
        case .hereWithYou: "Here With You"
        }
    }

    /// The pack's one-line rationale for each (Design-notes.md, "Rationale for all sixteen").
    var summary: String {
        switch self {
        case .leanIn: "A cupped hand and short voice bars: Doddy leaning in to listen."
        case .orbit: "A quiet dial around Doddy; one orange segment while he can hear you."
        case .inkRipple: "A cream ink shape with an orange energy line under it."
        case .negativeSpace: "A cream crescent holds Doddy's face and an offered hand."
        case .editorial: "Big type does the work, with a small Doddy in the corner."
        case .abstractHorizon: "Doddy above two soft horizon lines, with an orange marker."
        case .hereWithYou: "Two small hands and a conversation loop: here, without taking over."
        }
    }
}

/// What the right-hand sign shows.
enum IslandSign: Equatable, Sendable {
    case none
    /// The pack's voice bars; a fixed sign that Doddy can hear you, not a microphone level.
    case bars
    /// Three dots; the middle one orange only while live.
    case dots
    case symbol(String, IslandTint)
    case text(String)
    /// The running conversation time.
    case elapsed
    case check
}

enum IslandTint: Equatable, Sendable {
    case secondary, accent, warning, orange
}

/// The top-right slot of the expanded island.
enum IslandTime: Equatable, Sendable {
    case elapsed
    case text(String)
}

/// Everything the island draws, as plain data, so the widget and the Settings preview show
/// exactly the same thing. Built only from real state (`DoddyVoiceAttributes.ContentState`).
struct IslandScene: Equatable, Sendable {
    var board: IslandBoard
    var scenario: Int
    /// Doddy's expression; nil keeps the board's own.
    var face: IslandFace?
    /// Doddy can hear you right now: orange is allowed, the LIVE tag shows.
    var live: Bool
    var showsHands: Bool
    var label: String
    var time: IslandTime
    var title: String
    var subtitle: String
    var subtitleIsWarning: Bool
    /// Beside the buttons in the expanded view (only Lean In has one on the board).
    var expandedSign: IslandSign
    var compactSign: IslandSign
    var minimalSign: IslandSign

    func art(_ presentation: IslandPresentation) -> IslandArt {
        IslandBoardArt.art(board, scenario: scenario, presentation)
    }
}

extension DoddyVoiceAttributes.ContentState {
    /// The island for this state. `isStale`: iOS reports the app has not refreshed it (ADR-055).
    func islandScene(isStale: Bool) -> IslandScene {
        let stale = isStale && !isEnded
        let live = !stale && isLiveCue && status != .connecting
        if !stale, let moment, let scene = momentScene(moment, live: live) {
            return scene
        }
        return voiceScene(stale: stale, live: live)
    }

    private var face: IslandFace {
        if isEnded { return savedCount > 0 ? .proud : .calm }
        if showsMuted { return .calm }
        switch status {
        case .listening: return .listening
        case .speaking: return .speaking
        case .thinking, .needsConfirmation: return .thinking
        default: return .calm
        }
    }

    /// The running-conversation sign: bars while listening or speaking, dots while thinking or
    /// connecting, otherwise a symbol for what is wrong or waiting.
    private func voiceSign(stale: Bool) -> IslandSign {
        if stale { return .symbol("exclamationmark.triangle.fill", .warning) }
        if showsMuted { return .symbol("mic.slash.fill", .secondary) }
        switch status {
        case .listening, .speaking: return .bars
        case .thinking, .connecting: return .dots
        case .needsConfirmation: return .symbol("hand.tap.fill", .accent)
        default: return .symbol(symbolName, .secondary)
        }
    }

    private func voiceScene(stale: Bool, live: Bool) -> IslandScene {
        let style = islandStyle
        let sign = voiceSign(stale: stale)
        let compact: IslandSign = style == .hereWithYou && (status == .listening || status == .speaking) && !showsMuted && !stale
            ? .elapsed : sign
        let minimal: IslandSign = (sign == .bars || sign == .dots) ? sign : .none
        return IslandScene(
            board: style.board,
            // Here With You draws thinking on its second board (dots under Doddy).
            scenario: style == .hereWithYou && status == .thinking && !stale ? 1 : 0,
            face: stale ? .calm : face,
            live: live,
            // Lean In's hand at his ear means "listening", so it goes when he can't hear you.
            showsHands: style == .leanIn ? live : true,
            label: "VOICE",
            time: .elapsed,
            title: stale ? "Lost Doddy — open the app" : title,
            subtitle: stale ? "The app stopped in the background" : islandLine,
            subtitleIsWarning: stale,
            expandedSign: style == .leanIn ? sign : .none,
            compactSign: compact,
            minimalSign: minimal)
    }

    /// Second line under the status. Never words from the conversation.
    private var islandLine: String {
        if let detail { return detail }
        switch status {
        case .connecting: return "Getting ready"
        case .listening: return "Talk it through"
        case .thinking: return "One moment"
        case .speaking: return "One step at a time"
        default: return "Doddy"
        }
    }

    /// Thought Pocket, Step Stones and Reminder Knot for moments in a conversation (ADR-212).
    /// Only the kind of moment and counts are shown, never what the note or reminder says.
    private func momentScene(_ moment: Moment, live: Bool) -> IslandScene? {
        func scene(_ board: IslandBoard, _ scenario: Int, label: String, time: IslandTime, title: String,
                   subtitle: String, compact: IslandSign, minimal: IslandSign) -> IslandScene {
            IslandScene(board: board, scenario: scenario, face: nil, live: live, showsHands: true, label: label,
                        time: time, title: title, subtitle: subtitle, subtitleIsWarning: false,
                        expandedSign: .none, compactSign: compact, minimalSign: minimal)
        }
        let waiting = IslandSign.symbol("hand.tap.fill", .accent)
        switch moment {
        case .noteWaiting:
            return scene(.thoughtPocket, 0, label: "NOTE", time: .elapsed, title: "Save this note?",
                         subtitle: "Open Doddy to Save or Don't save", compact: waiting, minimal: .none)
        case .noteSaved:
            return scene(.thoughtPocket, 1, label: "NOTE", time: .text("Saved"), title: "Note saved",
                         subtitle: "Kept in Doddy on this iPhone", compact: .check, minimal: .none)
        case .planWaiting(let steps):
            return scene(.stepStones, 1, label: "PLAN", time: .text(steps == 1 ? "1 step" : "\(steps) steps"),
                         title: "Plan ready", subtitle: "Open Doddy to check the steps", compact: waiting, minimal: .none)
        case .planRunning(let step, let steps):
            return scene(.stepStones, 1, label: "PLAN", time: .text("\(step) / \(steps)"), title: "Doing the plan",
                         subtitle: "Step \(step) of \(steps)", compact: .text("\(step)/\(steps)"), minimal: .text("\(step)"))
        case .reminderWaiting:
            return scene(.reminderKnot, 0, label: "REMINDER", time: .elapsed, title: "Add this reminder?",
                         subtitle: "Open Doddy to confirm it", compact: waiting, minimal: .none)
        case .reminderAdding:
            return scene(.reminderKnot, 0, label: "REMINDER", time: .elapsed, title: "Adding reminder",
                         subtitle: "Waiting for Reminders to confirm", compact: .dots, minimal: .none)
        case .reminderSet:
            return scene(.reminderKnot, 1, label: "REMINDER", time: .text("Set"), title: "Reminder set",
                         subtitle: "Reminders confirmed it", compact: .check, minimal: .none)
        }
    }
}
