import DoddyCore
import SwiftUI

// The basket (docs/implementation/SHOPPING.md 3): from this week's leaflet answer, the cheapest single
// shop, the cheapest pair of shops and every item at its cheapest, each with how many of the items it
// covers. The sums are BasketSolver's (DoddyCore, integer grosze), not a model's. Doddy says how much
// the second shop saves and leaves the choice to the user; it never pushes a detour. The lists go out
// as plain text through the share sheet; nothing is written anywhere by this screen.

struct BasketView: View {
    let result: DealsResult
    private let language = NotificationLanguage.current

    var body: some View {
        let basket = BasketSolver.solve(result)
        Form {
            if let single = basket.bestSingleChain {
                Section("One shop") { PlanRow(plan: single, language: language) }
            }
            if let pair = basket.bestPair, pair.chains.count == 2 {
                Section("Two shops") {
                    PlanRow(plan: pair, language: language)
                    if let savings = basket.savings, savings.minor > 0 {
                        Text(String(format: NSLocalizedString("Saves %@ against one shop. Worth it if you pass both anyway.", comment: ""), savings.text(language)))
                            .font(Theme.hand(.body)).foregroundStyle(Theme.ink)
                    }
                    ShareLink(item: listsText(pair)) {
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
            }
        }
        .navigationTitle("Basket")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One list per shop, as plain text, for Notes, Messages or Doddy's lists.
    private func listsText(_ plan: BasketPlan) -> String {
        plan.chains.map { chain in
            let lines = plan.lines.filter { $0.chain == chain }.map { line in
                let conditions = line.conditions.isEmpty ? "" : " (\(line.conditions.joined(separator: ", ")))"
                return "– \(line.query): \(line.offer.product), \(line.offer.price.text(language))\(conditions)"
            }
            return ([chain.name] + lines).joined(separator: "\n")
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
                Text(plan.total.text(language)).font(.title2.weight(.heavy)).foregroundStyle(Theme.ink)
            }
            Text(plan.coverage(language)).font(.footnote).foregroundStyle(plan.coversAll ? Theme.secondaryText : Theme.error)
            ForEach(Array(plan.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.query).foregroundStyle(Theme.ink)
                    if plan.chains.count > 1 {
                        Text(line.chain.name).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Text(line.offer.price.text(language)).foregroundStyle(Theme.ink)
                }
                .font(.subheadline)
                if !line.conditions.isEmpty {
                    Text(line.conditions.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.accentText)
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
}
