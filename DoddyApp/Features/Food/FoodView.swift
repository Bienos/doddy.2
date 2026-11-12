import DoddyCore
import SwiftUI

/// Home's "Food" screen (owner, 11 Nov 2026: "maybe other button like food, as I add other ones as well there",
/// decision 2026-11-11-food-button). One row per delivery app in `FoodApps.all`; a tap opens that provider's own
/// front page (its app when it is installed, its website otherwise). Doddy reads nothing and places no order.
struct FoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FoodApps.all) { app in
                        Button { openURL(app.url) } label: {
                            HStack {
                                Text(verbatim: app.name)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("food.\(app.id)")
                    }
                } footer: {
                    Text("Opens the app if you have it, or the website. Doddy doesn't see or place the order.")
                }
            }
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
