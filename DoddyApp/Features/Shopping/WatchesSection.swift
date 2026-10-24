import DoddyCore
import SwiftUI

// "Pilnowane ceny" on the Tasks screen (docs/implementation/SHOPPING_WATCH.md section 4): each watch with its
// state in words, the last price the server confirmed and when the last check was, Stop for an active one,
// Delete, and "Buy at …" for one that dropped, which opens the shop's own page in Safari (no web view inside
// the app, scripts/check_forbidden_capabilities.sh). Everything shown is what the server last listed; nothing
// is shown as watching, stopped or dropped on the app's own say-so.

struct WatchesSection: View {
    private let model = WatchModel.shared

    var body: some View {
        if !model.watches.isEmpty || model.loadProblem != nil || model.message != nil {
            Section {
                if let problem = model.loadProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                        .accessibilityIdentifier("watch.loadProblem")
                }
                if let message = model.message {
                    Label(message, systemImage: "info.circle").foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("watch.message")
                }
            } header: {
                Text("Watched prices")
            } footer: {
                Text("Doddy's server reads each shop's page a few times a day while a watch is on. It only tells you; it never buys anything.")
            }
            ForEach(model.watches) { watch in
                WatchEntry(watch: watch)
            }
        }
    }
}

private struct WatchEntry: View {
    let watch: WatchSummary
    private let model = WatchModel.shared
    private let language = NotificationLanguage.current
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: watch.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(verbatim: watch.shop).font(.footnote).foregroundStyle(Theme.secondaryText)
                Text(WatchWords.state(watch, language)).font(.headline).foregroundStyle(stateColor)
                    .accessibilityIdentifier("watch.state")
                Text(WatchWords.yourPrice(watch, language)).font(.footnote).foregroundStyle(Theme.ink)
                if let last = WatchWords.lastPrice(watch, language) {
                    Text(last).font(.footnote).foregroundStyle(Theme.ink)
                }
                if let checked = watch.lastCheckedAt {
                    Text(String(format: NSLocalizedString("Last checked %@", comment: ""), DateText.full(checked)))
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                if watch.state.isActive, let ends = watch.endsAt {
                    Text(String(format: NSLocalizedString("Watching until %@", comment: ""), DateText.full(ends)))
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            if watch.canStop {
                Button("Stop") { Task { await model.stop(watch.id) } }
                    .disabled(model.busy.contains(watch.id))
                    .accessibilityIdentifier("watch.stop")
            }
            if watch.state == .triggered, let url = ShopPage.url(watch.url) {
                Button {
                    openURL(url) { opened in
                        if opened { ShopPage.record(shop: watch.shop, title: watch.title) }
                    }
                } label: {
                    Label(String(format: NSLocalizedString("Buy at %@", comment: "opens the shop's page"), watch.shop),
                          systemImage: "bag")
                }
                .accessibilityIdentifier("watch.buy")
            }
            Button("Delete", role: .destructive) { confirmDelete = true }
                .disabled(model.busy.contains(watch.id))
                .accessibilityIdentifier("watch.delete")
                .confirmationDialog("Delete this watch?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { Task { await model.delete(watch.id) } }
                } message: {
                    Text("It's removed from this list and from Doddy's server.")
                }
        }
    }

    /// A drop is green only with the confirmed price; a failure is red; the rest are plain.
    private var stateColor: Color {
        if watch.confirmedDrop != nil { return Theme.confirmed }
        if watch.state == .failed { return Theme.error }
        return watch.state.isActive ? Theme.ink : Theme.secondaryText
    }
}
