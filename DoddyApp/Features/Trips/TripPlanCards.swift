import DoddyCore
import SwiftUI

// The planner's cards on the Trips page (owner, 13 Nov 2026: "trzeba skupić się na zaplanowaniu wyjazdu, na
// wyszukiwaniu lotów, hoteli … ładnie wszystko tutaj pokazać … w kolorach Dodiego"). The search card is the
// form (`TripPlanForm`); the tell card takes the person's own words, or answers Doddy's one question; the
// results show Kiwi.com's flights as it answered them and the stays links. Nothing is booked or paid here:
// "Book on Kiwi.com" opens Kiwi.com, the stays open Booking.com and Airbnb with the dates filled in.

// MARK: - The search card (the form)

struct TripSearchCard: View {
    @Bindable var model: TripPlannerModel
    @State private var pickingWhen = false
    @FocusState private var focus: Field?
    private let polish = TripsModel.polish

    enum Field: Hashable { case from, to, budget }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            places
            whenRow
            nightsRow
            whoRow
            extrasRow
            budgetRow
            searchButton
            assumptionsRow
        }
        .doddyCard(padding: 18)
        .onChange(of: model.form) { _, _ in model.formChanged() }
        .sheet(isPresented: $pickingWhen) {
            TripWhenSheet(start: model.form.departFrom, end: model.form.departTo) { from, to in
                model.form.departFrom = from
                model.form.departTo = to
            }
        }
    }

    // MARK: From and to

    private var places: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                TripFieldCaption(title: "Leaving from", asked: model.question == .from)
                placeField(title: "City or airport", icon: "airplane.departure", text: $model.form.from, field: .from, need: .from)
                    .accessibilityIdentifier("planner.from")
                TripFieldCaption(title: "Going to", asked: model.question == .to)
                    .padding(.top, 4)
                placeField(title: "City, airport or country", icon: "airplane.arrival", text: $model.form.to, field: .to, need: .to)
                    .accessibilityIdentifier("planner.to")
            }
            Button { model.form.swapPlaces() } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.canvas, in: Circle())
                    .overlay { Circle().strokeBorder(Theme.separator, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityLabel("Swap from and to")
        }
    }

    private func placeField(title: LocalizedStringKey, icon: String, text: Binding<String>, field: Field, need: PlanNeed) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            TextField(title, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: field)
                .foregroundStyle(Theme.ink)
        }
        .doddyField()
        .overlay { TripAskedOutline(isAsked: model.question == need) }
    }

    // MARK: When

    private var whenRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TripFieldCaption(title: "When you leave", asked: model.question == .when)
            Button {
                focus = nil
                pickingWhen = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                    whenText
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .doddyField()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay { TripAskedOutline(isAsked: model.question == .when) }
            .accessibilityIdentifier("planner.when")
        }
    }

    @ViewBuilder private var whenText: some View {
        if let start = model.form.departFrom {
            let end = max(start, model.form.departTo ?? start)
            Text(verbatim: TripPlanText.window(from: start, to: end, polish: polish))
                .foregroundStyle(Theme.ink)
        } else {
            Text("Choose a day")
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Nights

    private var nightsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            TripFieldCaption(title: "Nights there", asked: model.question == .nights)
            TripChipFlow(spacing: 8) {
                nightsChip(title: "Weekend", nights: 2)
                nightsChip(title: "Long weekend", nights: 3)
                nightsChip(title: "A week", nights: 7)
                nightsChip(title: "Two weeks", nights: 14)
            }
            if let nights = model.form.nights {
                Stepper(value: nightsBinding, in: TripPlanForm.nightsRange) {
                    Text(verbatim: TripPlanText.nights(min: model.form.nightsMin ?? nights, max: nights, polish: polish))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityIdentifier("planner.nights")
            }
        }
    }

    private func nightsChip(title: LocalizedStringKey, nights: Int) -> some View {
        DoddyChip(title: title, isSelected: model.form.nightsMin == nights && model.form.nightsMax == nights) {
            model.form.setNights(nights)
        }
    }

    private var nightsBinding: Binding<Int> {
        Binding(get: { model.form.nights ?? 1 }, set: { model.form.setNights($0) })
    }

    // MARK: Who

    private var whoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            TripFieldCaption(title: "Who's going", asked: model.question == .who)
            Stepper(value: $model.form.adults, in: TripPlanForm.adultsRange) {
                Label {
                    Text(verbatim: TripPlanText.adults(model.form.adults, polish: polish))
                } icon: {
                    Image(systemName: "person.fill")
                }
                .foregroundStyle(Theme.ink)
            }
            .accessibilityIdentifier("planner.adults")
            Stepper(value: childrenBinding, in: TripPlanForm.childrenRange) {
                Label {
                    Text(verbatim: TripPlanText.children(model.form.children ?? 0, polish: polish))
                } icon: {
                    Image(systemName: "figure.and.child.holdinghands")
                }
                .foregroundStyle(Theme.ink)
            }
            .accessibilityIdentifier("planner.children")
        }
    }

    private var childrenBinding: Binding<Int> {
        Binding(get: { model.form.children ?? 0 }, set: { model.form.children = $0 })
    }

    // MARK: Extras and budget

    private var extrasRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            TripFieldCaption(title: "Extras")
            TripChipFlow(spacing: 8) {
                DoddyChip(title: "Checked bag", systemImage: "suitcase.rolling", isSelected: model.form.checkedBag == true) {
                    model.form.checkedBag = !(model.form.checkedBag ?? false)
                }
                DoddyChip(title: "Direct only", systemImage: "arrow.right", isSelected: model.form.directOnly == true) {
                    model.form.directOnly = !(model.form.directOnly ?? false)
                }
                DoddyChip(title: "Package holiday", systemImage: "beach.umbrella", isSelected: model.form.package == true) {
                    model.form.package = !(model.form.package ?? false)
                }
            }
            if model.form.package == true {
                DoddyFinePrint(text: Text("Adds a link to package holidays on wakacje.pl with the same dates. Doddy reads no prices there."))
            }
        }
    }

    private var budgetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TripFieldCaption(title: "Budget for the flights (optional)")
            HStack(spacing: 10) {
                Image(systemName: "banknote")
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                TextField("Most you'd pay, all together", text: budgetBinding)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .budget)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("planner.budget")
                Text(verbatim: currencyWord)
                    .foregroundStyle(Theme.secondaryText)
            }
            .doddyField()
        }
    }

    /// The server searches and budgets in PLN.
    private var currencyWord: String { polish ? "zł" : "PLN" }

    private var budgetBinding: Binding<String> {
        Binding(get: { model.form.budget.map { String($0) } ?? "" },
                set: { model.form.budget = TripPlanForm.budget(fromText: $0) })
    }

    // MARK: Search

    private var searchButton: some View {
        Button {
            focus = nil
            Task { await model.search() }
        } label: {
            Label(model.phase == .searching ? "Searching…" : "Search flights and stays", systemImage: "magnifyingglass")
        }
        .buttonStyle(DoddyAccentButtonStyle())
        .disabled(model.isBusy)
        .accessibilityIdentifier("planner.search")
    }

    @ViewBuilder private var assumptionsRow: some View {
        let assumed = model.form.assumptions
        if !assumed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("I'm assuming")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                TripChipFlow(spacing: 6) {
                    ForEach(assumed, id: \.self) { a in
                        TripInfoChip(text: TripPlanText.assumptionShort(a, polish: polish))
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Doddy's question, or the person's own words

struct TripTellCard: View {
    @Bindable var model: TripPlannerModel
    @State private var text = ""
    @FocusState private var focused: Bool
    private let polish = TripsModel.polish

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DoddyIconBadge(systemName: model.question == nil ? "text.bubble.fill" : "questionmark", size: 40)
                heading
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(model.question == nil ? "Where, when, with whom…" : "Your answer…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .foregroundStyle(Theme.ink)
                    .doddyField()
                    .accessibilityIdentifier("planner.field")
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(Theme.inkOnOrange)
                        .frame(width: 50, height: 50)
                        .background(Theme.orangeCue.opacity(canSend ? 1 : 0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("planner.send")
            }
            DoddyFinePrint(text: Text("What you type here goes to Doddy's server and to Anthropic, only to fill in the search above. You can also dictate with the microphone on your keyboard."))
        }
        .doddyCard(padding: 18, accent: model.question != nil)
    }

    @ViewBuilder private var heading: some View {
        if let need = model.question {
            VStack(alignment: .leading, spacing: 4) {
                Text("Doddy asks")
                    .textCase(.uppercase)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: TripPlanText.question(need, polish: polish))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Answer here, or fill it in above.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Or just tell Doddy")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("For example: “Lisbon around 12 February, 4 nights, the two of us, no more than 2000 zł”.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let words = text
        text = ""
        focused = false
        Task { await model.tell(words) }
    }
}

// MARK: - When you leave

struct TripWhenSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let onDone: (TripDay, TripDay) -> Void
    private let today: TripDay
    @State private var day: Date
    @State private var flex: Int
    private let polish = TripsModel.polish

    init(start: TripDay?, end: TripDay?, onDone: @escaping (TripDay, TripDay) -> Void) {
        self.onDone = onDone
        let today = TripsModel.today
        self.today = today
        var center = start ?? today.adding(days: 14)
        var flexDays = 0
        if let start, let end, end > start {
            let half = start.days(to: end) / 2
            center = start.adding(days: half)
            flexDays = half <= 3 ? 3 : 7
        }
        _day = State(initialValue: center.localDate ?? Date())
        _flex = State(initialValue: flexDays)
    }

    private var range: ClosedRange<Date> {
        let first = today.localDate ?? Date()
        let last = today.adding(days: TripPlanForm.daysAhead).localDate ?? first
        return first...max(first, last)
    }

    private var window: (from: TripDay, to: TripDay) {
        TripPlanForm.window(around: TripDay(localDate: day), flexDays: flex, today: today)
    }

    var body: some View {
        NavigationStack {
            DoddyPage {
                DatePicker("Leave on", selection: $day, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .doddyCard(padding: 10)
                VStack(alignment: .leading, spacing: 10) {
                    Text("How flexible?")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    TripChipFlow(spacing: 8) {
                        DoddyChip(title: "Exactly that day", isSelected: flex == 0) { flex = 0 }
                        DoddyChip(title: "± 3 days", isSelected: flex == 3) { flex = 3 }
                        DoddyChip(title: "± 7 days", isSelected: flex == 7) { flex = 7 }
                    }
                    Text(verbatim: TripPlanText.window(from: window.from, to: window.to, polish: polish))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                DoddyFinePrint(text: Text("Kiwi.com looks for flights leaving on any day in this window, up to 330 days ahead."))
            }
            .navigationTitle("When you leave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let chosen = window
                        onDone(chosen.from, chosen.to)
                        dismiss()
                    }
                    .accessibilityIdentifier("planner.when.done")
                }
            }
        }
    }
}

// MARK: - Results

struct TripResultsView: View {
    let plan: PlanResult
    let polish: Bool
    let onResearchStays: (PlanOption) -> Void

    private var people: Int { (plan.brief.adults ?? 1) + (plan.brief.children ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DoddySectionTitle(title: "Flights") {
                Text(verbatim: plan.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            searchedFor
            if plan.options.isEmpty {
                DoddyNotice(text: Text("Kiwi.com found no flights for these days. Try other days or a nearby airport."))
            } else {
                ForEach(plan.options) { option in
                    TripFlightCard(option: option, people: people, polish: polish)
                }
                DoddyFinePrint(text: Text(verbatim: String(
                    format: NSLocalizedString("Prices and times are Kiwi.com's, read %@. They can change before you book; the price shown is for the whole party with the bags counted above.", comment: ""),
                    checkedAt)))
                DoddySectionTitle(title: "Stays")
                    .padding(.top, 6)
                TripStaysCard(plan: plan, polish: polish, onResearch: onResearchStays)
            }
        }
    }

    private var searchedFor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Searched for")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            TripChipFlow(spacing: 6) {
                ForEach(TripPlanText.searched(plan.brief, polish: polish), id: \.self) { words in
                    TripInfoChip(text: words)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var checkedAt: String {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: plan.checkedAt) ?? plain.date(from: plan.checkedAt) else { return plan.checkedAt }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// One flight Kiwi.com returned: its label (only the one code gave it), the real total, both legs, the warnings.
struct TripFlightCard: View {
    let option: PlanOption
    let people: Int
    let polish: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            price
            TripFlightLegView(title: "Outbound", leg: option.outbound, polish: polish)
            if let back = option.inbound {
                Rectangle().fill(Theme.separator).frame(height: 1).accessibilityHidden(true)
                TripFlightLegView(title: "Return", leg: back, polish: polish)
            }
            traps
            if let url = URL(string: option.bookingUrl) {
                Button { openURL(url) } label: {
                    Label("Book on Kiwi.com", systemImage: "arrow.up.right")
                }
                .buttonStyle(DoddyAccentButtonStyle())
                .accessibilityHint("Opens Kiwi.com. You book and pay there.")
            }
        }
        .doddyCard(padding: 18)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TripPickTag(pick: option.pick, polish: polish)
            Spacer(minLength: 8)
            if option.overBudget {
                Label("Over your budget", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.error)
            }
        }
    }

    private var price: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: TripPlanText.money(option, polish: polish))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(verbatim: TripPlanText.party(option, people: people, polish: polish))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var traps: some View {
        if !option.traps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(option.traps, id: \.self) { trap in
                    Label {
                        Text(verbatim: TripPlanText.trap(trap, polish: polish))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.orangeCue)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// "Cheapest", "Fastest", "Easiest": the label the server's code gave this option, on an orange tag.
private struct TripPickTag: View {
    let pick: PlanOption.Pick
    let polish: Bool

    private var icon: String {
        switch pick {
        case .cheapest: "tag.fill"
        case .fastest: "bolt.fill"
        case .easiest: "sofa.fill"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption.weight(.bold)).accessibilityHidden(true)
            Text(verbatim: TripPlanText.pick(pick, polish: polish)).font(.subheadline.weight(.bold))
        }
        .foregroundStyle(Theme.inkOnOrange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.orangeCue, in: Capsule())
    }
}

/// One way: the airport codes big, the local times, how long and how many stops, the airlines.
private struct TripFlightLegView: View {
    let title: LocalizedStringKey
    let leg: PlanLeg
    let polish: Bool

    private var day: String {
        TripDay(String(leg.departs.prefix(10))).map { TripCheckText.day($0, polish: polish) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).textCase(.uppercase).tracking(1.0)
                Text(verbatim: "·")
                Text(verbatim: day)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .center, spacing: 8) {
                endpoint(code: leg.from, city: leg.fromCity, time: TripPlanText.time(leg.departs), shift: 0, leading: true)
                middle
                endpoint(code: leg.to, city: leg.toCity, time: TripPlanText.time(leg.arrives), shift: leg.arrivalDayShift, leading: false)
            }
            if !leg.airlines.isEmpty {
                Label {
                    Text(verbatim: leg.airlines.joined(separator: ", "))
                } icon: {
                    Image(systemName: "airplane.circle")
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TripPlanText.leg(leg, polish: polish) + " · " + TripPlanText.duration(minutes: leg.minutes, polish: polish)))
    }

    private func endpoint(code: String, city: String?, time: String, shift: Int, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: time)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if shift > 0 {
                    Text(verbatim: "+\(shift)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                }
            }
            Text(verbatim: code)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let city {
                Text(verbatim: city)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var middle: some View {
        VStack(spacing: 4) {
            Text(verbatim: TripPlanText.duration(minutes: leg.minutes, polish: polish))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 4) {
                Capsule().fill(Theme.separator).frame(height: 2)
                Image(systemName: "airplane")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orangeCue)
                Capsule().fill(Theme.separator).frame(height: 2)
            }
            .accessibilityHidden(true)
            Text(verbatim: TripPlanText.stops(leg.stops, polish: polish))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stays

/// Stays for the flights' dates: Booking.com and Airbnb with the city, dates and guests filled in (no prices
/// read), wakacje.pl when a package was asked for, and Doddy's background research after a card and a yes.
struct TripStaysCard: View {
    let plan: PlanResult
    let polish: Bool
    let onResearch: (PlanOption) -> Void
    @State private var pick: PlanOption.Pick? = nil
    @Environment(\.openURL) private var openURL

    private var option: PlanOption? { plan.options.first { $0.pick == pick } ?? plan.options.first }

    /// The options land or leave on different days, so the stays' dates depend on which flights.
    private var datesDiffer: Bool {
        Set(plan.options.map { "\($0.checkInDay?.description ?? "")/\($0.checkOutDay?.description ?? "")" }).count > 1
    }

    var body: some View {
        if let option { card(option) }
    }

    private func card(_ o: PlanOption) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                DoddyIconBadge(systemName: "bed.double.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: String(format: NSLocalizedString("Stays in %@", comment: ""), o.outbound.toCity ?? o.outbound.to))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: summary(o))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if datesDiffer { pickRow }
            HStack(spacing: 10) {
                stayLink(title: "Stays on Booking.com", o.links.booking)
                stayLink(title: "Airbnb", o.links.airbnb)
            }
            if let packages = o.links.packages {
                stayLink(title: "Holidays on wakacje.pl", packages)
            }
            DoddyFinePrint(text: Text("The links open with the city, dates and guests filled in. Doddy reads no prices from them."))
            Rectangle().fill(Theme.separator).frame(height: 1).accessibilityHidden(true)
            Button { onResearch(o) } label: {
                HStack(spacing: 12) {
                    DoddyIconBadge(systemName: "text.magnifyingglass", size: 36, filled: false)
                    Text("Have Doddy look at stays")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("planner.stays.research")
            DoddyFinePrint(text: Text("Doddy compares areas and example prices in the background, with sources. You see the exact words first; nothing is booked."))
        }
        .doddyCard(padding: 18)
    }

    private var pickRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dates of which flights?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            TripChipFlow(spacing: 6) {
                ForEach(plan.options) { o in
                    TripPickChip(text: TripPlanText.pick(o.pick, polish: polish), isSelected: o.pick == option?.pick) { pick = o.pick }
                }
            }
        }
    }

    private func summary(_ o: PlanOption) -> String {
        var parts: [String] = []
        if let checkIn = o.checkInDay, let checkOut = o.checkOutDay, checkIn < checkOut {
            parts.append(TripPlanText.window(from: checkIn, to: checkOut, polish: polish))
            let n = checkIn.days(to: checkOut)
            parts.append(TripPlanText.nights(min: n, max: n, polish: polish))
        }
        parts.append(TripPlanText.people(adults: plan.brief.adults ?? 1, children: plan.brief.children ?? 0, polish: polish))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func stayLink(title: LocalizedStringKey, _ address: String) -> some View {
        if let url = URL(string: address) {
            Button { openURL(url) } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Small pieces

/// A field's name over it, with Doddy's orange dot when it is what Doddy asked for.
private struct TripFieldCaption: View {
    let title: LocalizedStringKey
    var asked = false

    var body: some View {
        HStack(spacing: 6) {
            if asked {
                Circle().fill(Theme.orangeCue).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            Text(title)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// The orange outline round the field Doddy asked about (the question card says it in words too).
private struct TripAskedOutline: View {
    let isAsked: Bool

    var body: some View {
        if isAsked {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.orangeCue, lineWidth: 2)
                .accessibilityHidden(true)
        }
    }
}

/// A small chip that only says something (what was searched, what is assumed). Its words are data.
private struct TripInfoChip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.canvas, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 1) }
    }
}

/// `DoddyChip` with words that are data (a label from the server), so they aren't looked up as a key.
private struct TripPickChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.canvas : Theme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(isSelected ? Theme.ink : Theme.canvas, in: Capsule())
                .overlay { if !isSelected { Capsule().strokeBorder(Theme.separator, lineWidth: 1) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Chips that wrap onto the next line (the Trips screen's own copy, so it doesn't depend on another screen's).
struct TripChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: width, height: nil))
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

extension TripDay {
    /// This day at midnight in the iPhone's calendar, for a date picker.
    var localDate: Date? { Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) }

    /// The day a date picker shows, in the iPhone's calendar.
    init(localDate: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: localDate)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }
}
