import SwiftUI
import DoddyCore

struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    private var privacy: PrivacyDefaults { environment.privacy }

    var body: some View {
        NavigationStack {
            Form {
                Section("About this build") {
                    StatusRow(title: "Version", value: Self.versionText)
                    Text("Development build (milestone M0). DODDY is an AI assistant, not a person. The colours and character artwork are candidates awaiting owner approval, not a final brand.")
                }

                Section("Privacy") {
                    StatusRow(title: "Account required", value: privacy.accountRequired ? "Yes" : "No")
                    StatusRow(title: "Network requests", value: privacy.networkRequestsMade ? "Yes" : "None")
                    StatusRow(title: "Microphone", value: privacy.microphoneUsed ? "In use" : "Not used")
                    StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? "On" : "Off (not built)")
                    StatusRow(title: "Sync", value: privacy.syncEnabled ? "On" : "Off (not built)")
                    Text("This build has no networking, microphone or reminders code. Your appearance choices below are stored on this device only.")
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
        }
        .foregroundStyle(Theme.ink)
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
