import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var connectedAppsServerURL = ""
    @State private var sessionTokenDraft = ""
    @State private var hasSessionToken = KeychainSessionStore.read() != nil
    @State private var tokenMessage: String?
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
                    StatusRow(title: "Network", value: privacy.networkRequestsMade ? "While talking (ElevenLabs) and when you use Connected Apps" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "Only while talking" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "ElevenLabs, only while talking" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation and any notes Doddy looks up are sent to ElevenLabs, which runs the voice agent. If you use Connected Apps, the app sends the date and time zone you ask about to your Doddy server, which reads Google Calendar through Composio; your notes are never sent there. Nothing else is sent anywhere.")
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
