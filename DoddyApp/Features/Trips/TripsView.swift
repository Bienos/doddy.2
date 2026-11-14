import DoddyCore
import SwiftUI

// Trips (owner, 13 Nov 2026: "trzeba skupić się na zaplanowaniu wyjazdu, na wyszukiwaniu lotów, hoteli … w kolorach
// Dodiego"). One screen that starts with the question: an orange hero with Flights and Stays, the field (or the stay's
// form), and quick ideas. Under it the planner's conversation and its flights as boarding passes, or the stay's search
// links; then the trips saved on this iPhone. Reading Gmail for booking emails (TRAVEL_EMAILS.md) is no longer the
// screen's main button: it is "Import bookings from Gmail" in the ••• menu, and its card says what leaves the iPhone
// before anything runs (the tap on Import is the yes, decision 2026-11-11-asked-for-runs-at-once).
// Nothing is booked or paid here: "Book on Kiwi.com" opens Kiwi.com, stays open Booking.com and Airbnb with the days
// filled in, and "Doddy compares stays" is a background task with its own yes card.
// Words built in DoddyCore (`TripPlanText`, `StaySearch`, `TripCheckText`, `TripHomeCard`, `TravelScanProblem`) are
// shown verbatim.

struct TripsView: View {
    private enum Mode { case flights, stays }

    /// What "Doddy compares stays" would hand over, shown on its card first.
    private enum StayAsk: Identifiable {
        case afterFlight(PlanOption)
        case stay(StaySearch)
        var id: String {
            switch self {
            case .afterFlight(let o): "flight-\(o.id)"
            case .stay(let s): "stay-\(s.place)-\(s.checkIn)-\(s.nights)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = TripsModel.shared
    @State private var planner = TripPlannerModel()
    @State private var mode: Mode = .flights
    @State private var words = ""
    @State private var stayPlace = ""
    @State private var stayCheckIn = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var stayNights = 3
    @State private var stayAdults = 2
    @State private var stayChildren = 0
    @State private var stay: StaySearch?
    @State private var stayAsk: StayAsk?
    @State private var stayOutcome: String?
    @State private var askGmail = false
    @State private var confirmForget = false
    @State private var forgetFailed = false
    private let polish = TripsModel.polish

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        switch mode {
                        case .flights: flights
                        case .stays: stays
                        }
                        yourTrips
                    }
                    .padding(16)
                    .readableColumn()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: planner.lines) { _, lines in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: planner.phase) { _, phase in
                    if case .result = phase { withAnimation { proxy.scrollTo("trips.result", anchor: .top) } }
                }
            }
            .doddyScreen()
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { moreMenu }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Import bookings from Gmail?", isPresented: $askGmail, titleVisibility: .visible) {
                Button("Import") { Task { await model.find() } }
                    .accessibilityIdentifier("trips.find")
                Button("Not now", role: .cancel) {}
            } message: {
                Text(verbatim: NSLocalizedString("Doddy searches Gmail for booking emails from the last 400 days (airlines, Booking.com, Airbnb, travel agents, trains) and reads up to 25 of them.", comment: "")
                     + "\n\n" + NSLocalizedString("Links, PINs and card numbers are removed first. The rest of each email goes to Anthropic to be read, and nothing is kept on Doddy's server. Your trips are saved on this iPhone only.", comment: ""))
            }
            .confirmationDialog("Forget the trips saved on this iPhone?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { forgetFailed = !model.forget() }
            } message: {
                Text("Your emails stay as they are in Gmail.")
            }
            .confirmationDialog("Have Doddy look at stays?", isPresented: Binding(get: { stayAsk != nil }, set: { if !$0 { stayAsk = nil } }), titleVisibility: .visible) {
                Button("Yes, go") {
                    if let ask = stayAsk { Task { await handOver(ask) } }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                if let ask = stayAsk {
                    Text(verbatim: researchWords(ask)
                         + "\n\n" + NSLocalizedString("Doddy researches this in the background and the result waits in Tasks and in Messages. Nothing is booked. The words go to Doddy's server and to Anthropic.", comment: ""))
                }
            }
            .alert(Text(verbatim: stayOutcome ?? ""), isPresented: Binding(get: { stayOutcome != nil }, set: { if !$0 { stayOutcome = nil } })) {
                Button("OK") {}
            }
            .alert("The trips couldn't be deleted from this iPhone.", isPresented: $forgetFailed) { Button("OK") {} }
        }
    }

    // MARK: Hero

    private var hero: some View {
        DoddyHero(title: mode == .flights ? NSLocalizedString("Where are we flying?", comment: "") : NSLocalizedString("Where are you staying?", comment: ""),
                  subtitle: mode == .flights
                    ? NSLocalizedString("Where, when and with whom. Doddy shows up to three flights with the real total.", comment: "")
                    : NSLocalizedString("A place, the days and who's going. Doddy opens the searches with everything filled in.", comment: ""),
                  pose: mode == .flights ? .tiptoe : .yawnStretch) {
            HStack(spacing: 8) {
                DoddyChip(title: "Flights", systemImage: "airplane", isSelected: mode == .flights, onOrange: true) { mode = .flights }
                    .accessibilityIdentifier("trips.mode.flights")
                DoddyChip(title: "Stays", systemImage: "bed.double", isSelected: mode == .stays, onOrange: true) { mode = .stays }
                    .accessibilityIdentifier("trips.mode.stays")
            }
            switch mode {
            case .flights:
                if planner.lines.isEmpty {
                    DoddyAskField(placeholder: NSLocalizedString("Lisbon around 12 February, 4 nights, the two of us…", comment: ""),
                                  text: $words, systemImage: "airplane.departure", isBusy: planner.isBusy, identifier: "planner.field") { send(words) }
                    DoddyChipRow {
                        ForEach(Self.ideas, id: \.self) { idea in
                            DoddyChip(title: idea, onOrange: true) { send(idea) }
                        }
                    }
                } else {
                    DoddyChip(title: "New search", systemImage: "arrow.counterclockwise", onOrange: true) {
                        planner.startOver()
                        words = ""
                    }
                    .accessibilityIdentifier("trips.startOver")
                }
            case .stays:
                stayForm
            }
        }
    }

    /// Quick starts the planner understands as they are (the server reads Polish and English). Localized here, so
    /// the chip shows and sends the same words.
    private static var ideas: [String] {
        [NSLocalizedString("Lisbon for a long weekend", comment: ""), NSLocalizedString("Rome, 4 nights for two", comment: ""),
         NSLocalizedString("Barcelona in May", comment: ""), NSLocalizedString("Somewhere warm in February from Warsaw", comment: "")]
    }

    private var moreMenu: some View {
        Menu {
            Button { askGmail = true } label: { Label("Import bookings from Gmail", systemImage: "envelope.badge") }
                .disabled(model.phase == .searching)
            if model.saved != nil {
                Button(role: .destructive) { confirmForget = true } label: { Label("Forget my trips", systemImage: "trash") }
                    .accessibilityIdentifier("trips.forget")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("More"))
        .accessibilityIdentifier("trips.more")
    }

    // MARK: Flights

    @ViewBuilder private var flights: some View {
        if !planner.lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(planner.lines) { line in bubble(line).id(line.id) }
                if !planner.assumptions.isEmpty { assumptions }
                if planner.phase == .asking {
                    DoddyAskField(placeholder: NSLocalizedString("Answer Doddy…", comment: ""), text: $words,
                                  systemImage: "text.bubble", isBusy: planner.isBusy, identifier: "planner.answer") { send(words) }
                }
            }
        }
        switch planner.phase {
        case .thinking, .searching:
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accentText)
                Text(planner.phase == .searching ? "Looking for flights on Kiwi.com…" : "Thinking…")
                    .foregroundStyle(Theme.secondaryText)
            }
            .doddyCard()
        case let .result(plan):
            results(plan).id("trips.result")
        case let .problem(message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.circle") }
                .font(.subheadline)
                .foregroundStyle(Theme.error)
                .doddyCard()
        case .asking:
            if planner.lines.isEmpty {
                DoddyFootnote(text: NSLocalizedString("Type it or dictate it with your keyboard's microphone. Doddy asks for what's missing, one thing at a time. You book on Kiwi.com yourself; nothing is booked or paid here.", comment: ""),
                              systemImage: "sparkle")
            }
        }
    }

    private func bubble(_ line: TripPlannerModel.Line) -> some View {
        HStack {
            if line.who == .person { Spacer(minLength: 48) }
            Text(verbatim: line.text)
                .font(.body)
                .foregroundStyle(line.who == .person ? Theme.inkOnOrange : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(line.who == .person ? Theme.orangeCue : Theme.quietSurface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            if line.who == .doddy { Spacer(minLength: 48) }
        }
    }

    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("I'm assuming").font(.footnote.weight(.semibold))
            ForEach(planner.assumptions, id: \.self) { a in
                Text(verbatim: "· " + TripPlanText.assumption(a, polish: polish))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func results(_ plan: PlanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DoddySectionTitle(title: "Flights", detail: "Kiwi.com")
            if plan.options.isEmpty {
                Label("Kiwi.com found no flights for these days. Try other days or a nearby airport.", systemImage: "airplane.slash")
                    .font(.subheadline)
                    .doddyCard()
            } else {
                ForEach(plan.options) { option in
                    FlightPassCard(option: option, adults: planner.adults, polish: polish,
                                   book: { if let url = URL(string: option.bookingUrl) { openURL(url) } },
                                   open: { address in if let url = URL(string: address) { openURL(url) } },
                                   compareStays: { stayAsk = .afterFlight(option) })
                }
                DoddyFootnote(text: String(format: NSLocalizedString("Prices and times are Kiwi.com's, read %@. They can change before you book; the price shown is for the whole party with the bags counted above.", comment: ""),
                                           Self.checkedAt(plan.checkedAt)))
            }
        }
    }

    // MARK: Stays

    private var stayForm: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("City or area, e.g. Lisbon, Alfama", text: $stayPlace)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.vertical, 10)
                .accessibilityIdentifier("trips.stay.place")
            Divider()
            DatePicker("Check-in", selection: $stayCheckIn, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                .padding(.vertical, 4)
            Divider()
            Stepper(value: $stayNights, in: 1...StaySearch.maxNights) {
                Text(verbatim: String(format: NSLocalizedString("Nights: %lld", comment: ""), stayNights))
            }
            .padding(.vertical, 4)
            Stepper(value: $stayAdults, in: 1...StaySearch.maxAdults) {
                Text(verbatim: String(format: NSLocalizedString("Adults: %lld", comment: ""), stayAdults))
            }
            .padding(.vertical, 4)
            Stepper(value: $stayChildren, in: 0...StaySearch.maxChildren) {
                Text(verbatim: String(format: NSLocalizedString("Children: %lld", comment: ""), stayChildren))
            }
            .padding(.vertical, 4)
            Button {
                stay = StaySearch(place: stayPlace, checkIn: Self.tripDay(stayCheckIn), nights: stayNights,
                                  adults: stayAdults, children: stayChildren)
            } label: {
                Label("Show stays", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }
            .buttonStyle(DoddyInkButtonStyle())
            .disabled(stayPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 8)
            .accessibilityIdentifier("trips.stay.search")
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accentText)
        .padding(14)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var stays: some View {
        if let stay {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    DoddySymbolTile(systemImage: "bed.double.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: stay.place).font(.system(.title3, design: .rounded, weight: .bold))
                        Text(verbatim: stay.summary(polish: polish))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                VStack(spacing: 8) {
                    if let url = stay.bookingURL {
                        Button { openURL(url) } label: { providerRow("Booking.com", detail: NSLocalizedString("Hotels and apartments", comment: "")) }
                            .buttonStyle(DoddyTapStyle())
                    }
                    if let url = stay.airbnbURL {
                        Button { openURL(url) } label: { providerRow("Airbnb", detail: NSLocalizedString("Flats and houses", comment: "")) }
                            .buttonStyle(DoddyTapStyle())
                    }
                }
                Button { stayAsk = .stay(stay) } label: {
                    Label("Doddy compares stays for me", systemImage: "sparkle.magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(DoddyOutlineButtonStyle())
                .accessibilityIdentifier("trips.stay.research")
            }
            .doddyCard()
            DoddyFootnote(text: NSLocalizedString("The searches open on Booking.com and Airbnb with your days filled in; their prices are theirs. Doddy books nothing and reads nothing from those pages.", comment: ""))
        } else {
            DoddyFootnote(text: NSLocalizedString("Doddy opens Booking.com and Airbnb already filtered, or researches the best areas and prices for you in the background.", comment: ""),
                          systemImage: "sparkle")
        }
    }

    private func providerRow(_ name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.headline)
                Text(verbatim: detail).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: Your trips

    @ViewBuilder private var yourTrips: some View {
        let trips = model.trips
        let hasAnything = !trips.isEmpty || !model.notGoingAhead.isEmpty || model.storeUnreadable || model.phase != .idle
        if hasAnything {
            DoddySectionTitle(title: "Your trips")
            importStatus
            if model.storeUnreadable {
                Text("The trips saved on this iPhone couldn't be read. Search again to replace them.")
                    .font(.subheadline)
                    .doddyCard()
            }
            ForEach(trips) { trip in
                NavigationLink { TripDetailView(trip: trip, polish: polish) } label: { TripCard(trip: trip, polish: polish) }
                    .buttonStyle(DoddyTapStyle())
            }
            if !model.notGoingAhead.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Not going ahead").font(.headline)
                    ForEach(model.notGoingAhead) { booking in BookingSummary(booking: booking, polish: polish) }
                    Text("Cancelled or failed, as the seller's email says. Open the email to check.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .doddyCard()
            }
            if let saved = model.saved {
                DoddyFootnote(text: String(format: NSLocalizedString("Checked %@. Saved on this iPhone only.", comment: ""),
                                           saved.checkedAt.formatted(date: .abbreviated, time: .shortened)),
                              systemImage: "lock")
            }
        }
    }

    @ViewBuilder private var importStatus: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accentText)
                Text("Reading your booking emails…")
            }
            .doddyCard()
        case let .done(emails, bookings, unreadable):
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: String(format: NSLocalizedString("Read %lld emails, found %lld bookings.", comment: ""), emails, bookings))
                if unreadable > 0 {
                    Text(verbatim: String(format: NSLocalizedString("Couldn't read %lld of them; they are left out, not guessed.", comment: ""), unreadable))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .font(.subheadline)
            .doddyCard()
        case let .problem(problem):
            Label { Text(verbatim: problem.text(polish: polish)) } icon: { Image(systemName: "exclamationmark.circle") }
                .font(.subheadline)
                .foregroundStyle(Theme.error)
                .doddyCard()
        case .notSaved:
            Label("Doddy found bookings but couldn't save them on this iPhone. Nothing was saved; try again.",
                  systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(Theme.error)
                .doddyCard()
        }
    }

    // MARK: Actions

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !planner.isBusy else { return }
        words = ""
        Task { await planner.send(trimmed) }
    }

    private func researchWords(_ ask: StayAsk) -> String {
        switch ask {
        case .afterFlight(let option): TripPlanText.stayResearchWords(option, adults: planner.adults, children: planner.children)
        case .stay(let stay): stay.researchWords
        }
    }

    /// The stays task goes through the same hand-over as the Tasks screen, after the card above showed its words.
    private func handOver(_ ask: StayAsk) async {
        let draft = ErrandDraft.typed(researchWords(ask), language: polish ? "pl" : "en")
        switch await ErrandsModel.shared.handOverTyped(draft) {
        case .started, .maybeStarted:
            stayOutcome = NSLocalizedString("Doddy is on it. The result will wait in Tasks and in Messages.", comment: "")
        case .paused:
            stayOutcome = NSLocalizedString("Connections are paused, so nothing was sent.", comment: "")
        case .invalid, .notStarted, .alreadySending:
            stayOutcome = NSLocalizedString("The task couldn't be handed over. Nothing was started.", comment: "")
        }
    }

    private static func tripDay(_ date: Date) -> TripDay {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return TripDay(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }

    private static func checkedAt(_ iso: String) -> String {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: iso) ?? fractional.date(from: iso) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Flight card

/// One flight option as a boarding pass: the pick on top, each leg with its airport codes, times, length and stops,
/// a perforation, then the real total, what it covers, the traps, and the buttons.
private struct FlightPassCard: View {
    let option: PlanOption
    let adults: Int
    let polish: Bool
    let book: () -> Void
    let open: (String) -> Void
    let compareStays: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DoddyTag(text: TripPlanText.pick(option.pick, polish: polish), strong: option.pick == .cheapest)
                Spacer()
                if option.overBudget {
                    Label("Over your budget", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.error)
                }
            }
            LegView(leg: option.outbound, polish: polish)
            if let back = option.inbound {
                LegView(leg: back, polish: polish)
            }
            Perforation()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: TripPlanText.money(option, polish: polish))
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: TripPlanText.priceDetail(option, adults: adults, polish: polish))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            ForEach(option.traps, id: \.self) { trap in
                Label { Text(verbatim: TripPlanText.trap(trap, polish: polish)) } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.accentText)
                }
                .font(.footnote)
            }
            HStack(spacing: 8) {
                Button(action: book) { Label("Book on Kiwi.com", systemImage: "arrow.up.right") }
                    .buttonStyle(DoddyInkButtonStyle())
                    .disabled(URL(string: option.bookingUrl) == nil)
                Menu {
                    Button { open(option.links.booking) } label: { Label("Stays on Booking.com", systemImage: "bed.double") }
                    Button { open(option.links.airbnb) } label: { Label("Airbnb", systemImage: "house") }
                    if let packages = option.links.packages {
                        Button { open(packages) } label: { Label("Holidays on wakacje.pl", systemImage: "sun.max") }
                    }
                    Button(action: compareStays) { Label("Have Doddy look at stays", systemImage: "sparkle.magnifyingglass") }
                } label: {
                    Label("Stays", systemImage: "bed.double")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                }
                .foregroundStyle(Theme.ink)
            }
        }
        .padding(18)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Cream, with the pass's orange edge on the left.
            ZStack(alignment: .leading) {
                Theme.quietSurface
                Theme.orangeCue.frame(width: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// "WAW ✈ LIS" with the times under the codes, the cities, and the length and stops under the plane.
private struct LegView: View {
    let leg: PlanLeg
    let polish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .center, spacing: 8) {
                end(code: leg.from, time: TripPlanText.time(leg.departs), city: leg.fromCity, alignment: .leading)
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        line
                        Image(systemName: "airplane").foregroundStyle(Theme.orangeCue)
                        line
                    }
                    Text(verbatim: TripDuration.text(minutes: leg.minutes, polish: polish))
                        .font(.caption2.weight(.semibold))
                    Text(verbatim: TripPlanText.stops(leg.stops, polish: polish))
                        .font(.caption2)
                        .foregroundStyle(leg.stops == 0 ? Theme.confirmed : Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                end(code: leg.to, time: TripPlanText.time(leg.arrives), city: leg.toCity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TripPlanText.leg(leg, polish: polish)))
    }

    private var header: String {
        let day = TripDay(String(leg.departs.prefix(10))).map { TripCheckText.day($0, polish: polish) } ?? ""
        return ([day] + (leg.airlines.isEmpty ? [] : [leg.airlines.joined(separator: ", ")])).joined(separator: " · ")
    }

    private var line: some View {
        Rectangle().fill(Theme.separator).frame(height: 1.5).frame(maxWidth: 40)
    }

    private func end(code: String, time: String, city: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(verbatim: code).font(.system(.title2, design: .rounded, weight: .heavy))
            Text(verbatim: time).font(.subheadline.weight(.semibold).monospacedDigit())
            if let city { Text(verbatim: city).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The dashed line where a boarding pass tears.
private struct Perforation: View {
    var body: some View {
        Line()
            .stroke(Theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

// MARK: - Saved trips

/// A saved trip: when it is, the dates and how many things to check before going.
private struct TripCard: View {
    let trip: Trip
    let polish: Bool

    var body: some View {
        HStack(spacing: 14) {
            DoddySymbolTile(systemImage: "airplane", size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: TripHomeCard.title(trip, today: TripsModel.today, polish: polish))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(verbatim: "\(TripCheckText.day(trip.start, polish: polish)) – \(TripCheckText.day(trip.end, polish: polish))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: TripHomeCard.subtitle(trip, polish: polish))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .doddyCard()
        .accessibilityElement(children: .combine)
    }
}

struct TripDetailView: View {
    let trip: Trip
    let polish: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DoddySectionTitle(title: "Bookings")
                ForEach(trip.bookings) { BookingSummary(booking: $0, polish: polish).doddyCard() }
                DoddySectionTitle(title: "Before you go")
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
                    .doddyCard()
                }
            }
            .padding(16)
            .readableColumn()
        }
        .doddyScreen()
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
        case .cancelled: Text("Cancelled").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
        case .failed: Text("Didn't go through").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
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
