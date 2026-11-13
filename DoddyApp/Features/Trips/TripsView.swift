import DoddyCore
import SwiftUI
import UIKit

// Trips, planner first (owner, 13 Nov 2026: "trzeba skupić się na zaplanowaniu wyjazdu, na wyszukiwaniu lotów,
// hoteli … w kolorach Dodiego"). Top to bottom: where to (the form, then Doddy's question or the person's own
// words), the flights Kiwi.com found with the stays for their dates, the trips already saved on this iPhone,
// and low down what isn't going ahead. Finding trips in Gmail and forgetting them are in the ••• menu
// (TripsImportSheet). Nothing is booked or paid here (TRAVEL_PLANNER.md, TRAVEL_EMAILS.md).

struct TripsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var trips = TripsModel.shared
    @State private var planner = TripPlannerModel()
    @State private var showImport = false
    @State private var confirmForget = false
    @State private var forgetFailed = false
    @State private var stayTask: PlanOption? = nil
    @State private var stayOutcome: String? = nil
    private let polish = TripsModel.polish

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                DoddyPage {
                    DoddyPageHeader(
                        title: "Where to next?",
                        subtitle: "Flights from Kiwi.com, then stays on Booking.com and Airbnb. You book; Doddy never pays.",
                        pose: .reachingHigh)
                    TripSearchCard(model: planner)
                    TripTellCard(model: planner)
                        .id("tell")
                    plannerStatus
                    results
                    savedTrips
                    notGoingAhead
                    DoddyFinePrint(text: Text("Searching sends what you set (places, dates, nights, people, bags, stops) to Doddy's server and on to Kiwi.com; your budget stays on Doddy's server. Nothing is saved, and Doddy never books or pays: you book on Kiwi.com yourself."))
                }
                .onChange(of: planner.phase) { _, phase in
                    if case .result = phase { withAnimation { proxy.scrollTo("results", anchor: .top) } }
                }
                .onChange(of: planner.question) { _, question in
                    if question != nil { withAnimation { proxy.scrollTo("tell", anchor: .center) } }
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showImport) { TripsImportSheet() }
            .confirmationDialog("Forget the trips saved on this iPhone?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { forgetFailed = !trips.forget() }
            } message: {
                Text("Your emails stay as they are in Gmail.")
            }
            .alert("The trips couldn't be deleted from this iPhone.", isPresented: $forgetFailed) { Button("OK") {} }
            .confirmationDialog("Have Doddy look at stays?", isPresented: stayTaskShown, titleVisibility: .visible) {
                Button("Yes, go") {
                    if let option = stayTask { Task { await handOverStays(option) } }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                if let option = stayTask {
                    Text(verbatim: stayWords(option)
                         + "\n\n" + NSLocalizedString("Doddy researches this in the background and the result waits in Tasks and in Messages. Nothing is booked. The words go to Doddy's server and to Anthropic.", comment: ""))
                }
            }
            .alert(Text(verbatim: stayOutcome ?? ""), isPresented: stayOutcomeShown) {
                Button("OK") {}
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { moreMenu }
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .accessibilityLabel("Hide keyboard")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button { showImport = true } label: {
                Label("Import bookings from Gmail", systemImage: "envelope.badge")
            }
            .accessibilityIdentifier("trips.import")
            Button { planner.startOver() } label: {
                Label("Start a new plan", systemImage: "arrow.counterclockwise")
            }
            if trips.saved != nil {
                Button(role: .destructive) { confirmForget = true } label: {
                    Label("Forget my trips", systemImage: "trash")
                }
                .accessibilityIdentifier("trips.forget")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("trips.more")
    }

    // MARK: The planner's state and results

    @ViewBuilder private var plannerStatus: some View {
        switch planner.phase {
        case .thinking:
            progress(Text("Doddy is reading your words…"))
        case .searching:
            progress(Text("Looking for flights on Kiwi.com…"))
        case let .problem(message):
            DoddyNotice(text: Text(verbatim: message), isProblem: true)
        case .idle, .result:
            EmptyView()
        }
    }

    private func progress(_ text: Text) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            text.foregroundStyle(Theme.ink)
        }
        .doddyCard(padding: 14)
    }

    @ViewBuilder private var results: some View {
        if case let .result(plan) = planner.phase {
            TripResultsView(plan: plan, polish: polish) { option in stayTask = option }
                .id("results")
        }
    }

    // MARK: Trips saved on this iPhone

    @ViewBuilder private var savedTrips: some View {
        let today = TripsModel.today
        let all = trips.trips
        let coming = all.filter { $0.when(today: today) != .past }
        let earlier = all.filter { $0.when(today: today) == .past }
        if trips.storeUnreadable {
            DoddyNotice(text: Text("The trips saved on this iPhone couldn't be read. Import them from Gmail again to replace them."), isProblem: true)
        }
        if !coming.isEmpty {
            DoddySectionTitle(title: "Your trips")
                .padding(.top, 8)
            ForEach(coming) { trip in
                NavigationLink { TripDetailView(trip: trip, polish: polish) } label: {
                    TripCard(trip: trip, today: today, polish: polish)
                }
                .buttonStyle(.plain)
            }
        }
        if !earlier.isEmpty {
            DoddySectionTitle(title: "Earlier trips")
                .padding(.top, 8)
            ForEach(earlier) { trip in
                NavigationLink { TripDetailView(trip: trip, polish: polish) } label: {
                    TripCard(trip: trip, today: today, polish: polish)
                }
                .buttonStyle(.plain)
            }
        }
        if let saved = trips.saved {
            DoddyFinePrint(text: Text(verbatim: String(format: NSLocalizedString("Checked %@. Saved on this iPhone only.", comment: ""),
                                                       saved.checkedAt.formatted(date: .abbreviated, time: .shortened))))
        }
    }

    @ViewBuilder private var notGoingAhead: some View {
        let bookings = trips.notGoingAhead
        if !bookings.isEmpty {
            DoddySectionTitle(title: "Not going ahead")
                .padding(.top, 8)
            ForEach(bookings) { booking in
                TripBookingCard(booking: booking, polish: polish)
            }
            DoddyFinePrint(text: Text("Cancelled or failed, as the seller's email says. Open the email to check."))
        }
    }

    // MARK: Stays research (the same hand-over as the Tasks screen, after the card above showed its words)

    private var stayTaskShown: Binding<Bool> {
        Binding(get: { stayTask != nil }, set: { if !$0 { stayTask = nil } })
    }

    private var stayOutcomeShown: Binding<Bool> {
        Binding(get: { stayOutcome != nil }, set: { if !$0 { stayOutcome = nil } })
    }

    /// The party of the search the option came from, as the server echoed it.
    private var party: (adults: Int, children: Int) {
        if case let .result(plan) = planner.phase { return (plan.brief.adults ?? 1, plan.brief.children ?? 0) }
        return (1, 0)
    }

    private func stayWords(_ option: PlanOption) -> String {
        TripPlanText.stayResearchWords(option, adults: party.adults, children: party.children)
    }

    private func handOverStays(_ option: PlanOption) async {
        let draft = ErrandDraft.typed(stayWords(option), language: polish ? "pl" : "en")
        switch await ErrandsModel.shared.handOverTyped(draft) {
        case .started, .maybeStarted:
            stayOutcome = NSLocalizedString("Doddy is on it. The result will wait in Tasks and in Messages.", comment: "")
        case .paused:
            stayOutcome = NSLocalizedString("Connections are paused, so nothing was sent.", comment: "")
        case .invalid, .notStarted, .alreadySending:
            stayOutcome = NSLocalizedString("The task couldn't be handed over. Nothing was started.", comment: "")
        }
    }
}

/// Home's card while a trip is close (owner: "Karta na Home, gdy jest wyjazd"). Its words come from the
/// trips saved on this iPhone; the cross hides it for this trip.
struct TripHomeCardView: View {
    let trip: Trip
    let open: () -> Void
    @AppStorage("trips.hiddenHomeCard") private var hiddenTripID = ""

    var body: some View {
        if hiddenTripID != trip.id { card }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: open) {
                HStack(alignment: .center, spacing: 12) {
                    TripCountdownTile(when: trip.when(today: TripsModel.today))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: TripHomeCard.title(trip, today: TripsModel.today, polish: TripsModel.polish))
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Text(verbatim: TripHomeCard.subtitle(trip, polish: TripsModel.polish))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.trip")

            Button { hiddenTripID = trip.id } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .doddyCard(padding: 14)
    }
}
