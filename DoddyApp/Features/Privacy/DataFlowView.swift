import DoddyCore
import SwiftUI

/// Settings → Privacy → What leaves this iPhone. Rows come from DataFlow and the user's current
/// settings, so turning a switch on or off changes what this screen says.
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

    private var state: DataFlowState {
        let defaults = UserDefaults.standard
        return DataFlowState(
            rememberConversations: rememberConversations,
            shareProfileWithVoice: shareProfileWithVoice,
            tokenServerSet: !voiceTokenServer.trimmingCharacters(in: .whitespaces).isEmpty,
            connectionsOn: Set(VoiceConnection.allCases.filter { defaults.bool(forKey: $0.preferenceKey) }),
            pauseAll: pauseAll,
            // Same rule as OnlineAccountsClientFactory: an address and a session token.
            doddyServerSet: !connectedAppsServerURL.trimmingCharacters(in: .whitespaces).isEmpty
                && KeychainSessionStore.read() != nil,
            askDoddyOn: assistantConsent,
            askDoddyUsesNotes: assistantUseNotes,
            // Same rule as ServerConfig: the built-in address, or a valid one entered in Settings.
            messagingServerSet: ServerConfig.baseURL() != nil,
            pushOn: pushOn,
            memoryCopyOn: memoryCopyOn,
            morningCheckInOn: defaults.bool(forKey: MorningCheckInSettings.isOnKey),
            siriReadsNotes: siriReadsNotes,
            heyDoddyOn: heyDoddyOn,
            sharedLists: SharedListsController.shared.links.count,
            voiceProvider: VoiceProvider(stored: voiceProvider),
            learnedSharedWithVoice: defaults.bool(forKey: PreferenceKey.shareLearnedWithVoice))
    }

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
