import DoddyCore
import SwiftUI

/// Home › ••• › What I can do (decision 2026-11-09-what-i-can-do): a scene for each feature this build shows
/// (`AbilityCarousel`, decision 2026-11-09-what-i-can-do-scenes), the opening paragraph with the Privacy Policy,
/// then the same features as tiles with an honest status worked out in DoddyCore (`WhatICanDo`). A tile opens its
/// feature where there is one: calls inside this sheet, the rest from Home through `open` once the sheet has gone.
struct CapabilitiesSheet: View {
    /// Opens a feature that lives on Home (Messages, Tasks, leaflets, notes and lists) after this sheet closes.
    var open: ((DoddyAbility) -> Void)? = nil

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    /// Phone calls and calls for you open inside this sheet. A tile is a plain button that sets this: a
    /// NavigationLink inside a grid in a List row doesn't push (the hosted UI test caught it, 10 Nov 2026).
    @State private var openedInside: DoddyAbility?

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
                    // What leaves this iPhone left this sheet on 10 Nov 2026 (owner: it belongs in the Privacy
                    // Policy). The screen itself stays in Settings › Privacy.
                    Link(destination: LegalDocuments.url(.privacy, languageCode: SettingsView.languageCode)) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("capabilities.privacyPolicy")
                }
                // The same features as the scenes above, as tiles (owner, 10 Nov 2026: the long rows were too much).
                // A tile shows the name and the status; VoiceOver reads the whole row, as before.
                Section("What's built") {
                    LazyVGrid(columns: tileColumns, spacing: 10) {
                        ForEach(rows) { row in
                            abilityTile(row)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationDestination(item: $openedInside) { ability in
                switch ability {
                case .callsForYou: CallCasesView()
                default: CallsSettingsView()
                }
            }
            .navigationTitle("What I can do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Two tiles a row; one at the accessibility text sizes.
    private var tileColumns: [GridItem] {
        textSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    @ViewBuilder
    private func abilityTile(_ row: AbilityRow) -> some View {
        let id = "capabilities.row.\(row.ability.rawValue)"
        switch row.ability {
        case .phoneCalls, .callsForYou:
            Button { openedInside = row.ability } label: { AbilityTileView(row: row, opens: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier(id)
        case .notes, .lists, .messages, .tasks, .leaflets:
            if let open {
                Button {
                    open(row.ability)
                    dismiss()
                } label: {
                    AbilityTileView(row: row, opens: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(id)
            } else {
                AbilityTileView(row: row, opens: false)
                    .accessibilityIdentifier(id)
            }
        case .talk, .reminders, .translator:
            // Talking and reminders happen in a conversation on Home; the translator starts from Home's menu.
            AbilityTileView(row: row, opens: false)
                .accessibilityIdentifier(id)
        }
    }
}

/// One feature as a tile: its name, the status as a word on a chip (never colour alone) and, where the tile
/// opens something, an arrow. VoiceOver reads what it does and what stays with the person too.
private struct AbilityTileView: View {
    let row: AbilityRow
    let opens: Bool

    private var ready: Bool { row.status == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(row.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if opens {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            Text(row.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Theme.confirmed : Theme.accentText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill((ready ? Theme.confirmed : Theme.orangeCue).opacity(0.14)))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.quietSurface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.title). \(row.does) \(row.youControl) \(row.statusText)"))
        .accessibilityAddTraits(opens ? .isButton : [])
    }
}
