import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var assistantUseNotes = true
    @AppStorage(PreferenceKey.gatewayAddress) private var gatewayAddress = ""
    @State private var showAssistantConsent = false
    @State private var inviteDraft = ""
    @State private var hasInviteCode = false
    @State private var inviteError: String?
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
                    StatusRow(title: "Network", value: privacy.networkRequestsMade ? "Only while talking or asking" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "Only while talking" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "ElevenLabs (voice); OpenAI if Ask Doddy is on" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation and any notes Doddy looks up are sent to ElevenLabs, which runs the voice agent. If you turn on Ask Doddy, typed questions go to Doddy's server and on to OpenAI. Nothing else is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("settings.privacy")

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
                "Turn on Ask Doddy?",
                isPresented: $showAssistantConsent, titleVisibility: .visible
            ) {
                Button("Turn on") { assistantConsent = true }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("When you ask a question, it is sent with your last few messages to Doddy's server, which passes it to OpenAI to write the answer. If \"Use relevant saved notes\" is on, notes that match your question are sent too, and the answer shows which ones. Doddy's server does not store them and logs no text. We ask OpenAI not to keep the reply, but we can't verify that. Voice conversations are separate. You can turn this off at any time.")
            }
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

    private var assistantStatus: String {
        if !assistantConsent { return "Off" }
        if GatewayConfiguration(string: gatewayAddress) == nil { return "Needs a gateway address" }
        if !hasInviteCode { return "Needs an invite code" }
        return "Ready (not yet tested with a real server)"
    }

    private func refreshInviteState() async {
        guard let credentials = environment.assistant?.credentials else { return }
        hasInviteCode = ((try? await credentials.inviteCode()) ?? nil) != nil
    }

    private func saveInviteCode() async {
        guard let credentials = environment.assistant?.credentials else { return }
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
        guard let credentials = environment.assistant?.credentials else { return }
        do {
            try await credentials.setInviteCode(nil)
            try await credentials.setToken(nil)
            inviteError = nil
            hasInviteCode = false
        } catch {
            inviteError = "Couldn't remove the invite code."
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
