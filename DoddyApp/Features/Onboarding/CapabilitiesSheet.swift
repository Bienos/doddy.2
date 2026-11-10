import DoddyCore
import SwiftUI

/// Home › ••• › What I can do (decision 2026-11-09-what-i-can-do): a scene for each feature this build shows
/// (`AbilityCarousel`, decision 2026-11-09-what-i-can-do-scenes), the opening paragraph, then the same features
/// as rows, in plain words, with an honest status worked out in DoddyCore (`WhatICanDo`). A row opens its
/// feature where there is one: calls inside this sheet, the rest from Home through `open` once the sheet has gone.
struct CapabilitiesSheet: View {
    /// Opens a feature that lives on Home (Messages, Tasks, leaflets, notes and lists) after this sheet closes.
    var open: ((DoddyAbility) -> Void)? = nil

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    private var language: NotificationLanguage { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) }

    private var rows: [AbilityRow] {
        WhatICanDo.rows(catalog: environment.capabilities, scope: ReleaseScopeStore.current,
                        serverConfigured: ServerConfig.baseURL() != nil, language: language)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AbilityCarousel(rows: rows, language: language)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    Text(CapabilityIntroduction.text(for: environment.capabilities, language: language))
                        .accessibilityIdentifier("capabilities.introduction")
                }
                Section("What's built") {
                    ForEach(rows) { row in
                        abilityRow(row)
                    }
                }
                // What leaves this iPhone left Home's menu on 9 Nov 2026; the paragraph above points to it, and so does this.
                Section {
                    NavigationLink {
                        DataFlowView()
                    } label: {
                        Label("What leaves this iPhone", systemImage: "lock.shield")
                    }
                    .accessibilityIdentifier("capabilities.dataFlow")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("What I can do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func abilityRow(_ row: AbilityRow) -> some View {
        let id = "capabilities.row.\(row.ability.rawValue)"
        switch row.ability {
        case .phoneCalls:
            NavigationLink { CallsSettingsView() } label: { AbilityRowView(row: row) }
                .accessibilityIdentifier(id)
        case .callsForYou:
            NavigationLink { CallCasesView() } label: { AbilityRowView(row: row) }
                .accessibilityIdentifier(id)
        case .notes, .lists, .messages, .tasks, .leaflets:
            if let open {
                Button {
                    open(row.ability)
                    dismiss()
                } label: {
                    HStack {
                        AbilityRowView(row: row)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(id)
            } else {
                AbilityRowView(row: row)
                    .accessibilityIdentifier(id)
            }
        case .talk, .reminders, .translator:
            // Talking and reminders happen in a conversation on Home; the translator starts from Home's menu.
            AbilityRowView(row: row)
                .accessibilityIdentifier(id)
        }
    }
}

/// One feature: its name, what Doddy does, what stays with the person, and the status in words (never colour alone).
private struct AbilityRowView: View {
    let row: AbilityRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(row.does)
                .font(.body)
                .foregroundStyle(Theme.ink)
            Text(row.youControl)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Text(row.statusText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(row.status == .ready ? Theme.confirmed : Theme.accentText)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
