import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.voiceTokenServer) private var voiceTokenServer = ""
    @State private var accessCodeDraft = ""
    @State private var hasAccessCode = VoiceAccessCodeStore.read() != nil
    @State private var accessCodeError: String?
    @AppStorage(PreferenceKey.backTapTestedAt) private var backTapTestedAt = 0.0
    @State private var connections = ConnectionController()
    @State private var confirmDeleteAll = false
    @State private var deleteError: String?

    private var environment: AppEnvironment { store.environment }
    private var privacy: PrivacyDefaults { environment.privacy }

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
                    StatusRow(title: "Network", value: privacy.networkRequestsMade ? "Only while talking (ElevenLabs, token server)" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "Only while talking" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "ElevenLabs, only while talking" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation, and any notes, calendar entries, contact names or message drafts Doddy uses are sent to ElevenLabs, which runs the voice agent. When you ask for weather or facts, ElevenLabs looks them up for Doddy: the place name and coordinates go to Open-Meteo, and search words go to Wikipedia. If a token server is set, starting a conversation also sends your access code to it. Nothing else is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("settings.privacy")

                Section("Voice") {
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

                Section("Quick access") {
                    NavigationLink {
                        QuickAccessSetupView()
                    } label: {
                        Label("Set up Double Back Tap", systemImage: "hand.tap")
                    }
                    .accessibilityIdentifier("settings.quickAccess")
                    StatusRow(
                        title: "Double Back Tap",
                        value: QuickAccessStatus.backTap(testedAt: backTapTestedAt > 0 ? Date(timeIntervalSince1970: backTapTestedAt) : nil))
                    Text("Siri and Shortcuts: “Talk to Doddy”, “Save to Doddy” and “Ask Doddy”. Save and Ask work without opening the app and use only notes on this iPhone. When you use Siri, Apple handles your request and the reply it reads out. Doddy can't see or change your Back Tap, Action Button or Control Center settings.")
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
        }
        .foregroundStyle(Theme.ink)
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

    private var connectionSummary: String {
        let on = VoiceConnection.allCases.filter { connections.state(of: $0) == .on }.count
        return on == 0 ? "All off" : "\(on) of \(VoiceConnection.allCases.count) on"
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
