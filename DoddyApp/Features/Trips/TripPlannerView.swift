import DoddyCore
import SwiftUI

// The trip planner screen (TRAVEL_PLANNER.md): say or type what you want, answer one question at a time,
// get up to three flights with their real total and their traps, and links out. Nothing is booked or paid
// here: "Book on Kiwi.com" opens Kiwi.com, the stays open Booking.com and Airbnb with the dates filled in.

struct TripPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = TripPlannerModel()
    @State private var text = ""
    @State private var stayTask: PlanOption?
    @State private var stayOutcome: String?
    @FocusState private var focused: Bool
    private let polish = TripsModel.polish

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        intro
                        ForEach(model.lines) { line in bubble(line).id(line.id) }
                        if !model.assumptions.isEmpty, model.phase != .asking || !model.lines.isEmpty { assumptionsBox }
                        switch model.phase {
                        case .thinking, .searching:
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(model.phase == .searching ? "Looking for flights on Kiwi.com…" : "Thinking…")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        case let .result(plan):
                            resultView(plan).id("result")
                        case let .problem(message):
                            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.circle") }
                                .font(.subheadline)
                        case .asking:
                            EmptyView()
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.lines) { _, lines in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: model.phase) { _, phase in
                    if case .result = phase { withAnimation { proxy.scrollTo("result", anchor: .top) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Start over") { model.startOver(); text = "" } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Have Doddy look at stays?", isPresented: Binding(get: { stayTask != nil }, set: { if !$0 { stayTask = nil } }), titleVisibility: .visible) {
                Button("Yes, go") {
                    if let option = stayTask { Task { await handOverStays(option) } }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                if let option = stayTask {
                    Text(verbatim: TripPlanText.stayResearchWords(option, adults: model.adults, children: model.children)
                         + "\n\n" + NSLocalizedString("Doddy researches this in the background and the result waits in Tasks and in Messages. Nothing is booked. The words go to Doddy's server and to Anthropic.", comment: ""))
                }
            }
            .alert(Text(verbatim: stayOutcome ?? ""), isPresented: Binding(get: { stayOutcome != nil }, set: { if !$0 { stayOutcome = nil } })) {
                Button("OK") {}
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where, when, with whom and what you'd pay: write it, or dictate it with the microphone on your keyboard.")
                .font(.subheadline)
            Text("For example: “Lisbon around 12 February, 4 nights, the two of us, no more than 2000 zł”.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func bubble(_ line: TripPlannerModel.Line) -> some View {
        HStack {
            if line.who == .person { Spacer(minLength: 40) }
            Text(verbatim: line.text)
                .padding(12)
                .background(line.who == .person ? Theme.quietSurface : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay { if line.who == .doddy { RoundedRectangle(cornerRadius: 14).stroke(Theme.secondaryText.opacity(0.3)) } }
            if line.who == .doddy { Spacer(minLength: 40) }
        }
    }

    private var assumptionsBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("I'm assuming").font(.footnote.weight(.semibold))
            ForEach(model.assumptions, id: \.self) { a in
                Text(verbatim: "· " + TripPlanText.assumption(a, polish: polish)).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Say where you want to go…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityIdentifier("planner.field")
            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("planner.send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func send() {
        let words = text
        text = ""
        Task { await model.send(words) }
    }

    @ViewBuilder private func resultView(_ plan: PlanResult) -> some View {
        if plan.options.isEmpty {
            Label("Kiwi.com found no flights for these days. Try other days or a nearby airport.", systemImage: "airplane.slash")
                .font(.subheadline)
        } else {
            ForEach(plan.options) { option in optionCard(option) }
            Text(verbatim: String(format: NSLocalizedString("Prices and times are Kiwi.com's, read %@. They can change before you book; the price shown is for the whole party with the bags counted above.", comment: ""),
                                  Self.checkedAt(plan.checkedAt, polish: polish)))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func optionCard(_ o: PlanOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: TripPlanText.pick(o.pick, polish: polish)).font(.headline)
                Spacer()
                if o.overBudget { Text("Over your budget").font(.caption.weight(.semibold)).foregroundStyle(.red) }
            }
            Text(verbatim: TripPlanText.price(o, adults: model.adults, polish: polish)).font(.title3.weight(.semibold))
            Text(verbatim: TripPlanText.leg(o.outbound, polish: polish)).font(.subheadline)
            if let back = o.inbound { Text(verbatim: TripPlanText.leg(back, polish: polish)).font(.subheadline) }
            ForEach(o.traps, id: \.self) { trap in
                Label { Text(verbatim: TripPlanText.trap(trap, polish: polish)) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.footnote)
            }
            if let url = URL(string: o.bookingUrl) {
                Button { openURL(url) } label: { Label("Book on Kiwi.com", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                linkButton("Stays on Booking.com", o.links.booking)
                linkButton("Airbnb", o.links.airbnb)
            }
            if let packages = o.links.packages { linkButton("Holidays on wakacje.pl", packages) }
            Button { stayTask = o } label: { Label("Have Doddy look at stays", systemImage: "bed.double") }
                .font(.footnote)
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func linkButton(_ title: LocalizedStringKey, _ address: String) -> some View {
        Group {
            if let url = URL(string: address) {
                Button { openURL(url) } label: { Text(title) }.buttonStyle(.bordered).font(.footnote)
            }
        }
    }

    /// The stays task goes through the same hand-over as the Tasks screen, after the card above showed its words.
    private func handOverStays(_ option: PlanOption) async {
        let draft = ErrandDraft.typed(
            TripPlanText.stayResearchWords(option, adults: model.adults, children: model.children), language: polish ? "pl" : "en")
        switch await ErrandsModel.shared.handOverTyped(draft) {
        case .started, .maybeStarted:
            stayOutcome = NSLocalizedString("Doddy is on it. The result will wait in Tasks and in Messages.", comment: "")
        case .paused:
            stayOutcome = NSLocalizedString("Connections are paused, so nothing was sent.", comment: "")
        case .invalid, .notStarted, .alreadySending:
            stayOutcome = NSLocalizedString("The task couldn't be handed over. Nothing was started.", comment: "")
        }
    }

    private static func checkedAt(_ iso: String, polish: Bool) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: iso) }() else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
