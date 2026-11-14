import DoddyCore
import SwiftUI

// Price alerts (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision 2026-11-14-price-alerts-screen).
// A sheet over Shopping: what the server keeps for this account (one card per alert: the words, the price, the shops, when
// it ends, what it found, when it was last checked), a way to add one (`PriceAlertForm`) and to see what an alert matches in
// the leaflets now (`PriceAlertMatchesView`). Every line is from `DealWatchWords` (DoddyCore, tested in both languages)
// and every fact is what the server last said: nothing is shown as saved, found or deleted on the app's own say-so. An alert
// only tells; nothing here buys anything. The Shopping row that opens this screen appears only once the server has said price
// alerts are on (`PriceAlertsModel.availability`), so while they are off nothing about them is on screen.
// Motion follows `ShoppingMotion`: cards arrive once, one after another; the bell bounces once when an alert is saved;
// nothing loops, and under Reduce Motion nothing moves.

// MARK: The row on the Shopping screen

/// "Price alerts" on Shopping: shown only while the server keeps them (`availability == .available`).
struct PriceAlertsRow: View {
    let action: () -> Void
    private let model = PriceAlertsModel.shared
    private let language = NotificationLanguage.current

    private var newOffers: Int { model.watches.reduce(0) { $0 + $1.found } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DoddySymbolTile(systemImage: "bell.badge")
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: DealWatchWords.title(language))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: DealWatchWords.rowSubtitle(language))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if newOffers > 0 {
                        DoddyTag(text: DealWatchWords.offersCount(newOffers, language), systemImage: "bell.fill", strong: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .doddyCard(padding: 14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DoddyTapStyle())
        .accessibilityIdentifier("shopping.priceAlerts.row")
    }
}

// MARK: The screen

struct PriceAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    private let model = PriceAlertsModel.shared
    private let language = NotificationLanguage.current
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var toDelete: DealWatch?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introCard
                    if let problem = model.loadProblem {
                        Label { Text(verbatim: problem) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(Theme.error)
                            .doddyCard(padding: 14)
                            .accessibilityIdentifier("priceAlerts.loadProblem")
                    }
                    if let message = model.message {
                        Label { Text(verbatim: message) } icon: { Image(systemName: "info.circle") }
                            .foregroundStyle(Theme.ink)
                            .doddyCard(padding: 14)
                            .accessibilityIdentifier("priceAlerts.message")
                    }
                    alerts
                    Button { adding = true } label: {
                        Label { Text(verbatim: DealWatchWords.add(language)) } icon: { Image(systemName: "plus") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("priceAlerts.add")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .readableColumn()
            }
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationTitle(DealWatchWords.title(language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(DealWatchWords.done(language)) { dismiss() } }
            }
            .sheet(isPresented: $adding) { PriceAlertForm() }
            .confirmationDialog(DealWatchWords.deleteAsk(language), isPresented: $confirmDelete, titleVisibility: .visible, presenting: toDelete) { watch in
                Button(DealWatchWords.delete(language), role: .destructive) {
                    Task { await model.delete(watch) }
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
        .accessibilityIdentifier("shopping.priceAlerts")
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            BellTile(rings: false)
            Text(verbatim: DealWatchWords.intro(language))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard(padding: 14)
    }

    @ViewBuilder private var alerts: some View {
        if !model.hasLoaded {
            HStack(spacing: 10) {
                ProgressView()
                Text(verbatim: DealWatchWords.loading(language)).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        } else if model.watches.isEmpty && model.loadProblem == nil {
            Text(verbatim: DealWatchWords.empty(language))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("priceAlerts.empty")
        } else {
            ForEach(Array(model.watches.enumerated()), id: \.element.id) { index, watch in
                PriceAlertCard(watch: watch, language: language, busy: model.busy.contains(watch.id)) {
                    toDelete = watch
                    confirmDelete = true
                }
                .arrivesInOrder(index)
            }
        }
    }
}

// MARK: One alert

private struct PriceAlertCard: View {
    let watch: DealWatch
    let language: NotificationLanguage
    let busy: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: watch.item)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                DoddyTag(text: DealWatchWords.priceLine(watch, language), systemImage: "tag")
                if watch.found > 0 {
                    DoddyTag(text: DealWatchWords.foundLine(watch, language), systemImage: "bell.fill", strong: true)
                }
            }
            if watch.found == 0 {
                Text(verbatim: DealWatchWords.foundLine(watch, language)).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Text(verbatim: DealWatchWords.shopsLine(watch, language)).font(.footnote).foregroundStyle(Theme.secondaryText)
            if let ends = DealWatchWords.endsLine(watch, now: Date(), language) {
                Text(verbatim: ends).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            checkedLine
            HStack(spacing: 10) {
                NavigationLink {
                    PriceAlertMatchesView(watch: watch)
                } label: {
                    Label { Text(verbatim: DealWatchWords.matchesTitle(language)) } icon: { Image(systemName: "list.bullet") }
                }
                .buttonStyle(DoddyOutlineButtonStyle())
                Spacer(minLength: 0)
                Button(role: .destructive, action: onDelete) {
                    Label { Text(verbatim: DealWatchWords.delete(language)) } icon: { Image(systemName: "trash") }
                }
                .buttonStyle(DoddyOutlineButtonStyle())
                .disabled(busy)
            }
        }
        .doddyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("priceAlerts.card")
    }

    @ViewBuilder private var checkedLine: some View {
        if let raw = watch.lastCheckedAt, let date = ServerDates.parse(raw) {
            Text(verbatim: "\(DealWatchWords.checkedLabel(language)): \(DateText.full(date))")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        } else {
            Text(verbatim: DealWatchWords.neverChecked(language)).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: The bell

/// The orange tile with a bell. It bounces once when `rings` (an alert was just saved); under Reduce Motion it doesn't move.
struct BellTile: View {
    var rings: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rang = false

    var body: some View {
        DoddySymbolTile(systemImage: "bell.badge")
            .symbolEffect(.bounce, options: .nonRepeating, value: rang)
            .onAppear {
                guard rings, !reduceMotion else { return }
                rang.toggle()
            }
    }
}
