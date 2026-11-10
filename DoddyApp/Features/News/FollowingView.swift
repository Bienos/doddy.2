import DoddyCore
import SwiftUI

// Following (ADR-656): Home › Following. A row of what the person follows across the top, like a
// row of stories, and under it the publishers' stories as cards: who wrote it, when, the picture,
// the headline and a line of summary, and three quiet actions (open, save, share). Doddy adds no
// words of his own; the one AI line is the disclosure that none was used.

struct FollowingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let model = FollowingModel.shared
    @State private var showAdd = false
    @State private var showManage = false
    /// The follow whose "tell me when" is being changed.
    @State private var alertFor: NewsFollow?
    private let polish = FollowingModel.polish

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    followsRow
                        .padding(.vertical, 12)
                    Divider()
                    if !model.isServerConfigured {
                        notice(Text("On my radar needs a Doddy messaging server, and none is connected in this build yet."))
                    } else if model.follows.isEmpty {
                        notice(Text("You're not following anything. Add a topic or your own words above."))
                    }
                    if let problem = model.problem {
                        notice(Text(problem), isProblem: true)
                    }
                    if let message = model.message {
                        notice(Text(message))
                    }
                    // On my radar (decision 2026-11-10-radar-alerts): the tapped follow's sources, its "tell me when",
                    // and what Doddy's server spotted for it (or for all follows).
                    if let follow = model.selectedFollow {
                        FollowDetail(model: model, follow: follow, polish: polish, tellMe: { alertFor = follow })
                    }
                    SpottedList(model: model, follow: model.selectedFollow, polish: polish,
                                open: { hit in if let link = hit.link { openURL(link) } })
                    if model.cards.isEmpty, model.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    } else if model.cards.isEmpty, model.fetchedAt != nil, model.problem == nil, !model.follows.isEmpty {
                        notice(Text("Nothing from the last two days for what you follow. Pull down to look again."))
                    }
                    ForEach(model.sections) { section in
                        Text(section.day.title(polish: polish))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.cards) { card in
                            StoryCard(card: card, polish: polish, now: model.fetchedAt ?? Date(),
                                      flags: model.flaggedWords(on: card),
                                      isSaved: model.savedStoryIDs.contains(card.id),
                                      open: { if let link = card.link { openURL(link) } },
                                      save: { Task { await model.save(card) } })
                                .padding(.bottom, 24)
                        }
                    }
                    if model.fetchedAt != nil, !model.cards.isEmpty {
                        Text("Headlines, summaries and pictures are the publishers' own, from their public feeds; the link opens the full story. No AI wrote or picked anything here. What you follow stays on this iPhone and is sent with each refresh to your Doddy server, which keeps none of it.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(16)
                    }
                    if model.alerts.anyServerChecks(model.follows) {
                        Text("Except what you let Doddy's server check for you: it keeps that follow, its words and how to tell you, until you turn checking off.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
            .background(Theme.canvas)
            .navigationTitle("On my radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { showManage = true }.accessibilityIdentifier("following.manage")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await model.refresh() } }) { RadarAddSheet(model: model) }
            .sheet(isPresented: $showManage, onDismiss: { Task { await model.refresh() } }) { ManageFollowsSheet(model: model) }
            .sheet(item: $alertFor) { follow in RadarAlertSheet(model: model, follow: follow) }
        }
    }

    /// The row across the top: one circle per follow, and a "+" to add one.
    private var followsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(model.follows.follows) { follow in
                    // A tap shows only this follow's stories; a second tap shows them all again.
                    Button {
                        model.selectedFollowID = model.selectedFollowID == follow.id ? nil : follow.id
                    } label: {
                        FollowBubble(follow: follow, isSelected: model.selectedFollowID == follow.id,
                                     hasNew: model.unseenCount(for: follow) > 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.selectedFollowID == follow.id ? .isSelected : [])
                    .accessibilityHint(Text("Shows only this follow's stories"))
                }
                Button { showAdd = true } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().strokeBorder(Theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            Image(systemName: "plus").font(.title3).foregroundStyle(Theme.accentText)
                        }
                        .frame(width: 64, height: 64)
                        Text("Follow").font(.caption2).foregroundStyle(Theme.ink).lineLimit(2)
                    }
                    .frame(width: 72)
                }
                .disabled(model.follows.isFull)
                .accessibilityIdentifier("following.add")
            }
            .padding(.horizontal, 16)
        }
    }

    private func notice(_ text: Text, isProblem: Bool = false) -> some View {
        Label { text } icon: { Image(systemName: isProblem ? "exclamationmark.triangle" : "info.circle") }
            .font(.footnote)
            .foregroundStyle(isProblem ? Theme.error : Theme.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityIdentifier("following.notice")
    }
}

/// One follow in the top row: a ring in Doddy's orange, the initial, the name under it. Filled when it is the
/// one being shown; a dot when Doddy's server spotted something not seen yet.
private struct FollowBubble: View {
    let follow: NewsFollow
    var isSelected = false
    var hasNew = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().strokeBorder(Theme.orangeCue, lineWidth: isSelected ? 4 : 2.5)
                    Circle().fill(isSelected ? Theme.orangeCue : Theme.quietSurface).padding(isSelected ? 6 : 4)
                    Text(follow.label.first.map { String($0).uppercased() } ?? "•")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.inkOnOrange : Theme.ink)
                }
                if hasNew {
                    Circle().fill(Theme.orangeCue)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                        .accessibilityLabel(Text("New stories spotted"))
                }
            }
            .frame(width: 64, height: 64)
            Text(follow.label)
                .font(.caption2)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(follow.label)
    }
}

/// One story. Everything on it came from the publisher's feed.
private struct StoryCard: View {
    let card: NewsCard
    let polish: Bool
    let now: Date
    /// The person's own "tell me when" words this story mentions (matched on this iPhone).
    var flags: [String] = []
    let isSaved: Bool
    let open: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.quietSurface)
                    Text(card.sourceInitial).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.source).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    if let age = card.ageText(now: now, polish: polish) {
                        Text(age).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                if !card.follows.isEmpty {
                    Text(card.follows.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Theme.accentText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)

            Button(action: open) {
                picture
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open the full story"))

            VStack(alignment: .leading, spacing: 6) {
                if !flags.isEmpty {
                    Label { Text(verbatim: flags.joined(separator: ", ")) } icon: { Image(systemName: "flag.fill") }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityLabel(Text(String(format: NSLocalizedString("Mentions your words: %@", comment: ""), flags.joined(separator: ", "))))
                }
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 22) {
                Button(action: open) { Label("Open", systemImage: "arrow.up.right.square") }
                    .disabled(card.link == nil)
                    .accessibilityIdentifier("following.open")
                Button(action: save) { Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark") }
                    .disabled(isSaved)
                    .accessibilityIdentifier("following.save")
                if let link = card.link {
                    ShareLink(item: link, subject: Text(card.title), message: Text(verbatim: "\(card.title) · \(card.source)")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("following.card")
    }

    /// The publisher's picture, 4:3, or a quiet square with a newspaper when the feed had none.
    /// Only https pictures are asked for, straight from the publisher's address, with nothing added.
    @ViewBuilder
    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 0)
        ZStack {
            Theme.quietSurface
            if let image = card.image {
                AsyncImage(url: image) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: placeholder
                    default: ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "newspaper")
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(Theme.secondaryText)
    }
}

/// Reorder or stop following.
private struct ManageFollowsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FollowingModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.follows.follows) { follow in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(follow.label).foregroundStyle(Theme.ink)
                            if !follow.keywords.isEmpty {
                                Text(follow.keywords.joined(separator: ", ")).font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for id in offsets.map({ model.follows.follows[$0].id }) { model.remove(id: id) }
                    }
                    .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Swipe to stop following. Drag to change the order of the row at the top.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("What you follow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
