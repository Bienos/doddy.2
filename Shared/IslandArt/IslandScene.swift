import Foundation

/// The looks the voice island can take (ADR-239): the owner's V4 boards that have a voice
/// conversation state, and Whole Doddy (ADR-264), his whole body from the owner's pose pack.
/// Chosen in Settings → Voice → Dynamic Island style; Whole Doddy until the user picks one
/// (ADR-267). Settings lists them in this order.
enum IslandStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case wholeDoddy, leanIn, orbit, inkRipple, negativeSpace, editorial, abstractHorizon, hereWithYou

    /// The style used until the user picks one in Settings (owner: "make whole doddy the default
    /// style", ADR-267). A style the user picked is stored and kept.
    static let preferredDefault: IslandStyle = .wholeDoddy

    /// The style stored in Settings, or the default when none is (or an unknown one is) stored.
    static func stored(_ raw: String?) -> IslandStyle {
        raw.flatMap(IslandStyle.init(rawValue:)) ?? preferredDefault
    }

    var board: IslandBoard {
        switch self {
        case .leanIn: .leanIn
        case .orbit: .orbit
        case .inkRipple: .inkRipple
        case .negativeSpace: .negativeSpace
        case .editorial: .editorial
        case .abstractHorizon: .abstractHorizon
        case .hereWithYou: .hereWithYou
        // Drawn from `IslandPose`; Lean In's board only backs its signs and sizes.
        case .wholeDoddy: .leanIn
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
        case .wholeDoddy: "Whole Doddy"
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
        case .wholeDoddy: "Doddy's whole body from your pose pack: his pose shows what he's doing."
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
    /// Time left until this moment, ticking without app updates.
    case countdown(Date)
    case check
}

enum IslandTint: Equatable, Sendable {
    case secondary, accent, warning, orange
}

/// The top-right slot of the expanded island.
enum IslandTime: Equatable, Sendable {
    case elapsed
    case countdown(Date)
    case text(String)
}

/// The status line: words, or a countdown in the focus board's 32 pt numerals.
enum IslandTitle: Equatable, Sendable {
    case text(String)
    case countdown(Date)
    /// A fixed time left (paused), in the same big numerals.
    case bigText(String)
}

/// A short word drawn on the art itself, where the board has text the generator leaves out
/// (Language Bridge's two speech bubbles). Board units; `x`, `y` is the word's centre.
struct IslandArtLabel: Equatable, Sendable {
    var text: String
    var x: Double
    var y: Double
    var size: Double
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
    /// When set, drawn instead of `title` (which stays as its spoken form).
    var bigTitle: IslandTitle?
    var subtitle: String
    var subtitleIsWarning: Bool
    /// Beside the buttons in the expanded view (only Lean In has one on the board).
    var expandedSign: IslandSign
    var compactSign: IslandSign
    var minimalSign: IslandSign
    /// Minimal boards without a face (Tiny Promise) put the sign in the middle.
    var minimalSignCentred = false
    /// Words on the expanded drawing, in black on its cream shapes.
    var artLabels: [IslandArtLabel] = []
    /// Whole Doddy (ADR-264): drawn instead of the board's art when set.
    var pose: IslandPose?

    func art(_ presentation: IslandPresentation) -> IslandArt {
        IslandBoardArt.art(board, scenario: scenario, presentation)
    }
}

extension DoddyVoiceAttributes.ContentState {
    /// The island for this state. `isStale`: iOS reports the app has not refreshed it (ADR-055).
    func islandScene(isStale: Bool) -> IslandScene {
        let stale = isStale && !isEnded
        let live = !stale && isLiveCue && status != .connecting
        var scene: IslandScene
        if !stale, let moment, let shown = momentScene(moment, live: live) {
            scene = shown
        } else {
            scene = voiceScene(stale: stale, live: live)
        }
        if islandStyle == .wholeDoddy { scene.pose = wholeDoddyPose(stale: stale) }
        return scene
    }

    /// Whole Doddy's pose for this state (ADR-264). One pose means one thing everywhere. Nil
    /// keeps the moment's own board: translating stays on Language Bridge.
    func wholeDoddyPose(stale: Bool) -> IslandPose? {
        if stale { return .facepalm }
        if let moment {
            switch moment {
            case .noteWaiting, .reminderWaiting, .reminderAdding: return .reachingHigh
            case .noteSaved, .reminderSet: return .fistpump
            case .planWaiting, .planRunning: return .tiptoe
            case .translating: return nil
            }
        }
        if isEnded { return .fistpump }
        if showsMuted { return .shush }
        let greets = !(greeting ?? "").isEmpty
        switch status {
        // The greeting after "Hey Doddy" is a wave (ADR-290), also while he says it (ADR-576).
        case .connecting: return greets ? .wave : .yawnStretch
        case .listening: return greets ? .wave : .listening
        case .thinking: return .kneelingInspect
        case .speaking: return greets ? .wave : .shrug
        case .needsConfirmation: return .reachingHigh
        case .wakeListening: return .crosslegged
        case .wakePaused: return .leaning
        case .ended: return .fistpump
        #if DEBUG
        case .testFixture: return .listening
        #endif
        }
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
            // "Hey Doddy" waiting (ADR-254) is not a conversation: no timer, its own label.
            label: isWakeMode ? "HEY DODDY" : "VOICE",
            time: isWakeMode ? .text("") : .elapsed,
            title: stale ? (isWakeMode ? "Not listening — open Doddy" : "Lost Doddy — open the app") : title,
            bigTitle: nil,
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

    /// Thought Pocket, Step Stones and Reminder Knot for moments in a conversation (ADR-240).
    /// Only the kind of moment and counts are shown, never what the note or reminder says.
    private func momentScene(_ moment: Moment, live: Bool) -> IslandScene? {
        func scene(_ board: IslandBoard, _ scenario: Int, label: String, time: IslandTime, title: String,
                   subtitle: String, compact: IslandSign, minimal: IslandSign) -> IslandScene {
            IslandScene(board: board, scenario: scenario, face: nil, live: live, showsHands: true, label: label,
                        time: time, title: title, bigTitle: nil, subtitle: subtitle, subtitleIsWarning: false,
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
        case .translating(let from, let to, let bothWays):
            // Language Bridge, first board only (ADR-244): the board's second one, "Translation
            // ready / Hear it", has no step in a live conversation. Translator mode is private,
            // so only the pair is drawn, and only as codes (`IslandLanguageCode`).
            let a = IslandLanguageCode.shown(from), b = IslandLanguageCode.shown(to)
            var s = scene(.languageBridge, 0, label: "TRANSLATE", time: .elapsed, title: "Translating",
                          subtitle: "\(a) \(bothWays ? "⇄" : "→") \(b)",
                          compact: .text(bothWays ? "⇄ \(b)" : "→ \(b)"), minimal: .text(b))
            // The two bubbles' centres on board H (language-bridge-0-expanded.svg).
            s.artLabels = [IslandArtLabel(text: a, x: 34, y: 96, size: 10),
                           IslandArtLabel(text: b, x: 71.5, y: 96, size: 10)]
            return s
        }
    }
}

/// Language codes as the island shows them. Translator mode is private (ADR-215, ADR-244): the
/// island may show which languages, never what was said, so anything that is not a 2–3 letter
/// code is drawn as "?" rather than shown.
enum IslandLanguageCode {
    static func shown(_ code: String) -> String {
        let letters = code.unicodeScalars
        guard (2...3).contains(letters.count),
              letters.allSatisfy({ ("a"..."z").contains($0) || ("A"..."Z").contains($0) }) else { return "?" }
        return code.uppercased()
    }
}

extension DoddyToolAttributes {
    /// The island for the focus timer (Tiny Promise, ADR-241), breathing (Calm Tide, ADR-242)
    /// and reading a note aloud (Story Spool, ADR-243). `isStale`: iOS says the app has not
    /// updated it; a focus or breathing activity is given its end time as its stale date, so
    /// stale there means the time is up.
    func islandScene(_ state: ContentState, isStale: Bool, now: Date = Date()) -> IslandScene {
        var shown = boardScene(state, isStale: isStale, now: now)
        if state.islandStyle == .wholeDoddy { shown.pose = wholeDoddyPose(state, isStale: isStale) }
        return shown
    }

    /// Whole Doddy's pose for a tool (ADR-299, ADR-313): dribbling while focusing, balancing on
    /// one leg while breathing, reading lying on his front. Done, waiting and lost are the same
    /// poses as in a conversation (fist pump, cross-legged, facepalm).
    func wholeDoddyPose(_ state: ContentState, isStale: Bool) -> IslandPose {
        if isStale && kind == .readAloud { return .facepalm }
        if state.isFinished || isStale { return .fistpump }
        if state.isPaused { return .crosslegged }
        switch kind {
        case .focus: return .basketballDribble
        case .breathing: return .onelegBalance
        case .readAloud: return .bellyReading
        }
    }

    /// The owner's V4 board for a tool, before any Whole Doddy pose.
    private func boardScene(_ state: ContentState, isStale: Bool, now: Date) -> IslandScene {
        let over = state.isFinished || (isStale && kind != .readAloud)
        let lost = isStale && kind == .readAloud
        let running = !over && !lost && !state.isPaused
        func scene(_ board: IslandBoard, _ scenario: Int, label: String, time: IslandTime, title: String,
                   bigTitle: IslandTitle? = nil, subtitle: String, warning: Bool = false,
                   compact: IslandSign, minimal: IslandSign, centred: Bool = false) -> IslandScene {
            IslandScene(board: board, scenario: scenario, face: nil, live: running, showsHands: true, label: label,
                        time: time, title: title, bigTitle: bigTitle, subtitle: subtitle, subtitleIsWarning: warning,
                        expandedSign: .none, compactSign: compact, minimalSign: minimal, minimalSignCentred: centred)
        }
        switch kind {
        case .focus:
            let minutes = "\(Int((duration / 60).rounded())) min"
            if over {
                return scene(.tinyPromise, 0, label: "FOCUS", time: .text("Done"), title: "Time's up",
                             subtitle: state.label ?? "Focus finished", compact: .check, minimal: .check, centred: true)
            }
            if state.isPaused {
                let left = Self.clock(state.remaining)
                return scene(.tinyPromise, 1, label: "FOCUS", time: .text("Paused"), title: "Paused, \(left) left",
                             bigTitle: .bigText(left), subtitle: state.label ?? "Ready when you are",
                             compact: .text(left), minimal: .text("\(Int((state.remaining / 60).rounded(.up)))m"), centred: true)
            }
            let end = state.endsAt ?? now
            return scene(.tinyPromise, 0, label: "FOCUS", time: .text(minutes), title: "Focusing",
                         bigTitle: .countdown(end), subtitle: state.label ?? "One thing at a time",
                         compact: .countdown(end), minimal: .countdown(end), centred: true)
        case .breathing:
            if over {
                return scene(.calmTide, 1, label: "BREATHE", time: .text("Done"), title: "Breathing done",
                             subtitle: "Nicely done", compact: .check, minimal: .none)
            }
            let end = state.endsAt ?? now
            return scene(.calmTide, 0, label: "BREATHE", time: .countdown(end), title: "Breathing",
                         subtitle: "Open Doddy to follow along", compact: .countdown(end), minimal: .none)
        case .readAloud:
            var shown: IslandScene
            if lost {
                shown = scene(.storySpool, 1, label: "READ ALOUD", time: .text(""), title: "Stopped",
                              subtitle: "Open Doddy to read it again", warning: true,
                              compact: .symbol("exclamationmark.triangle.fill", .warning), minimal: .none)
            } else if over {
                shown = scene(.storySpool, 1, label: "READ ALOUD", time: .text("Done"), title: "Finished reading",
                              subtitle: "Your note", compact: .check, minimal: .none)
            } else if state.isPaused {
                shown = scene(.storySpool, 1, label: "READ ALOUD", time: .text("Paused"), title: "Paused",
                              subtitle: "Pick up where you left off", compact: .symbol("pause.fill", .secondary), minimal: .none)
            } else {
                shown = scene(.storySpool, 0, label: "READ ALOUD", time: .text("Note"), title: "Reading aloud",
                              subtitle: "Your note", compact: .bars, minimal: .bars)
            }
            return shown
        }
    }

    /// "12:48" for a time left.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
