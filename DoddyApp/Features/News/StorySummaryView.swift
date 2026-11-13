import DoddyCore
import SwiftUI

// A story opened from On my radar (owner, 13 Nov 2026: a tap gives a quick AI summary of the article, by Claude
// Haiku). The publisher's own picture, name, time and headline; under them the summary Doddy's server had Claude Haiku
// write from the article's text, labelled as written by AI; then the full article and share. The summary is shown
// only from the server's answer (FollowingModel.summary(for:)); with none, the sheet says why. The fine print says
// what left the iPhone for it.

struct StorySummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let model: FollowingModel
    let card: NewsCard
    let now: Date
    @State private var state: FollowingModel.SummaryState = .loading
    private let polish = FollowingModel.polish

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if card.image != nil { picture }
                    RadarPublisherLine(card: card, polish: polish, now: now)
                    Text(card.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    summaryCard
                    actions
                    DoddyFinePrint(text: Text("To write this summary, your Doddy server read the article from the publisher's site and sent its text to Anthropic (Claude Haiku). Only the story's address and headline left this iPhone, never what you follow. A summary is kept on the server for up to 6 hours, linked to nobody, so the same story isn't summarised twice."))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: card.id) { await load() }
        }
    }

    private func load() async {
        state = .loading
        state = await model.summary(for: card)
    }

    // MARK: The summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                DoddyIconBadge(systemName: "sparkles", size: 32)
                Text("Summary")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            summaryBody
        }
        .doddyCard(accent: true)
        .accessibilityIdentifier("story.summary")
    }

    @ViewBuilder
    private var summaryBody: some View {
        switch state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Doddy's server is reading the article…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        case .ready(let summary):
            SummaryPoints(summary: summary)
        case .unavailable(let why):
            DoddyNotice(text: Text(verbatim: why))
        case .failed(let why):
            DoddyNotice(text: Text(verbatim: why), isProblem: true)
            Button {
                Task { await load() }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story.retry")
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if let link = card.link {
            VStack(spacing: 10) {
                Button {
                    openURL(link)
                } label: {
                    Label("Read the full article", systemImage: "arrow.up.right")
                }
                .buttonStyle(DoddyAccentButtonStyle())
                .accessibilityIdentifier("story.open")
                ShareLink(item: link, subject: Text(card.title), message: Text(verbatim: "\(card.title) · \(card.source)")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    /// The publisher's picture, 16:9, from its https address.
    private var picture: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image = card.image {
                    AsyncImage(url: image) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: RadarPicturePlaceholder()
                        default:
                            ZStack {
                                Theme.quietSurface
                                ProgressView()
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The written summary: its points, why it matters, and the label that says an AI wrote it.
private struct SummaryPoints: View {
    let summary: NewsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(Theme.orangeCue)
                        .frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { d in d.height + 3 }
                        .accessibilityHidden(true)
                    Text(verbatim: point)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Why it matters")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: summary.whyItMatters)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Label {
                Text(verbatim: String(format: NSLocalizedString("Written by AI (%@) from the article. It may contain mistakes.", comment: ""), summary.writerName))
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("story.aiLabel")
        }
    }
}
