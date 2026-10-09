import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.rememberConversations) private var rememberConversations = true
    @State private var confirmDeleteAll = false
    @State private var deleteError: String?

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
                    StatusRow(title: "Network", value: privacy.networkRequestsMade ? "Only while talking (ElevenLabs)" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "Only while talking" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "ElevenLabs, only while talking" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation, your saved notes and (if switched on) your last few conversations are sent to ElevenLabs, which runs the voice agent. Weather and Wikipedia lookups are made by ElevenLabs\u{2019} servers, not by this app. ElevenLabs keeps a recording and transcript of each conversation. Nothing else is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("settings.privacy")

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
                    TextField("ElevenLabs agent ID", text: $voiceAgentID)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.voiceAgentID")
                    if voiceAgentID != VoiceConfig.developmentAgentID {
                        Button("Use the development agent") { voiceAgentID = VoiceConfig.developmentAgentID }
                    }
                    Text("Development prototype: Doddy's voice runs on an ElevenLabs agent. Conversations count toward the owner's ElevenLabs minutes.")
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
        }
        .foregroundStyle(Theme.ink)
    }

    private func deleteAll() async {
        do {
            try await store.deleteAll()
            deleteError = nil
        } catch {
            deleteError = UserFacingError.message(for: error)
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
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
