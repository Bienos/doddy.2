import DoddyCore
import SwiftUI

// The trips already saved on this iPhone (from booking emails, TRAVEL_EMAILS.md): a card per trip with the
// countdown, and one trip's page with its bookings and what it asks of the person before they go. Words
// built in DoddyCore (`TripCheckText`, `TripHomeCard`, `TripPlanText`) are shown verbatim.

/// A trip on the Trips page: the countdown on an orange tile, where, when, and how many things to check.
struct TripCard: View {
    let trip: Trip
    let today: TripDay
    let polish: Bool

    private var dates: String { TripPlanText.window(from: trip.start, to: trip.end, polish: polish) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TripCountdownTile(when: trip.when(today: today))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: trip.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(verbatim: dates)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: TripHomeCard.subtitle(trip, polish: polish))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .doddyCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [TripHomeCard.title(trip, today: today, polish: polish), dates,
                                            TripHomeCard.subtitle(trip, polish: polish)].joined(separator: ", ")))
    }
}

/// How far off a trip is, big on Doddy's orange: "12 days", "Tomorrow", "Now". Its words are also in the
/// card's own label, so the tile is hidden from VoiceOver.
struct TripCountdownTile: View {
    let when: Trip.When

    var body: some View {
        VStack(spacing: 0) { content }
            .foregroundStyle(Theme.inkOnOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 64, minHeight: 64)
            .background(Theme.orangeCue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch when {
        case .ongoing:
            Image(systemName: "airplane").font(.title3.weight(.bold))
            Text("Now").font(.caption.weight(.bold))
        case .upcoming(0):
            Image(systemName: "sun.max.fill").font(.title3.weight(.bold))
            Text("Today").font(.caption.weight(.bold))
        case .upcoming(1):
            Image(systemName: "moon.stars.fill").font(.title3.weight(.bold))
            Text("Tomorrow").font(.caption.weight(.bold))
        case let .upcoming(days):
            Text(verbatim: "\(days)")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("days").font(.caption.weight(.bold))
        case .past:
            Image(systemName: "checkmark").font(.title3.weight(.bold))
            Text("Past").font(.caption.weight(.bold))
        }
    }
}

/// One trip: when, every booking, and what to check before travelling.
struct TripDetailView: View {
    let trip: Trip
    let polish: Bool

    var body: some View {
        DoddyPage {
            header
            DoddySectionTitle(title: "Bookings")
            ForEach(trip.bookings) { booking in
                TripBookingCard(booking: booking, polish: polish)
            }
            beforeYouGo
        }
        .navigationTitle(Text(verbatim: trip.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: trip.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .background(alignment: .bottomLeading) {
                        Capsule().fill(Theme.orangeCue).frame(width: 44, height: 5).offset(y: 6)
                            .accessibilityHidden(true)
                    }
                    .padding(.bottom, 6)
                Text(verbatim: TripPlanText.window(from: trip.start, to: trip.end, polish: polish))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: TripHomeCard.title(trip, today: TripsModel.today, polish: polish))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TripCountdownTile(when: trip.when(today: TripsModel.today))
        }
    }

    @ViewBuilder private var beforeYouGo: some View {
        let checks = TripChecks.checks(for: trip)
        if !checks.isEmpty {
            DoddySectionTitle(title: "Before you travel")
            ForEach(checks) { check in
                TripCheckCard(check: check, trip: trip, polish: polish)
            }
        }
    }
}

/// One thing to check before the trip, with where its rule comes from.
private struct TripCheckCard: View {
    let check: TripCheck
    let trip: Trip
    let polish: Bool

    private var icon: String {
        switch check.kind {
        case .checkIn: "airplane.departure"
        case .freeCancellation: "calendar.badge.clock"
        case .deposit: "creditcard"
        case .payOnSite: "banknote"
        case .documents: "person.text.rectangle"
        case .waitingForSeller: "hourglass"
        case .fromTheEmail: "envelope.open"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DoddyIconBadge(systemName: icon, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: TripCheckText.title(check, polish: polish))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: TripCheckText.detail(check, trip: trip, polish: polish))
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = check.sourceURL, let url = URL(string: source) {
                    Link(destination: url) {
                        Label("Where this rule comes from", systemImage: "link")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .doddyCard(padding: 14)
    }
}

/// One booking: what it is, its state, and the email it came from.
struct TripBookingCard: View {
    let booking: TravelBooking
    let polish: Bool

    private var icon: String {
        switch booking.kind {
        case .flight: "airplane"
        case .stay: "bed.double.fill"
        case .package: "beach.umbrella.fill"
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .carRental: "car.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                DoddyIconBadge(systemName: icon, size: 36)
                Text(verbatim: [booking.provider, booking.reference].compactMap { $0 }.joined(separator: " · "))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                stateBadge
            }
            ForEach(Array(booking.facts.segments.enumerated()), id: \.offset) { _, s in
                Text(verbatim: segmentLine(s)).font(.subheadline).foregroundStyle(Theme.ink)
            }
            if let stay = booking.facts.stay {
                Text(verbatim: stayLine(stay)).font(.subheadline).foregroundStyle(Theme.ink)
            }
            if let total = booking.facts.total {
                Text(verbatim: "\(total.amount) \(total.currency)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(booking.sources.suffix(1), id: \.messageId) { source in
                if let url = URL(string: "https://mail.google.com/mail/u/0/#all/\(source.messageId)") {
                    Link(destination: url) {
                        Text(verbatim: String(format: NSLocalizedString("From an email by %@", comment: ""), source.senderDomain))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .doddyCard(padding: 14)
    }

    @ViewBuilder private var stateBadge: some View {
        switch booking.state {
        case .booked: EmptyView()
        case .changed: badge(Text("Changed"), problem: false)
        case .waiting: badge(Text("Waiting"), problem: false)
        case .cancelled: badge(Text("Cancelled"), problem: true)
        case .failed: badge(Text("Didn't go through"), problem: true)
        }
    }

    private func badge(_ text: Text, problem: Bool) -> some View {
        text
            .font(.caption.weight(.semibold))
            .foregroundStyle(problem ? Theme.error : Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.canvas, in: Capsule())
            .overlay { Capsule().strokeBorder(problem ? Theme.error : Theme.separator, lineWidth: 1) }
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
