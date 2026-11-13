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
// The look and motion (13 Nov 2026, owner: "graficznie i animacyjnie, kreatywnie, ale … łatwe do ogarnięcia"): the
// tabs are one control whose ink pill slides to the picked tab, with each tab's total under its name
// (`BasketTabPicker`); the content crossfades and moves a few points in the direction of the change, with a light
// selection haptic; rows arrive one after another; the cheapest price and each plan's total carry an orange marker;
// shops are badges and the leaflet's conditions are chips with an icon each (`DealChip`); "Missing" is a dashed note,
// not an error; two shops' saving is one line in Doddy's hand ("You save PLN 3.20 in two shops", `savingsLine`) whose
// marker draws once. Under Reduce Motion nothing slides: the tab changes at once and rows only fade in.

struct BasketTabsView: View {
    let result: DealsResult
    var quantities: [ListQuantity?] = []
    var programs: DealsPrograms = .all
    /// Each item's name as the answer shows it ("mleka · 2 l"), by its place; the query when missing.
    var headers: [String] = []
    /// The user's own minimum for a second shop, in grosze (ADR-664), stored on this iPhone.
    @AppStorage(PreferenceKey.dealsMinimumSaving) private var storedMinimum = 0
    @State private var picked: BasketTabs.Tab?
    /// The last tab change went to a later tab: the new content comes in from the trailing side.
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let language = NotificationLanguage.current
    private static let minimums = [0, 500, 1_000, 2_000, 3_000]

    var body: some View {
        let tabs = BasketTabs.make(result, quantities: quantities, programs: programs, minimumSaving: storedMinimum)
        let today = ShoppingCalendar.today()
        let shown = picked.flatMap { tabs.tabs.contains($0) ? $0 : nil } ?? tabs.firstTab
        VStack(alignment: .leading, spacing: 12) {
            if tabs.tabs.count > 1 {
                BasketTabPicker(tabs: tabs.tabs, shown: shown, totals: totals(tabs)) { tab in
                    select(tab, among: tabs.tabs, from: shown)
                }
                .sensoryFeedback(.selection, trigger: picked)
            }
            ZStack(alignment: .topLeading) {
                content(shown, tabs: tabs, today: today)
                    .id(shown)
                    .transition(contentTransition)
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

    private func select(_ tab: BasketTabs.Tab, among all: [BasketTabs.Tab], from current: BasketTabs.Tab?) {
        guard tab != current else { return }
        let from = current.flatMap { all.firstIndex(of: $0) } ?? 0
        forward = (all.firstIndex(of: tab) ?? 0) >= from
        withAnimation(ShoppingMotion.change(reduceMotion)) { picked = tab }
    }

    /// The new tab's content moves in a few points from the side the picked tab is on, and fades; the old one fades.
    /// Under Reduce Motion the change has no animation at all (`select`), so this never plays.
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = forward ? 28 : -28
        return .asymmetric(insertion: AnyTransition.offset(x: shift).combined(with: .opacity), removal: .opacity)
    }

    /// Each tab's total, from its plan: "41,94 zł", or with the coverage when the plan lacks items ("38,10 zł · 5 of 6").
    private func totals(_ tabs: BasketTabs) -> [BasketTabs.Tab: String] {
        var out: [BasketTabs.Tab: String] = [:]
        for tab in tabs.tabs {
            guard let plan = tabs.plan(for: tab) else { continue }
            let total = PlanRow.totalText(plan, language)
            out[tab] = plan.coversAll ? total : "\(total) · \(plan.coverage(language))"
        }
        return out
    }

    @ViewBuilder
    private func content(_ shown: BasketTabs.Tab?, tabs: BasketTabs, today: DealDay?) -> some View {
        switch shown {
        case .oneShop?: oneShop(tabs, today: today)
        case .twoShops?: twoShops(tabs, today: today)
        case .eachItem?: eachItem(tabs, today: today)
        case nil: EmptyView()
        }
    }

    // MARK: One shop

    @ViewBuilder
    private func oneShop(_ tabs: BasketTabs, today: DealDay?) -> some View {
        if let plan = tabs.oneShop {
            VStack(alignment: .leading, spacing: 12) {
                PlanRow(plan: plan, language: language, today: today)
                    .accessibilityIdentifier("basket.oneShop")
                if let why = noSecondShopText(tabs.noSecondShop) {
                    Label(why, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
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
                gain(tabs, pair: pair)
                PlanRow(plan: pair, language: language, today: today)
                    .accessibilityIdentifier("basket.twoShops")
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

    /// What the second shop gains, first: the saving in Doddy's hand, or more items.
    @ViewBuilder
    private func gain(_ tabs: BasketTabs, pair: BasketPlan) -> some View {
        if let line = tabs.savingsLine(language) {
            SavingsLine(text: line)
        } else if case .moreItems? = tabs.secondShopGain, let single = tabs.oneShop {
            Text(String(format: NSLocalizedString("Two shops have %@ items; one shop has %@.", comment: "two coverages such as 3 of 3"),
                        pair.coverage(language), single.coverage(language)))
                .font(Theme.hand(.body)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
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

    private func eachItem(_ tabs: BasketTabs, today: DealDay?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let all = tabs.everything, tabs.eachItem.count > 1 {
                EverythingHeader(plan: all, language: language)
            }
            VStack(spacing: 0) {
                ForEach(Array(tabs.eachItem.enumerated()), id: \.element.itemIndex) { position, row in
                    VStack(spacing: 0) {
                        if position > 0 { Divider().overlay(Theme.separator) }
                        NavigationLink(value: DealsItemPage(index: row.itemIndex)) {
                            EachItemRow(row: row, header: header(row), emptyWords: emptyWords(row), language: language, today: today)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(sentence(row, today: today)))
                        .accessibilityIdentifier("deals.item.\(row.itemIndex)")
                    }
                    .arrivesInOrder(position)
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
    }

    private func header(_ row: BasketTabs.ItemRow) -> String {
        row.itemIndex < headers.count ? headers[row.itemIndex] : row.query
    }

    /// What a row with no counted price says instead: a promotion without a price, only prices that aren't counted, or
    /// nothing in the leaflets that were read.
    private func emptyWords(_ row: BasketTabs.ItemRow) -> String {
        let item = row.itemIndex < result.items.count ? result.items[row.itemIndex] : nil
        if let item, !item.promotions.isEmpty {
            return NSLocalizedString("A promotion without a printed price", comment: "")
        }
        if let item, !item.offers.isEmpty {
            return NSLocalizedString("Only prices that aren't counted here. Tap for details.", comment: "")
        }
        return NSLocalizedString("Not in the leaflets that were read.", comment: "")
    }

    /// A row for VoiceOver in one sentence: "masło: cheapest at Biedronka, 4,99 zł. For 2. Masło Extra 200 g. With the
    /// Moja Biedronka app, until Sat 15 Nov. Other shops: Lidl 5,49 zł."
    private func sentence(_ row: BasketTabs.ItemRow, today: DealDay?) -> String {
        let name = header(row)
        guard let line = row.cheapest else { return "\(name). \(emptyWords(row))" }
        var parts = [String(format: NSLocalizedString("%@: cheapest at %@, %@.", comment: "an item, a shop, the price for the quantity asked"),
                            name, line.chain.name, PlanRow.lineText(line, language))]
        if line.quantity > 1 {
            parts.append(String(format: NSLocalizedString("For %lld.", comment: "how many pieces a price is for"), line.quantity))
        }
        parts.append("\(line.offer.product).")
        if line.needsChecking { parts.append(NSLocalizedString("Check the leaflet", comment: "") + ".") }
        let chips = DealChip.chips(for: line.offer, today: today).map { DealChipView.words($0) }
        if !chips.isEmpty { parts.append(chips.joined(separator: ", ") + ".") }
        if let others = row.othersText(language) {
            parts.append(String(format: NSLocalizedString("Other shops: %@", comment: "other shops' prices for one item, in one line"), others))
        }
        return parts.joined(separator: " ")
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

// MARK: - Parts

/// Two shops' saving in one line, in Doddy's hand, with an orange marker that draws once under it and an arrow that
/// bounces once. The amount is `BasketTabs.savingsLine`'s, from the solver. Under Reduce Motion both are still.
private struct SavingsLine: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var noticed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.orangeCue)
                .symbolEffect(.bounce, value: noticed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                PriceMark(text: text, font: Theme.hand(.title3), delay: 0.25, alignment: .leading)
                Text("Compared with one shop. Worth it if you pass both anyway.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("basket.savings")
        .task {
            guard !reduceMotion, !noticed else { return }
            try? await Task.sleep(for: .milliseconds(350))
            noticed = true
        }
    }
}

/// "Everything at its cheapest": the total, marked, and the shops that takes, as badges.
private struct EverythingHeader: View {
    let plan: BasketPlan
    let language: NotificationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Everything at its cheapest").font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                PriceMark(text: PlanRow.totalText(plan, language))
                    .layoutPriority(1)
            }
            ChipFlow(spacing: 6) {
                ForEach(Array(plan.chains.enumerated()), id: \.offset) { index, chain in
                    ShopBadge(name: chain.name, style: index == 0 ? 0 : 1)
                }
            }
            Text(String(format: NSLocalizedString("%@ items", comment: "a coverage such as 5 of 6"), plan.coverage(language)))
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("basket.everything")
    }
}

/// One item of "Each item separately": its name and cheapest price, the product, the shop and the leaflet's conditions
/// as chips, and the other shops in one line. At accessibility text sizes the price goes under the name.
private struct EachItemRow: View {
    let row: BasketTabs.ItemRow
    let header: String
    let emptyWords: String
    let language: NotificationLanguage
    let today: DealDay?
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                nameAndPrice
                details
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private var nameAndPrice: some View {
        let large = textSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                           : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(verbatim: header).font(.headline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !large { Spacer(minLength: 8) }
            if let line = row.cheapest {
                VStack(alignment: large ? .leading : .trailing, spacing: 2) {
                    PriceMark(text: PlanRow.lineText(line, language), alignment: large ? .leading : .trailing)
                    if line.quantity > 1 {
                        Text(verbatim: "×\(line.quantity)").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                .layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        if let line = row.cheapest {
            Text(verbatim: line.offer.product).font(.footnote).foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            ChipFlow(spacing: 6) {
                ShopBadge(name: line.chain.name)
                if line.needsChecking {
                    ShoppingChip(text: NSLocalizedString("Check the leaflet", comment: ""), symbol: "exclamationmark.circle", tint: Theme.error)
                }
                ForEach(Array(DealChip.chips(for: line.offer, today: today).enumerated()), id: \.offset) { _, chip in
                    DealChipView(chip: chip)
                }
            }
            if let others = row.othersText(language) {
                Text(String(format: NSLocalizedString("Other shops: %@", comment: "other shops' prices for one item, in one line"), others))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(verbatim: emptyWords).font(.footnote).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One plan: the shops as badges and the marked total, how many items it covers, each line with its shop (in a pair),
/// its conditions as chips and its notes, and what it lacks.
private struct PlanRow: View {
    let plan: BasketPlan
    let language: NotificationLanguage
    var today: DealDay?
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(String(format: NSLocalizedString("%@ items", comment: "a coverage such as 5 of 6"), plan.coverage(language)))
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Divider().overlay(Theme.separator)
            ForEach(Array(plan.lines.enumerated()), id: \.offset) { index, line in
                PlanLineRow(line: line, shopStyle: style(of: line.chain), showsShop: plan.chains.count > 1,
                            language: language, today: today)
                    .arrivesInOrder(index)
            }
            if !plan.missing.isEmpty {
                MissingNote(items: plan.missing)
            }
            if plan.needsChecking {
                Label("Some prices couldn't be confirmed by Doddy. Check the leaflet.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        let large = textSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                           : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            ChipFlow(spacing: 6) {
                ForEach(Array(plan.chains.enumerated()), id: \.offset) { index, chain in
                    ShopBadge(name: chain.name, style: index == 0 ? 0 : 1, large: true)
                }
            }
            PriceMark(text: Self.totalText(plan, language), font: .title2.weight(.heavy), alignment: large ? .leading : .trailing)
                .layoutPriority(1)
        }
    }

    /// The first shop of a plan is the orange badge, the second the outlined one.
    private func style(of chain: DealsChain) -> Int {
        (plan.chains.firstIndex(of: chain) ?? 0) == 0 ? 0 : 1
    }

    /// "at least 41,94 zł" when a price beyond a limit isn't printed.
    static func totalText(_ plan: BasketPlan, _ language: NotificationLanguage) -> String {
        plan.totalIsLowerBound
            ? String(format: NSLocalizedString("at least %@", comment: "a basket total"), plan.total.text(language))
            : plan.total.text(language)
    }

    /// One line's total, "at least" when the price beyond a limit isn't printed.
    static func lineText(_ line: BasketPlan.Line, _ language: NotificationLanguage) -> String {
        line.cost.isLowerBound
            ? String(format: NSLocalizedString("at least %@", comment: "a basket total"), line.total.text(language))
            : line.total.text(language)
    }
}

/// One line of a plan: the item and how many, its total, its shop's badge in a pair, its conditions as chips (the
/// days are in "Before you go"), and what its price needs.
private struct PlanLineRow: View {
    let line: BasketPlan.Line
    let shopStyle: Int
    let showsShop: Bool
    let language: NotificationLanguage
    let today: DealDay?

    var body: some View {
        let chips = DealChip.chips(for: line.offer, today: today).filter { !$0.isDay }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: line.quantity > 1 ? "\(line.query) ×\(line.quantity)" : line.query)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: PlanRow.lineText(line, language))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .font(.subheadline)
            if showsShop || !chips.isEmpty {
                ChipFlow(spacing: 6) {
                    if showsShop {
                        ShopBadge(name: line.chain.name, style: shopStyle)
                    }
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        DealChipView(chip: chip)
                    }
                }
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Text(note).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notes: [String] {
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
                Label("Before you go", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if sections.count > 1 {
                        Text(section.chain.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                            .padding(.top, 2)
                    }
                    ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                        Label {
                            Text(ChecklistText.text(entry)).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.orangeCue)
                        }
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
