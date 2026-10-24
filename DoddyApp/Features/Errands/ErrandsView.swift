import DoddyCore
import SwiftUI

// Tasks handed to Doddy (ADR-570): the list, and one task's result card. Everything shown comes
// from the store on this iPhone or from the server's answer; a task still working is never shown
// as done, and a link on the card is one the server's run actually saw.

struct ErrandsView: View {
    @Environment(\.dismiss) private var dismiss
    private let model = ErrandsModel.shared
    @State private var opened: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Hand Doddy a task in a conversation, like \"compare flights to Rome next month under 2000 zł\". One yes lets Doddy search the web and read pages as often as the task needs, in the background. You get a notification when it's done. Nothing is booked, bought or sent.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if !model.isServerConfigured {
                        Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                }
                if let problem = model.loadProblem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                        Button("Try again") { Task { await model.load() } }
                    }
                }
                if !model.errands.isEmpty {
                    Section("Your tasks") {
                        ForEach(model.errands) { errand in
                            Button { opened = errand.id } label: { ErrandRow(errand: errand) }
                                .accessibilityIdentifier("errands.row")
                        }
                    }
                } else if model.hasLoaded && model.loadProblem == nil {
                    Section { Text("No tasks yet.").foregroundStyle(Theme.secondaryText) }
                }
                if let message = model.message {
                    Section { Label(message, systemImage: "info.circle").accessibilityIdentifier("errands.message") }
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { id in ErrandDetailView(id: id) }
            .refreshable { await model.refresh() }
            .task {
                await model.load()
                await model.refresh()
            }
        }
    }
}

private struct ErrandRow: View {
    let errand: StoredErrand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(errand.title).font(.headline).foregroundStyle(Theme.ink)
            Text("\u{201C}\(errand.draft.words)\u{201D}").lineLimit(2).foregroundStyle(Theme.ink)
            Text("\(ErrandText.state(errand)) · \(DateText.full(errand.createdAt))")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct ErrandDetailView: View {
    let id: UUID
    private let model = ErrandsModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let errand = model.errand(id) {
                content(errand)
            } else {
                Text("This task isn't on this iPhone any more.").foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle(model.errand(id)?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.markSeen(id) }
    }

    @ViewBuilder
    private func content(_ errand: StoredErrand) -> some View {
        Form {
            Section {
                Text(ErrandText.state(errand)).font(.headline)
                    .foregroundStyle(errand.state == .failed ? Theme.error : Theme.ink)
                    .accessibilityIdentifier("errand.state")
                if errand.state == .failed, let failure = errand.failure {
                    Text(failure.explanation).foregroundStyle(Theme.ink)
                }
                if errand.state == .unknown {
                    Text("Doddy couldn't confirm this task started. Pull down to check again; it isn't sent again by itself.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            if let result = errand.result {
                if let shopping = result.shopping {
                    // A shopping task (SHOPPING.md): the picks, their prices and the report.
                    ShoppingResultSections(errand: errand, result: result, shopping: shopping)
                } else {
                    resultSections(result)
                }
            }
            Section("You said") {
                Text("\u{201C}\(errand.draft.words)\u{201D}").foregroundStyle(Theme.ink).textSelection(.enabled)
                LabeledContent("Doddy's note", value: errand.draft.brief)
            }
            if !errand.deletions.isEmpty {
                Section {
                    Text("Saved on this iPhone. Doddy's server deleted its copy of the words and the result.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            Section {
                if errand.state.isOpen {
                    Button("Stop this task") { Task { await model.cancel(errand.id) } }
                        .accessibilityIdentifier("errand.cancel")
                }
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("errand.delete")
            }
            if let message = model.message {
                Section { Label(message, systemImage: "info.circle") }
            }
        }
        .refreshable { await model.refresh() }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { if await model.delete(errand.id) { dismiss() } }
            }
        } message: {
            Text("It's deleted from this iPhone and, if it's still there, from Doddy's server.")
        }
    }

    @ViewBuilder
    private func resultSections(_ result: ErrandResult) -> some View {
        Section {
            Text(result.answer).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).textSelection(.enabled)
            if let recommendation = result.recommendation, !recommendation.isEmpty {
                Text(recommendation).foregroundStyle(Theme.ink)
            }
            if let budget = result.budget {
                LabeledContent(String(format: NSLocalizedString("Budget: %@", comment: ""), "\u{201C}\(budget.asked)\u{201D}"),
                               value: ErrandText.budget(budget.within))
            }
            if let checked = result.checkedDate {
                Text(String(format: NSLocalizedString("Checked %@. Prices and availability can change.", comment: ""), DateText.full(checked)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
            Section(section.heading) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    ErrandItemRow(item: item, checklist: section.kind == .checklist)
                }
            }
        }
        if !result.next.isEmpty {
            Section("What next") {
                ForEach(result.next, id: \.self) { line in
                    Label(line, systemImage: "arrow.turn.down.right").foregroundStyle(Theme.ink)
                }
                Text("Ask Doddy in a conversation to do any of these.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        if !result.sources.isEmpty {
            Section("Sources") {
                ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                    if let url = URL(string: source.url), url.scheme == "https" || url.scheme == "http" {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title).foregroundStyle(Theme.ink)
                                Text(source.site ?? url.host() ?? "").font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ErrandItemRow: View {
    let item: ErrandResult.Item
    let checklist: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if checklist { Image(systemName: "circle").foregroundStyle(Theme.secondaryText) }
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let price = item.price { Text(price).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
            }
            if let when = item.when { Text(when).font(.footnote).foregroundStyle(Theme.ink) }
            if let detail = item.detail { Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText) }
            if let link = item.url.flatMap({ URL(string: $0) }), link.scheme == "https" || link.scheme == "http" {
                Link(item.site ?? link.host() ?? link.absoluteString, destination: link).font(.footnote)
            } else if let site = item.site {
                Text(site).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Words for a task's state and budget, in the app's languages.
enum ErrandText {
    static func state(_ errand: StoredErrand) -> String {
        switch errand.state {
        case .draft, .queued: NSLocalizedString("Waiting to start", comment: "")
        case .running: NSLocalizedString("Doddy is working on it", comment: "")
        case .done: NSLocalizedString("Done", comment: "")
        case .failed: NSLocalizedString("Couldn't finish", comment: "")
        case .cancelled: NSLocalizedString("Stopped", comment: "")
        case .unknown: NSLocalizedString("Not confirmed", comment: "")
        }
    }

    static func budget(_ fit: ErrandResult.BudgetFit) -> String {
        switch fit {
        case .yes: NSLocalizedString("fits", comment: "")
        case .no: NSLocalizedString("goes over", comment: "")
        default: NSLocalizedString("not sure", comment: "")
        }
    }
}
