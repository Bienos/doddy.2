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
    private let polish = FollowingModel.polish

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    followsRow
                        .padding(.vertical, 12)
                    Divider()
                    if !model.isServerConfigured {
                        notice(Text("Following needs a Doddy messaging server, and none is connected in this build yet."))
                    } else if model.follows.isEmpty {
                        notice(Text("You're not following anything. Add a topic or your own words above."))
                    }
                    if let problem = model.problem {
                        notice(Text(problem), isProblem: true)
                    }
                    if let message = model.message {
                        notice(Text(message))
                    }
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
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { showManage = true }.accessibilityIdentifier("following.manage")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await model.refresh() } }) { AddFollowSheet(model: model) }
            .sheet(isPresented: $showManage, onDismiss: { Task { await model.refresh() } }) { ManageFollowsSheet(model: model) }
        }
    }

    /// The row across the top: one circle per follow, and a "+" to add one.
    private var followsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(model.follows.follows) { follow in
                    FollowBubble(follow: follow)
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

/// One follow in the top row: a ring in Doddy's orange, the initial, the name under it.
private struct FollowBubble: View {
    let follow: NewsFollow

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().strokeBorder(Theme.orangeCue, lineWidth: 2.5)
                Circle().fill(Theme.quietSurface).padding(4)
                Text(follow.label.first.map { String($0).uppercased() } ?? "•")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
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

/// Add a follow: a topic from Doddy's catalog, or the person's own words.
private struct AddFollowSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FollowingModel
    @State private var name = ""
    @State private var keywordsText = ""
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. CPK", text: $name)
                    TextField("Words to look for, comma separated", text: $keywordsText)
                        .textInputAutocapitalization(.never)
                    Button("Follow these words") {
                        guard let follow = NewsFollowList.words(name: name, keywordsText: keywordsText) else {
                            note = NSLocalizedString("Give it a name and at least one word of two or more letters.", comment: "")
                            return
                        }
                        if model.add(follow) { dismiss() } else { note = NSLocalizedString("You already follow that, or you follow ten things already.", comment: "") }
                    }
                    .disabled(name.isEmpty || keywordsText.isEmpty)
                    .accessibilityIdentifier("following.addWords")
                } header: {
                    Text("My own words")
                } footer: {
                    if model.keywordSearch {
                        Text("Doddy's server searches news sources for these words.")
                    } else {
                        Text("Doddy's server looks for these words in the stories of your other follows.")
                    }
                }
                Section("Topics") {
                    if model.availableTopics.isEmpty, model.catalog.isEmpty {
                        Text("Loading topics…").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(model.availableTopics) { topic in
                        Button {
                            if model.add(.topic(id: topic.id, label: topic.label)) { dismiss() }
                        } label: {
                            HStack {
                                Text(topic.label).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Theme.accentText)
                            }
                        }
                    }
                }
                if let note {
                    Section { Label(note, systemImage: "info.circle") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Follow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await model.loadCatalog() }
        }
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
