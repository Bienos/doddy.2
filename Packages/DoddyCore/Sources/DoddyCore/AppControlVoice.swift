import Foundation

// Steering the app by voice (decision 2026-11-27-voice-first-doddy, step 1, second part): open any of Doddy's own
// screens ("pokaż moje zadania"), and change Doddy's own settings from a fixed list ("mów krócej", "bez żartów",
// "ciemny motyw"). Both run at once, like Doddy's other own things: a screen only opens (the conversation goes on in
// the Dynamic Island), and a setting is changed back the same way. The list is fixed here, never the model's: a
// setting that isn't on it can't be changed by voice, and each value is one of the setting's own.
//
// Privacy, the Face ID lock, accounts, connections, payments and anything that sends data somewhere new stay in
// Settings, by hand (docs/product/VOICE_COVERAGE.md).
//
// Platforms: iPhone and iPad (the voice conversation). The app maps each setting to its own stored key.

/// A screen of the app Doddy can open.
public enum AppScreen: String, CaseIterable, Sendable {
    case home, notes, lists, settings, today, tasks, messages, files, radar, calls, shopping, deals, trips, food
    case myCity = "my_city"
    case whatICanDo = "what_i_can_do"
    case recordings

    /// The feature whose way in it is, as Home's menu shows it (decision 2026-11-07-release-scope); nil for a screen
    /// every build has. A screen whose feature the build hides doesn't open.
    public var feature: Feature? {
        switch self {
        case .tasks, .shopping: .errands
        case .deals: .deals
        case .radar: .following
        case .calls: .phoneCalls
        case .trips: .onlineAccounts
        case .messages: .messages
        case .files: .files
        case .recordings: .recordings
        case .home, .notes, .lists, .settings, .today, .food, .myCity, .whatICanDo: nil
        }
    }

    /// The screen's name as the app shows it, for the reply.
    public var title: String {
        switch self {
        case .home: "Home"
        case .notes: "Notes"
        case .lists: "Lists"
        case .settings: "Settings"
        case .today: "Today"
        case .tasks: "Tasks"
        case .messages: "Messages"
        case .files: "Files"
        case .radar: "On my radar"
        case .calls: "Phone calls"
        case .shopping: "Shopping"
        case .deals: "Leaflets"
        case .trips: "Trips"
        case .food: "Food"
        case .myCity: "My city"
        case .whatICanDo: "What I can do"
        case .recordings: "Recordings"
        }
    }
}

/// One of Doddy's own settings that can be changed by voice.
public enum VoiceSetting: String, CaseIterable, Sendable {
    case humour
    case replyLength = "reply_length"
    case tone, mood
    case voiceSpeed = "voice_speed"
    case voiceExpressiveness = "voice_expressiveness"
    case appearance
    case characterArt = "character_art"
    case noteSavedIsland = "note_saved_island"
    case listenOnOpen = "listen_on_open"
    case rememberConversations = "remember_conversations"
    case suggestNotes = "suggest_notes"

    /// The values it takes, as stored: a choice setting's own raw values, or "on" and "off".
    public var values: [String] {
        switch self {
        case .humour: HumourLevel.allCases.map(\.rawValue)
        case .replyLength: ReplyLength.allCases.map(\.rawValue)
        case .tone: Formality.allCases.map(\.rawValue)
        case .mood: Mood.allCases.map(\.rawValue)
        case .voiceSpeed: SpeakingSpeed.allCases.map(\.rawValue)
        case .voiceExpressiveness: Expressiveness.allCases.map(\.rawValue)
        case .appearance: AppearancePreference.allCases.map(\.rawValue)
        case .characterArt, .noteSavedIsland, .listenOnOpen, .rememberConversations, .suggestNotes: ["on", "off"]
        }
    }

    public var isSwitch: Bool { values == ["on", "off"] }

    /// Doddy's style and voice are read when a conversation starts, so they change from the next one.
    public var fromNextConversation: Bool {
        [.humour, .replyLength, .tone, .mood, .voiceSpeed, .voiceExpressiveness].contains(self)
    }

    /// Its name in Settings, for the reply.
    public var title: String {
        switch self {
        case .humour: "Humour"
        case .replyLength: "Reply length"
        case .tone: "Tone"
        case .mood: "Mood"
        case .voiceSpeed: "Voice speed"
        case .voiceExpressiveness: "Expressiveness"
        case .appearance: "Appearance"
        case .characterArt: "Character artwork"
        case .noteSavedIsland: "\u{201C}Note saved\u{201D} in the Dynamic Island"
        case .listenOnOpen: "Listen when the app opens"
        case .rememberConversations: "Remember recent conversations"
        case .suggestNotes: "Suggest notes after a conversation"
        }
    }
}

public enum AppControlVoice {
    /// Both run at once (owner, 27 Nov 2026: Doddy's own things run as asked).
    public static let atOnceTools: Set<String> = [VoiceToolName.openScreen, VoiceToolName.changeSetting]

    static func parse(_ args: Arguments, name: String) -> VoiceToolRequest {
        if name == VoiceToolName.openScreen {
            guard let raw = args.text("screen") else { return .invalid(name: name, reason: "missing screen") }
            guard let screen = AppScreen(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) else {
                return .invalid(name: name, reason: "screen must be one of \(AppScreen.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return .openScreen(screen)
        }
        guard let raw = args.text("setting") else { return .invalid(name: name, reason: "missing setting") }
        guard let setting = VoiceSetting(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) else {
            return .invalid(name: name, reason: "this setting can't be changed by voice; the ones that can: \(VoiceSetting.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        guard let value = args.text("value")?.trimmingCharacters(in: .whitespaces).lowercased(), setting.values.contains(value) else {
            return .invalid(name: name, reason: "\(setting.rawValue) takes one of \(setting.values.joined(separator: ", "))")
        }
        return .changeSetting(setting, value: value)
    }

    // MARK: Replies (the first word is what the prompt's rules read)

    public static func opening(_ screen: AppScreen) -> String {
        "opened: the app was asked to show \(screen.title). The voice screen goes down to the Dynamic Island and the conversation goes on. Say in a few words that it is on screen."
    }

    public static func hidden(_ screen: AppScreen) -> String {
        "not available: \(screen.title) isn't in this build of the app, so nothing opened. Say so in one sentence."
    }

    public static func changed(_ setting: VoiceSetting, to value: String) -> String {
        let when = setting.fromNextConversation ? " It applies from the next conversation." : ""
        return "changed: \(setting.title) is now \(value).\(when) Say it in one short line; it can be changed back the same way."
    }

    public static func alreadySet(_ setting: VoiceSetting, _ value: String) -> String {
        "not changed: \(setting.title) is already \(value). Say so in one short line."
    }

    public static func notChanged(_ setting: VoiceSetting) -> String {
        "failed: \(setting.title) didn't change. Say it wasn't changed and that it is in Settings."
    }
}
