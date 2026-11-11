import DoddyCore
import SwiftUI

// The trips screen (TRAVEL_EMAILS.md): the trips Doddy found in the person's booking emails, what each
// one asks of them before they go, and the one button that searches Gmail. The tap is the yes (decision
// 2026-11-11-asked-for-runs-at-once); what leaves the iPhone is said right under the button.
// Words built in DoddyCore (`TripCheckText`, `TripHomeCard`, `TravelScanProblem`) are shown verbatim.

struct TripsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = TripsModel.shared
    @State private var confirmForget = false
    @State private var forgetFailed = false
    private let polish = TripsModel.polish

    var body: some View {
        NavigationStack {
            List {
                searchSection
                if model.storeUnreadable {
                    Section { Text("The trips saved on this iPhone couldn't be read. Search again to replace them.") }
                }
                let trips = model.trips
                if !trips.isEmpty {
                    Section("Trips") {
                        ForEach(trips) { trip in
                            NavigationLink { TripDetailView(trip: trip, polish: polish) } label: { TripRow(trip: trip, polish: polish) }
                        }
                    }
                }
                if !model.notGoingAhead.isEmpty {
                    Section {
                        ForEach(model.notGoingAhead) { booking in BookingSummary(booking: booking, polish: polish) }
                    } header: {
                        Text("Not going ahead")
                    } footer: {
                        Text("Cancelled or failed, as the seller's email says. Open the email to check.")
                    }
                }
                if let saved = model.saved {
                    Section {
                        Button("Forget my trips", role: .destructive) { confirmForget = true }
                            .accessibilityIdentifier("trips.forget")
                    } footer: {
                        Text(verbatim: String(format: NSLocalizedString("Checked %@. Saved on this iPhone only.", comment: ""),
                                              saved.checkedAt.formatted(date: .abbreviated, time: .shortened)))
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Forget the trips saved on this iPhone?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { forgetFailed = !model.forget() }
            } message: {
                Text("Your emails stay as they are in Gmail.")
            }
            .alert("The trips couldn't be deleted from this iPhone.", isPresented: $forgetFailed) { Button("OK") {} }
        }
    }

    @ViewBuilder private var searchSection: some View {
        Section {
            switch model.phase {
            case .idle, .done, .problem, .notSaved:
                if case let .problem(problem) = model.phase {
                    Label { Text(verbatim: problem.text(polish: polish)) } icon: { Image(systemName: "exclamationmark.circle") }
                }
                if case .notSaved = model.phase {
                    Label("Doddy found bookings but couldn't save them on this iPhone. Nothing was saved; try again.",
                          systemImage: "exclamationmark.circle")
                }
                if case let .done(emails, bookings, unreadable) = model.phase {
                    Text(verbatim: String(format: NSLocalizedString("Read %lld emails, found %lld bookings.", comment: ""), emails, bookings))
                    if unreadable > 0 {
                        Text(verbatim: String(format: NSLocalizedString("Couldn't read %lld of them; they are left out, not guessed.", comment: ""), unreadable))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Button {
                    Task { await model.find() }
                } label: {
                    Label(model.saved == nil ? "Find my trips in Gmail" : "Check Gmail again", systemImage: "envelope.badge")
                }
                .accessibilityIdentifier("trips.find")
            case .searching:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading your booking emails…")
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if model.saved == nil, case .idle = model.phase {
                    Text("Doddy looks for flight, stay, holiday and train bookings, then lists what each trip needs: online check-in, documents, free cancellation and what's paid there.")
                }
                Text("Doddy searches Gmail for booking emails from the last 400 days (airlines, Booking.com, Airbnb, travel agents, trains) and reads up to 25 of them.")
                Text("Links, PINs and card numbers are removed first. The rest of each email goes to Anthropic to be read, and nothing is kept on Doddy's server. Your trips are saved on this iPhone only.")
            }
        }
    }
}

private struct TripRow: View {
    let trip: Trip
    let polish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: TripHomeCard.title(trip, today: TripsModel.today, polish: polish)).font(.headline)
            Text(verbatim: "\(TripCheckText.day(trip.start, polish: polish)) – \(TripCheckText.day(trip.end, polish: polish))")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TripDetailView: View {
    let trip: Trip
    let polish: Bool

    var body: some View {
        List {
            Section("Bookings") {
                ForEach(trip.bookings) { BookingSummary(booking: $0, polish: polish) }
            }
            Section("Before you go") {
                ForEach(TripChecks.checks(for: trip)) { check in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: TripCheckText.title(check, polish: polish)).font(.headline)
                        Text(verbatim: TripCheckText.detail(check, trip: trip, polish: polish))
                            .font(.subheadline)
                        if let source = check.sourceURL, let url = URL(string: source) {
                            Link(destination: url) { Label("Where this rule comes from", systemImage: "link") }
                                .font(.footnote)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(Text(verbatim: trip.title))
    }
}

/// One booking: what it is, its state, and the emails it came from.
private struct BookingSummary: View {
    let booking: TravelBooking
    let polish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: [booking.provider, booking.reference].compactMap { $0 }.joined(separator: " · ")).font(.headline)
                Spacer()
                stateBadge
            }
            ForEach(Array(booking.facts.segments.enumerated()), id: \.offset) { _, s in
                Text(verbatim: segmentLine(s)).font(.subheadline)
            }
            if let stay = booking.facts.stay {
                Text(verbatim: stayLine(stay)).font(.subheadline)
            }
            if let total = booking.facts.total {
                Text(verbatim: "\(total.amount) \(total.currency)").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            ForEach(booking.sources.suffix(1), id: \.messageId) { source in
                if let url = URL(string: "https://mail.google.com/mail/u/0/#all/\(source.messageId)") {
                    Link(destination: url) {
                        Text(verbatim: String(format: NSLocalizedString("From an email by %@", comment: ""), source.senderDomain))
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var stateBadge: some View {
        switch booking.state {
        case .booked: EmptyView()
        case .changed: Text("Changed").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        case .waiting: Text("Waiting").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        case .cancelled: Text("Cancelled").font(.caption.weight(.semibold)).foregroundStyle(.red)
        case .failed: Text("Didn't go through").font(.caption.weight(.semibold)).foregroundStyle(.red)
        }
    }

    private func segmentLine(_ s: TravelBooking.Segment) -> String {
        let day = TripDay(s.departDate).map { TripCheckText.day($0, polish: polish) }
        let route = [s.from.name ?? s.from.code, s.to.name ?? s.to.code].compactMap { $0 }.joined(separator: " → ")
        return [s.number, day, s.departTime, route].compactMap { $0 }.joined(separator: " · ")
    }

    private func stayLine(_ stay: TravelBooking.Stay) -> String {
        let days = [TripDay(stay.checkInDate), TripDay(stay.checkOutDate)].compactMap { $0 }.map { TripCheckText.day($0, polish: polish) }
        return [stay.name ?? stay.city, days.isEmpty ? nil : days.joined(separator: " – ")].compactMap { $0 }.joined(separator: " · ")
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
        HStack(alignment: .top, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 6) {
                    Label { Text(verbatim: TripHomeCard.title(trip, today: TripsModel.today, polish: TripsModel.polish)) } icon: { Image(systemName: "airplane") }
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: TripHomeCard.subtitle(trip, polish: TripsModel.polish))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}
