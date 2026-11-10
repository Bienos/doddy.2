import ActivityKit
import Foundation

/// The Live Activity (Dynamic Island and Lock Screen) for a voice conversation that is running.
/// Compiled into the app, which starts, updates and ends it, and into the DoddyWidgets
/// extension, which draws it. The status only ever mirrors real SDK events in
/// `VoiceSessionController`; the activity ends as soon as the conversation does.
/// Nothing said in the conversation is put in here: the Lock Screen is visible to anyone.
struct DoddyVoiceAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case connecting, listening, thinking, speaking
            /// Doddy proposed a note and waits for Save / Don't save on the app's screen.
            case needsConfirmation
            /// The final state after End or a lost connection: shown briefly on the Lock Screen
            /// (the Dynamic Island drops ended activities at once). Doddy is not listening.
            case ended
            /// The final state after a start that failed or a connection that dropped (ADR-579):
            /// shown briefly on the Lock Screen with Open Doddy. Doddy is not listening.
            case failed
            #if DEBUG
            /// Native lifecycle fixture only; never represents microphone or provider state.
            case testFixture
            #endif
        }

        var status: Status
        var isMuted: Bool
        /// Notes the user tapped Save on in this conversation. Shown only when it has ended.
        var savedCount: Int = 0
        /// Set with `.ended`, for the "2:31 total" line.
        var endedAt: Date?
        /// Something happening inside the conversation that has its own island (ADR-240).
        /// Only its kind and counts, never what a note or reminder says.
        var moment: Moment?
        /// The island's look: Whole Doddy, the only one left.
        var islandStyle: IslandStyle = .wholeDoddy

        enum Moment: Codable, Hashable {
            /// "Save this note?" waits for the user's tap in the app.
            case noteWaiting
            /// A note was written to the store (shown for a few seconds after it really saved).
            case noteSaved
            /// A plan card waits for the user's tap.
            case planWaiting(steps: Int)
            /// The confirmed plan is running; `step` is the one in progress (1-based).
            case planRunning(step: Int, of: Int)
            /// A reminder card waits for the user's tap.
            case reminderWaiting
            /// Add was tapped; Reminders has not answered yet.
            case reminderAdding
            /// Reminders confirmed it (added, or already there). Never shown for an unknown result.
            case reminderSet
            /// Translator mode is on (ADR-244): the language pair as codes ("en", "fr", or "?" while
            /// their language is not known yet), never anything said. `bothWays` is face to face;
            /// listen only translates one way, `from` the room `to` the owner.
            case translating(from: String, to: String, bothWays: Bool)
            /// Any other card waits for the user's tap, or Doddy asks for access or a sign-in
            /// (ADR-616). Only the kind: never who a text is to, what it says or which event.
            case actionWaiting(IslandAction)
            /// Something Doddy made or found is on the conversation's screen (ADR-616), shown
            /// for a few seconds. Only the kind, and "ready" only for a file that is ready.
            case resultReady(IslandResult)
        }
        /// "Hey Pat, what's up?" from a Talk to Doddy shortcut or Talk in the Island (ADR-254,
        /// ADR-577), shown instead of "Connecting…" / "Listening" / "Speaking" until the user first
        /// speaks. Only the greeting Doddy opens with, never anything the user said.
        var greeting: String?
        /// When this conversation started, if it differs from the activity's own start.
        var conversationStartedAt: Date?
        /// The language Doddy's screens are in ("pl", "en", …), so the island and the Lock Screen
        /// use it too (ADR-617); the widget extension can't see the app's own setting. Nil: the
        /// iPhone's language.
        var language: String?
        /// How loud Doddy's voice was over the last moment, as a step from 0 (a pause between his
        /// words) to `IslandVoiceBeat.maxStep` (ADR-683): the island swells with it while he talks
        /// and Doddy is not on screen. Nil otherwise. A number from the loudness of the audio he
        /// plays, never the microphone and never what he says.
        var voiceBeat: Int?
    }

    /// When the activity started.
    var startedAt: Date
}

/// The kind of card that waits for the user in a conversation, for the island (ADR-616). Each
/// is a fixed word: the island and the Lock Screen are visible to anyone, so nothing the card
/// says (a name, a number, a message, an amount) is carried here.
enum IslandAction: String, Codable, Hashable, Sendable, CaseIterable {
    /// A text Doddy drafted; the user sends it in Messages.
    case text
    /// An email: a draft for Mail, or Gmail or Outlook through Doddy's server.
    case email
    /// A BLIK transfer the user sends in their bank app.
    case transfer
    case calendar
    /// A change to a reminder that exists (adding one has its own Reminder Knot moment).
    case reminder
    /// A timer or an alarm to set, or an alarm to turn off.
    case alarm
    case map
    case shortcut
    case camera
    case presentation
    case list
    /// A change in another online app (Todoist, Notion, Google, …).
    case onlineApp
    /// "Doddy wants to …" before a lookup: a spoken yes is enough for a read (ASK-01).
    case askFirst
    /// Doddy needs an iPhone permission or a function that is off.
    case access
    /// An online account isn't connected.
    case signIn
    /// Anything else with a card (undo, parking, when to leave, several changes).
    case other
}

/// The kind of thing Doddy made or found that the conversation's screen now shows (ADR-616).
enum IslandResult: String, Codable, Hashable, Sendable, CaseIterable {
    /// A file Claude made that Doddy's server reports ready.
    case document
    /// A file Claude is still making; its button is on the screen.
    case documentStarted
    case presentation
    case photos
}

extension DoddyVoiceAttributes.ContentState {
    private enum CodingKeys: String, CodingKey {
        case status, isMuted, savedCount, endedAt, moment, islandStyle, greeting, conversationStartedAt, language
        case voiceBeat
    }

    /// Content written by an older build (without `savedCount`, `endedAt`, `moment`,
    /// `islandStyle`, `greeting`, `conversationStartedAt` or `voiceBeat`) still decodes. An unknown style or
    /// moment from a newer build falls back to Whole Doddy and no moment rather than failing. A
    /// status this build no longer has (the "Hey Doddy" states, removed with the wake word,
    /// ADR-549) reads as ended, so nothing claims to be listening.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = Status(rawValue: try container.decode(String.self, forKey: .status)) ?? .ended
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        savedCount = try container.decodeIfPresent(Int.self, forKey: .savedCount) ?? 0
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        moment = (try? container.decodeIfPresent(Moment.self, forKey: .moment)) ?? nil
        islandStyle = (try? container.decodeIfPresent(IslandStyle.self, forKey: .islandStyle)) ?? .wholeDoddy
        greeting = try container.decodeIfPresent(String.self, forKey: .greeting)
        conversationStartedAt = try container.decodeIfPresent(Date.self, forKey: .conversationStartedAt)
        language = try? container.decodeIfPresent(String.self, forKey: .language)
        voiceBeat = (try? container.decodeIfPresent(Int.self, forKey: .voiceBeat)) ?? nil
    }

    /// The island draws his talking waves, so a beat would show (ADR-683): speaking, live, not
    /// muted, nothing on the island instead (a card, a result, translating).
    var wantsVoiceBeat: Bool {
        status == .speaking && wholeDoddyWaves(stale: false) == .speaking
    }

    /// A final state: ended normally, or stopped by a failure. Neither claims anything live.
    var isEnded: Bool { status == .ended || status == .failed }
    var isFailed: Bool { status == .failed }
    /// Muted only means something while the conversation runs and nothing waits in the app.
    var showsMuted: Bool { isMuted && status != .needsConfirmation && !isEnded }

    /// The greeting replaces Connecting, Listening and Speaking until the user first answers: it
    /// is Doddy's first message (`opening_line`), so while he speaks it the island shows his words
    /// (ADR-577; the island opens up then). It never hides Thinking, Muted or a card waiting in
    /// the app.
    private var showsGreeting: Bool {
        guard let greeting, !greeting.isEmpty, !showsMuted else { return false }
        return status == .connecting || status == .listening || status == .speaking
    }

    /// For the elapsed time: the conversation's own start when it was given one.
    func conversationStart(activityStartedAt: Date) -> Date {
        conversationStartedAt ?? activityStartedAt
    }

    /// Short label for the island and Lock Screen.
    var title: String {
        #if DEBUG
        if status == .testFixture { return isMuted ? islandWord("Test muted") : islandWord("Test activity") }
        #endif
        if showsMuted { return islandWord("Muted") }
        if showsGreeting, let greeting { return greeting }
        switch status {
        case .connecting: return islandWord("Connecting…")
        case .listening: return islandWord("Listening")
        case .thinking: return islandWord("Working on it…")
        case .speaking: return islandWord("Speaking")
        case .needsConfirmation: return islandWord("Confirm in Doddy")
        case .ended: return islandWord("Conversation ended")
        case .failed: return islandWord("Conversation stopped")
        #if DEBUG
        case .testFixture: return islandWord("Test activity")
        #endif
        }
    }

    /// Second line on the Lock Screen, when there is something true to add.
    var detail: String? {
        if showsMuted { return islandWord("Doddy can't hear you") }
        switch status {
        case .ended:
            switch savedCount {
            case 0: return islandWord("Doddy isn't listening · nothing saved")
            case 1: return islandWord("Doddy isn't listening · 1 note saved")
            default: return "Doddy isn't listening · \(savedCount) notes saved"
            }
        case .failed:
            switch savedCount {
            case 0: return islandWord("Doddy isn't listening · open Doddy to try again")
            case 1: return islandWord("Doddy isn't listening · 1 note saved")
            default: return "Doddy isn't listening · \(savedCount) notes saved"
            }
        // Every card, not only a note's (ADR-616: a text or a transfer said "Save or Don't save").
        case .needsConfirmation: return islandWord("Open Doddy to see it and decide")
        default: return nil
        }
    }

    var symbolName: String {
        if showsMuted { return "mic.slash.fill" }
        switch status {
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .needsConfirmation: return "hand.tap.fill"
        case .ended: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        #if DEBUG
        case .testFixture: return isMuted ? "mic.slash.fill" : "wrench.and.screwdriver"
        #endif
        }
    }

    /// The orange cue means "Doddy is live and can hear you" and nothing else.
    var isLiveCue: Bool {
        #if DEBUG
        if status == .testFixture { return false }
        #endif
        return !showsMuted && !isEnded && status != .needsConfirmation
    }
}

/// An English word of the island or the Lock Screen that the string catalogs translate (ADR-617):
/// `tools/build_strings_catalog.py` collects every `islandWord("…")`, and the island's views look
/// it up in Doddy's language (`IslandLanguage`). It returns the English as it is, so the scene
/// logic and its checks stay in English.
func islandWord(_ english: String) -> String { english }
