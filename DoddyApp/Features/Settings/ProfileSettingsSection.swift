import DoddyCore
import SwiftUI

/// Profile settings and its editor. The user-approved profile stays separate from saved memories.
struct ProfileSettingsSection: View {
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    @State private var editingProfile = false
    @State private var confirmForget = false
    @State private var forgetError: String?

    var body: some View {
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
            Text("Stored on this iPhone with your memories, but separately: forgetting these doesn't delete memories, and deleting memories doesn't forget these. With \"Use in voice conversations\" on, these answers are sent to OpenAI, or ElevenLabs if you switch Home's voice to it at the start of each conversation so Doddy knows them; off, they stay on this iPhone.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $editingProfile) { ProfileEditSheet() }
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
