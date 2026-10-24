import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// Edit the approved profile. Cancel leaves it exactly as it was.
struct ProfileEditSheet: View {
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

/// Who runs Doddy's voice, and for OpenAI which model (ADR-265, ADR-442). Same notes, lists, tools
/// and cards either way; it takes effect when the next conversation starts, and Settings › What
/// leaves this iPhone follows it. Always in Settings › Voice; on Home only after the first
/// conversation (ADR-325, ADR-443), so a new user's Home keeps to Talk to Doddy.
struct VoiceProviderPicker: View {
    /// "home" or "settings", for the UI tests' identifiers.
    let idPrefix: String
    /// Empty until the user chooses; then ElevenLabs (ADR-546).
    @AppStorage(VoiceProvider.preferenceKey) private var voiceProvider = ""
    @AppStorage(OpenAIRealtimeModel.preferenceKey) private var realtimeModel = OpenAIRealtimeModel.default.rawValue

    var body: some View {
        let provider = VoiceProvider.effective(stored: voiceProvider, tokenServerSet: true)
        VStack(alignment: .leading, spacing: 6) {
            Picker("Voice", selection: Binding(get: { provider.rawValue }, set: { voiceProvider = $0 })) {
                ForEach(VoiceProvider.allCases) { option in
                    Text(verbatim: option.shortName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(idPrefix).voiceProvider")
            if provider == .openAIRealtime {
                Picker("OpenAI model", selection: $realtimeModel) {
                    ForEach(OpenAIRealtimeModel.allCases) { option in
                        Text(verbatim: option.shortName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("\(idPrefix).realtimeModel")
            }
            Text(verbatim: provider == .openAIRealtime
                ? "OpenAI Realtime \(OpenAIRealtimeModel(stored: realtimeModel).shortName) runs your next conversation, through the token server. Weather and Wikipedia don't work with it."
                : "ElevenLabs runs your next conversation.")
                .font(.caption2).foregroundStyle(Theme.secondaryText)
            // ADR-614: a Debug build's developer connection reaches ElevenLabs only, so OpenAI asks for
            // Sign in with Apple, which needs a paid Apple team (not `make project-iphone`).
            if provider == .openAIRealtime && VoiceConfig.directVoiceEnabled {
                Text(verbatim: "OpenAI needs your Doddy voice account: Sign in with Apple, which needs a paid Apple team. The developer connection only reaches ElevenLabs.")
                    .font(.caption2).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("\(idPrefix).openAINeedsAccount")
            }
        }
    }
}

/// Voice identity is optional until the first voice feature is used. The persistent session
/// restores in the background and sign-out revokes it on DODDY's server.
struct VoiceAccountSettings: View {
    @State private var session = VoiceAuthSession.shared
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(title: "Voice account", value: session.isSignedIn ? "Connected" : "Sign in when you first use voice")
                .accessibilityIdentifier("settings.voiceAccount")
            if session.isSignedIn {
                Button("Sign out of voice", role: .destructive) {
                    Task { await session.signOut() }
                }
                .accessibilityIdentifier("settings.voiceSignOut")
                Button("Ask again before sharing voice") {
                    VoiceProviderConsent.reset()
                }
                .accessibilityIdentifier("settings.resetVoiceConsent")
                Button("Delete Doddy voice account", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("settings.deleteVoiceAccount")
            }
            if let message = session.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityAddTraits(.updatesFrequently)
                if session.hasSavedSession {
                    Button("Retry") { Task { await session.restore() } }
                        .accessibilityIdentifier("settings.voiceRetry")
                }
            }
        }
        .task { await session.restore() }
        .confirmationDialog("Delete your Doddy voice account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete voice account", role: .destructive) { Task { await session.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This revokes all Doddy voice sessions on your devices. To remove Doddy from Sign in with Apple, also revoke it in your Apple ID settings.")
        }
    }
}
