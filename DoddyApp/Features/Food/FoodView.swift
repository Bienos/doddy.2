import DoddyCore
import SwiftUI

/// Home's "Food" screen. Since 13 Nov 2026 it starts with what the person wants to eat (owner: "ja mówię, że chcę
/// burgera i to mi pokazuje … z tych wszystkich apek"): an orange hero "What do you feel like?" with a field and
/// quick picks, then every delivery app in `FoodApps.all` ready to look for exactly that. A tap copies the words to
/// the clipboard (this iPhone only, gone after two minutes, `NoteClipboard`) and opens the app, where the person
/// pastes them in its search: the apps publish no search address Doddy could fill in (decision 2026-11-11-food-button),
/// and Doddy reads no menus, prices or delivery times from them, so it never says which is nearest or cheapest.
/// Doddy places no order and logs in to nothing; ordering for the person needs a wallet or card the owner hasn't
/// decided on yet (docs/OWNER_QUEUE.md). Below the question, "Near you" (`FoodNearbySection`) lists the restaurants,
/// cafés and bakeries Apple Maps finds for the dish near a typed address; that is Apple Maps' list of places, not a
/// list of what the delivery apps offer or charge.
struct FoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var craving = ""
    /// What the apps below look for; nil until the person asks.
    @State private var looking: String?
    @State private var copiedFor: String?
    /// The last few things looked for, newest first, on this iPhone only.
    @AppStorage("food.recentCravings") private var recentStore = ""

    private var recent: [String] { recentStore.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DoddyHero(title: "What do you feel like?",
                              subtitle: "Say a dish or a place. Doddy gets every delivery app ready to look for it.",
                              pose: .reachingHigh) {
                        DoddyAskField(placeholder: NSLocalizedString("Burger, sushi, pho, pierogi…", comment: ""),
                                      text: $craving, systemImage: "fork.knife", identifier: "food.field") { look(for: craving) }
                        DoddyChipRow {
                            ForEach(Self.picks, id: \.self) { pick in
                                DoddyChip(title: pick, isSelected: looking == pick, onOrange: true) { look(for: pick) }
                            }
                        }
                    }
                    if !recent.isEmpty, looking == nil {
                        DoddySectionTitle(title: "Lately")
                        DoddyChipRow {
                            ForEach(recent, id: \.self) { item in
                                DoddyChip(title: item, systemImage: "clock.arrow.circlepath") { look(for: item) }
                            }
                        }
                    }
                    // Places near the person's typed address, from Apple Maps (decision 2026-11-13-food-search-nearby).
                    FoodNearbySection(dish: looking)
                    DoddySectionTitle(title: looking == nil ? NSLocalizedString("Delivery apps", comment: "")
                                                            : String(format: NSLocalizedString("Where to look for “%@”", comment: ""), looking ?? ""))
                    ForEach(FoodApps.all) { app in
                        Button { open(app) } label: { appRow(app) }
                            .buttonStyle(DoddyTapStyle())
                            .accessibilityIdentifier("food.\(app.id)")
                    }
                    DoddyFootnote(text: looking == nil
                                  ? NSLocalizedString("Opens the app if you have it, or the website. Doddy doesn't see or place the order.", comment: "")
                                  : NSLocalizedString("Doddy copies your words (this iPhone only, for two minutes) and opens the app: paste them in its search. Prices, delivery times and what's nearest are the app's own; Doddy reads none of them and orders nothing.", comment: ""))
                }
                .padding(16)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .doddyScreen()
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Quick picks: what people in Poland order most, in the app's language.
    private static var picks: [String] {
        [NSLocalizedString("Burger", comment: ""), NSLocalizedString("Pizza", comment: ""), NSLocalizedString("Sushi", comment: ""),
         NSLocalizedString("Kebab", comment: ""), NSLocalizedString("Ramen", comment: ""), NSLocalizedString("Pierogi", comment: ""),
         NSLocalizedString("Thai", comment: ""), NSLocalizedString("Vegan", comment: "")]
    }

    private func appRow(_ app: FoodApp) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: String(app.name.prefix(1)))
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.inkOnOrange)
                .frame(width: 44, height: 44)
                .background(Theme.orangeCue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: app.name).font(.headline).foregroundStyle(Theme.ink)
                if let looking {
                    Text(verbatim: String(format: NSLocalizedString("Look for “%@” in %@", comment: ""), looking, app.name))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                if copiedFor == app.id {
                    Label("Copied, paste it in the search", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.confirmed)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
        }
        .doddyCard(padding: 14)
        .contentShape(Rectangle())
    }

    private func look(for words: String) {
        // One line: the recent list is stored one per line, and an app's search box takes one.
        let trimmed = words.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= FoodHandoff.searchMaxLength else { return }
        looking = trimmed
        craving = ""
        copiedFor = nil
        let rest = recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        recentStore = ([trimmed] + rest).prefix(5).joined(separator: "\n")
    }

    private func open(_ app: FoodApp) {
        if let looking {
            NoteClipboard.copy(looking)
            copiedFor = app.id
        }
        openURL(app.url)
    }
}
