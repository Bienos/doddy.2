import Foundation

/// The look of the voice island: Whole Doddy (ADR-264), his whole body from the owner's pose
/// pack. It is the only one: the seven other looks from the V4 pack (Lean In, Orbit, Ink Ripple,
/// Negative Space, Editorial, Abstract Horizon, Here With You) and their Settings picker were
/// removed on the owner's say-so, so the island is never a mix of two designs. A style stored by
/// an older build is ignored and decodes as Whole Doddy.
enum IslandStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case wholeDoddy

    /// Any stored value, such as a look an older build wrote ("leanIn", "orbit"), reads as Whole
    /// Doddy: a running island from before the others were removed keeps updating.
    init(from decoder: any Decoder) throws {
        self = .wholeDoddy
    }

    /// Drawn from `IslandPose`; the voice board's art only backs its signs and sizes.
    var board: IslandBoard { .leanIn }
}

/// Doddy's orange waves on the Whole Doddy island (ADR-596): a line beside his status while he
/// can hear you, the whole island in lines while he talks. Never while muted, stale, ended, or
/// during a moment (a card waiting, a reminder set), which keeps its own sign.
enum IslandWaveState: Equatable, Sendable {
    case none, listening, speaking
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
    /// The stopwatch's time so far, counting up from the clock start (ADR-652).
    case elapsed
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
    /// Whether the minimal island (another app's activity is also running) draws Whole Doddy's face.
    /// Not with a centred sign: the timer, wind-down, focus and stopwatch put their time, tick or
    /// symbol in the middle of the small bubble, and his face drawn there too covered it (seen on a
    /// phone on 8 Nov 2026: a timer's "14:34" behind his face).
    var minimalShowsPoseFace: Bool { pose != nil && !(minimalSignCentred && minimalSign != .none) }
    /// Words on the expanded drawing, in black on its cream shapes.
    var artLabels: [IslandArtLabel] = []
    /// Whole Doddy (ADR-264): drawn instead of the board's art when set.
    var pose: IslandPose?
    /// Whole Doddy's waves (ADR-596).
    var waves: IslandWaveState = .none
    /// His beat while he talks and Doddy is not on screen (ADR-683), 0 to `IslandScene.maxBeat`;
    /// nil when the app sends none, and always nil unless `waves` is `.speaking`.
    var voiceBeat: Int?
    /// Something waits for the user in the conversation, or is ready there: the expanded island's
    /// main button is Show (`doddy://conversation`), which opens it (ADR-616). Opening approves nothing.
    var showsInDoddy = false

    func art(_ presentation: IslandPresentation) -> IslandArt {
        IslandBoardArt.art(board, scenario: scenario, presentation)
    }
}

/// How the island moves with his beat (ADR-683). Outside the app the island can't run Home's
/// moving strip (`IslandExtension`): iOS draws a Live Activity again only when the app sends an
/// update, and keeps everything inside the island's black shape. The owner picked option C,
/// "Aurora, like Home", on 1 Nov 2026 from the island pulse board: the small island draws his
/// voice as Home's fine orange-to-rose lines beside his head, taller with each beat; no halo, no
/// glow, and the island's outline stays as it was. iOS moves between two beats with its own short
/// animation. Plain numbers here so they are checked on Linux (`IslandSceneChecks`).
extension IslandScene {
    /// The loudest beat (`IslandVoiceBeat.maxStep` in DoddyCore, which the widget can't import).
    static let maxBeat = 4

    /// 0 for a pause between his words, 1 for his loudest; nil with no beat.
    var beatStrength: Double? {
        voiceBeat.map { Double($0) / Double(Self.maxBeat) }
    }

    /// How tall the big island's talking waves are drawn: as they always were with no beat, a
    /// little lower in a pause. Never taller: they stay in their band under his status (ADR-615).
    var beatWaveScale: Double {
        guard let strength = beatStrength else { return 1 }
        return 0.75 + 0.25 * strength
    }

    /// How many bars the small island's voice has: a few round bars like the iPhone's own call
    /// island (owner, 9 Nov 2026), not Home's fine lines.
    static let auroraColumnCount = 7

    /// How strongly the aurora is drawn, 0 to 1: calm while he hears you (Home's listening level),
    /// steady while he talks with no beat (Doddy on screen, Reduce Motion, before the first beat),
    /// and with each beat from a pause (0.15) to his loudest (1).
    var auroraLevel: Double {
        switch waves {
        case .none: return 0
        case .listening: return 0.5
        case .speaking:
            guard let voiceBeat else { return 0.6 }
            let levels = [0.15, 0.4, 0.6, 0.8, 1]
            return levels[min(levels.count - 1, max(0, voiceBeat))]
        }
    }

    /// The small island's aurora (option C): Home's fine lines, orange at the left, amber in the
    /// middle, rose at the right, highest in the middle and fading to the ends. Each line's height
    /// is a fraction of the band. While he talks each beat gives the lines their own shape, so two
    /// beats in a row never look the same; while he hears you, and with no beat, they stand still.
    /// Empty when the island shows no waves (muted, a moment, stale).
    var aurora: [IslandAuroraColumn] {
        guard waves != .none else { return [] }
        let level = auroraLevel
        let n = Self.auroraColumnCount
        let phase = voiceBeat.map(Double.init)
        return (0..<n).map { k in
            let u = Double(k) / Double(n - 1)
            // Bars like a call: the middle ones tallest, the outer ones short.
            let envelope = 0.45 + 0.55 * sin(Double.pi * (0.1 + 0.8 * u))
            let noise: Double
            if waves == .speaking, let t = phase {
                let kk = Double(k)
                noise = 0.6 + 0.25 * sin(kk * 2.3 + t * 1.7) + 0.15 * sin(kk * 4.1 - t * 2.9)
            } else {
                noise = 0.8 + 0.2 * sin(Double(k) * 1.7)
            }
            let height = min(1, max(0.06, (0.12 + 0.88 * level) * envelope * noise))
            return IslandAuroraColumn(height: height, colour: Self.warm(u))
        }
    }

    /// Home's colours (`IslandExtension`): orange at the left, amber in the middle, rose at the
    /// right, as 0 to 1 red, green, blue.
    static func warm(_ u: Double) -> IslandRGB {
        let orange = IslandRGB(red: 236, green: 128, blue: 63)
        let amber = IslandRGB(red: 255, green: 176, blue: 102)
        let rose = IslandRGB(red: 229, green: 82, blue: 107)
        func mix(_ a: IslandRGB, _ b: IslandRGB, _ amount: Double) -> IslandRGB {
            let k = min(1, max(0, amount))
            return IslandRGB(red: a.red + (b.red - a.red) * k, green: a.green + (b.green - a.green) * k,
                             blue: a.blue + (b.blue - a.blue) * k)
        }
        let c = u < 0.5 ? mix(orange, amber, u * 1.2) : mix(amber, rose, (u - 0.5) * 1.4)
        return IslandRGB(red: c.red / 255, green: c.green / 255, blue: c.blue / 255)
    }
}

/// A colour as red, green and blue (0 to 255 while it is mixed, 0 to 1 once `warm` returns it).
struct IslandRGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

/// One fine line of the small island's aurora (ADR-683, option C).
struct IslandAuroraColumn: Equatable, Sendable {
    /// Its height as a fraction of the band, 0.06 to 1.
    var height: Double
    var colour: IslandRGB
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
        if islandStyle == .wholeDoddy {
            scene.pose = wholeDoddyPose(stale: stale)
            scene.waves = wholeDoddyWaves(stale: stale)
        }
        // ADR-683: only over his talking waves; a stale island never pulses.
        if scene.waves == .speaking, let voiceBeat {
            scene.voiceBeat = min(IslandScene.maxBeat, max(0, voiceBeat))
        }
        return scene
    }

    /// Whole Doddy's waves for this state (ADR-596): only from real provider states, only while
    /// he can hear you, and not while a moment is on the island.
    func wholeDoddyWaves(stale: Bool) -> IslandWaveState {
        guard !stale, !isEnded, moment == nil, !showsMuted, isLiveCue else { return .none }
        switch status {
        case .listening: return .listening
        case .speaking: return .speaking
        default: return .none
        }
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
            // ADR-616: a card waits (he reaches for it), or what he made is ready (fist pump).
            case .actionWaiting: return .reachingHigh
            case .resultReady(let result): return result == .documentStarted ? .tiptoe : .fistpump
            }
        }
        // A failure is the facepalm, as on the voice screen; a normal end the fist pump.
        if isFailed { return .facepalm }
        if isEnded { return .fistpump }
        if showsMuted { return .shush }
        let greets = !(greeting ?? "").isEmpty
        switch status {
        // The greeting is a wave (ADR-290), also while he says it (ADR-577).
        case .connecting: return greets ? .wave : .yawnStretch
        case .listening: return greets ? .wave : .listening
        case .thinking: return .kneelingInspect
        case .speaking: return greets ? .wave : .shrug
        case .needsConfirmation: return .reachingHigh
        case .ended: return .fistpump
        case .failed: return .facepalm
        #if DEBUG
        case .testFixture: return .listening
        #endif
        }
    }

    private var face: IslandFace {
        if isEnded { return savedCount > 0 && !isFailed ? .proud : .calm }
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
        let sign = voiceSign(stale: stale)
        let compact: IslandSign = sign
        let minimal: IslandSign = (sign == .bars || sign == .dots) ? sign : .none
        var scene = IslandScene(
            board: islandStyle.board,
            scenario: 0,
            face: stale ? .calm : face,
            live: live,
            showsHands: true,
            label: islandWord("VOICE"),
            time: .elapsed,
            title: stale ? islandWord("Lost Doddy — open the app") : title,
            bigTitle: nil,
            subtitle: stale ? islandWord("The app stopped in the background") : islandLine,
            subtitleIsWarning: stale,
            expandedSign: .none,
            compactSign: compact,
            minimalSign: minimal)
        // A card waits in Doddy (ADR-616): Show opens it. Not when stale: there is no card to show.
        scene.showsInDoddy = !stale && status == .needsConfirmation
        return scene
    }

    /// Second line under the status. Never words from the conversation.
    private var islandLine: String {
        if let detail { return detail }
        switch status {
        case .connecting: return islandWord("Getting ready")
        case .listening: return islandWord("Talk it through")
        case .thinking: return islandWord("One moment")
        case .speaking: return islandWord("One step at a time")
        default: return islandWord("Doddy")
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
            var s = scene(.thoughtPocket, 0, label: islandWord("NOTE"), time: .elapsed, title: "Save this note?",
                          subtitle: "Open Doddy to Save or Don't save", compact: waiting, minimal: .none)
            s.showsInDoddy = true
            return s
        case .noteSaved:
            return scene(.thoughtPocket, 1, label: islandWord("NOTE"), time: .text(islandWord("Saved")), title: "Note saved",
                         subtitle: "Kept in Doddy on this iPhone", compact: .check, minimal: .none)
        case .planWaiting(let steps):
            var s = scene(.stepStones, 1, label: islandWord("PLAN"), time: .text(steps == 1 ? islandWord("1 step") : "\(steps) steps"),
                          title: "Plan ready", subtitle: "Open Doddy to check the steps", compact: waiting, minimal: .none)
            s.showsInDoddy = true
            return s
        case .planRunning(let step, let steps):
            return scene(.stepStones, 1, label: islandWord("PLAN"), time: .text("\(step) / \(steps)"), title: "Doing the plan",
                         subtitle: "Step \(step) of \(steps)", compact: .text("\(step)/\(steps)"), minimal: .text("\(step)"))
        case .reminderWaiting:
            var s = scene(.reminderKnot, 0, label: islandWord("REMINDER"), time: .elapsed, title: "Add this reminder?",
                          subtitle: "Open Doddy to confirm it", compact: waiting, minimal: .none)
            s.showsInDoddy = true
            return s
        case .reminderAdding:
            return scene(.reminderKnot, 0, label: islandWord("REMINDER"), time: .elapsed, title: "Adding reminder",
                         subtitle: "Waiting for Reminders to confirm", compact: .dots, minimal: .none)
        case .reminderSet:
            return scene(.reminderKnot, 1, label: islandWord("REMINDER"), time: .text(islandWord("Set")), title: "Reminder set",
                         subtitle: "Reminders confirmed it", compact: .check, minimal: .none)
        case .translating(let from, let to, let bothWays):
            // Language Bridge, first board only (ADR-244): the board's second one, "Translation
            // ready / Hear it", has no step in a live conversation. Translator mode is private,
            // so only the pair is drawn, and only as codes (`IslandLanguageCode`).
            let a = IslandLanguageCode.shown(from), b = IslandLanguageCode.shown(to)
            var s = scene(.languageBridge, 0, label: islandWord("TRANSLATE"), time: .elapsed, title: "Translating",
                          subtitle: "\(a) \(bothWays ? "⇄" : "→") \(b)",
                          compact: .text(bothWays ? "⇄ \(b)" : "→ \(b)"), minimal: .text(b))
            // The two bubbles' centres on board H (language-bridge-0-expanded.svg).
            s.artLabels = [IslandArtLabel(text: a, x: 34, y: 96, size: 10),
                           IslandArtLabel(text: b, x: 71.5, y: 96, size: 10)]
            return s
        case .actionWaiting(let action):
            // ADR-616: the kind of card only, in fixed words; the card itself is in Doddy.
            let words = action.island
            var s = scene(.thoughtPocket, 0, label: words.label, time: .elapsed, title: words.title,
                          subtitle: words.subtitle, compact: waiting, minimal: .none)
            s.showsInDoddy = true
            return s
        case .resultReady(let result):
            let words = result.island
            var s = scene(.thoughtPocket, result == .documentStarted ? 0 : 1, label: words.label,
                          time: result == .documentStarted ? .elapsed : .text(islandWord("Ready")), title: words.title,
                          subtitle: words.subtitle, compact: result == .documentStarted ? .dots : .check, minimal: .none)
            s.showsInDoddy = true
            return s
        }
    }
}

/// What the island says for each kind of card (ADR-616): a label beside the camera, a title and
/// a second line, all fixed words. A change never happens from the island: Show opens the card.
struct IslandWords: Equatable, Sendable {
    let label: String
    let title: String
    let subtitle: String
}

extension IslandAction {
    var island: IslandWords {
        switch self {
        case .text: IslandWords(label: islandWord("MESSAGE"), title: "A text to check", subtitle: "You send it yourself, in Messages")
        case .email: IslandWords(label: islandWord("EMAIL"), title: "An email to check", subtitle: "Nothing is sent until you tap yes")
        case .transfer: IslandWords(label: islandWord("BLIK"), title: "A transfer to check", subtitle: "You send it in your bank app")
        case .calendar: IslandWords(label: islandWord("CALENDAR"), title: "A calendar change", subtitle: "Nothing changes until you tap yes")
        case .reminder: IslandWords(label: islandWord("REMINDER"), title: "A reminder change", subtitle: "Nothing changes until you tap yes")
        case .alarm: IslandWords(label: islandWord("ALARM"), title: "An alarm to check", subtitle: "Nothing is set until you tap yes")
        case .map: IslandWords(label: islandWord("MAPS"), title: "Open Maps?", subtitle: "Show the place in Doddy first")
        case .shortcut: IslandWords(label: islandWord("SHORTCUT"), title: "Run a shortcut?", subtitle: "Nothing runs until you tap yes")
        case .camera: IslandWords(label: islandWord("CAMERA"), title: "Open the camera?", subtitle: "It opens only on your tap")
        case .presentation: IslandWords(label: islandWord("SLIDES"), title: "Slides to check", subtitle: "Nothing is made until you tap yes")
        case .list: IslandWords(label: islandWord("LIST"), title: "A list change", subtitle: "Nothing changes until you tap yes")
        case .onlineApp: IslandWords(label: islandWord("ONLINE"), title: "A change in an online app", subtitle: "Nothing is sent until you tap yes")
        case .askFirst: IslandWords(label: islandWord("ASK"), title: "Doddy asks first", subtitle: "Say yes, or tap it in Doddy")
        case .access: IslandWords(label: islandWord("ACCESS"), title: "Doddy needs your OK", subtitle: "Allow it or say Not now, in Doddy")
        case .signIn: IslandWords(label: islandWord("ACCOUNT"), title: "Connect an account?", subtitle: "Sign in from Doddy")
        case .other: IslandWords(label: islandWord("CHECK"), title: "Something to check", subtitle: "Nothing happens until you tap yes")
        }
    }
}

extension IslandResult {
    var island: IslandWords {
        switch self {
        case .document: IslandWords(label: islandWord("READY"), title: "Your document is ready", subtitle: "Show opens it in Doddy")
        case .documentStarted: IslandWords(label: islandWord("DOCUMENT"), title: "Making your document", subtitle: "Its button is in Doddy")
        case .presentation: IslandWords(label: islandWord("READY"), title: "Your slides are ready", subtitle: "Show opens them in Doddy")
        case .photos: IslandWords(label: islandWord("PHOTOS"), title: "Photos to look at", subtitle: "Show opens them in Doddy")
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
    /// The island for the focus timer (Tiny Promise, ADR-241) and reading a note aloud (Story
    /// Spool, ADR-243). `isStale`: iOS says the app has not updated it; a focus activity is given
    /// its end time as its stale date, so stale there means the time is up.
    func islandScene(_ state: ContentState, isStale: Bool, now: Date = Date()) -> IslandScene {
        var shown = boardScene(state, isStale: isStale, now: now)
        if state.islandStyle == .wholeDoddy { shown.pose = wholeDoddyPose(state, isStale: isStale) }
        return shown
    }

    /// Whole Doddy's pose for a tool (ADR-299, ADR-313, ADR-780): dribbling while focusing,
    /// reading lying on his front, kneeling to watch a
    /// timer, stretching sleepily through a wind-down. Done, waiting and lost are the same poses
    /// as in a conversation (fist pump, cross-legged, facepalm); a wind-down ends cross-legged,
    /// not with a fist pump, since it is bedtime.
    func wholeDoddyPose(_ state: ContentState, isStale: Bool) -> IslandPose {
        if isStale && kind == .readAloud { return .facepalm }
        if state.isFinished || isStale { return kind == .windDown ? .crosslegged : .fistpump }
        if state.isPaused { return .crosslegged }
        switch kind {
        case .focus: return .basketballDribble
        case .readAloud: return .bellyReading
        case .stopwatch: return .tiptoe
        case .timer: return .kneelingInspect
        case .windDown: return .yawnStretch
        case .noteSaved: return .fistpump
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
                return scene(.tinyPromise, 0, label: islandWord("FOCUS"), time: .text(islandWord("Done")), title: "Time's up",
                             subtitle: state.label ?? islandWord("Focus finished"), compact: .check, minimal: .check, centred: true)
            }
            if state.isPaused {
                let left = Self.clock(state.remaining)
                return scene(.tinyPromise, 1, label: islandWord("FOCUS"), time: .text(islandWord("Paused")), title: "Paused, \(left) left",
                             bigTitle: .bigText(left), subtitle: state.label ?? islandWord("Ready when you are"),
                             compact: .text(left), minimal: .text("\(Int((state.remaining / 60).rounded(.up)))m"), centred: true)
            }
            let end = state.endsAt ?? now
            return scene(.tinyPromise, 0, label: islandWord("FOCUS"), time: .text(minutes), title: "Focusing",
                         bigTitle: .countdown(end), subtitle: state.label ?? islandWord("One thing at a time"),
                         compact: .countdown(end), minimal: .countdown(end), centred: true)
        case .timer, .windDown:
            // The kitchen timer and the wind-down (ADR-780) use the focus board (Tiny Promise):
            // the pack has no timer board of its own, and the words tell them apart.
            let isWindDown = kind == .windDown
            let label = isWindDown ? islandWord("WIND DOWN") : islandWord("TIMER")
            let length = Self.length(duration)
            if over {
                return scene(.tinyPromise, 0, label: label, time: .text(islandWord("Done")),
                             title: isWindDown ? "Wind-down over" : "Time's up",
                             subtitle: isWindDown ? islandWord("Time to put the phone down") : (state.label ?? islandWord("Timer finished")),
                             compact: .check, minimal: .check, centred: true)
            }
            if state.isPaused {
                let left = Self.clock(state.remaining)
                return scene(.tinyPromise, 1, label: label, time: .text(islandWord("Paused")), title: "Paused, \(left) left",
                             bigTitle: .bigText(left), subtitle: isWindDown ? islandWord("Ready when you are") : (state.label ?? islandWord("Ready when you are")),
                             compact: .text(left), minimal: .text("\(Int((state.remaining / 60).rounded(.up)))m"), centred: true)
            }
            let end = state.endsAt ?? now
            return scene(.tinyPromise, 0, label: label, time: .text(length),
                         title: isWindDown ? "Winding down" : "Timer",
                         bigTitle: .countdown(end),
                         subtitle: isWindDown ? islandWord("Phone down when it ends") : (state.label ?? islandWord("Counting down")),
                         compact: .countdown(end), minimal: .countdown(end), centred: true)
        case .noteSaved:
            // The same card as the conversation's "Note saved" moment (ADR-240): never the words.
            return scene(.thoughtPocket, 1, label: islandWord("NOTE"), time: .text(islandWord("Saved")), title: "Note saved",
                         subtitle: "Kept in Doddy on this iPhone", compact: .check, minimal: .none)
        case .readAloud:
            var shown: IslandScene
            if lost {
                shown = scene(.storySpool, 1, label: islandWord("READ ALOUD"), time: .text(""), title: "Stopped",
                              subtitle: "Open Doddy to read it again", warning: true,
                              compact: .symbol("exclamationmark.triangle.fill", .warning), minimal: .none)
            } else if over {
                shown = scene(.storySpool, 1, label: islandWord("READ ALOUD"), time: .text(islandWord("Done")), title: "Finished reading",
                              subtitle: "Your note", compact: .check, minimal: .none)
            } else if state.isPaused {
                shown = scene(.storySpool, 1, label: islandWord("READ ALOUD"), time: .text(islandWord("Paused")), title: "Paused",
                              subtitle: "Pick up where you left off", compact: .symbol("pause.fill", .secondary), minimal: .none)
            } else {
                shown = scene(.storySpool, 0, label: islandWord("READ ALOUD"), time: .text(islandWord("Note")), title: "Reading aloud",
                              subtitle: "Your note", compact: .bars, minimal: .bars)
            }
            return shown
        case .stopwatch:
            // Counts up (ADR-652): the Tiny Promise board with a ticking time, no end and no alert.
            let total = Self.elapsedClock(state.elapsed ?? 0)
            if state.isFinished {
                return scene(.tinyPromise, 0, label: islandWord("STOPWATCH"), time: .text(islandWord("Stopped")), title: "Stopped at \(total)",
                             bigTitle: .bigText(total), subtitle: state.label ?? "Nicely timed",
                             compact: .check, minimal: .check, centred: true)
            }
            if state.isPaused {
                return scene(.tinyPromise, 1, label: islandWord("STOPWATCH"), time: .text(islandWord("Paused")), title: "Paused at \(total)",
                             bigTitle: .bigText(total), subtitle: state.label ?? "Ready when you are",
                             compact: .text(total), minimal: .symbol("pause.fill", .secondary), centred: true)
            }
            return scene(.tinyPromise, 0, label: islandWord("STOPWATCH"), time: .text(islandWord("Running")), title: "Stopwatch",
                         bigTitle: .elapsed, subtitle: state.label ?? "Counting up",
                         compact: .elapsed, minimal: .symbol("stopwatch.fill", .orange), centred: true)
        }
    }

    /// "12:07" for a time counted so far (whole seconds, never rounded up).
    static func elapsedClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// A note-saved island is finished from the start: it only ever shows the done card.
    var isMomentary: Bool { kind == .noteSaved }

    /// "10 min", "1 h 30 min" or "45 s": a countdown's length, as `CountdownSession.lengthText`
    /// says it (kept here too because the island files don't link DoddyCore).
    static func length(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return s > 0 && m < 5 ? "\(m) min \(s) s" : "\(m) min" }
        return "\(s) s"
    }

    /// "12:48" for a time left.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
