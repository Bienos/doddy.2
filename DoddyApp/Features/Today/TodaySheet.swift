import SwiftUI

/// Home's ••• → Today (it used to be a card on Home): the day at a glance, with Doddy and the date
/// (decision 2026-11-10-today-at-a-glance), on Doddy's page since 13 Nov 2026. Half height first; pull up
/// for the rest of the day.
struct TodaySheet: View {
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DoddyPage {
                TodayCard(openSettings: openSettings, showsDoddy: true)
            }
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
