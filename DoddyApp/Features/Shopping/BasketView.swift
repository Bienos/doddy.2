import DoddyCore
import SwiftUI

// The basket (docs/implementation/SHOPPING.md 3): from this week's leaflet answer, the cheapest single
// shop, the cheapest pair of shops and every item at its cheapest, each with how many of the items it
// covers. The sums are BasketSolver's (DoddyCore, integer grosze), not a model's. Doddy says how much
// the second shop saves and leaves the choice to the user; it never pushes a detour. The lists go out
// as plain text through the share sheet; nothing is written anywhere by this screen.
// Since ADR-661: each line is costed for the quantity in the user's words (a "2+1" in whole groups,
// a price "from 2 pieces" counted at 2, the rest beyond a limit at the regular price), prices that
// need an app the user doesn't use aren't counted, and "Before you go" lists what the till needs:
// the app or card, how many to take, the limit, the deposit, the days (trading Sundays and holidays).

struct BasketView: View {
    let result: DealsResult
    var quantities: [ListQuantity?] = []
    var programs: DealsPrograms = .all
    private let language = NotificationLanguage.current

    var body: some View {
        let basket = BasketSolver.solve(result, quantities: quantities, programs: programs)
        let today = ShoppingCalendar.today()
        Form {
            if let single = basket.bestSingleChain {
                Section("One shop") {
                    PlanRow(plan: single, language: language)
                    ChecklistRows(sections: DealsChecklist.sections(single, today: today))
                    ShareLink(item: listsText(single, today: today)) {
                        Label("Share the list", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if let pair = basket.bestPair, pair.chains.count == 2 {
                Section("Two shops") {
                    PlanRow(plan: pair, language: language)
                    if let savings = basket.savings, savings.minor > 0 {
                        Text(String(format: NSLocalizedString("Saves %@ against one shop. Worth it if you pass both anyway.", comment: ""), savings.text(language)))
                            .font(Theme.hand(.body)).foregroundStyle(Theme.ink)
                    }
                    ChecklistRows(sections: DealsChecklist.sections(pair, today: today))
                    ShareLink(item: listsText(pair, today: today)) {
                        Label("Share the two lists", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("basket.share")
                }
            }
            if let all = basket.everythingCheapest, all.chains.count > 2 {
                Section("Everything at its cheapest") { PlanRow(plan: all, language: language) }
            }
            Section {
                Text("The sums are added up by the app from the leaflet prices, not by an AI. Conditions such as the shop's app or a minimum quantity are listed with each item.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                if !programs.notUsed.isEmpty {
                    Text(String(format: NSLocalizedString("Not counted: prices that need %@.", comment: "loyalty apps the user doesn't use"),
                                programs.notUsed.map(\.name).sorted().joined(separator: ", ")))
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .navigationTitle("Basket")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One list per shop, as plain text, for Notes, Reminders, Messages or Doddy's lists, with what
    /// to remember at the till.
    private func listsText(_ plan: BasketPlan, today: DealDay?) -> String {
        let notes = DealsChecklist.sections(plan, today: today)
        return plan.chains.map { chain in
            let lines = plan.lines.filter { $0.chain == chain }.map { line in
                let count = line.quantity > 1 ? " ×\(line.quantity)" : ""
                let conditions = line.conditions.isEmpty ? "" : " (\(line.conditions.joined(separator: ", ")))"
                return "– \(line.query)\(count): \(line.offer.product), \(line.total.text(language))\(conditions)"
            }
            let before = (notes.first { $0.chain == chain }?.entries ?? []).map { "☐ " + ChecklistText.text($0) }
            return ([chain.name] + lines + before).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

private struct PlanRow: View {
    let plan: BasketPlan
    let language: NotificationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.chains.map(\.name).joined(separator: " + ")).font(.headline).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(totalText).font(.title2.weight(.heavy)).foregroundStyle(Theme.ink)
            }
            Text(plan.coverage(language)).font(.footnote).foregroundStyle(plan.coversAll ? Theme.secondaryText : Theme.error)
            ForEach(Array(plan.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.quantity > 1 ? "\(line.query) ×\(line.quantity)" : line.query).foregroundStyle(Theme.ink)
                    if plan.chains.count > 1 {
                        Text(line.chain.name).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Text(line.total.text(language)).foregroundStyle(Theme.ink)
                }
                .font(.subheadline)
                if !line.conditions.isEmpty {
                    Text(line.conditions.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.accentText)
                }
                ForEach(Array(notes(line).enumerated()), id: \.offset) { _, note in
                    Text(note).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            if !plan.missing.isEmpty {
                Text(String(format: NSLocalizedString("Not in these leaflets: %@", comment: ""), plan.missing.joined(separator: ", ")))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if plan.needsChecking {
                Label("Some prices couldn't be confirmed by Doddy. Check the leaflet.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Theme.error)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "at least 41,94 zł" when a price beyond a limit isn't printed.
    private var totalText: String {
        plan.lines.contains { $0.cost.isLowerBound }
            ? String(format: NSLocalizedString("at least %@", comment: "a basket total"), plan.total.text(language))
            : plan.total.text(language)
    }

    private func notes(_ line: BasketPlan.Line) -> [String] {
        line.cost.notes.compactMap { note -> String? in
            switch note {
            case .groups: nil
            case .takeMore(let to):
                String(format: NSLocalizedString("Take %lld: it costs no more.", comment: "a multi-buy such as 2+1"), to)
            case .raisedToMinimum(let n):
                String(format: NSLocalizedString("The price is for at least %lld, so %lld are counted.", comment: ""), n, n)
            case .overLimit(let n):
                String(format: NSLocalizedString("At most %lld at this price; the rest at the regular price.", comment: ""), n)
            case .overLimitUnpriced(let n):
                String(format: NSLocalizedString("At most %lld at this price, and the leaflet doesn't say what the rest cost.", comment: ""), n)
            }
        }
    }
}

/// "Before you go": per shop, what the till needs.
private struct ChecklistRows: View {
    let sections: [DealsChecklistSection]

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before you go").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if sections.count > 1 {
                        Text(section.chain.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                    ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                        Label(ChecklistText.text(entry), systemImage: "checklist")
                            .font(.footnote).foregroundStyle(Theme.ink)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("basket.checklist")
        }
    }
}

/// The checklist's words (the entries are code's; the app words them in the user's language).
enum ChecklistText {
    static func text(_ entry: DealsChecklistEntry) -> String {
        let what = body(entry.kind)
        guard let product = entry.product else { return what }
        return String(format: NSLocalizedString("%@: %@", comment: "a product and what to remember for it"), product, what)
    }

    private static func body(_ kind: DealsChecklistEntry.Kind) -> String {
        switch kind {
        case .openApp(let program):
            program.map { String(format: NSLocalizedString("Open %@: activate its coupons and scan it at the till.", comment: "a loyalty app"), $0.name) }
                ?? NSLocalizedString("Open the shop's app: activate its coupons and scan it at the till.", comment: "")
        case .showCard(let program):
            program.map { String(format: NSLocalizedString("Show the %@ card.", comment: "a loyalty card"), $0.name) }
                ?? NSLocalizedString("Show the shop's loyalty card.", comment: "")
        case .take(let n): String(format: NSLocalizedString("take %lld to get the offer", comment: ""), n)
        case .atMost(let n): String(format: NSLocalizedString("at most %lld per customer", comment: ""), n)
        case .deposit: NSLocalizedString("a deposit is added at the till", comment: "")
        case .whileStocksLast: NSLocalizedString("while stocks last", comment: "")
        case .selectedStores: NSLocalizedString("only in some shops: check yours", comment: "")
        case .startsOn(let day): String(format: NSLocalizedString("not on until %@", comment: ""), DealDayText.text(day))
        case .lastDay: NSLocalizedString("today is the last day", comment: "")
        case .lastOpenDay(let day): String(format: NSLocalizedString("shops are closed on its last day: buy by %@", comment: ""), DealDayText.text(day))
        case .closedToday: NSLocalizedString("Most of its shops are closed today.", comment: "a closed Sunday or holiday")
        case .closesEarlyToday(let hour): String(format: NSLocalizedString("Its shops close at %lld:00 today.", comment: ""), hour)
        }
    }
}
