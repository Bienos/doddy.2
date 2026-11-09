import DoddyCore
import SwiftUI

/// Home › ••• › What I can do (decision 2026-11-09-what-i-can-do): the opening paragraph, then each feature this
/// build shows, in plain words, with an honest status worked out in DoddyCore (`WhatICanDo`). A row opens its
/// feature where there is one: calls inside this sheet, the rest from Home through `open` once the sheet has gone.
struct CapabilitiesSheet: View {
    /// Opens a feature that lives on Home (Messages, Tasks, leaflets, notes and lists) after this sheet closes.
    var open: ((DoddyAbility) -> Void)? = nil

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    /// The ink storyboard has played (ADR-380).
    @State private var inkPlayed = false

    private var language: NotificationLanguage { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) }

    private var rows: [AbilityRow] {
        WhatICanDo.rows(catalog: environment.capabilities, scope: ReleaseScopeStore.current,
                        serverConfigured: ServerConfig.baseURL() != nil, language: language)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Off the page and into a real street (the pack's 040, ADR-380).
                    PanelStoryView(story: .ink, played: $inkPlayed, height: 220)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
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
                KeysExampleSection()
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

/// "Where are my keys?" (ADR-380): the pack's keys storyboard (041) as a worked example, never
/// as the user's data. It only works for something the user told Doddy, so the captions say so.
private struct KeysExampleSection: View {
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    private static let count = PanelStory.keys.panelCount

    @ViewBuilder
    private func caption(_ panel: Int) -> some View {
        switch panel {
        case 1: Text("The keys aren't on the hook.")
        case 2: Text("You ask Doddy where they are.")
        case 3: Text("Doddy looks through what you told it.")
        case 4: Text("You'd saved “keys under the sofa cushion”.")
        case 5: Text("There they are.")
        default: Text("Found, from your own note.")
        }
    }

    var body: some View {
        Section {
            if !hideCharacterArt {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(1...PanelStory.keys.panelCount, id: \.self) { panel in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(decorative: PanelStory.keys.assetName(panel))
                                .resizable()
                                .scaledToFill()
                                .frame(height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.separator, lineWidth: 1))
                            caption(panel)
                                .font(.footnote)
                        }
                    }
                }
                .doddyArtMarker("doddy.story.keys")
                .padding(.vertical, 4)
            } else {
                // Pictures hidden: the same story in words.
                ForEach(1...Self.count, id: \.self) { panel in
                    caption(panel)
                }
            }
            Text("Doddy can only find what you told it. It can't see your home or track your things.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        } header: {
            Text("An example: lost keys")
        }
    }
}
