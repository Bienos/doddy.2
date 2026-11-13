import DoddyCore
import SwiftUI

// Finding trips in Gmail (TRAVEL_EMAILS.md), moved off the Trips page into Trips › ••• (owner, 13 Nov 2026:
// "znajdź moje w Gmailu też jest bez sensu" on the planning page). The flow is unchanged: the tap is the yes
// (decision 2026-11-11-asked-for-runs-at-once), and what leaves the iPhone is said right under the button.
// Words built in DoddyCore (`TravelScanProblem`) are shown verbatim.

struct TripsImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = TripsModel.shared
    private let polish = TripsModel.polish

    var body: some View {
        NavigationStack {
            DoddyPage {
                DoddyPageHeader(
                    title: "Your trips from Gmail",
                    subtitle: "Doddy looks for flight, stay, holiday and train bookings, then lists what each trip needs: online check-in, documents, free cancellation and what's paid there.",
                    pose: .kneelingInspect)
                status
                Button {
                    Task { await model.find() }
                } label: {
                    Label(model.saved == nil ? "Find my trips in Gmail" : "Check Gmail again", systemImage: "envelope.badge")
                }
                .buttonStyle(DoddyAccentButtonStyle())
                .disabled(model.phase == .searching)
                .accessibilityIdentifier("trips.find")
                DoddyFinePrint(text: Text("Doddy searches Gmail for booking emails from the last 400 days (airlines, Booking.com, Airbnb, travel agents, trains) and reads up to 25 of them."))
                DoddyFinePrint(text: Text("Links, PINs and card numbers are removed first. The rest of each email goes to Anthropic to be read, and nothing is kept on Doddy's server. Your trips are saved on this iPhone only."))
            }
            .navigationTitle("Gmail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 12) {
                ProgressView()
                Text("Reading your booking emails…")
                    .foregroundStyle(Theme.ink)
            }
            .doddyCard(padding: 14)
        case let .problem(problem):
            DoddyNotice(text: Text(verbatim: problem.text(polish: polish)), isProblem: true)
        case .notSaved:
            DoddyNotice(text: Text("Doddy found bookings but couldn't save them on this iPhone. Nothing was saved; try again."), isProblem: true)
        case let .done(emails, bookings, unreadable):
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(verbatim: String(format: NSLocalizedString("Read %lld emails, found %lld bookings.", comment: ""), emails, bookings))
                        .foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.confirmed)
                }
                .font(.headline)
                if unreadable > 0 {
                    Text(verbatim: String(format: NSLocalizedString("Couldn't read %lld of them; they are left out, not guessed.", comment: ""), unreadable))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if bookings > 0 {
                    Text("Close this to see them on the Trips page.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .doddyCard(padding: 14)
        }
    }
}
