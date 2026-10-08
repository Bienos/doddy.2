import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @AppStorage(CloudAIConsent.storageKey) private var consentVersion = 0
    @State private var showConsentNotice = false
    @State private var confirmDeleteAll = false
    @State private var deleteError: String?

    private var environment: AppEnvironment { store.environment }
    private var cloudAIConsented: Bool { CloudAIConsent.isGranted(consentVersion) }
    private var privacy: PrivacyDefaults {
        cloudAIConsented ? .m2(cloudAIConsented: true) : environment.privacy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About this build") {
                    StatusRow(title: "Version", value: Self.versionText)
                    Text("Development build. DODDY is an AI assistant, not a person. The colours and character artwork are candidates awaiting approval, not a final brand.")
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

                Section("Cloud AI (preview)") {
                    Toggle("Let Doddy answer questions", isOn: Binding(
                        get: { cloudAIConsented },
                        set: { newValue in
                            if newValue { showConsentNotice = true } else { consentVersion = 0 }
                        }))
                        .accessibilityIdentifier("settings.cloudAI")
                    Text("Off by default. When on, a question you ask — plus up to 3 matching saved notes — is sent over the internet to Doddy's server and on to OpenAI to write the answer. Nothing is sent unless you ask. Untested on a physical iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("Privacy") {
                    StatusRow(title: "Account required", value: privacy.accountRequired ? "Yes" : "No")
                    StatusRow(title: "Network requests", value: privacy.networkRequestsMade ? "Yes, when you ask Doddy" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "In use" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "On (preview)" : "Off")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text(privacy.cloudAIEnabled
                         ? "Cloud AI preview is on: only the question you ask and up to 3 matching saved notes leave this iPhone, and only when you ask. The rest of your memories stay here. There is no microphone or reminders code."
                         : "Until you turn on the Cloud AI preview, this app makes no network requests. Nothing you save leaves this iPhone unless you export it. There is no microphone or reminders code.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityIdentifier("settings.privacy")

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
            .sheet(isPresented: $showConsentNotice) {
                CloudAIConsentSheet(
                    onAccept: { consentVersion = CloudAIConsent.noticeVersion; showConsentNotice = false },
                    onDecline: { showConsentNotice = false })
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
