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
    /// The user chose to keep notes, and conversations, as text on Doddy's server so the web can show them
    /// and answer questions about them (ADR-603). Both off by default.
    public var webNotesKept: Bool
    public var webConversationsKept: Bool
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
        newsWriterProvider: String? = nil,
        webNotesKept: Bool = false, webConversationsKept: Bool = false
    ) {
        self.webNotesKept = webNotesKept
        self.webConversationsKept = webConversationsKept
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

        var webKept: [String] = []
        if state.webNotesKept { webKept.append("a copy of your saved notes (not private ones), as text") }
        if state.webConversationsKept { webKept.append("the text of your conversations (not private ones), never audio") }

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
            // ADR-600: the phone vouches for a browser; the browser sees what the server already keeps.
            DataFlowRow(
                id: "webSignIn", destination: "A browser you sign in to Doddy on the web",
                what: "From this iPhone only a request for a sign-in code, to your Doddy server. The browser you type the code into then sees what that server already keeps for you: files Doddy made, your online accounts and their tools, and Doddy's receipts. "
                    + (webKept.isEmpty ? "Never your saved notes, lists, profile or conversations." : "It also sees the notes and conversations you keep on Doddy's server (see the next row). Never your lists or profile."),
                when: "When you tap Get a sign-in code, and while that browser stays signed in (30 days at most; sign it out in Settings › Doddy on the web).",
                isActive: state.doddyServerSet,
                note: state.doddyServerSet ? nil : "No Doddy server is set, so no browser can sign in."),
            // ADR-603: only what the person chose to keep there, as text, and only while a switch is on.
            DataFlowRow(
                id: "webMemory", destination: "Your Doddy server, and Anthropic when you ask a question on the web (notes and conversations you keep there)",
                what: webKept.isEmpty ? "Nothing: both switches are off." : sentence(webKept),
                when: "Once when you turn a switch on, then whenever a note changes or a conversation ends. Claude reads the best matches only when you ask a question on the web.",
                isActive: state.doddyServerSet && !webKept.isEmpty,
                note: !state.doddyServerSet
                    ? "No Doddy server is set, so nothing goes there."
                    : webKept.isEmpty
                        ? "Keep on Doddy's server is off in Settings › Doddy on the web, so nothing goes there."
                        : "Stored encrypted; the server can read it so the web can search it. Never audio, never private notes or private conversations. Conversations are kept 1 year. Turning a switch off, or Delete everything, removes it from Doddy's server."),
            DataFlowRow(
                id: "messagingServer", destination: "Your Doddy messaging server (Apple, Twilio, ElevenLabs, \(writer), GNews)",
                what: sentence(messaging),
                when: "When you turn on notifications, texts, phone calls or daily news, and while they are on.",
                isActive: state.messagingServerSet,
                note: state.messagingServerSet
                    ? "It sends notifications through Apple and texts and calls through Twilio; calls run on ElevenLabs. Daily news sends your topics and public headlines to \(writer), and your own keywords to GNews."
                    : "No messaging server is set, so nothing goes there."),
            // ADR-570: a task handed to Doddy's background worker.
            DataFlowRow(
                id: "errands", destination: "Your Doddy messaging server and Anthropic (tasks you hand over)",
                what: "The words of a task you hand to Doddy, Doddy's one-line note on it and its language, and for a shopping task what matters most to you. Anthropic's Claude searches the web and reads pages for it, so search words made from your task go to Anthropic's search provider. For a shopping task, search words Claude writes also go to Serper (Google Shopping results), and Doddy's server opens shops' pages; your own words go to neither. Never your saved notes, lists, profile or earlier conversations.",
                when: "Only when you say yes to handing a task over, until its result is saved on this iPhone.",
                isActive: state.messagingServerSet,
                note: state.messagingServerSet
                    ? "The server keeps the words and the result, encrypted, until the result is saved on this iPhone, then deletes them; a result never fetched is deleted after 30 days. The notification has no words from the task."
                    : "No messaging server is set, so tasks can't be handed over."),
            // SHOPPING.md section 2: leaflets read on request; nothing that identifies the user goes to the chains
            // (Rossmann gets the item names as a search on rossmann.pl, from Doddy's server).
            DataFlowRow(
                id: "deals", destination: "Your Doddy messaging server, the shops' leaflet pages and Anthropic (leaflets)",
                what: "The names of the items you ask about and which shops to check. Doddy's server fetches the shops' leaflet pages itself and, for leaflets that are only pictures, sends those pages and the item names to Anthropic's Claude to read. For Rossmann, the item names go to rossmann.pl as a search from Doddy's server. Nothing that identifies you goes to any shop. Never your saved notes, lists or profile.",
                when: "Only when you say yes to checking this week's leaflets.",
                isActive: state.messagingServerSet && !state.pauseAll,
                note: !state.messagingServerSet
                    ? "No messaging server is set, so leaflets can't be checked."
                    : state.pauseAll
                        ? "Connections are paused, so leaflets aren't checked."
                        : "The server keeps no leaflet pages, offers or item names, only daily counts of checks."),
            // SHOPPING_WATCH.md (ADR-614): a price Doddy's server watches for the user. No model is involved, so
            // nothing here goes to an AI service; the shop's own page is read by Doddy's server, not by this app.
            DataFlowRow(
                id: "watches", destination: "Your Doddy messaging server and the shops' pages (prices you watch)",
                what: "For each price you ask Doddy to watch: the shop's name and page address, the product's title and the price you want. Doddy's server reads that shop's page a few times a day for 30 days, as a polite automated reader that follows the shop's rules, and sends you one notification if the price it read reaches yours. The notification has no product words. Nothing is bought, ordered or signed in. Never your saved notes, lists or profile.",
                when: "Only when you say yes to watching a price, until it ends (30 days at most) or you stop or delete it.",
                isActive: state.messagingServerSet && !state.pauseAll,
                note: !state.messagingServerSet
                    ? "No messaging server is set, so prices can't be watched."
                    : state.pauseAll
                        ? "Connections are paused, so no new price is watched. Prices you already watch keep being checked by Doddy's server until you stop or delete them."
                        : "The server keeps the words encrypted only while the watch runs and for 30 days after it ends; Delete removes it at once. It keeps no page content, only the prices it read and when."),
            DataFlowRow(
                id: "siri", destination: "Apple (Siri)",
                what: "What you ask Siri to look for, and the note Siri reads back with when you saved it.",
                when: "Only when you say \"Ask Doddy what I saved\" with your iPhone unlocked.",
                isActive: state.siriReadsNotes,
                note: state.siriReadsNotes
                    ? "Doddy searches on this iPhone; Siri hears the request and speaks the answer as your Siri settings allow, which can include Apple's servers."
                    : "Reading notes aloud with Siri is off, so Siri gets no notes from Doddy."),
            DataFlowRow(
                id: "askDoddy", destination: "Your Doddy messaging server and Anthropic (Ask Doddy)",
                what: ask + ".", when: "Only when you send a typed question in Messages.",
                isActive: state.askDoddyOn && state.messagingServerSet,
                note: !state.askDoddyOn
                    ? "Ask Doddy is off, so nothing goes there."
                    : state.messagingServerSet
                        ? "Your messaging server passes it to Anthropic and keeps only counts, not words. The conversation itself stays on this iPhone."
                        : "No messaging server is set, so typed questions can't be sent."),
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
        if active.contains("askDoddy") { parts.append("Anthropic (Ask Doddy)") }
        // ADR-603: Claude reads the best matches of what you keep on Doddy's server, when you ask on the web.
        if active.contains("webMemory") { parts.append("Anthropic (questions you ask on the web about what you keep on Doddy's server)") }
        if active.contains("messagingServer") {
            parts.append("ElevenLabs (phone calls) and \(newsWriter(state)) (daily news) on your messaging server")
        }
        // ADR-570: Claude researches the tasks you hand over.
        if active.contains("errands") { parts.append("Anthropic (tasks you hand over)") }
        // SHOPPING.md: item names and leaflet pages, for leaflets that are only pictures.
        if active.contains("deals") { parts.append("Anthropic (leaflets you check)") }
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
        "deals": "the shops' leaflet pages and Anthropic (leaflets you check, through your messaging server)",
        "watches": "the shops' pages, read by your messaging server (prices you watch)",
        "siri": "Siri (when you ask it)",
        "askDoddy": "Anthropic (Ask Doddy, through your messaging server)",
        "webMemory": "your Doddy server and Anthropic (notes and conversations you keep there)",
    ]

    /// Covered by another name (translator mode goes to whichever service runs the voice, which is
    /// named), or not sent by the app (a backup file goes where you save it).
    // webSignIn: the same Doddy server the doddyServer row already names.
    static let notInNetworkSummary: Set<String> = ["translator", "backup", "webSignIn"]

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
