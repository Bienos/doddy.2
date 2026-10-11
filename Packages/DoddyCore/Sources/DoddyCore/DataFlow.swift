import Foundation

/// Settings → What leaves this iPhone (docs/design/SETTINGS_AND_CONNECTIONS.md §6): one row per
/// place data can go, built from the user's current settings, so the screen changes when a
/// switch does. The wording restates the Privacy paragraph in SettingsView row by row; change
/// both together.
public struct DataFlowState: Equatable, Sendable {
    public var rememberConversations: Bool
    public var shareProfileWithVoice: Bool
    public var tokenServerSet: Bool
    /// Device connections switched on in Settings → Connections.
    public var connectionsOn: Set<VoiceConnection>
    public var pauseAll: Bool
    /// A Doddy server address is set for Connected Apps and online accounts.
    public var doddyServerSet: Bool
    public var askDoddyOn: Bool
    public var askDoddyUsesNotes: Bool
    /// A Doddy messaging server address is set (notifications, texts, calls, news; ADR-139).
    public var messagingServerSet: Bool
    /// The user turned Doddy's notifications on.
    public var pushOn: Bool
    /// The user turned on the server copy of their notes for phone calls.
    public var memoryCopyOn: Bool
    /// The morning check-in is on (ADR-220).
    public var morningCheckInOn: Bool
    /// Siri may read saved notes aloud (ADR-248).
    public var siriReadsNotes: Bool
    /// "Hey Doddy" listening is switched on (ADR-254).
    public var heyDoddyOn: Bool
    /// Lists shared through iCloud, by this user or with them (ADR-263).
    public var sharedLists: Int

    public init(
        rememberConversations: Bool, shareProfileWithVoice: Bool, tokenServerSet: Bool,
        connectionsOn: Set<VoiceConnection>, pauseAll: Bool, doddyServerSet: Bool,
        askDoddyOn: Bool, askDoddyUsesNotes: Bool,
        messagingServerSet: Bool = false, pushOn: Bool = false, memoryCopyOn: Bool = false,
        morningCheckInOn: Bool = false,
        siriReadsNotes: Bool = false, heyDoddyOn: Bool = false, sharedLists: Int = 0
    ) {
        self.morningCheckInOn = morningCheckInOn
        self.sharedLists = sharedLists
        self.rememberConversations = rememberConversations
        self.shareProfileWithVoice = shareProfileWithVoice
        self.tokenServerSet = tokenServerSet
        self.connectionsOn = connectionsOn
        self.pauseAll = pauseAll
        self.doddyServerSet = doddyServerSet
        self.askDoddyOn = askDoddyOn
        self.askDoddyUsesNotes = askDoddyUsesNotes
        self.messagingServerSet = messagingServerSet
        self.pushOn = pushOn
        self.memoryCopyOn = memoryCopyOn
        self.siriReadsNotes = siriReadsNotes
        self.heyDoddyOn = heyDoddyOn
    }
}

public struct DataFlowRow: Equatable, Identifiable, Sendable {
    public let id: String
    /// Where it goes, e.g. "ElevenLabs (Doddy's voice)".
    public let destination: String
    /// What goes there, in plain words.
    public let what: String
    public let when: String
    /// True when the current settings let data go there.
    public let isActive: Bool
    /// Extra fact, or why it is off right now.
    public let note: String?
}

public enum DataFlow {
    public static func rows(_ state: DataFlowState) -> [DataFlowRow] {
        let apps = state.pauseAll ? [] : state.connectionsOn
        var voice = ["your voice", "the conversation", "your saved notes", "your list names (items only when Doddy reads or changes a list)", "your personality settings"]
        if state.rememberConversations { voice.append("your last few conversations") }
        if state.morningCheckInOn { voice.append("today's Doddy reminders and lists with things left, when you talk through the morning check-in") }
        if state.shareProfileWithVoice { voice.append("your introduction answers") }
        if !apps.isEmpty { voice.append("calendar entries, reminders, contact names or drafts Doddy uses (\(names(apps)))") }
        if state.doddyServerSet && !state.pauseAll { voice.append("results from your online accounts that Doddy uses") }

        var messaging = ["an anonymous account token"]
        if state.pushOn { messaging.append("this iPhone's notification token") }
        messaging.append("your phone number, only if you confirm it with a code for texts or calls")
        messaging.append("the news topics and feeds you pick, if you turn on daily news")
        if state.memoryCopyOn { messaging.append("a copy of your saved notes, for phone calls with Doddy") }

        var ask = "Typed questions"
        if state.askDoddyUsesNotes { ask += " and the saved notes that match them" }

        return [
            DataFlowRow(
                id: "elevenlabs", destination: "ElevenLabs (Doddy's voice)",
                what: sentence(voice),
                when: "Only while a conversation is open.", isActive: true,
                note: "ElevenLabs keeps a recording and transcript of each conversation."),
            DataFlowRow(
                id: "translator", destination: "ElevenLabs (translator mode)",
                what: "The other person's voice too, and everything said while translating. Opened from Translate on Home, your notes, conversations and profile aren't sent. Started in a conversation, what Doddy already had in it stays there, and he is told never to repeat it to them.",
                when: "Only while translator mode is on.", isActive: true,
                note: "Listen only hears whoever is near you. Nothing of it is kept on this iPhone unless you tap Copy or Save within 5 minutes of the end."),
            DataFlowRow(
                id: "backup", destination: "Where you save a backup file",
                what: "Your notes, lists, photos, voice memos, time reminders and About you answers, locked with your passphrase.",
                when: "Only when you make a backup file and choose where to save it.", isActive: true,
                note: "Doddy has no copy of the passphrase or the file. Without the passphrase nobody can open it."),
            DataFlowRow(
                id: "iCloudSharing", destination: "Your iCloud (Apple) and the people you share lists with",
                what: "The name and items of each list you share or joined, and every change to them.",
                when: "While a list is shared.", isActive: state.sharedLists > 0,
                note: state.sharedLists > 0
                    ? "Only the lists you chose. Stop sharing deletes the copy in your iCloud; Leave takes you off someone else's list."
                    : "No list is shared, so nothing goes there."),
            DataFlowRow(
                id: "lookups", destination: "Open-Meteo and Wikipedia",
                what: "A place name and its coordinates; search words.",
                when: "Only when you ask about the weather or a fact.", isActive: true,
                note: "ElevenLabs makes these requests for Doddy; this app doesn't contact them."),
            DataFlowRow(
                id: "placeSearch", destination: "Apple Maps (place search)",
                what: "The words you type to find a place, and roughly where you are if Doddy already knows.",
                when: "Only when you search for a place for a reminder.", isActive: true,
                note: "Doddy keeps only the place you pick. iOS watches it on this iPhone; Doddy doesn't follow where you go."),
            DataFlowRow(
                id: "tokenServer", destination: "Voice token server",
                what: "Your access code.", when: "When a conversation starts.", isActive: state.tokenServerSet,
                note: state.tokenServerSet ? nil : "No token server is set, so nothing goes there."),
            DataFlowRow(
                id: "doddyServer", destination: "Your Doddy server (Google, Notion, Todoist via Composio)",
                what: "What you ask for: a date, a search word, or the text of a draft or task you confirm. Never your saved notes.",
                when: "When you use Connected Apps, or Doddy uses an online-account tool you switched on.",
                isActive: state.doddyServerSet,
                note: !state.doddyServerSet
                    ? "No Doddy server is set, so nothing goes there."
                    : state.pauseAll ? "Connections are paused, so Doddy doesn't use it in conversations. The Connected Apps screen still works when you open it." : nil),
            DataFlowRow(
                id: "messagingServer", destination: "Your Doddy messaging server (Apple, Twilio, ElevenLabs, Anthropic, GNews)",
                what: sentence(messaging),
                when: "When you turn on notifications, texts, phone calls or daily news, and while they are on.",
                isActive: state.messagingServerSet,
                note: state.messagingServerSet
                    ? "It sends notifications through Apple and texts and calls through Twilio; calls run on ElevenLabs. Daily news sends your topics and public headlines to Anthropic, and your own keywords to GNews."
                    : "No messaging server is set, so nothing goes there."),
            DataFlowRow(
                id: "siri", destination: "Apple (Siri)",
                what: "What you ask Siri to look for, and the note Siri reads back with when you saved it.",
                when: "Only when you say \"Ask Doddy what I saved\" with your iPhone unlocked.",
                isActive: state.siriReadsNotes,
                note: state.siriReadsNotes
                    ? "Doddy searches on this iPhone; Siri hears the request and speaks the answer as your Siri settings allow, which can include Apple's servers."
                    : "Reading notes aloud with Siri is off, so Siri gets no notes from Doddy."),
            DataFlowRow(
                id: "picovoice", destination: "Picovoice (the \"Hey Doddy\" detector)",
                what: "Your Picovoice AccessKey, so Picovoice can check it and count its use against your plan. No sound: the wake word is detected on this iPhone.",
                when: "When \"Hey Doddy\" listening starts.",
                isActive: state.heyDoddyOn,
                note: state.heyDoddyOn
                    ? "After the wake word, the conversation goes to ElevenLabs exactly as if you had tapped Talk."
                    : "\"Hey Doddy\" is off, so nothing goes there and the microphone isn't used for it."),
            DataFlowRow(
                id: "askDoddy", destination: "Ask Doddy gateway (OpenAI)",
                what: ask + ".", when: "Only when you send a typed question.", isActive: state.askDoddyOn,
                note: state.askDoddyOn ? "A separate server from your Doddy server." : "Ask Doddy is off, so nothing goes there."),
        ]
    }

    /// What never leaves, apart from the uses listed above.
    public static func staysOnPhone(_ state: DataFlowState) -> [String] {
        [
            "Your saved notes, except as listed above.",
            // ADR-252: the corrections table is read only by the note screen and exports.
            "Earlier wordings of notes you corrected, except in files you export.",
            "What Doddy did (the activity list).",
            state.rememberConversations
                ? "Remembered conversations, except the last few at the start of a conversation."
                : "Conversations: none are remembered.",
            "Your calendar, reminders and contacts, except the items Doddy uses in a conversation.",
            "Places you set for reminders, and when you arrive or leave: iOS checks this on this iPhone.",
            "Notes suggested after a conversation: picked from your own words on this iPhone.",
            "\"Hey Doddy\": what the microphone hears while it waits for the wake word is checked on this iPhone and not kept or sent.",
            "Access codes and tokens, in this iPhone's Keychain.",
        ]
    }

    private static func names(_ connections: Set<VoiceConnection>) -> String {
        VoiceConnection.allCases.filter(connections.contains).map(\.title).joined(separator: ", ")
    }

    private static func sentence(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        let text = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }
}
