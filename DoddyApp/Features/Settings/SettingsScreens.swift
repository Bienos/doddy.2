import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

// The screens Settings opens (ADR-580). Every control that was on the one long Settings form is
// on one of these, with the same preference key and accessibility identifier, so nothing a user
// set changes. Long explanations became one short line, or moved to "What leaves this iPhone",
// "Everything Doddy sends", Help and the Privacy Policy.

// MARK: Profile

/// Settings › My profile: the reviewed introduction answers (ADR-085).
struct AboutYouSettingsView: View {
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    @State private var editingProfile = false
    @State private var confirmForget = false
    @State private var forgetError: String?

    var body: some View {
        Form {
            Section {
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
            }
            Section {
                Toggle("Use in voice conversations", isOn: $shareProfileWithVoice)
                    .accessibilityIdentifier("settings.shareProfileWithVoice")
            } footer: {
                // At the point of decision: what turning it on sends, and where (ADR-580 rule 5).
                Text("On: these answers go to ElevenLabs, or OpenAI if you chose it, at the start of each conversation. Off: they stay on this iPhone.")
            }
            Section {
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
                Button("Forget all of this", role: .destructive) { confirmForget = true }
                    .disabled(profiles.profile.isEmpty)
                    .accessibilityIdentifier("settings.forgetProfile")
                    // On the row that opens it, so on iPad its popover points here (ADR-437).
                    .confirmationDialog(
                        "Forget your name and preferences?",
                        isPresented: $confirmForget, titleVisibility: .visible
                    ) {
                        Button("Forget", role: .destructive) { Task { await forgetProfile() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes what you told Doddy in the introduction from this iPhone. Your saved memories stay.")
                    }
                if let forgetError {
                    Label(forgetError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
            } footer: {
                Text("Kept on this iPhone, apart from your memories: forgetting these keeps your memories, and the other way round.")
            }
        }
        .settingsPage()
        .navigationTitle("My profile")
        .sheet(isPresented: $editingProfile) { ProfileEditSheet() }
        .coversDoddy(editingProfile)
    }

    private func forgetProfile() async {
        do {
            try await profiles.forget()
            forgetError = nil
        } catch {
            forgetError = ProfileErrorText.message(for: error)
        }
    }
}

/// Settings › Appearance.
struct AppearanceSettingsView: View {
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases, id: \.rawValue) { option in
                        Text(option.rawValue.capitalized).tag(option.rawValue)
                    }
                }
                Toggle("Hide character artwork", isOn: $hideCharacterArt)
            } footer: {
                Text("Text size follows your iPhone's settings. With Reduce Motion on, Doddy stays still.")
            }
        }
        .settingsPage()
        .navigationTitle("Appearance")
    }
}

// MARK: Voice and interaction

/// Settings › Voice: who runs Doddy's voice, starting on open, and the voice account.
struct VoiceSettingsView: View {
    @AppStorage(PreferenceKey.listenOnOpen) private var listenOnOpen = OpeningPreferences.listenOnOpenDefault
    #if DEBUG
    @AppStorage(VoiceConfig.directVoiceKey) private var directVoice = true
    #endif

    var body: some View {
        Form {
            Section {
                VoiceProviderPicker(idPrefix: "settings")
                Toggle(isOn: $listenOnOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-start voice")
                        Text("Start talking when Doddy opens.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityIdentifier("settings.listenOnOpen")
                #if DEBUG
                Toggle("Developer: talk without Apple sign-in", isOn: $directVoice)
                    .accessibilityIdentifier("settings.directVoice")
                #endif
            } footer: {
                Text("Your voice and the conversation go to the voice service only after you agree, the first time you talk. iOS shows its orange dot while Doddy listens.")
            }
            Section("Account") {
                VoiceAccountSettings()
                StatusRow(title: "Connection", value: connectionText)
                    .accessibilityIdentifier("settings.voiceConnection")
            }
        }
        .settingsPage()
        .navigationTitle("Voice")
    }

    private var connectionText: String {
        VoiceSessionKeychain.refreshToken() == nil
            ? NSLocalizedString("Sign in on first use", comment: "")
            : NSLocalizedString("Doddy voice account", comment: "")
    }
}

/// Settings › Siri and Back Tap: the ways to open Doddy that aren't the Action Button (ADR-558).
struct WaysSettingsView: View {
    @AppStorage(PreferenceKey.backTapAction) private var backTapActionRaw = BackTapAction.conversation.rawValue
    @AppStorage(PreferenceKey.siriReadsNotes) private var siriReadsNotes = true
    private var router: ShortcutRouter { .shared }

    private var backTapStatus: String {
        switch router.setup.phase {
        case .notStarted: NSLocalizedString("Not set up", comment: "")
        case .deferred: NSLocalizedString("Set up later", comment: "")
        case .userReportedTested(let at): "Tested by you · \(DateText.full(at))"
        case .guiding, .testing, .receiptReceived: NSLocalizedString("In progress", comment: "")
        }
    }

    var body: some View {
        Form {
            // Back Tap exists only on iPhone (ADR-337).
            if DeviceSupport.hasBackTap {
                Section {
                    StatusRow(title: "Double Back Tap", value: backTapStatus)
                        .accessibilityIdentifier("settings.backTap.status")
                    // The Back Tap guide, the Action Button, the controls and Siri (ADR-558).
                    Button("Ways to open Doddy") {
                        router.isSetupPresented = true
                    }
                    .accessibilityIdentifier("settings.backTap")
                    // One reminder a week for four weeks, until a way is in use (ADR-559).
                    Toggle("Remind me about ways to open Doddy", isOn: Binding(
                        get: { !router.setup.offer.remindersOff },
                        set: { on in
                            router.setup.setReminders(on: on)
                            Task { await OpenWaysReminderScheduler.refresh(router.setup) }
                        }))
                        .accessibilityIdentifier("settings.waysReminder")
                } footer: {
                    Text("Once a week for four weeks, only until you use one. Only if notifications are already on.")
                }
            }
            Section {
                // What Siri, the Shortcuts app and Back Tap's "Talk to Doddy" do. The Action Button's
                // control has its own choice in Settings (ADR-579).
                Picker("When Siri or Back Tap opens Doddy", selection: $backTapActionRaw) {
                    Text("Start a conversation").tag(BackTapAction.conversation.rawValue)
                    Text("Only open Doddy").tag(BackTapAction.openApp.rawValue)
                }
                .accessibilityIdentifier("settings.backTapAction")
                // ADR-248: "Ask Doddy what I saved".
                Toggle("Siri can read my notes aloud", isOn: $siriReadsNotes)
                    .accessibilityIdentifier("settings.siriReadsNotes")
            } footer: {
                Text("Say \"Ask Doddy what I saved\". Siri reads the matching note aloud, with your iPhone unlocked. Siri is Apple's and works under your Siri settings.")
            }
        }
        .settingsPage()
        .navigationTitle(DeviceSupport.hasBackTap ? Text("Siri and Back Tap") : Text("Siri"))
    }
}

// MARK: Memory and privacy

/// Settings › Memories: export, restore, delete, backups and imports (DOD-06).
struct MemoriesSettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.memoryCopyOn) private var memoryCopyOn = false
    @State private var confirmDeleteAll = false
    @State private var choosingRestoreFile = false
    @State private var restorePlan: MemoryRestorePlan?
    /// List items from the same file (ADR-216), put back after their lists.
    @State private var restoreItems: [ListItem] = []
    @State private var restoreMessage: String?
    @State private var restoreFailed = false
    @State private var deleteError: String?

    private var environment: AppEnvironment { store.environment }

    var body: some View {
        Form {
            Section {
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
                    // On the row that opens it, so on iPad its popover points here (ADR-437).
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
                if let restoreMessage {
                    Label(restoreMessage, systemImage: restoreFailed ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(restoreFailed ? Theme.error : Theme.confirmed)
                }
                Button("Delete all memories", role: .destructive) { confirmDeleteAll = true }
                    .disabled(!hasSavedAnything)
                    .accessibilityIdentifier("settings.deleteAll")
                    // On the row that opens it, so on iPad its popover points here (ADR-437).
                    .confirmationDialog(
                        deleteAllTitle,
                        isPresented: $confirmDeleteAll, titleVisibility: .visible
                    ) {
                        Button("Delete all", role: .destructive) { Task { await deleteAll() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        // The full consequences stay at the point of decision (ADR-580 rule 5).
                        Text("This removes every note, every list with its items, the search index and any unfinished notes from this iPhone and can't be undone. Lists you shared stop being shared, so the people you invited lose them too. With Memory on calls on, the copy on your Doddy messaging server is emptied. Exported files and older backups aren't affected. Everything Doddy learned from what you said, and the counts of what you corrected, are removed too. So are the notes and lists rows in What Doddy did.")
                    }
                if let deleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
            } footer: {
                Text(memoriesWhereText)
            }

            BackupSettingsSection()

            NoteImportSettingsSection()
        }
        .settingsPage()
        .navigationTitle("Memories")
        .fileImporter(isPresented: $choosingRestoreFile, allowedContentTypes: [.json]) { result in
            prepareRestore(result)
        }
        // Motion v2 (MV3): the file picker hides him in the frame it starts.
        .coversDoddy(choosingRestoreFile)
    }

    /// Where memories are, as switched on now (DOD-11): never "only on this iPhone" while a copy is
    /// on the messaging server or a list is shared through iCloud.
    private var memoriesWhereText: String {
        var text = NSLocalizedString("Kept in Doddy on this iPhone and in your iPhone backups. Photos and voice memos aren't in exports; an encrypted backup can include them. Deleting here doesn't remove files you exported or older backups.", comment: "")
        if memoryCopyOn {
            text += " " + NSLocalizedString("With Memory on calls on, a copy of your notes is also on your Doddy messaging server.", comment: "")
        }
        if SharedListsController.shared.links.count > 0 {
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

    /// Stops sharing the user's own shared lists first (their iCloud copy is deleted for everyone),
    /// then deletes on this iPhone, then empties the server copy if Memory on calls is on and
    /// waits for the server's answer. Whatever couldn't be undone outside this iPhone is said
    /// plainly, never covered by "deleted" (DOD-06/11).
    private func deleteAll() async {
        let stillShared = await SharedListsController.shared.stopAllOwnedShares()
        let stillSharedNames = stillShared.compactMap { store.list(id: $0)?.name }
        do {
            try await store.deleteAll()
            // Everything Doddy learned and the counts of corrections go with the notes (ADR-440).
            try await store.learning?.deleteAll()
            // Calls Doddy made for the user: cards, answers and transcripts on this iPhone (ADR-500).
            try await environment.callCaseRepository.deleteAll()
            // Tasks handed to Doddy (ADR-570): words and results kept on this iPhone.
            try await environment.errandRepository.deleteAll()
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
}

/// Settings › What Doddy knows: remembered conversations, suggested notes, what he learned.
struct KnowledgeSettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.rememberConversations) private var rememberConversations = true
    @AppStorage(PreferenceKey.suggestSavesAfterConversation) private var suggestSaves = true
    @AppStorage(PreferenceKey.learningOn) private var learningOn = false
    private var conversationLogs: ConversationLogStore { .shared }

    var body: some View {
        Form {
            Section {
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
                if let problem = conversationLogs.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
            } footer: {
                Text("When a conversation starts, Doddy gets your saved notes and, with this on, your last few conversations. They're kept only on this iPhone.")
            }
            Section {
                // ADR-247: "Worth keeping?" after a voice conversation.
                Toggle("Suggest notes after a conversation", isOn: $suggestSaves)
                    .accessibilityIdentifier("settings.suggestSaves")
                if let learning = store.learning, learning.isAvailable {
                    // ADR-440: facts and routines Doddy kept, each confirmed by the user.
                    NavigationLink {
                        LearnedView(learning: learning)
                    } label: {
                        StatusRow(
                            title: "What I've learned",
                            value: learningOn
                                ? "On · \(learning.confirmedFacts.count + learning.confirmedProcedures.count)"
                                : "Off")
                    }
                    .accessibilityIdentifier("settings.learned")
                }
            } footer: {
                Text("Up to three things you said, offered when a conversation ends. Nothing is saved unless you tap Save.")
            }
        }
        .settingsPage()
        .navigationTitle("What Doddy knows")
    }
}

/// Settings › Privacy: the lock, iPhone search, widgets, what leaves this iPhone and the status
/// as switched on right now.
struct PrivacySettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.listenOnOpen) private var listenOnOpen = OpeningPreferences.listenOnOpenDefault
    @AppStorage(PreferenceKey.widgetsShowContent) private var widgetsOn = true
    @AppStorage(PreferenceKey.memoryCopyOn) private var memoryCopyOn = false

    private var privacy: PrivacyDefaults { store.environment.privacy }

    /// The privacy summary that used to be at the bottom of Home (ADR-326).
    private var privacySummary: String {
        memoryCopyOn
            ? NSLocalizedString("Doddy is an AI, not a person. Notes are kept on this iPhone, and because Memory on calls is on, a copy is on your Doddy messaging server so Doddy can answer on calls. While a conversation is open, notes and your last few conversations go to ElevenLabs, or OpenAI if you switch Home's voice to it so Doddy knows them. Typed questions go to Doddy's server and OpenAI only if you turn on Ask Doddy in Settings. Calendar, reminders and contacts stay off until you turn them on in Settings, and Today reads them on this iPhone only; Google Calendar reading is in Settings › Connected Apps.", comment: "")
            : NSLocalizedString("Doddy is an AI, not a person. Notes stay on this iPhone; while a conversation is open they and your last few conversations go to ElevenLabs, or OpenAI if you switch Home's voice to it so Doddy knows them. Typed questions go to Doddy's server and OpenAI only if you turn on Ask Doddy in Settings. Calendar, reminders and contacts stay off until you turn them on in Settings, and Today reads them on this iPhone only; Google Calendar reading is in Settings › Connected Apps.", comment: "")
    }

    var body: some View {
        Form {
            Section {
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
                NavigationLink {
                    PrivacyDetailsView()
                } label: {
                    Label("Everything Doddy sends, in one page", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("settings.privacyDetails")
                Link(destination: LegalDocuments.url(.privacy, languageCode: SettingsView.languageCode)) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            } footer: {
                Text(privacySummary)
                    .accessibilityIdentifier("settings.privacySummary")
            }
            Section("Right now") {
                StatusRow(title: "Voice sign-in", value: "Optional for notes; required for voice")
                // From the same rows as What leaves this iPhone, for the settings right now (ADR-447).
                StatusRow(title: "Network", value: privacy.networkRequestsMade ? DataFlow.networkSummary(.current()) : "None")
                StatusRow(
                    title: "Microphone",
                    value: !privacy.microphoneUsed ? "Not used"
                        : listenOnOpen ? "Only while talking. A conversation starts when you open Doddy; turn that off under Voice"
                        : "Only while talking")
                StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? DataFlow.cloudAISummary(.current()) : "Off (not built)")
                StatusRow(title: "Sync", value: privacy.syncText)
            }
            .accessibilityIdentifier("settings.privacy")
            // Widgets (ADR-219): what they show, and the switch that empties the shared file.
            Section {
                if WidgetSync.shared.isAvailable {
                    Toggle("Show notes and lists in widgets", isOn: $widgetsOn)
                        .accessibilityIdentifier("settings.widgetsOn")
                    if let problem = WidgetSync.shared.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    }
                }
            } header: {
                Text("Widgets")
            } footer: {
                Text(!WidgetSync.shared.isAvailable
                     ? "This build can't share anything with widgets, so they show only \"Open Doddy\"."
                     : widgetsOn
                     ? "On the Lock Screen, iOS hides the text until you unlock."
                     : "Widgets show nothing of yours.")
            }
            WatchSettingsSection()
        }
        .settingsPage()
        .navigationTitle("Privacy")
    }
}

/// The long privacy paragraph Settings used to show, on its own page (ADR-580): kept word for
/// word so nothing it said is lost; `DataFlowView` restates it row by row, so change both
/// together, and the Privacy Policy on the website is the full version.
struct PrivacyDetailsView: View {
    var body: some View {
        ScrollView {
            Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation, your saved notes (except ones you mark Private), your list names (a list's items only when Doddy reads or changes it), your personality settings, and (if switched on) your last few conversations and your introduction answers are sent to ElevenLabs, or OpenAI if you switch Home's voice to it, which runs the voice agent. Calendar entries, contact names and birthdays (day and month) or message drafts Doddy uses in a conversation go too. When you ask for weather or facts with ElevenLabs as the voice, it looks them up for Doddy: the place name and coordinates go to Open-Meteo, and search words go to Wikipedia; this app makes no such requests itself. ElevenLabs keeps a recording and transcript of each conversation it runs; how long OpenAI keeps the audio and transcript isn't verified in this build. When you sign in with Apple, its identity token is sent to Doddy’s server for verification. Voice requests use a short-lived Doddy session credential; this server does not receive your voice, transcripts, notes or profile details for token requests. If you use Connected Apps or switch on an online-account tool, the app sends what you ask (a date, a search word, or the text of a draft, reply or task you confirm) to your Doddy server, which talks to Google, Microsoft (Outlook), Notion or Todoist through Composio, and the results come back to the app and, during a conversation, to ElevenLabs, or OpenAI if you switch Home's voice to it so Doddy can answer; your saved notes are never sent to that server. If you ask Siri \u{201C}Ask Doddy what I saved\u{201D} (it can be turned off below), Doddy searches on this iPhone and hands the matching note to Siri, Apple's assistant, to read aloud; Siri handles what you say and the answer under your Siri settings. If you switch on web search, your search words go the same way to your Doddy server, which looks them up through Monid (a paid search service Doddy's server uses; you don't sign in to it). If you turn on Ask Doddy, typed questions (and, if you allow it, saved notes that match them) go to the Ask Doddy gateway, a separate server, which passes them to OpenAI. If a Doddy messaging server is set and you turn on notifications, texts, phone calls or daily news, it gets an anonymous account token, this iPhone's notification token, your phone number once you confirm it with a code, and the news topics you pick; it sends through Apple and Twilio, runs calls on ElevenLabs, and writes the news with an AI (Anthropic or OpenAI, as the server is set up; Daily news names which) and GNews. Your saved notes go there only if you turn on \u{201C}Let Doddy use my memories on calls\u{201D}. If you search for a place for a reminder, the words you type (and roughly where you are, if Doddy already knows) go to Apple Maps; the place you pick stays on this iPhone, and iOS, not Doddy, notices when you get there. In translator mode the other person's voice goes to ElevenLabs, or OpenAI if you switch Home's voice to it too (listen only hears whoever is near you); started from Translate on Home, your notes, conversations and profile aren't sent, and nothing of it is kept on this iPhone unless you tap Copy or Save within 5 minutes. If you share a list, its name and items go to your iCloud (Apple) and to the people you invite, and their changes come back; a list reminder's place goes there too only if you tap Share this place. If you ask Doddy to convert money, the app downloads the European Central Bank's public exchange-rate file; nothing about you is sent with it. If you switch on Read an email or Read a Notion page, the one email (sender, subject and its text) or page (title and text) you ask about, cut short, comes from your Doddy server and goes to ElevenLabs, or OpenAI if you switch Home's voice to it during that conversation. Text you share to Doddy from another app, to-dos found in a voice memo and your Focus settings stay on this iPhone; the parking widget shows when you parked and your note, never where. If you ask Doddy to remind you when to leave, where your iPhone is and the place you're going go to Apple Maps once, to work out the travel time; neither is kept. If you turn on Show notes in iPhone search, your notes and lists (never private ones) are indexed by iOS on this iPhone. Nothing else is sent anywhere.")
                .font(.callout)
                .padding(20)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle("Everything Doddy sends")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Connected apps

/// Settings › Ask Doddy (typed questions), a private-beta feature (ADR-113).
struct AskDoddySettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var assistantUseNotes = true
    @AppStorage(PreferenceKey.gatewayAddress) private var gatewayAddress = ""
    @State private var showAssistantConsent = false
    @State private var inviteDraft = ""
    @State private var hasInviteCode = false
    @State private var inviteError: String?

    private var environment: AppEnvironment { store.environment }
    private static let assistantUnavailable = "Ask Doddy isn't available while Doddy's storage can't be opened."

    var body: some View {
        Form {
            Section {
                Toggle("Turn on Ask Doddy", isOn: Binding(
                    get: { assistantConsent },
                    set: { wanted in
                        if wanted { showAssistantConsent = true } else { assistantConsent = false }
                    }))
                    .accessibilityIdentifier("settings.assistantConsent")
                    // On the row that opens it, so on iPad its popover points here (ADR-437).
                    .confirmationDialog(
                        "Turn on Ask Doddy?",
                        isPresented: $showAssistantConsent, titleVisibility: .visible
                    ) {
                        Button("Turn on") { assistantConsent = true }
                        Button("Not now", role: .cancel) {}
                    } message: {
                        Text("When you ask a question, it is sent with your last few messages to Doddy's server, which passes it to OpenAI to write the answer. If \"Use relevant saved notes\" is on, notes that match your question are sent too, and the answer shows which ones. Doddy's server does not store them and logs no text. We ask OpenAI not to keep the reply, but we can't verify that. Voice conversations are separate. You can turn this off at any time.")
                    }
                Toggle("Use relevant saved notes", isOn: $assistantUseNotes)
                    .disabled(!assistantConsent)
                    .accessibilityIdentifier("settings.assistantUseNotes")
                StatusRow(title: "Status", value: assistantStatus)
                    .accessibilityIdentifier("settings.assistantStatus")
            } footer: {
                Text("Private beta. Typed questions go to Doddy's server and OpenAI only while this is on.")
            }
            Section("Access") {
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
            }
        }
        .settingsPage()
        .navigationTitle("Ask Doddy")
        .task { await refreshInviteState() }
    }

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
}

// MARK: Notifications

/// Settings › Check-ins and reminders: the morning, evening and weekly routines and note reminders.
struct RoutinesSettingsView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        Form {
            MorningCheckInSettingsSection()
            EveningWrapUpSettingsSection()
            WeeklyLookBackSettingsSection()
            TidyUpSettingsSection()
            if store.environment.capabilities.isAvailable(.noteReminders) {
                NoteReminderSettingsSection()
            }
        }
        .settingsPage()
        .navigationTitle("Check-ins and reminders")
    }
}

// MARK: About

/// Settings › Advanced: build details, what's built, and the development server. The server
/// fields show only in Debug builds, or when one is already set, so it can still be removed.
struct AdvancedSettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var connectedAppsServerURL = ""
    @State private var sessionTokenDraft = ""
    @State private var hasSessionToken = KeychainSessionStore.hasToken
    @State private var tokenMessage: String?

    private var showsDeveloperServer: Bool {
        #if DEBUG
        return true
        #else
        return !connectedAppsServerURL.isEmpty || hasSessionToken
        #endif
    }

    var body: some View {
        Form {
            Section("About this build") {
                StatusRow(title: "Version", value: SettingsView.versionText)
                Text("Development build. Physical-device and release checks are still outstanding.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Section("What's built") {
                ForEach(Capability.allCases, id: \.self) { capability in
                    StatusRow(
                        title: capability.displayName,
                        value: StatusCopy.text(for: store.environment.capabilities.status(of: capability)))
                }
            }
            .accessibilityIdentifier("settings.capabilities")
            if showsDeveloperServer { developerServer }
        }
        .settingsPage()
        .navigationTitle("Advanced")
    }

    private var developerServer: some View {
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
            Text("Use https, or http://localhost with the Simulator. The token is kept in this iPhone's Keychain for that address only.")
        }
    }
}

extension View {
    /// A Settings page: the canvas behind the form and an inline title (set with
    /// `.navigationTitle("…")` next to it, so the string catalog finds the title).
    func settingsPage() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
    }
}
