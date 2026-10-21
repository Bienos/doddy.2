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
    /// Lists shared through iCloud, by this user or with them (ADR-263).
    public var sharedLists: Int
    /// Who runs the live voice: the voice picker's choice, or its default, ElevenLabs (ADR-265, ADR-546).
    public var voiceProvider: VoiceProvider
    /// Settings → What I've learned → "Use in voice conversations" (ADR-440).
    public var learnedSharedWithVoice: Bool
    /// Who writes the daily news on the messaging server, as it reported it
    /// (`NewsSettings.Available.writerProvider`: "anthropic" or "openai"). Nil until it is known.
    public var newsWriterProvider: String?

    public init(
        rememberConversations: Bool, shareProfileWithVoice: Bool, tokenServerSet: Bool,
        connectionsOn: Set<VoiceConnection>, pauseAll: Bool, doddyServerSet: Bool,
        askDoddyOn: Bool, askDoddyUsesNotes: Bool,
        messagingServerSet: Bool = false, pushOn: Bool = false, memoryCopyOn: Bool = false,
        morningCheckInOn: Bool = false,
        siriReadsNotes: Bool = false, sharedLists: Int = 0,
        voiceProvider: VoiceProvider = .elevenLabs,
        learnedSharedWithVoice: Bool = false,
        newsWriterProvider: String? = nil
    ) {
        self.learnedSharedWithVoice = learnedSharedWithVoice
        self.newsWriterProvider = newsWriterProvider
        self.morningCheckInOn = morningCheckInOn
        self.sharedLists = sharedLists
        self.voiceProvider = voiceProvider
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
        if state.learnedSharedWithVoice { voice.append("the facts and routines you confirmed under What I've learned") }
        if !apps.isEmpty { voice.append("calendar entries, reminders, contact names and birthdays (day and month) or drafts Doddy uses (\(names(apps)))") }
        if state.doddyServerSet && !state.pauseAll { voice.append("results from your online accounts that Doddy uses") }

        var messaging = ["an anonymous account token"]
        if state.pushOn { messaging.append("this iPhone's notification token") }
        messaging.append("your phone number, only if you confirm it with a code for texts or calls")
        messaging.append("the news topics and feeds you pick, if you turn on daily news")
        if state.memoryCopyOn { messaging.append("a copy of your saved notes, for phone calls with Doddy") }

        // The server can use either provider (ADR-197); name one only when the server said which.
        let writer = switch state.newsWriterProvider {
        case "anthropic": "Anthropic"
        case "openai": "OpenAI"
        default: "Anthropic or OpenAI, as the server is set up"
        }

        var ask = "Typed questions"
        if state.askDoddyUsesNotes { ask += " and the saved notes that match them" }

        let openAIVoice = state.voiceProvider == .openAIRealtime
        return [
            DataFlowRow(
                id: "elevenlabs", destination: "ElevenLabs (Doddy's voice)",
                what: sentence(voice),
                when: openAIVoice
                    ? "Only while a conversation is open, and not while Home's voice switch says OpenAI."
                    : "Only while a conversation is open.",
                // When OpenAI Realtime was chosen (and the token server is set), nothing goes to
                // ElevenLabs for voice, and the row says so instead of claiming it.
                isActive: !(openAIVoice && state.tokenServerSet),
                note: "ElevenLabs keeps a recording and transcript of each conversation. Notes you mark Private are never sent."),
            DataFlowRow(
                id: "openaiVoice", destination: "OpenAI (Doddy's voice)",
                what: sentence(voice),
                when: "Only while a conversation is open and Home's voice switch says OpenAI.",
                isActive: openAIVoice && state.tokenServerSet,
                note: !openAIVoice
                    ? "Home's voice switch says ElevenLabs, so nothing goes to OpenAI for voice."
                    : state.tokenServerSet
                        ? "Weather and Wikipedia don't work with this voice. How long OpenAI keeps the audio and transcript isn't verified in this build."
                        : "OpenAI voice needs the token server, so nothing goes there yet."),
            DataFlowRow(
                id: "translator", destination: openAIVoice && state.tokenServerSet ? "OpenAI (translator mode)" : "ElevenLabs (translator mode)",
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
                what: "The name and items of each list you share or joined, and every change to them; a reminder's place only if you tap Share this place.",
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
                id: "exchangeRates", destination: "European Central Bank (exchange rates)",
                what: "Nothing about you: the app downloads the ECB's public daily rates file.",
                when: "When you ask Doddy to convert money, at most every six hours.", isActive: !state.pauseAll,
                note: state.pauseAll ? "Connections are paused, so the rates aren't fetched." : "The amount and currencies stay on this iPhone; the conversion is worked out here."),
            DataFlowRow(
                id: "placeSearch", destination: "Apple Maps (place search and travel time)",
                what: "The words you type to find a place, and roughly where you are if Doddy already knows. For a leave reminder: where your iPhone is and the place you're going.",
                when: "Only when you search for a place for a reminder, or ask when to leave.", isActive: true,
                note: "Doddy keeps only the place you pick. iOS watches it on this iPhone; Doddy doesn't follow where you go."),
            DataFlowRow(
                id: "tokenServer", destination: "Voice token server",
                what: "A short-lived DODDY session credential and the selected voice provider/model. Apple sign-in is verified here to create your account; the session authorizes voice access. No voice, transcript, notes or profile details are sent to this server for token requests.",
                when: "When you sign in or refresh your session, and when a conversation or wake-word setup requests a provider connection credential.", isActive: state.tokenServerSet,
                note: state.tokenServerSet ? "Provider credentials stay on DODDY's server. Your voice and any approved conversation context go directly to the selected provider." : "Voice isn't set up yet."),
            DataFlowRow(
                id: "doddyServer", destination: "Your Doddy server (Google, Microsoft Outlook, Notion, Todoist via Composio)",
                what: "What you ask for, only after you say yes: a date, a search word, or the text of a draft, email, reply or task you tap to confirm. An email you send or forward goes on to its recipient. Never your saved notes. With Read an email or Read a Notion page on, that one email or page comes back.",
                when: "When you use Connected Apps, or Doddy uses an online-account tool you switched on.",
                isActive: state.doddyServerSet,
                note: !state.doddyServerSet
                    ? "No Doddy server is set, so nothing goes there."
                    : state.pauseAll ? "Connections are paused, so Doddy doesn't use it in conversations. The Connected Apps screen still works when you open it." : nil),
            DataFlowRow(
                id: "messagingServer", destination: "Your Doddy messaging server (Apple, Twilio, ElevenLabs, \(writer), GNews)",
                what: sentence(messaging),
                when: "When you turn on notifications, texts, phone calls or daily news, and while they are on.",
                isActive: state.messagingServerSet,
                note: state.messagingServerSet
                    ? "It sends notifications through Apple and texts and calls through Twilio; calls run on ElevenLabs. Daily news sends your topics and public headlines to \(writer), and your own keywords to GNews."
                    : "No messaging server is set, so nothing goes there."),
            // ADR-563: a task handed to Doddy's background worker.
            DataFlowRow(
                id: "errands", destination: "Your Doddy messaging server and Anthropic (tasks you hand over)",
                what: "The words of a task you hand to Doddy, Doddy's one-line note on it and its language. Anthropic's Claude searches the web and reads pages for it, so search words made from your task go to Anthropic's search provider. Never your saved notes, lists, profile or earlier conversations.",
                when: "Only when you say yes to handing a task over, until its result is saved on this iPhone.",
                isActive: state.messagingServerSet,
                note: state.messagingServerSet
                    ? "The server keeps the words and the result, encrypted, until the result is saved on this iPhone, then deletes them; a result never fetched is deleted after 30 days. The notification has no words from the task."
                    : "No messaging server is set, so tasks can't be handed over."),
            DataFlowRow(
                id: "siri", destination: "Apple (Siri)",
                what: "What you ask Siri to look for, and the note Siri reads back with when you saved it.",
                when: "Only when you say \"Ask Doddy what I saved\" with your iPhone unlocked.",
                isActive: state.siriReadsNotes,
                note: state.siriReadsNotes
                    ? "Doddy searches on this iPhone; Siri hears the request and speaks the answer as your Siri settings allow, which can include Apple's servers."
                    : "Reading notes aloud with Siri is off, so Siri gets no notes from Doddy."),
            DataFlowRow(
                id: "askDoddy", destination: "Ask Doddy gateway (OpenAI)",
                what: ask + ".", when: "Only when you send a typed question.", isActive: state.askDoddyOn,
                note: state.askDoddyOn ? "A separate server from your Doddy server." : "Ask Doddy is off, so nothing goes there."),
        ]
    }

    /// Settings → Privacy "Network": where something can go right now, built from `rows` so it
    /// never lists less than What leaves this iPhone (audit 2026-10-12 §5 #6, ADR-447).
    public static func networkSummary(_ state: DataFlowState) -> String {
        let names = rows(state).filter(\.isActive).compactMap { networkNames[$0.id] }
        guard let last = names.last else { return "None" }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return list + ". Each only when you use it; What leaves this iPhone says what goes."
    }

    /// Settings → Privacy "Cloud AI": the AI services that can get what you say or type right now.
    public static func cloudAISummary(_ state: DataFlowState) -> String {
        let active = Set(rows(state).filter(\.isActive).map(\.id))
        var parts: [String] = []
        if active.contains("elevenlabs") { parts.append("ElevenLabs (voice)") }
        if active.contains("openaiVoice") { parts.append("OpenAI (voice)") }
        if active.contains("askDoddy") { parts.append("OpenAI (Ask Doddy)") }
        if active.contains("messagingServer") {
            parts.append("ElevenLabs (phone calls) and \(newsWriter(state)) (daily news) on your messaging server")
        }
        // ADR-563: Claude researches the tasks you hand over.
        if active.contains("errands") { parts.append("Anthropic (tasks you hand over)") }
        return parts.isEmpty ? "None" : parts.joined(separator: "; ")
    }

    /// The short name each row has in the Network summary. Every row id is here or in
    /// `notInNetworkSummary` (DataFlowTests), so a new row can't be left out by accident.
    static let networkNames: [String: String] = [
        "elevenlabs": "ElevenLabs (while talking)",
        "openaiVoice": "OpenAI (while talking)",
        "iCloudSharing": "iCloud (lists you share)",
        "lookups": "Open-Meteo and Wikipedia (looked up by ElevenLabs)",
        "exchangeRates": "the European Central Bank (exchange rates; nothing about you)",
        "placeSearch": "Apple Maps (place searches)",
        "tokenServer": "your voice token server",
        "doddyServer": "your Doddy server (Connected Apps)",
        "messagingServer": "your Doddy messaging server",
        "errands": "Anthropic (tasks you hand over, through your messaging server)",
        "siri": "Siri (when you ask it)",
        "askDoddy": "the Ask Doddy gateway",
    ]

    /// Covered by another name (translator mode goes to whichever service runs the voice, which is
    /// named), or not sent by the app (a backup file goes where you save it).
    static let notInNetworkSummary: Set<String> = ["translator", "backup"]

    private static func newsWriter(_ state: DataFlowState) -> String {
        switch state.newsWriterProvider {
        case "anthropic": "Anthropic"
        case "openai": "OpenAI"
        default: "Anthropic or OpenAI"
        }
    }

    /// What never leaves, apart from the uses listed above.
    public static func staysOnPhone(_ state: DataFlowState) -> [String] {
        [
            "Your saved notes, except as listed above.",
            // ADR-362: drafts are never searched, sent, exported or backed up.
            "Unfinished notes: what you typed before tapping Save, until you save or discard it (30 days at most).",
            // ADR-252: the corrections table is read only by the note screen and exports.
            "Earlier wordings of notes you corrected, except in files you export.",
            "What Doddy did (the activity list).",
            state.rememberConversations
                ? "Remembered conversations, except the last few at the start of a conversation."
                : "Conversations: none are remembered.",
            "Your calendar, reminders and contacts, except the items Doddy uses in a conversation.",
            "Places you set for reminders, and when you arrive or leave: iOS checks this on this iPhone.",
            "Notes suggested after a conversation: picked from your own words on this iPhone.",
            // ADR-440: proposals are picked here; only what you confirm and switch on is ever handed over.
            "What Doddy learned (facts, routines, and counts of what you corrected): kept here; confirmed ones go to a conversation only if you turn that on.",
            "DODDY voice refresh sessions and connected-app credentials, in this iPhone's Keychain; short-lived provider credentials stay in memory.",
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
