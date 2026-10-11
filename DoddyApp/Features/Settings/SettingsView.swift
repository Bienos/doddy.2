import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.openingScene) private var openingOn = true
    @AppStorage(PreferenceKey.listenOnOpen) private var listenOnOpen = OpeningPreferences.listenOnOpenDefault
    @AppStorage(PreferenceKey.widgetsShowContent) private var widgetsOn = true
    @AppStorage(PreferenceKey.heyDoddyOn) private var heyDoddyOn = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.rememberConversations) private var rememberConversations = true
    @State private var connections = ConnectionController()
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    @AppStorage(PreferenceKey.voiceTokenServer) private var voiceTokenServer = ""
    @State private var accessCodeDraft = ""
    @State private var hasAccessCode = VoiceAccessCodeStore.read() != nil
    @State private var accessCodeError: String?
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var connectedAppsServerURL = ""
    @AppStorage(PreferenceKey.memoryCopyOn) private var memoryCopyOn = false
    @State private var sessionTokenDraft = ""
    @State private var hasSessionToken = KeychainSessionStore.hasToken
    @State private var tokenMessage: String?
    @State private var confirmDeleteAll = false
    @State private var choosingRestoreFile = false
    @State private var restorePlan: MemoryRestorePlan?
    /// List items from the same file (ADR-216), put back after their lists.
    @State private var restoreItems: [ListItem] = []
    @State private var restoreMessage: String?
    @State private var restoreFailed = false
    @State private var deleteError: String?
    @AppStorage(PreferenceKey.suggestSavesAfterConversation) private var suggestSaves = true
    @AppStorage(PreferenceKey.siriReadsNotes) private var siriReadsNotes = true
    @State private var editingProfile = false
    @State private var confirmForget = false
    @State private var forgetError: String?
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var assistantUseNotes = true
    @AppStorage(PreferenceKey.gatewayAddress) private var gatewayAddress = ""
    @State private var showAssistantConsent = false
    @State private var inviteDraft = ""
    @State private var hasInviteCode = false
    @State private var inviteError: String?

    private var environment: AppEnvironment { store.environment }
    private var privacy: PrivacyDefaults { environment.privacy }
    private var router: ShortcutRouter { .shared }
    private var conversationLogs: ConversationLogStore { .shared }
    private var activityLog: ActivityLogStore { .shared }
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false

    private var activitySummary: String {
        let today = activityLog.entries.filter { Calendar.current.isDateInToday($0.at) }.count
        return activityLog.entries.isEmpty ? "Nothing yet" : "\(today) today"
    }

    private var backTapStatus: String {
        switch router.setup.phase {
        case .notStarted: NSLocalizedString("Not set up", comment: "")
        case .deferred: NSLocalizedString("Set up later", comment: "")
        case .userReportedTested(let at): "Tested by you · \(DateText.full(at))"
        case .shortcutPreparation, .guiding, .testing, .receiptReceived: NSLocalizedString("In progress", comment: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    JourneyHeading(eyebrow: "Less magic. More control.", title: "Yours to keep.\nYours to change.")
                    HStack(spacing: 18) {
                        UploadedCharacterView(assetName: "UploadedDoddy_Privacy", height: 110)
                        Text("You choose each saved memory. See the original, edit it or remove it.")
                            .font(.subheadline)
                    }
                    Text("Text capture and search work locally. Voice has separate network and microphone behaviour, explained below.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.canvas)
                Section("About this build") {
                    StatusRow(title: "Version", value: Self.versionText)
                    Text("Development build. DODDY is an AI assistant, not a person. This memory interface uses your approved numbered-asset design; physical-device and release checks remain outstanding.")
                }

                Section {
                    Link(destination: Self.tiktokURL) {
                        Label("TikTok · doddy_mate", systemImage: "play.rectangle")
                    }
                    .accessibilityIdentifier("settings.tiktok")
                    Link(destination: Self.instagramURL) {
                        Label("Instagram · doddy_mate", systemImage: "camera")
                    }
                    .accessibilityIdentifier("settings.instagram")
                } header: {
                    Text("Follow Doddy")
                } footer: {
                    Text("Opens TikTok or Instagram outside Doddy. Nothing from the app is shared.")
                }

                Section("About you") {
                    if profiles.profile.isEmpty {
                        Text("Nothing saved. Doddy only keeps what you review and save.")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(ProfileKey.allCases.filter { profiles.profile.value($0) != nil }, id: \.self) { key in
                            StatusRow(title: key.label, value: profiles.profile.value(key) ?? "")
                        }
                    }
                    Button(profiles.profile.isEmpty ? "Add preferences" : "Edit") { editingProfile = true }
                        .disabled(profiles.progress == nil)
                        .accessibilityIdentifier("settings.editProfile")
                    Button("Answer the intro questions again") {
                        Task { await profiles.reopenIntroduction() }
                    }
                    .disabled(profiles.progress == nil)
                    Toggle("Use in voice conversations", isOn: $shareProfileWithVoice)
                        .accessibilityIdentifier("settings.shareProfileWithVoice")
                    Button("Forget all of this", role: .destructive) { confirmForget = true }
                        .disabled(profiles.profile.isEmpty)
                        .accessibilityIdentifier("settings.forgetProfile")
                    if let forgetError {
                        Label(forgetError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    ShareLink(
                        item: ProfileJSONExport(profile: profiles.profile),
                        preview: SharePreview("Doddy profile and settings (JSON)")
                    ) {
                        Label("Export with your settings as JSON", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.exportProfileJSON")
                    ShareLink(
                        item: ProfileTextExport(profile: profiles.profile),
                        preview: SharePreview("Doddy profile and settings (text)")
                    ) {
                        Label("Export with your settings as text", systemImage: "doc.plaintext")
                    }
                    .accessibilityIdentifier("settings.exportProfileText")
                    Text("Stored on this iPhone with your memories, but separately: forgetting these doesn't delete memories, and deleting memories doesn't forget these. With \"Use in voice conversations\" on, these answers are sent to ElevenLabs at the start of each conversation so Doddy knows them; off, they stay on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("Your memories") {
                    StatusRow(title: "Saved on this iPhone", value: "\(store.memories.count)")
                    ShareLink(
                        item: JSONExport(
                            records: store.memories + store.lists.map(\.record), listItems: store.lists.flatMap(\.items),
                            corrections: store.corrections),
                        preview: SharePreview("Doddy memories (JSON)")
                    ) {
                        Label("Export as JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!hasSavedAnything)
                    ShareLink(
                        item: MemoryExport.plainText(store.memories, lists: store.lists, corrections: store.corrections, exportedAt: .now),
                        preview: SharePreview("Doddy memories (text)")
                    ) {
                        Label("Export as text", systemImage: "doc.plaintext")
                    }
                    .disabled(!hasSavedAnything)
                    ShareLink(
                        item: MarkdownFileExport(records: store.memories, lists: store.lists, corrections: store.corrections),
                        preview: SharePreview("Doddy memories (Markdown)")
                    ) {
                        Label("Export as Markdown", systemImage: "doc.richtext")
                    }
                    .disabled(!hasSavedAnything)
                    .accessibilityIdentifier("settings.exportMarkdown")
                    Button {
                        restoreMessage = nil
                        choosingRestoreFile = true
                    } label: {
                        Label("Restore from a JSON export", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!store.isStorageAvailable)
                    .accessibilityIdentifier("settings.restoreMemories")
                    if let restoreMessage {
                        Label(restoreMessage, systemImage: restoreFailed ? "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundStyle(restoreFailed ? Theme.error : Theme.confirmed)
                    }
                    Button("Delete all memories", role: .destructive) { confirmDeleteAll = true }
                        .disabled(!hasSavedAnything)
                        .accessibilityIdentifier("settings.deleteAll")
                    if let deleteError {
                        Label(deleteError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    Text(memoriesWhereText)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                MorningCheckInSettingsSection()

                EveningWrapUpSettingsSection()

                WeeklyLookBackSettingsSection()

                TidyUpSettingsSection()

                BackupSettingsSection()

                NoteImportSettingsSection()

                WatchSettingsSection()

                // Widgets (ADR-219): what they show, and the switch that empties the shared file.
                Section("Widgets") {
                    if WidgetSync.shared.isAvailable {
                        Toggle("Show notes and lists in widgets", isOn: $widgetsOn)
                            .accessibilityIdentifier("settings.widgetsOn")
                        Text(widgetsOn
                             ? "Widgets show your pinned notes, your next reminders and your lists, shortened. They're kept in a file only Doddy and its widgets can open. On the Lock Screen, iOS hides the text until you unlock. Ticking from a widget needs your iPhone unlocked."
                             : "Widgets show nothing of yours, and the widgets' file holds nothing of yours.")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                        if let problem = WidgetSync.shared.problem {
                            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                        }
                    } else {
                        Text("This build of Doddy can't share anything with widgets (it isn't signed with Doddy's App Group), so widgets show only \"Open Doddy\".")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }

                Section("Privacy") {
                    // ADR-310: Face ID when Doddy opens, and after a minute away.
                    AppLockToggle()
                    // iPhone search (ADR-330), off until switched on.
                    SpotlightToggle()
                    NavigationLink {
                        DataFlowView()
                    } label: {
                        Label("What leaves this iPhone", systemImage: "arrow.up.right.circle")
                    }
                    .accessibilityIdentifier("settings.dataFlow")
                    StatusRow(title: "Account required", value: privacy.accountRequired ? "Yes" : "No")
                    StatusRow(title: "Network", value: privacy.networkRequestsMade ? "While talking (ElevenLabs, token server), when you use Connected Apps, and when you use Ask Doddy" : "None")
                    StatusRow(
                        title: "Microphone",
                        value: !privacy.microphoneUsed ? "Not used"
                            : heyDoddyOn ? "While talking, and while \u{201C}Hey Doddy\u{201D} listens for its wake word on this iPhone; turn that off under Hey Doddy"
                            : listenOnOpen ? "Only while talking. A conversation starts when you open Doddy; turn that off under Voice"
                            : "Only while talking")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "ElevenLabs (voice); OpenAI if Ask Doddy is on" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncText)
                    // DataFlow (What leaves this iPhone) restates this paragraph row by row; change both together.
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation, your saved notes (except ones you mark Private), your list names (a list's items only when Doddy reads or changes it), your personality settings, and (if switched on) your last few conversations and your introduction answers are sent to ElevenLabs, which runs the voice agent. Calendar entries, contact names and birthdays (day and month) or message drafts Doddy uses in a conversation go too. When you ask for weather or facts, ElevenLabs looks them up for Doddy: the place name and coordinates go to Open-Meteo, and search words go to Wikipedia; this app makes no such requests itself. ElevenLabs keeps a recording and transcript of each conversation. If a token server is set, starting a conversation also sends your access code to it. If you use Connected Apps or switch on an online-account tool, the app sends what you ask (a date, a search word, or the text of a draft, reply or task you confirm) to your Doddy server, which talks to Google, Microsoft (Outlook), Notion or Todoist through Composio, and the results come back to the app and, during a conversation, to ElevenLabs so Doddy can answer; your saved notes are never sent to that server. If you ask Siri \u{201C}Ask Doddy what I saved\u{201D} (it can be turned off below), Doddy searches on this iPhone and hands the matching note to Siri, Apple's assistant, to read aloud; Siri handles what you say and the answer under your Siri settings. If you turn on \u{201C}Hey Doddy\u{201D}, the microphone listens for the wake word on this iPhone and what it hears isn't kept or sent; Picovoice gets your AccessKey to check it, and the conversation the wake word starts goes to ElevenLabs like any other. If you switch on web search, your search words go the same way to your Doddy server, which looks them up through Monid (a paid search service Doddy's server uses; you don't sign in to it). If you turn on Ask Doddy, typed questions (and, if you allow it, saved notes that match them) go to the Ask Doddy gateway, a separate server, which passes them to OpenAI. If a Doddy messaging server is set and you turn on notifications, texts, phone calls or daily news, it gets an anonymous account token, this iPhone's notification token, your phone number once you confirm it with a code, and the news topics you pick; it sends through Apple and Twilio, runs calls on ElevenLabs, and writes the news with an AI (Anthropic or OpenAI, as the server is set up; Daily news names which) and GNews. Your saved notes go there only if you turn on \u{201C}Let Doddy use my memories on calls\u{201D}. If you search for a place for a reminder, the words you type (and roughly where you are, if Doddy already knows) go to Apple Maps; the place you pick stays on this iPhone, and iOS, not Doddy, notices when you get there. In translator mode the other person's voice goes to ElevenLabs too (listen only hears whoever is near you); started from Translate on Home, your notes, conversations and profile aren't sent, and nothing of it is kept on this iPhone unless you tap Copy or Save within 5 minutes. If you share a list, its name and items go to your iCloud (Apple) and to the people you invite, and their changes come back; a list reminder's place goes there too only if you tap Share this place. If you ask Doddy to convert money, the app downloads the European Central Bank's public exchange-rate file; nothing about you is sent with it. If you switch on Read an email or Read a Notion page, the one email (sender, subject and its text) or page (title and text) you ask about, cut short, comes from your Doddy server and goes to ElevenLabs during that conversation. Text you share to Doddy from another app, to-dos found in a voice memo and your Focus settings stay on this iPhone; the parking widget shows when you parked and your note, never where. If you ask Doddy to remind you when to leave, where your iPhone is and the place you're going go to Apple Maps once, to work out the travel time; neither is kept. If you turn on Show notes in iPhone search, your notes and lists (never private ones) are indexed by iOS on this iPhone. Nothing else is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("settings.privacy")

                Section {
                    NavigationLink {
                        ConnectedAppsScreen()
                    } label: {
                        Label("Connected Apps", systemImage: "link")
                    }
                    .accessibilityIdentifier("settings.connectedApps")
                } header: {
                    Text("Connected Apps")
                } footer: {
                    Text("Google Calendar, read-only. Shows tomorrow's events when you ask; nothing is saved unless you tap Save.")
                }

                Section {
                    NavigationLink {
                        OnlineAccountsScreen()
                    } label: {
                        Label("Online accounts", systemImage: "switch.2")
                    }
                    .accessibilityIdentifier("settings.onlineAccounts")
                } header: {
                    Text("Online accounts")
                } footer: {
                    Text("Gmail, Google Drive, Notion and Todoist through Composio, with a switch for every tool. All off until you turn them on; anything that adds or creates asks you first.")
                }

                Section {
                    TextField("Server address (https://…)", text: $connectedAppsServerURL)
                        .font(.body.monospaced())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.connectedAppsServer")
                    if hasSessionToken {
                        StatusRow(title: "Session token", value: "Saved in Keychain")
                        Button("Remove session token", role: .destructive) {
                            KeychainSessionStore.delete()
                            hasSessionToken = false
                            tokenMessage = nil
                        }
                    } else {
                        SecureField("Session token", text: $sessionTokenDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("settings.connectedAppsToken")
                        Button("Save session token") {
                            let token = sessionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            // The token is kept for this server only and never sent to another (DOD-11).
                            if let server = URL(string: connectedAppsServerURL.trimmingCharacters(in: .whitespaces)),
                               server.scheme != nil, server.host != nil {
                                if KeychainSessionStore.save(token, issuedBy: server) {
                                    hasSessionToken = true
                                    tokenMessage = nil
                                } else {
                                    tokenMessage = "The Keychain didn't accept the token, so it wasn't saved."
                                }
                                sessionTokenDraft = ""
                            } else {
                                tokenMessage = "Enter the server address first. The token is kept for that server only."
                            }
                        }
                        .disabled(sessionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let tokenMessage {
                        Label(tokenMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    }
                } header: {
                    Text("Connected Apps server (development)")
                } footer: {
                    Text("Development setting. Use https, or http://localhost with the Simulator. The token comes from the server owner and is stored only in this iPhone's Keychain, for the server address set when you saved it; it is never sent to another address.")
                }

                Section("What Doddy knows") {
                    Toggle("Remember recent conversations", isOn: $rememberConversations)
                        .accessibilityIdentifier("settings.rememberConversations")
                    NavigationLink {
                        RememberedConversationsView(store: conversationLogs)
                    } label: {
                        StatusRow(title: "Remembered conversations", value: "\(conversationLogs.logs.count) of the last \(ConversationLogStore.maxLogs)")
                    }
                    .accessibilityIdentifier("settings.rememberedConversations")
                    Button("Forget remembered conversations", role: .destructive) { conversationLogs.clear() }
                        .disabled(conversationLogs.logs.isEmpty)
                    // ADR-247: "Worth keeping?" after a voice conversation.
                    Toggle("Suggest notes after a conversation", isOn: $suggestSaves)
                        .accessibilityIdentifier("settings.suggestSaves")
                    Text("When a conversation ends, Doddy may offer up to three things you said, in your words, to save as notes. Nothing is ticked and nothing is saved unless you tap Save. They're picked on this iPhone; never for a private conversation, and never passwords or card numbers.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if let problem = conversationLogs.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    Text("When a conversation starts, the app hands Doddy your saved notes and, if this is on, your last few conversations, so he can carry on where you left off. They are kept only on this iPhone. Weather comes from Open-Meteo and facts from Wikipedia.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                if environment.capabilities.isAvailable(.noteReminders) {
                    NoteReminderSettingsSection()
                }

                Section("Voice") {
                    PersonalityLinkRow()
                    // The Dynamic Island and Lock Screen styles: iPhone only (ADR-432).
                    if DeviceSupport.hasLiveActivities { IslandStyleLinkRow() }
                    Toggle("Start listening when I open Doddy", isOn: $listenOnOpen)
                        .accessibilityIdentifier("settings.listenOnOpen")
                    Text(listenOnOpen
                        ? "When you open Doddy (after the opening, if that's on), Talk to Doddy opens by itself and listens until you end the conversation, as if you had tapped the button. iOS asks for the microphone the first time and shows its orange indicator while Doddy listens. Coming back within five minutes doesn't start another one. It doesn't start when iOS has refused the microphone, or when you open Doddy from Back Tap or Siri, which start their own."
                        : "Off: nothing listens until you tap Talk to Doddy.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("settings.listenOnOpen.note")
                    StatusRow(title: "Connection", value: connectionText)
                        .accessibilityIdentifier("settings.voiceConnection")
                    TextField("Token server (https://…)", text: $voiceTokenServer)
                        .font(.body.monospaced())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.voiceTokenServer")
                    if hasAccessCode {
                        Button("Remove access code", role: .destructive) {
                            VoiceAccessCodeStore.delete()
                            hasAccessCode = false
                        }
                    } else {
                        SecureField("Access code", text: $accessCodeDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("settings.voiceAccessCode")
                        Button("Save access code") { saveAccessCode() }
                            .disabled(accessCodeDraft.allSatisfy(\.isWhitespace))
                    }
                    if let accessCodeError {
                        Label(accessCodeError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    if voiceTokenServer.allSatisfy(\.isWhitespace) {
                        TextField("ElevenLabs agent ID", text: $voiceAgentID)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("settings.voiceAgentID")
                        if voiceAgentID != VoiceConfig.developmentAgentID {
                            Button("Use the development agent") { voiceAgentID = VoiceConfig.developmentAgentID }
                        }
                    }
                    Text("With a token server, Doddy sends only your access code to it to get a one-conversation pass; the conversation itself goes to ElevenLabs. Without one, the development agent is open to anyone who has its ID. Conversations count toward the owner's ElevenLabs minutes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                // ADR-254: "Hey Doddy" wake word, off unless turned on.
                HeyDoddySettingsSection()

                Section {
                    // Back Tap exists only on iPhone (ADR-337).
                    if DeviceSupport.hasBackTap {
                        StatusRow(title: "Double Back Tap", value: backTapStatus)
                            .accessibilityIdentifier("settings.backTap.status")
                        Button(router.setup.coordinator.isDone ? "Go through the setup again" : "Set up Double Back Tap") {
                            router.isSetupPresented = true
                        }
                        .accessibilityIdentifier("settings.backTap")
                    }
                    Text("\"Talk to Doddy\" is built in as a shortcut for Siri, the Shortcuts app and the Action Button, and on iOS 18 or later as a control you can add to Control Center or the Lock Screen (edit Control Center, then Add a Control, then search Doddy). Back Tap and controls are placed by you; Doddy can't add them and can't see whether they're set.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    // ADR-248: "Ask Doddy what I saved".
                    Toggle("Siri can read my notes aloud", isOn: $siriReadsNotes)
                        .accessibilityIdentifier("settings.siriReadsNotes")
                    Text("Say \"Ask Doddy what I saved\", then what you're looking for. Doddy searches your notes on this iPhone and Siri reads the matching note and when you saved it, without opening the app. Your iPhone must be unlocked. Siri is Apple's: it hears your request and speaks the answer, under your Siri settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } header: {
                    if DeviceSupport.hasBackTap { Text("Back Tap and Siri") } else { Text("Siri") }
                }

                Section {
                    Toggle("Pause all connections", isOn: $pauseAllConnections)
                        .accessibilityIdentifier("settings.pauseAll")
                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        StatusRow(title: "Calendar, reminders, contacts", value: connectionSummary)
                    }
                    .accessibilityIdentifier("settings.connections")
                    // Connections uses its own controller; re-read when coming back from it.
                    .onAppear { Task { await connections.refresh() } }
                    NavigationLink {
                        ActivityView()
                    } label: {
                        StatusRow(title: "What Doddy did", value: activitySummary)
                    }
                    .accessibilityIdentifier("settings.activity")
                    NavigationLink {
                        AlarmsView()
                    } label: {
                        Label("Alarms", systemImage: "alarm")
                    }
                    .accessibilityIdentifier("settings.alarms")
                    NavigationLink {
                        BirthdaysView()
                    } label: {
                        Label("Birthdays", systemImage: "gift")
                    }
                    .accessibilityIdentifier("settings.birthdays")
                    NavigationLink {
                        PlanPracticeView()
                    } label: {
                        Label("Try a plan card", systemImage: "checklist")
                    }
                    .accessibilityIdentifier("settings.planPractice")
                } header: {
                    Text("Connections")
                } footer: {
                    HStack(alignment: .top, spacing: 12) {
                        // Paused: Doddy lies low, crouching (ADR-323).
                        if pauseAllConnections { WholeDoddyView(pose: .sneakyCrouch, height: 56) }
                        Text(pauseAllConnections
                            ? "Paused: Doddy doesn't use Calendar, Reminders, Contacts, Timers, Maps, Shortcuts, Messages or your online accounts. Your notes still work. Turning this off brings back the ones you had on; iPhone permissions don't change."
                            : "Each one starts off. Turning one on asks iPhone for permission first.")
                    }
                }

                Section {
                    NavigationLink {
                        UpdatesSettingsView()
                    } label: {
                        Label("Notifications and texts", systemImage: "bell")
                    }
                    .accessibilityIdentifier("settings.updates")
                    NavigationLink {
                        NewsSettingsView()
                    } label: {
                        Label("Daily news", systemImage: "newspaper")
                    }
                    .accessibilityIdentifier("settings.news")
                    NavigationLink {
                        CallsSettingsView()
                    } label: {
                        Label("Phone calls", systemImage: "phone")
                    }
                    .accessibilityIdentifier("settings.calls")
                } header: {
                    Text("Messages from Doddy")
                } footer: {
                    Text("Needs a Doddy messaging server. Each one is off until you turn it on.")
                }

                Section("Ask Doddy (typed questions)") {
                    Toggle("Turn on Ask Doddy", isOn: Binding(
                        get: { assistantConsent },
                        set: { wanted in
                            if wanted { showAssistantConsent = true } else { assistantConsent = false }
                        }))
                        .accessibilityIdentifier("settings.assistantConsent")
                    Toggle("Use relevant saved notes", isOn: $assistantUseNotes)
                        .disabled(!assistantConsent)
                        .accessibilityIdentifier("settings.assistantUseNotes")
                    TextField("Gateway address (https://…)", text: $gatewayAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.gatewayAddress")
                    if !gatewayAddress.isEmpty && GatewayConfiguration(string: gatewayAddress) == nil {
                        Label("That isn't a valid https address.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    SecureField(hasInviteCode ? "Invite code saved. Enter a new one to replace it" : "Invite code", text: $inviteDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.inviteCode")
                    Button("Save invite code") { Task { await saveInviteCode() } }
                        .disabled(inviteDraft.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                    if hasInviteCode {
                        Button("Remove invite code", role: .destructive) { Task { await removeInviteCode() } }
                    }
                    if let inviteError {
                        Label(inviteError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    StatusRow(title: "Status", value: assistantStatus)
                        .accessibilityIdentifier("settings.assistantStatus")
                    Text("Private-beta feature. Doddy's server keeps the AI key, so no key is stored on your iPhone. The invite code and a random install ID (not linked to you) are kept in the iOS Keychain on this iPhone to prove it may use the server.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .task { await refreshInviteState() }

                Section("Appearance and accessibility") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases, id: \.rawValue) { option in
                            Text(option.rawValue.capitalized).tag(option.rawValue)
                        }
                    }
                    Toggle("Hide character artwork", isOn: $hideCharacterArt)
                    Toggle("Doddy's opening", isOn: $openingOn)
                        .accessibilityIdentifier("settings.openingScene")
                    Text("Each time you open Doddy: a two-second cartoon. A pen sketches Doddy in, he scores a basket and pops up ready to talk, then the buttons slide in. Tap it to skip. With Reduce Motion on it's a still picture; with character artwork hidden or VoiceOver on it doesn't play.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Text size follows your iOS settings, including larger accessibility sizes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("What's built") {
                    ForEach(Capability.allCases, id: \.self) { capability in
                        StatusRow(
                            title: capability.displayName,
                            value: StatusCopy.text(for: environment.capabilities.status(of: capability)))
                    }
                }
                .accessibilityIdentifier("settings.capabilities")
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .tabBar)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Turn on Ask Doddy?",
                isPresented: $showAssistantConsent, titleVisibility: .visible
            ) {
                Button("Turn on") { assistantConsent = true }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("When you ask a question, it is sent with your last few messages to Doddy's server, which passes it to OpenAI to write the answer. If \"Use relevant saved notes\" is on, notes that match your question are sent too, and the answer shows which ones. Doddy's server does not store them and logs no text. We ask OpenAI not to keep the reply, but we can't verify that. Voice conversations are separate. You can turn this off at any time.")
            }
            .confirmationDialog(
                deleteAllTitle,
                isPresented: $confirmDeleteAll, titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { Task { await deleteAll() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every note, every list with its items, and the search index from this iPhone and can't be undone. Lists you shared stop being shared, so the people you invited lose them too. With Memory on calls on, the copy on your Doddy messaging server is emptied. Exported files and older backups aren't affected.")
            }
            .fileImporter(isPresented: $choosingRestoreFile, allowedContentTypes: [.json]) { result in
                prepareRestore(result)
            }
            .confirmationDialog(
                restorePlan.map(RestoreCopy.title) ?? "",
                isPresented: Binding(get: { restorePlan != nil }, set: { if !$0 { restorePlan = nil } }),
                titleVisibility: .visible,
                presenting: restorePlan
            ) { plan in
                Button(RestoreCopy.action(plan)) { Task { await restore(plan) } }
                Button("Cancel", role: .cancel) { restorePlan = nil }
            } message: { plan in
                Text(RestoreCopy.details(plan))
            }
            .confirmationDialog(
                "Forget your name and preferences?",
                isPresented: $confirmForget, titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) { Task { await forgetProfile() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes what you told Doddy in the introduction from this iPhone. Your saved memories stay.")
            }
            .sheet(isPresented: $editingProfile) { ProfileEditSheet() }
        }
        .foregroundStyle(Theme.ink)
    }

    /// Where memories are, as switched on now (DOD-11): never "only on this iPhone" while a copy is
    /// on the messaging server or a list is shared through iCloud.
    private var memoriesWhereText: String {
        let sharedLists = SharedListsController.shared.links.count
        guard memoryCopyOn || sharedLists > 0 else {
            return NSLocalizedString("Memories live only in this app on this iPhone, protected by iOS Data Protection. Like other app data they are included in your iPhone backups. Photos and voice memos added to notes stay on this iPhone and aren't in exports; they go in an encrypted backup file only if you include them. Deleting a note deletes its photo and recording. Voice memos are written out on this iPhone, never sent. Deleting here does not remove files you exported or older backups. Your answers under About you and your voice and personality settings are exported there, not here.", comment: "")
        }
        var text = NSLocalizedString("Memories are kept in this app on this iPhone, protected by iOS Data Protection. Like other app data they are included in your iPhone backups. Photos and voice memos added to notes stay on this iPhone and aren't in exports; they go in an encrypted backup file only if you include them. Deleting a note deletes its photo and recording. Voice memos are written out on this iPhone, never sent. Deleting here does not remove files you exported or older backups. Your answers under About you and your voice and personality settings are exported there, not here.", comment: "")
        if memoryCopyOn {
            text += " " + NSLocalizedString("With Memory on calls on, a copy of your notes is also on your Doddy messaging server.", comment: "")
        }
        if sharedLists > 0 {
            text += " " + NSLocalizedString("Lists you share are also in iCloud and with the people you invited.", comment: "")
        }
        return text
    }

    /// Lists are memories too: they are exported and deleted with the notes (DOD-06).
    private var hasSavedAnything: Bool { !store.memories.isEmpty || !store.lists.isEmpty }

    /// Names everything Delete all removes, notes and lists, never notes alone.
    private var deleteAllTitle: String {
        String(
            format: NSLocalizedString("Delete all %lld notes and %lld lists?", comment: ""),
            store.memories.count, store.lists.count)
    }

    private var connectionSummary: String {
        if pauseAllConnections { return NSLocalizedString("Paused", comment: "") }
        let on = VoiceConnection.allCases.filter { connections.state(of: $0) == .on }.count
        return on == 0 ? "All off" : "\(on) of \(VoiceConnection.allCases.count) on"
    }

    private var connectionText: String {
        switch VoiceConnectionMode.resolve(
            serverAddress: voiceTokenServer, accessCode: hasAccessCode ? VoiceAccessCodeStore.read() : nil,
            publicAgentID: voiceAgentID) {
        case .tokenServer: NSLocalizedString("Private (token server)", comment: "")
        case .publicAgent: NSLocalizedString("Development (public agent)", comment: "")
        case .notSetUp: NSLocalizedString("Not set up", comment: "")
        }
    }

    private func saveAccessCode() {
        let code = accessCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if VoiceAccessCodeStore.save(code) {
            hasAccessCode = true
            accessCodeDraft = ""
            accessCodeError = nil
        } else {
            accessCodeError = "The access code couldn't be saved in the Keychain. Nothing was stored."
        }
    }

    private static let assistantUnavailable = "Ask Doddy isn't available while Doddy's storage can't be opened."

    private var assistantStatus: String {
        if !assistantConsent { return "Off" }
        if environment.assistant == nil { return NSLocalizedString("Not available (storage problem)", comment: "") }
        if GatewayConfiguration(string: gatewayAddress) == nil { return NSLocalizedString("Needs a gateway address", comment: "") }
        if !hasInviteCode { return NSLocalizedString("Needs an invite code", comment: "") }
        return NSLocalizedString("Ready (not yet tested with a real server)", comment: "")
    }

    private func refreshInviteState() async {
        guard let credentials = environment.assistant?.credentials else { return }
        hasInviteCode = ((try? await credentials.inviteCode()) ?? nil) != nil
    }

    private func saveInviteCode() async {
        guard let credentials = environment.assistant?.credentials else {
            inviteError = Self.assistantUnavailable
            return
        }
        let code = inviteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await credentials.setInviteCode(code)
            try await credentials.setToken(nil) // a new code needs a new token
            inviteDraft = ""
            inviteError = nil
            hasInviteCode = true
        } catch {
            inviteError = "Couldn't save the invite code on this iPhone."
        }
    }

    private func removeInviteCode() async {
        guard let credentials = environment.assistant?.credentials else {
            inviteError = Self.assistantUnavailable
            return
        }
        do {
            try await credentials.setInviteCode(nil)
            try await credentials.setToken(nil)
            inviteError = nil
            hasInviteCode = false
        } catch {
            inviteError = "Couldn't remove the invite code."
        }
    }

    /// Stops sharing the user's own shared lists first (their iCloud copy is deleted for everyone),
    /// then deletes on this iPhone, then empties the server copy if Memory on calls is on and
    /// waits for the server's answer. Whatever couldn't be undone outside this iPhone is said
    /// plainly, never covered by "deleted" (DOD-06/11).
    private func deleteAll() async {
        let stillShared = await SharedListsController.shared.stopAllOwnedShares()
        let stillSharedNames = stillShared.compactMap { store.list(id: $0)?.name }
        do {
            try await store.deleteAll()
            UserDefaults.standard.removeObject(forKey: PreferenceKey.pinnedNotes)
        } catch {
            deleteError = UserFacingError.message(for: error)
            return
        }
        var problems: [String] = []
        if !stillShared.isEmpty {
            problems.append(String(
                format: NSLocalizedString("Deleted on this iPhone, but sharing couldn't be stopped for %lld shared lists (%@). Their copy stays in iCloud and with the people you invited.", comment: ""),
                stillShared.count, stillSharedNames.joined(separator: ", ")))
        }
        do {
            try await MemoryCopySync.shared.uploadNow([])
        } catch {
            problems.append(String(
                format: NSLocalizedString("The copy on your Doddy messaging server (Memory on calls) couldn't be emptied yet: %@ Doddy tries again the next time you open it.", comment: ""),
                UpdatesModel.text(for: error)))
        }
        deleteError = problems.isEmpty ? nil : problems.joined(separator: " ")
    }

    /// Reads and checks the chosen file and works out what it would add. Nothing is written
    /// until the user confirms (ADR-178).
    private func prepareRestore(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= MemoryRestore.maxFileBytes else {
                throw MemoryRestoreError.tooLarge(bytes: size, maximum: MemoryRestore.maxFileBytes)
            }
            let data = try Data(contentsOf: url)
            let file = try MemoryRestore.read(data)
            restoreItems = try MemoryRestore.listItems(data)
            let plan = MemoryRestore.plan(
                file.records, corrections: file.corrections, existing: store.memories + store.lists.map(\.record),
                exportedAt: file.exportedAt)
            if plan.isEmpty {
                restoreFailed = false
                restoreMessage = RestoreCopy.nothingToAdd(plan)
            } else {
                restorePlan = plan
            }
        } catch {
            restoreFailed = true
            restoreMessage = RestoreCopy.failure(error)
        }
    }

    private func restore(_ plan: MemoryRestorePlan) async {
        restorePlan = nil
        do {
            let added = try await store.restore(plan.toAdd, corrections: plan.corrections, listItems: restoreItems)
            restoreItems = []
            restoreFailed = false
            restoreMessage = added.count == 1 ? "Added 1 note from the export." : "Added \(added.count) notes from the export."
        } catch {
            restoreFailed = true
            restoreMessage = RestoreCopy.failure(error)
        }
    }

    private func forgetProfile() async {
        do {
            try await profiles.forget()
            forgetError = nil
        } catch {
            forgetError = ProfileErrorText.message(for: error)
        }
    }

    // Doddy's own social accounts (ADR-130). Opening one hands off to the system; the app sends nothing.
    private static let tiktokURL = URL(string: "https://www.tiktok.com/@doddy_mate")!
    private static let instagramURL = URL(string: "https://www.instagram.com/doddy_mate/")!

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Edit the approved profile. Cancel leaves it exactly as it was.
private struct ProfileEditSheet: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ProfileDraft()
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileFieldsEditor(draft: $draft)
                    if draft.isEffectivelyEmpty {
                        Text("Saving now stores nothing and removes anything saved before.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    addMissing
                    if let errorText {
                        ProblemView(message: errorText)
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("About you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("profileEdit.save")
                }
            }
            .onAppear { draft = profiles.profile.draft }
        }
        .foregroundStyle(Theme.ink)
        .interactiveDismissDisabled(isSaving)
    }

    /// Fields not answered yet can be added here too.
    @ViewBuilder
    private var addMissing: some View {
        let missing = ProfileKey.allCases.filter { draft[$0] == nil }
        if !missing.isEmpty {
            Menu {
                ForEach(missing, id: \.self) { key in
                    Button(key.label) { draft[key] = "" }
                }
            } label: {
                Label("Add a preference", systemImage: "plus")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await profiles.commit(draft)
            dismiss()
        } catch {
            errorText = ProfileErrorText.message(for: error)
        }
    }
}

/// Wording for restoring memories from an export (ADR-178).
enum RestoreCopy {
    static func title(_ plan: MemoryRestorePlan) -> String {
        plan.toAdd.count == 1 ? "Add 1 note from this export?" : "Add \(plan.toAdd.count) notes from this export?"
    }

    static func action(_ plan: MemoryRestorePlan) -> String {
        plan.toAdd.count == 1 ? "Add 1 note" : "Add \(plan.toAdd.count) notes"
    }

    static func details(_ plan: MemoryRestorePlan) -> String {
        var parts: [String] = []
        if let exportedAt = plan.exportedAt {
            parts.append("Exported \(exportedAt.formatted(date: .abbreviated, time: .shortened)).")
        }
        parts.append("Notes come back exactly as exported, with their original dates and corrections.")
        if plan.alreadyHere > 0 { parts.append("\(plan.alreadyHere) already on this iPhone.") }
        if plan.keptOnPhone > 0 {
            parts.append("\(plan.keptOnPhone) changed on this iPhone since the export; those stay as they are here.")
        }
        if plan.skippedSamples > 0 { parts.append("\(plan.skippedSamples) sample notes are left out.") }
        parts.append("Nothing on this iPhone is changed or removed.")
        return parts.joined(separator: " ")
    }

    static func nothingToAdd(_ plan: MemoryRestorePlan) -> String {
        plan.keptOnPhone > 0
            ? "Nothing to add: every note in this export is already here, and the ones changed since stay as they are here."
            : "Nothing to add: every note in this export is already on this iPhone."
    }

    static func failure(_ error: any Error) -> String {
        guard let error = error as? MemoryRestoreError else {
            if error is CocoaError { return NSLocalizedString("That file couldn't be opened. Nothing was added.", comment: "") }
            if (error as? MemoryStoreError) == .verificationFailed {
                return NSLocalizedString("The restored notes couldn't be confirmed, so nothing from the file was added.", comment: "")
            }
            return UserFacingError.message(for: error)
        }
        switch error {
        case .tooLarge:
            return NSLocalizedString("That file is too large to be a Doddy export. Nothing was added.", comment: "")
        case .notADoddyExport:
            return NSLocalizedString("That isn't a Doddy memory export (Settings › Export as JSON). Nothing was added.", comment: "")
        case .newerFormat:
            return NSLocalizedString("That export was made by a newer version of Doddy. Update the app, then try again. Nothing was added.", comment: "")
        case .unreadableNote(let position):
            return "Note \(position) in that file is damaged, so nothing from it was added."
        case .conflictingDuplicate(let position):
            return "Note \(position) in that file repeats another one with different text, so nothing from it was added."
        case .unreadableCorrection(let position):
            return "Correction \(position) in that file is damaged, so nothing from it was added."
        }
    }
}

/// Profile and style settings for the share sheet (format: `ProfileExport.json`, ADR-176).
/// The settings are read when the file is made, so the export matches what is stored then.
struct ProfileJSONExport: Transferable {
    let profile: ApprovedProfile

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try ProfileExport.json(export.profile, style: .stored(), exportedAt: Date())
        }
        .suggestedFileName("doddy-profile.json")
    }
}

/// The same as text. Built when shared, not when Settings last drew, so voice and personality
/// changes made a moment ago are included.
struct ProfileTextExport: Transferable {
    let profile: ApprovedProfile

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (export: ProfileTextExport) in
            ProfileExport.plainText(export.profile, style: .stored(), exportedAt: Date())
        })
    }
}

/// Markdown file for the share sheet (`MarkdownExport`, ADR-203). Built when shared.
struct MarkdownFileExport: Transferable {
    let records: [MemoryRecord]
    let lists: [DoddyList]
    let corrections: [MemoryCorrection]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText) { export in
            Data(MarkdownExport.markdown(export.records, lists: export.lists, corrections: export.corrections, exportedAt: Date()).utf8)
        }
        .suggestedFileName("doddy-memories.md")
    }
}

/// JSON export file for the share sheet (format: `MemoryExport.json`).
struct JSONExport: Transferable {
    let records: [MemoryRecord]
    /// List items (ADR-216); their lists are among `records`.
    let listItems: [ListItem]
    let corrections: [MemoryCorrection]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try MemoryExport.json(export.records, listItems: export.listItems, corrections: export.corrections, exportedAt: Date())
        }
        .suggestedFileName("doddy-memories.json")
    }
}
