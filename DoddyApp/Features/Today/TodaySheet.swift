import SwiftUI

/// Home's ••• → Today (it used to be a card on Home): the day at a glance, with Doddy and the date
/// (decision 2026-11-10-today-at-a-glance). Half height first; pull up for the rest of the day.
struct TodaySheet: View {
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayCard(openSettings: openSettings, showsDoddy: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                    .readableColumn()
            }
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Today")
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
