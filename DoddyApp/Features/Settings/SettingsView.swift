import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.rememberConversations) private var rememberConversations = true
    @State private var connections = ConnectionController()
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    @AppStorage(PreferenceKey.voiceTokenServer) private var voiceTokenServer = ""
    @State private var accessCodeDraft = ""
    @State private var hasAccessCode = VoiceAccessCodeStore.read() != nil
    @State private var accessCodeError: String?
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var connectedAppsServerURL = ""
    @State private var sessionTokenDraft = ""
    @State private var hasSessionToken = KeychainSessionStore.read() != nil
    @State private var tokenMessage: String?
    @State private var confirmDeleteAll = false
    @State private var deleteError: String?
    @State private var editingProfile = false
    @State private var confirmForget = false
    @State private var forgetError: String?

    private var environment: AppEnvironment { store.environment }
    private var privacy: PrivacyDefaults { environment.privacy }
    private var router: ShortcutRouter { .shared }
    private var conversationLogs: ConversationLogStore { .shared }

    private var backTapStatus: String {
        switch router.setup.phase {
        case .notStarted: "Not set up"
        case .deferred: "Set up later"
        case .userReportedTested(let at): "Tested by you · \(DateText.full(at))"
        case .shortcutPreparation, .guiding, .testing, .receiptReceived: "In progress"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About this build") {
                    StatusRow(title: "Version", value: Self.versionText)
                    Text("Development build. DODDY is an AI assistant, not a person. The colours, voice and character artwork are candidates awaiting approval, not a final brand.")
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
                    Text("Stored on this iPhone with your memories, but separately: forgetting these doesn't delete memories, and deleting memories doesn't forget these. With \"Use in voice conversations\" on, these answers are sent to ElevenLabs at the start of each conversation so Doddy knows them; off, they stay on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("Your memories") {
                    StatusRow(title: "Saved on this iPhone", value: "\(store.memories.count)")
                    ShareLink(
                        item: JSONExport(records: store.memories),
                        preview: SharePreview("Doddy memories (JSON)")
                    ) {
                        Label("Export as JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.memories.isEmpty)
                    ShareLink(
                        item: MemoryExport.plainText(store.memories, exportedAt: .now),
                        preview: SharePreview("Doddy memories (text)")
                    ) {
                        Label("Export as text", systemImage: "doc.plaintext")
                    }
                    .disabled(store.memories.isEmpty)
                    Button("Delete all memories", role: .destructive) { confirmDeleteAll = true }
                        .disabled(store.memories.isEmpty)
                        .accessibilityIdentifier("settings.deleteAll")
                    if let deleteError {
                        Label(deleteError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    Text("Memories live only in this app on this iPhone, protected by iOS Data Protection. Like other app data they are included in your iPhone backups. Deleting here does not remove files you exported or older backups.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("Privacy") {
                    StatusRow(title: "Account required", value: privacy.accountRequired ? "Yes" : "No")
                    StatusRow(title: "Network", value: privacy.networkRequestsMade ? "While talking (ElevenLabs, token server) and when you use Connected Apps" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "Only while talking" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "ElevenLabs, only while talking" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation, your saved notes, your personality settings, and (if switched on) your last few conversations and your introduction answers are sent to ElevenLabs, which runs the voice agent. Calendar entries, contact names or message drafts Doddy uses in a conversation go too. When you ask for weather or facts, ElevenLabs looks them up for Doddy: the place name and coordinates go to Open-Meteo, and search words go to Wikipedia; this app makes no such requests itself. ElevenLabs keeps a recording and transcript of each conversation. If a token server is set, starting a conversation also sends your access code to it. If you use Connected Apps, the app sends the date and time zone you ask about to your Doddy server, which reads Google Calendar through Composio; your notes are never sent there. Nothing else is sent anywhere.")
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
                            if KeychainSessionStore.save(token) {
                                hasSessionToken = true
                                tokenMessage = nil
                            } else {
                                tokenMessage = "The Keychain didn't accept the token, so it wasn't saved."
                            }
                            sessionTokenDraft = ""
                        }
                        .disabled(sessionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let tokenMessage {
                        Label(tokenMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    }
                } header: {
                    Text("Connected Apps server (development)")
                } footer: {
                    Text("Development setting. Use https, or http://localhost with the Simulator. The token comes from the server owner and is stored only in this iPhone's Keychain.")
                }

                Section("What Doddy knows") {
                    Toggle("Remember recent conversations", isOn: $rememberConversations)
                        .accessibilityIdentifier("settings.rememberConversations")
                    StatusRow(title: "Remembered conversations", value: "\(conversationLogs.logs.count) of the last \(ConversationLogStore.maxLogs)")
                    Button("Forget remembered conversations", role: .destructive) { conversationLogs.clear() }
                        .disabled(conversationLogs.logs.isEmpty)
                    if let problem = conversationLogs.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    Text("When a conversation starts, the app hands Doddy your saved notes and, if this is on, your last few conversations, so he can carry on where you left off. They are kept only on this iPhone. Weather comes from Open-Meteo and facts from Wikipedia.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("Voice") {
                    PersonalityLinkRow()
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

                Section("Back Tap and Siri") {
                    StatusRow(title: "Double Back Tap", value: backTapStatus)
                    Button(router.setup.coordinator.isDone ? "Go through the setup again" : "Set up Double Back Tap") {
                        router.isSetupPresented = true
                    }
                    .accessibilityIdentifier("settings.backTap")
                    Text("\"Talk to Doddy\" is built in as a shortcut for Siri, the Shortcuts app and the Action Button. Back Tap is chosen by you in iOS Settings; Doddy can't set it and can't see what it's set to.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section {
                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        StatusRow(title: "Calendar, reminders, contacts", value: connectionSummary)
                    }
                    .accessibilityIdentifier("settings.connections")
                    // Connections uses its own controller; re-read when coming back from it.
                    .onAppear { Task { await connections.refresh() } }
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Each one starts off. Turning one on asks iPhone for permission first.")
                }

                Section("Appearance and accessibility") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases, id: \.rawValue) { option in
                            Text(option.rawValue.capitalized).tag(option.rawValue)
                        }
                    }
                    Toggle("Hide character artwork", isOn: $hideCharacterArt)
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
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete all \(store.memories.count) memories?",
                isPresented: $confirmDeleteAll, titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { Task { await deleteAll() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every memory and its search index from this iPhone and can't be undone. Exported files and older backups aren't affected.")
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

    private var connectionSummary: String {
        let on = VoiceConnection.allCases.filter { connections.state(of: $0) == .on }.count
        return on == 0 ? "All off" : "\(on) of \(VoiceConnection.allCases.count) on"
    }

    private var connectionText: String {
        switch VoiceConnectionMode.resolve(
            serverAddress: voiceTokenServer, accessCode: hasAccessCode ? VoiceAccessCodeStore.read() : nil,
            publicAgentID: voiceAgentID) {
        case .tokenServer: "Private (token server)"
        case .publicAgent: "Development (public agent)"
        case .notSetUp: "Not set up"
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

    private func deleteAll() async {
        do {
            try await store.deleteAll()
            deleteError = nil
        } catch {
            deleteError = UserFacingError.message(for: error)
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

/// JSON export file for the share sheet (format: `MemoryExport.json`).
struct JSONExport: Transferable {
    let records: [MemoryRecord]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try MemoryExport.json(export.records, exportedAt: Date())
        }
        .suggestedFileName("doddy-memories.json")
    }
}
