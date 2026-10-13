import DoddyCore
import SwiftUI

/// Settings → Privacy → What leaves this iPhone. Rows come from DataFlow and the user's current
/// settings, so turning a switch on or off changes what this screen says.
extension DataFlowState {
    /// The user's settings right now, for What leaves this iPhone and Settings → Privacy. Unset
    /// switches read as their @AppStorage defaults (some start on), not as off.
    @MainActor
    static func current(_ defaults: UserDefaults = .standard) -> DataFlowState {
        func flag(_ key: String, default value: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? value }
        func text(_ key: String) -> String { (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces) }
        return DataFlowState(
            rememberConversations: flag(PreferenceKey.rememberConversations, default: true),
            shareProfileWithVoice: flag(PreferenceKey.shareProfileWithVoice, default: false),
            tokenServerSet: !text(PreferenceKey.voiceTokenServer).isEmpty,
            connectionsOn: Set(VoiceConnection.allCases.filter { defaults.bool(forKey: $0.preferenceKey) }),
            pauseAll: flag(ConnectionPause.preferenceKey, default: false),
            // Same rule as OnlineAccountsClientFactory: an address and a session token.
            doddyServerSet: !text(PreferenceKey.connectedAppsServerURL).isEmpty && KeychainSessionStore.read() != nil,
            askDoddyOn: flag(PreferenceKey.assistantConsent, default: false),
            askDoddyUsesNotes: flag(PreferenceKey.assistantUseNotes, default: true),
            // Same rule as ServerConfig: the built-in address, or a valid one entered in Settings.
            messagingServerSet: ServerConfig.baseURL(defaults: defaults) != nil,
            pushOn: flag(PreferenceKey.pushUpdatesOn, default: false),
            memoryCopyOn: flag(PreferenceKey.memoryCopyOn, default: false),
            morningCheckInOn: defaults.bool(forKey: MorningCheckInSettings.isOnKey),
            siriReadsNotes: flag(PreferenceKey.siriReadsNotes, default: true),
            heyDoddyOn: flag(PreferenceKey.heyDoddyOn, default: false),
            sharedLists: SharedListsController.shared.links.count,
            voiceProvider: VoiceProvider(stored: defaults.string(forKey: VoiceProvider.preferenceKey)),
            learnedSharedWithVoice: defaults.bool(forKey: PreferenceKey.shareLearnedWithVoice))
    }
}

struct DataFlowView: View {
    @AppStorage(PreferenceKey.rememberConversations) private var rememberConversations = true
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false
    @AppStorage(PreferenceKey.voiceTokenServer) private var voiceTokenServer = ""
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var connectedAppsServerURL = ""
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = false
    @AppStorage(PreferenceKey.assistantUseNotes) private var assistantUseNotes = true
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAll = false
    @AppStorage(PreferenceKey.messagingServerURL) private var messagingServerURL = ""
    @AppStorage(PreferenceKey.pushUpdatesOn) private var pushOn = false
    @AppStorage(PreferenceKey.memoryCopyOn) private var memoryCopyOn = false
    @AppStorage(PreferenceKey.siriReadsNotes) private var siriReadsNotes = true
    @AppStorage(PreferenceKey.heyDoddyOn) private var heyDoddyOn = false
    @AppStorage(VoiceProvider.preferenceKey) private var voiceProvider = VoiceProvider.elevenLabs.rawValue

    /// The @AppStorage values above redraw this screen when a switch changes; the state itself is
    /// read by `DataFlowState.current()`, which Settings' Privacy rows use too (ADR-447).
    private var state: DataFlowState { .current() }

    var body: some View {
        let rows = DataFlow.rows(state)
        List {
            Section {
                Text("Where your information goes, based on your settings right now. Nothing is sold, and there are no ads or analytics.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Section("Sent, with your current settings") {
                ForEach(rows.filter(\.isActive)) { row in
                    flowRow(row)
                }
            }
            let off = rows.filter { !$0.isActive }
            if !off.isEmpty {
                Section("Not sent right now") {
                    ForEach(off) { row in
                        flowRow(row)
                    }
                }
            }
            Section("Stays on this iPhone") {
                ForEach(DataFlow.staysOnPhone(state), id: \.self) { line in
                    Label(line, systemImage: "iphone")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("What leaves this iPhone")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func flowRow(_ row: DataFlowRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.destination).font(.body.weight(.semibold))
            if row.isActive {
                Text(row.what).font(.subheadline)
                Text(row.when).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let note = row.note {
                Text(note).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dataFlow.\(row.id)")
    }
}
