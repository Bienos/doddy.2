import DoddyCore
import QuickLook
import SwiftUI
import UIKit
import UserNotifications

// Studio (S0, ADR-584): the list of what Doddy made, and one item with its brief (Quick Look), its
// infographic, its sources and dates, Share and Delete. Everything shown comes from the server's
// answer; an item still being made never shows files, and "deleted" is said only after the list
// was read back without it (StudioModel).

extension StudioModel {
    /// One model for the voice controller, Home and Studio, so they never disagree. The server is
    /// looked up each time, so a server address set after launch is used.
    static let shared = StudioModel(
        backend: { ServerConfig.client() },
        cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Studio", isDirectory: true),
        afterJobStarted: { await StudioNotifications.register() })
}

/// The "ready" notification needs this iPhone's push token on the server; asked the first time a
/// job is allowed, as Tasks does. A refusal just leaves the result in Studio.
@MainActor
enum StudioNotifications {
    static func register() async {
        guard let client = ServerConfig.client() else { return }
        let status = await PushRegistrar.shared.authorizationStatus()
        let token: Data?
        switch status {
        case .notDetermined: token = try? await PushRegistrar.shared.requestDeviceToken()
        case .authorized, .provisional, .ephemeral: token = try? await PushRegistrar.shared.currentDeviceToken()
        default: token = nil
        }
        guard let token else { return }
        try? await client.registerPushToken(token, environment: ServerConfig.pushEnvironment)
    }
}

struct StudioView: View {
    @Environment(\.dismiss) private var dismiss
    private let model = StudioModel.shared
    @State private var opened: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ask Doddy in a conversation to research something, like \"research heat pumps for a Polish house\". After one yes, Doddy searches the web, writes a research brief (PDF) and makes an infographic, in the background. You get a notification when it's ready. Nothing is published or sent.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if !model.isServerConfigured {
                        Label("Doddy's server isn't set up in this build, so Studio can't make anything yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                }
                if let problem = model.loadProblem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                        Button("Try again") { Task { await model.refresh() } }
                    }
                }
                if !model.items.isEmpty {
                    Section("Made by Doddy") {
                        ForEach(model.items) { item in
                            Button { opened = item.id } label: { StudioRow(item: item, title: model.displayTitle(item.id, title: item.title)) }
                                .accessibilityIdentifier("studio.row")
                        }
                    }
                } else if model.hasLoaded && model.loadProblem == nil {
                    Section { Text("Nothing here yet.").foregroundStyle(Theme.secondaryText) }
                }
                if let message = model.message {
                    Section { Label(message, systemImage: "info.circle").accessibilityIdentifier("studio.message") }
                }
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { id in StudioItemView(id: id) }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }
}

private struct StudioRow: View {
    let item: StudioItemSummary
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.ink)
            Text(StudioText.line(item))
                .font(.footnote).foregroundStyle(item.state == .failed ? Theme.error : Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StudioItemView: View {
    let id: UUID
    private let model = StudioModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var previewURL: URL?
    @State private var briefURL: URL?
    @State private var pictureURL: URL?
    @State private var printURL: URL?
    @State private var isLoadingFiles = false

    var body: some View {
        Group {
            if let item = model.details[id] {
                content(item)
            } else if let message = model.message {
                Text(message).foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView().accessibilityLabel(Text("Loading"))
            }
        }
        .navigationTitle(model.displayTitle(id, title: model.details[id]?.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.open(id)
            await loadFiles()
        }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private func content(_ item: StudioItem) -> some View {
        Form {
            Section {
                Text(item.state.label(.current)).font(.headline)
                    .foregroundStyle(item.state == .failed ? Theme.error : Theme.ink)
                    .accessibilityIdentifier("studio.state")
                if item.state == .failed {
                    Text((item.failure ?? .unknown).explanation(.current)).foregroundStyle(Theme.ink)
                }
                if item.state == .needsLook {
                    Text("Doddy's checks found something to look at before you share this:").font(.footnote).foregroundStyle(Theme.ink)
                    ForEach(item.failedChecks, id: \.name) { check in
                        Label(check.detail?.isEmpty == false ? "\(check.name): \(check.detail!)" : check.name, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Theme.ink)
                    }
                }
                if item.state.isOpen {
                    Text("Doddy is still working on this. You'll get a notification when it's ready.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                if let summary = item.summary {
                    Text(summary.answer).foregroundStyle(Theme.ink).textSelection(.enabled)
                }
            }
            if item.showsFiles {
                filesSection(item)
            }
            if let job = item.job {
                Section("You asked for") {
                    Text("\u{201C}\(job.topic)\u{201D}").foregroundStyle(Theme.ink).textSelection(.enabled)
                    if let details = job.details { Text("\u{201C}\(details)\u{201D}").font(.footnote).foregroundStyle(Theme.secondaryText) }
                }
            }
            if !item.sources.isEmpty {
                Section("Sources") {
                    ForEach(item.sources) { source in
                        if let url = URL(string: source.url), url.scheme == "https" || url.scheme == "http" {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.title).foregroundStyle(Theme.ink)
                                    Text(StudioText.sourceLine(source, host: url.host() ?? "")).font(.footnote).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
            if let cost = item.cost {
                Section {
                    LabeledContent("Cost", value: StudioMoney.text(cost.usd))
                    Text("Paid from Doddy's account at Anthropic, as measured by the server.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            Section {
                if item.state.isOpen {
                    Button("Stop making this") { Task { await model.cancel(item.id) } }
                        .accessibilityIdentifier("studio.cancel")
                }
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("studio.delete")
            }
            if let message = model.message {
                Section { Label(message, systemImage: "info.circle") }
            }
        }
        .refreshable {
            await model.open(id)
            await loadFiles()
        }
        .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete(item.id) {
                        previewURL = nil
                        dismiss()
                    }
                }
            }
        } message: {
            Text("It's deleted from Doddy's server and this iPhone. Doddy's server also deletes Anthropic's working copies.")
        }
    }

    @ViewBuilder
    private func filesSection(_ item: StudioItem) -> some View {
        Section("Files") {
            if let pictureURL, let image = UIImage(contentsOfFile: pictureURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text("Infographic"))
                    .accessibilityValue(Text(verbatim: item.summary?.altText ?? ""))
                    .onTapGesture { previewURL = pictureURL }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("studio.infographic")
            }
            if let briefURL {
                Button { previewURL = briefURL } label: { Label("Open the brief (PDF)", systemImage: "doc.richtext") }
                    .accessibilityIdentifier("studio.openBrief")
            }
            let shared = [briefURL, pictureURL, printURL].compactMap { $0 }
            if !shared.isEmpty {
                ShareLink(items: shared) { Label("Share", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("studio.share")
            }
            if isLoadingFiles {
                ProgressView().accessibilityLabel(Text("Loading the files"))
            }
        }
    }

    private func loadFiles() async {
        guard let item = model.details[id], item.showsFiles else { return }
        isLoadingFiles = true
        defer { isLoadingFiles = false }
        if let file = item.file(.brief) { briefURL = await model.localFile(id, file) }
        if let file = item.file(.infographicPNG) { pictureURL = await model.localFile(id, file) }
        if let file = item.file(.infographicPrint) { printURL = await model.localFile(id, file) }
    }
}

/// Words for a row and a source, in the app's languages.
enum StudioText {
    static func line(_ item: StudioItemSummary) -> String {
        var parts = [item.state.label(.current), DateText.full(item.createdAt)]
        if let cost = item.costUsd, cost > 0 { parts.append(StudioMoney.text(cost)) }
        return parts.joined(separator: " · ")
    }

    static func sourceLine(_ source: StudioSource, host: String) -> String {
        guard let date = source.fetchedDate else { return host }
        return String(format: NSLocalizedString("%@ · seen %@", comment: ""), host, DateText.full(date))
    }
}
