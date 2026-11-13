import DoddyCore
import SwiftUI

// Where to go with the list (docs/implementation/SHOPPING.md 3; decision 2026-11-13-shopping-one-field): the
// leaflet answer as three tabs, all from `BasketTabs` (DoddyCore), which takes every sum from `BasketSolver`, in
// integer grosze, not from a model.
//   - One shop: where most items cost least, its total, what it lacks, "Before you go" and the list to share.
//   - Two shops: only when the pair covers more items or saves at least the person's own minimum (ADR-664), with what
//     it saves and both lists. With no pair, the one-shop tab says why.
//   - Each item separately: item → cheapest shop → price, the other shops in one line under it; a tap opens the
//     item's card (DealsView) with every offer, its conditions and its last day.
// One item has nothing to choose between, so it is shown as its row only. Doddy says how much the second shop saves
// and leaves the choice to the user; it never pushes a detour. The lists go out as plain text through the share
// sheet; nothing is written anywhere by this view. Since ADR-661 each line is costed for the quantity in the user's
// words, prices that need an app the user doesn't use aren't counted, and "Before you go" lists what the till needs:
// the app or card, how many to take, the limit, the deposit, the days (trading Sundays and holidays).
// Until 13 Nov 2026 the shops were a separate "Basket" screen behind a button, and the answer listed each item's
// best value per kg; that pick and its reason are on the item's card now.

struct BasketTabsView: View {
    let result: DealsResult
    var quantities: [ListQuantity?] = []
    var programs: DealsPrograms = .all
    /// Each item's name as the answer shows it ("mleka · 2 l"), by its place; the query when missing.
    var headers: [String] = []
    /// The user's own minimum for a second shop, in grosze (ADR-664), stored on this iPhone.
    @AppStorage(PreferenceKey.dealsMinimumSaving) private var storedMinimum = 0
    @State private var picked: BasketTabs.Tab?
    private let language = NotificationLanguage.current
    private static let minimums = [0, 500, 1_000, 2_000, 3_000]

    var body: some View {
        let tabs = BasketTabs.make(result, quantities: quantities, programs: programs, minimumSaving: storedMinimum)
        let today = ShoppingCalendar.today()
        let shown = picked.flatMap { tabs.tabs.contains($0) ? $0 : nil } ?? tabs.firstTab
        VStack(alignment: .leading, spacing: 12) {
            if tabs.tabs.count > 1 {
                tabPicker(tabs.tabs, shown: shown)
            }
            switch shown {
            case .oneShop?: oneShop(tabs, today: today)
            case .twoShops?: twoShops(tabs, today: today)
            case .eachItem?: eachItem(tabs)
            case nil: EmptyView()
            }
            if tabs.oneShop != nil, result.items.count > 1 {
                minimumPicker
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("The sums are added up by the app from the leaflet prices, not by an AI. Conditions such as the shop's app or a minimum quantity are listed with each item.")
                if !programs.notUsed.isEmpty {
                    Text(String(format: NSLocalizedString("Not counted: prices that need %@.", comment: "loyalty apps the user doesn't use"),
                                programs.notUsed.map(\.name).sorted().joined(separator: ", ")))
                }
            }
            .font(.footnote).foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The tabs

    /// Chips that wrap, so the three names fit at any text size (a segmented control cuts them).
    private func tabPicker(_ tabs: [BasketTabs.Tab], shown: BasketTabs.Tab?) -> some View {
        ChipFlow(spacing: 8) {
            ForEach(tabs, id: \.self) { tab in
                let on = tab == shown
                Button { picked = tab } label: {
                    title(tab)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(minHeight: 36)
                        .foregroundStyle(on ? Theme.inkOnOrange : Theme.ink)
                        .background(Capsule().fill(on ? Theme.orangeCue : Theme.canvas))
                        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: on ? 0 : 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("deals.tab.\(tab.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func title(_ tab: BasketTabs.Tab) -> some View {
        switch tab {
        case .oneShop: Text("One shop")
        case .twoShops: Text("Two shops")
        case .eachItem: Text("Each item separately")
        }
    }

    // MARK: One shop

    @ViewBuilder
    private func oneShop(_ tabs: BasketTabs, today: DealDay?) -> some View {
        if let plan = tabs.oneShop {
            VStack(alignment: .leading, spacing: 12) {
                PlanRow(plan: plan, language: language)
                    .accessibilityIdentifier("basket.oneShop")
                if let why = noSecondShopText(tabs.noSecondShop) {
                    Text(why).font(.footnote).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ChecklistRows(sections: DealsChecklist.sections(plan, today: today))
                ShareLink(item: listsText(plan, today: today)) {
                    Label("Share the list", systemImage: "square.and.arrow.up")
                }
                .font(.subheadline.weight(.semibold))
            }
            .tasksCard()
        }
    }

    private func noSecondShopText(_ reason: BasketTabs.NoSecondShop?) -> String? {
        switch reason {
        case .savesNothing?:
            NSLocalizedString("A second shop wouldn't save anything on these items.", comment: "why the answer has no two-shop tab")
        case .savesTooLittle(let saving, let minimum)?:
            String(format: NSLocalizedString("A second shop would save %@, less than your minimum of %@.", comment: "a saving, the user's minimum"),
                   saving.text(language), minimum.text(language))
        case nil:
            nil
        }
    }

    // MARK: Two shops

    @ViewBuilder
    private func twoShops(_ tabs: BasketTabs, today: DealDay?) -> some View {
        if let pair = tabs.twoShops {
            VStack(alignment: .leading, spacing: 12) {
                PlanRow(plan: pair, language: language)
                    .accessibilityIdentifier("basket.twoShops")
                if let savings = tabs.savings, savings.minor > 0 {
                    Text(String(format: NSLocalizedString("Saves %@ against one shop. Worth it if you pass both anyway.", comment: ""), savings.text(language)))
                        .font(Theme.hand(.body)).foregroundStyle(Theme.ink)
                } else if let single = tabs.oneShop, pair.covered > single.covered {
                    Text(String(format: NSLocalizedString("Two shops have %@ items; one shop has %@.", comment: "two coverages such as 3 of 3"),
                                pair.coverage(language), single.coverage(language)))
                        .font(Theme.hand(.body)).foregroundStyle(Theme.ink)
                }
                ChecklistRows(sections: DealsChecklist.sections(pair, today: today))
                ShareLink(item: listsText(pair, today: today)) {
                    Label("Share the two lists", systemImage: "square.and.arrow.up")
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("basket.share")
            }
            .tasksCard()
        }
    }

    /// The person's own minimum for a second shop: shown under every tab, so it can be lowered when no pair is shown.
    private var minimumPicker: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("A second shop only when it saves at least")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Picker("A second shop only when it saves at least", selection: $storedMinimum) {
                ForEach(Self.minimums, id: \.self) { minor in
                    Text(minor == 0 ? NSLocalizedString("Any saving", comment: "") : Money(minor: minor).text(language)).tag(minor)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.accentText)
            .accessibilityIdentifier("basket.minimumSaving")
        }
    }

    // MARK: Each item separately

    private func eachItem(_ tabs: BasketTabs) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let all = tabs.everything, tabs.eachItem.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Everything at its cheapest").font(.headline)
                        Spacer(minLength: 8)
                        Text(verbatim: PlanRow.totalText(all, language)).font(.title3.weight(.heavy))
                    }
                    Text(verbatim: "\(all.chains.map(\.name).joined(separator: " + ")) · \(all.coverage(language))")
                        .font(.footnote).foregroundStyle(all.coversAll ? Theme.secondaryText : Theme.error)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("basket.everything")
            }
            VStack(spacing: 0) {
                ForEach(Array(tabs.eachItem.enumerated()), id: \.element.itemIndex) { position, row in
                    if position > 0 { Divider().overlay(Theme.separator) }
                    NavigationLink(value: DealsItemPage(index: row.itemIndex)) {
                        itemRow(row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deals.item.\(row.itemIndex)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
    }

    /// One item: its name, the cheapest line's product, shop and condition, the other shops in one line, the price.
    private func itemRow(_ row: BasketTabs.ItemRow) -> some View {
        let item = row.itemIndex < result.items.count ? result.items[row.itemIndex] : nil
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: header(row)).font(.headline)
                if let line = row.cheapest {
                    Text(verbatim: line.offer.product).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(verbatim: line.chain.name)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.orangeCue.opacity(0.18)))
                        if line.needsChecking {
                            Text("Check the leaflet").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
                        } else if !line.conditions.isEmpty {
                            Text(verbatim: line.conditions.joined(separator: " · "))
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText).lineLimit(1)
                        }
                    }
                    if let others = row.othersText(language) {
                        Text(String(format: NSLocalizedString("Other shops: %@", comment: "other shops' prices for one item, in one line"), others))
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let item, !item.promotions.isEmpty {
                    Text("A promotion without a printed price").font(.footnote).foregroundStyle(Theme.secondaryText)
                } else if let item, !item.offers.isEmpty {
                    Text("Only prices that aren't counted here. Tap for details.").font(.footnote).foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Not in the leaflets that were read.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if let line = row.cheapest {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: PlanRow.lineText(line, language)).font(.title3.weight(.heavy))
                    if line.quantity > 1 {
                        Text(verbatim: "×\(line.quantity)").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func header(_ row: BasketTabs.ItemRow) -> String {
        row.itemIndex < headers.count ? headers[row.itemIndex] : row.query
    }

    // MARK: Sharing

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

/// One plan: the shops, the total, how many items it covers, each line with its conditions and notes, and what it lacks.
private struct PlanRow: View {
    let plan: BasketPlan
    let language: NotificationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.chains.map(\.name).joined(separator: " + ")).font(.headline).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(Self.totalText(plan, language)).font(.title2.weight(.heavy)).foregroundStyle(Theme.ink)
            }
            Text(plan.coverage(language)).font(.footnote).foregroundStyle(plan.coversAll ? Theme.secondaryText : Theme.error)
            ForEach(Array(plan.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: line.quantity > 1 ? "\(line.query) ×\(line.quantity)" : line.query).foregroundStyle(Theme.ink)
                    if plan.chains.count > 1 {
                        Text(line.chain.name).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Text(Self.lineText(line, language)).foregroundStyle(Theme.ink)
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
                Text(String(format: NSLocalizedString("Missing: %@", comment: "items no shop in this plan has"), plan.missing.joined(separator: ", ")))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.error)
            }
            if plan.needsChecking {
                Label("Some prices couldn't be confirmed by Doddy. Check the leaflet.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Theme.error)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "at least 41,94 zł" when a price beyond a limit isn't printed.
    static func totalText(_ plan: BasketPlan, _ language: NotificationLanguage) -> String {
        plan.lines.contains { $0.cost.isLowerBound }
            ? String(format: NSLocalizedString("at least %@", comment: "a basket total"), plan.total.text(language))
            : plan.total.text(language)
    }

    /// One line's total, "at least" when the price beyond a limit isn't printed.
    static func lineText(_ line: BasketPlan.Line, _ language: NotificationLanguage) -> String {
        line.cost.isLowerBound
            ? String(format: NSLocalizedString("at least %@", comment: "a basket total"), line.total.text(language))
            : line.total.text(language)
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
