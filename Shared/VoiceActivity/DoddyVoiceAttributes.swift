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
        /// Something happening inside the conversation that has its own island (ADR-213).
        /// Only its kind and counts, never what a note or reminder says.
        var moment: Moment?
        /// The look the user picked in Settings (ADR-212).
        var islandStyle: IslandStyle = .leanIn

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
        }
    }

    /// When the conversation started, for the elapsed-time counter.
    var startedAt: Date
}

extension DoddyVoiceAttributes.ContentState {
    private enum CodingKeys: String, CodingKey { case status, isMuted, savedCount, endedAt, moment, islandStyle }

    /// Content written by an older build (without `savedCount`, `endedAt`, `moment` or
    /// `islandStyle`) still decodes. An unknown style or moment from a newer build falls back
    /// to Lean In and no moment rather than failing.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        savedCount = try container.decodeIfPresent(Int.self, forKey: .savedCount) ?? 0
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        moment = (try? container.decodeIfPresent(Moment.self, forKey: .moment)) ?? nil
        islandStyle = (try? container.decodeIfPresent(IslandStyle.self, forKey: .islandStyle)) ?? .leanIn
    }

    var isEnded: Bool { status == .ended }

    /// Muted only means something while the conversation runs and nothing waits in the app.
    var showsMuted: Bool { isMuted && status != .needsConfirmation && status != .ended }

    /// Short label for the island and Lock Screen.
    var title: String {
        #if DEBUG
        if status == .testFixture { return isMuted ? "Test muted" : "Test activity" }
        #endif
        if showsMuted { return "Muted" }
        switch status {
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        case .needsConfirmation: return "Confirm in Doddy"
        case .ended: return "Conversation ended"
        #if DEBUG
        case .testFixture: return "Test activity"
        #endif
        }
    }

    /// Second line on the Lock Screen, when there is something true to add.
    var detail: String? {
        if showsMuted { return "Doddy can't hear you" }
        switch status {
        case .ended:
            switch savedCount {
            case 0: return "Doddy isn't listening · nothing saved"
            case 1: return "Doddy isn't listening · 1 note saved"
            default: return "Doddy isn't listening · \(savedCount) notes saved"
            }
        case .needsConfirmation: return "Open Doddy to Save or Don't save"
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
