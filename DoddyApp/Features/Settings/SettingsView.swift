import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(PreferenceKey.voiceAgentID) private var voiceAgentID = VoiceConfig.developmentAgentID
    @State private var confirmDeleteAll = false
    @State private var deleteError: String?
    @State private var editingProfile = false
    @State private var confirmForget = false
    @State private var forgetError: String?

    private var environment: AppEnvironment { store.environment }
    private var privacy: PrivacyDefaults { environment.privacy }

    var body: some View {
        NavigationStack {
            Form {
                Section("About this build") {
                    StatusRow(title: "Version", value: Self.versionText)
                    Text("Development build. DODDY is an AI assistant, not a person. The colours, voice and character artwork are candidates awaiting approval, not a final brand.")
                }

                Section("Getting started") {
                    StatusRow(title: "Double Back Tap", value: profiles.progress?.setupDecision.statusText ?? "Unavailable")
                    Button(profiles.progress?.setupFinished == true ? "Go through Back Tap setup again" : "Set up Double Back Tap") {
                        Task { await profiles.reopenSetup() }
                    }
                    .disabled(profiles.progress == nil)
                    .accessibilityIdentifier("settings.setup")
                    Text("Doddy can't read your Back Tap setting. This shows what you told it during setup.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
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
                    Button("Forget all of this", role: .destructive) { confirmForget = true }
                        .disabled(profiles.profile.isEmpty)
                        .accessibilityIdentifier("settings.forgetProfile")
                    if let forgetError {
                        Label(forgetError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                    Text("Stored on this iPhone with your memories, but separately: forgetting these doesn't delete memories, and deleting memories doesn't forget these. Voice conversations don't use them yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("settings.aboutYou")

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
                    Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation and any notes Doddy looks up are sent to ElevenLabs, which runs the voice agent. Nothing else is sent anywhere.")
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
