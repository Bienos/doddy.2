import DoddyCore
import SwiftUI

// On my radar, 13 Nov 2026 (owner: "trzeba wiedzieć z jakich źródeł można podłączyć … jak się naciśnie … można dostać
// podsumowanie artykułu AI-owego … z modelem Haiku"). Two sheets:
//   - Sources: every topic Doddy's server reads, with its publishers, followed with one tap; what "your own words"
//     and "your own feed" search; and the person's own feeds.
//   - A story's AI summary: asked for only on the tap, written by Claude Haiku on Doddy's server from the publisher's
//     page, labelled as AI on screen, and never shown half-done. The full story is always one tap away.

/// Where the radar's stories come from, and how to follow more.
struct RadarSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FollowingModel
    let addOwn: () -> Void
    private let polish = FollowingModel.polish

    private func isFollowed(_ topic: NewsCatalogTopic) -> Bool {
        model.follows.follows.contains { $0.id == "topic:\(topic.id)" }
    }

    private var ownFeeds: [NewsFollow] { model.follows.follows.filter { $0.feedURL != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DoddyHero(title: "Where the news comes from",
                              subtitle: "Doddy reads these publishers' public feeds. Pick a topic to follow it; your own words are looked for in all of them.",
                              pose: .bellyReading)
                    if model.catalog.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.accentText)
                            Text("Loading topics…").foregroundStyle(Theme.secondaryText)
                        }
                        .doddyCard()
                    }
                    ForEach(model.catalog) { topic in
                        topicCard(topic)
                    }
                    DoddySectionTitle(title: "Your own")
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your own words", systemImage: "text.magnifyingglass").font(.headline)
                        Text(model.keywordSearch
                             ? "Doddy's server searches news sources for these words."
                             : "Doddy looks for these words, with their Polish and English endings, in every publisher's feed it reads.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Label("Your own feed", systemImage: "dot.radiowaves.up.forward").font(.headline).padding(.top, 4)
                        Text("Any site's RSS or Atom feed: paste its address. Doddy's server checks it first, https only, never a private network.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        ForEach(ownFeeds) { follow in
                            HStack {
                                Text(verbatim: follow.label).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(verbatim: follow.feedURL.flatMap { URL(string: $0)?.host } ?? "")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        Button {
                            dismiss()
                            addOwn()
                        } label: {
                            Label("Add words or a feed", systemImage: "plus")
                        }
                        .buttonStyle(DoddyInkButtonStyle())
                        .disabled(model.follows.isFull)
                        .accessibilityIdentifier("radar.sources.addOwn")
                    }
                    .doddyCard()
                    DoddyFootnote(text: NSLocalizedString("Headlines, summaries on the cards and pictures are the publishers' own. Doddy's server fetches the feeds and keeps nothing about you.", comment: ""),
                                  systemImage: "lock")
                }
                .padding(16)
                .readableColumn()
            }
            .doddyScreen()
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.loadCatalog() }
        }
    }

    private func topicCard(_ topic: NewsCatalogTopic) -> some View {
        let followed = isFollowed(topic)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: topic.label).font(.system(.headline, design: .rounded))
                Spacer()
                if followed {
                    Button { model.remove(id: "topic:\(topic.id)") } label: { Label("Following", systemImage: "checkmark") }
                        .buttonStyle(DoddyOutlineButtonStyle())
                        .accessibilityHint(Text("Stops following this topic"))
                        .accessibilityIdentifier("radar.sources.unfollow.\(topic.id)")
                } else {
                    Button { _ = model.add(.topic(id: topic.id, label: topic.label)) } label: { Label("Follow", systemImage: "plus") }
                        .buttonStyle(DoddyInkButtonStyle())
                        .disabled(model.follows.isFull)
                        .accessibilityIdentifier("radar.sources.follow.\(topic.id)")
                }
            }
            if let sources = topic.sources, !sources.isEmpty {
                ChipFlow(spacing: 6) {
                    ForEach(sources, id: \.self) { source in
                        Text(verbatim: source)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.canvas, in: Capsule())
                    }
                }
            }
        }
        .doddyCard()
    }
}

/// One story's AI summary, asked for when the sheet opens.
struct StorySummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let card: NewsCard
    let model: FollowingModel
    private let polish = FollowingModel.polish

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(verbatim: card.source).font(.subheadline.weight(.semibold))
                        if let age = card.ageText(now: model.fetchedAt ?? Date(), polish: polish) {
                            Text(verbatim: "· " + age).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Text(verbatim: card.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    content
                    if let link = card.link {
                        Button { openURL(link) } label: {
                            Label("Read the full story", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DoddyInkButtonStyle())
                        .accessibilityIdentifier("radar.summary.open")
                    }
                    DoddyFootnote(text: NSLocalizedString("The story's link goes to Doddy's server, which reads the publisher's page; its text goes to Anthropic to be summarized. Nothing about you is sent with it, and the summary is kept only while the app is open.", comment: ""),
                                  systemImage: "lock")
                }
                .padding(16)
                .readableColumn()
            }
            .doddyScreen()
            .navigationTitle("AI summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.summarize(card) }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var content: some View {
        switch model.summaries[card.id] {
        case .none, .loading?:
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accentText)
                Text("Doddy is reading the story…").foregroundStyle(Theme.secondaryText)
            }
            .doddyCard()
            .accessibilityIdentifier("radar.summary.loading")
        case .ready(let summary)?:
            VStack(alignment: .leading, spacing: 12) {
                DoddyTag(text: NSLocalizedString("AI summary", comment: ""), systemImage: "sparkles", strong: true)
                Text(verbatim: summary.summary.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(summary.summary.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.orangeCue).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(verbatim: point).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let why = summary.summary.whyItMatters, !why.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters").font(.footnote.weight(.bold)).foregroundStyle(Theme.accentText)
                        Text(verbatim: why).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(verbatim: String(format: NSLocalizedString("Written by %@ from %@'s page. It can get things wrong; the full story is the publisher's.", comment: ""),
                                      summary.writerName, summary.source.host))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .doddyCard()
            .accessibilityIdentifier("radar.summary.ready")
        case .failed(let problem)?:
            VStack(alignment: .leading, spacing: 10) {
                Label { Text(verbatim: problem.text(polish: polish)) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(problem == .off ? Theme.secondaryText : Theme.error)
                if problem == .failed || problem == .unreadable {
                    Button("Try again") { Task { await model.summarize(card) } }
                        .buttonStyle(DoddyOutlineButtonStyle())
                }
            }
            .doddyCard()
            .accessibilityIdentifier("radar.summary.problem")
        }
    }
}
