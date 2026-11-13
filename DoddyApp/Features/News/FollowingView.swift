import DoddyCore
import SwiftUI

// On my radar (ADR-656; redesigned 13 Nov 2026 in Doddy's colours, owner: "Na radarze też powinien tutaj być jakiś
// design poprawiony"). Top to bottom: the page header; what the person follows as chips, with "Add sources", which
// opens the Sources list (RadarViews.swift: every publisher Doddy's server can read, by topic); the tapped follow's
// sources and "tell me when"; what Doddy's server spotted; then the publishers' stories as cards. A tap on a story
// opens it with a short AI summary (StorySummaryView.swift). Cards are the publishers' own words; the summary is the
// one thing an AI writes here, only on a tap, and it says so.

struct FollowingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let model = FollowingModel.shared
    @State private var showAdd = false
    @State private var showManage = false
    /// The follow whose "tell me when" is being changed.
    @State private var alertFor: NewsFollow?
    /// The story opened with its summary.
    @State private var reading: NewsCard?
    private let polish = FollowingModel.polish

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    DoddyPageHeader(eyebrow: "Your news", title: "On my radar",
                                    subtitle: "The newest stories from the publishers you follow. Tap a story for a short summary.",
                                    pose: .kneelingInspect)
                    RadarFollowsRow(model: model, add: { showAdd = true })
                    notices
                    // On my radar (decision 2026-11-10-radar-alerts): the tapped follow's sources, its "tell me when",
                    // and what Doddy's server spotted for it (or for all follows).
                    if let follow = model.selectedFollow {
                        FollowDetail(model: model, follow: follow, polish: polish, tellMe: { alertFor = follow })
                    }
                    SpottedList(model: model, follow: model.selectedFollow, polish: polish,
                                open: { hit in if let link = hit.link { openURL(link) } })
                    stories
                    finePrint
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { showManage = true }
                        .disabled(model.follows.isEmpty)
                        .accessibilityIdentifier("following.manage")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .task { await model.loadCatalog() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await model.refresh() } }) { RadarAddSheet(model: model) }
            .sheet(isPresented: $showManage, onDismiss: { Task { await model.refresh() } }) { ManageFollowsSheet(model: model) }
            .sheet(item: $alertFor) { follow in RadarAlertSheet(model: model, follow: follow) }
            .sheet(item: $reading) { card in
                StorySummarySheet(model: model, card: card, now: model.fetchedAt ?? Date())
            }
        }
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if !model.isServerConfigured {
            notice(Text("On my radar needs a Doddy messaging server, and none is connected in this build yet."))
        } else if model.follows.isEmpty {
            notice(Text("You're not following anything yet. Tap Add sources to pick a topic, your own words or your own feed."))
        }
        if let problem = model.problem {
            notice(Text(problem), isProblem: true)
        }
        if let message = model.message {
            notice(Text(message))
        }
    }

    private func notice(_ text: Text, isProblem: Bool = false) -> some View {
        DoddyNotice(text: text, isProblem: isProblem)
            .accessibilityIdentifier("following.notice")
    }

    // MARK: Stories

    @ViewBuilder
    private var stories: some View {
        // The stories on screen, not all of them (11 Nov 2026): a follow just added and tapped showed a blank
        // area while its first stories were being read, because other follows' stories were already there.
        if model.visibleCards.isEmpty, model.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading the publishers' feeds…").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else if model.cards.isEmpty, model.fetchedAt != nil, model.problem == nil, !model.follows.isEmpty {
            notice(Text("Nothing from the last two days for what you follow. Pull down to look again."))
        }
        ForEach(model.sections) { section in
            dayHeading(section.day.title(polish: polish))
            ForEach(section.cards) { card in
                StoryCard(card: card, polish: polish, now: model.fetchedAt ?? Date(),
                          flags: model.flaggedWords(on: card),
                          isSaved: model.savedStoryIDs.contains(card.id),
                          read: { reading = card },
                          open: { if let link = card.link { openURL(link) } },
                          save: { Task { await model.save(card) } })
            }
        }
    }

    private func dayHeading(_ title: String) -> some View {
        Text(verbatim: title)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Fine print

    /// Every line true after 13 Nov 2026: the cards are the publishers' own, the summary is AI and only on a tap,
    /// and what goes where (the follows to Doddy's server only; a tapped story's address to the server, its text to
    /// Anthropic).
    @ViewBuilder
    private var finePrint: some View {
        if model.fetchedAt != nil, !model.cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                DoddyFinePrint(text: Text("Headlines, descriptions and pictures on these cards are the publishers' own, from their public feeds. No AI picks, orders or rewrites them."))
                DoddyFinePrint(text: Text("An AI summary is written only when you tap a story: Doddy's server then reads that article from the publisher's site and sends its text to Anthropic, whose Claude Haiku writes the summary. It can contain mistakes."))
                DoddyFinePrint(text: Text("What you follow stays on this iPhone and goes to your Doddy server with each refresh, which keeps none of it. It is never sent to Anthropic."))
                if model.alerts.anyServerChecks(model.follows) {
                    DoddyFinePrint(text: Text("Except what you let Doddy's server check for you: it keeps that follow, its words and how to tell you, until you turn checking off."))
                }
            }
            .padding(.top, 8)
        }
    }
}

/// What the person follows, as a row of chips: All, one per follow (a dot when Doddy's server spotted something not
/// seen yet), and Add sources.
private struct RadarFollowsRow: View {
    let model: FollowingModel
    let add: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !model.follows.isEmpty {
                    DoddyChip(title: "All", isSelected: model.selectedFollowID == nil) {
                        model.selectedFollowID = nil
                    }
                    .accessibilityHint(Text("Shows the stories of everything you follow"))
                }
                ForEach(model.follows.follows) { follow in
                    // A tap shows only this follow's stories; a second tap shows them all again.
                    FollowChip(follow: follow, isSelected: model.selectedFollowID == follow.id,
                               hasNew: model.unseenCount(for: follow) > 0) {
                        model.selectedFollowID = model.selectedFollowID == follow.id ? nil : follow.id
                    }
                }
                addChip
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var addChip: some View {
        Button(action: add) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.footnote.weight(.bold))
                Text("Add sources").font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(Theme.inkOnOrange)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.orangeCue.opacity(model.follows.isFull ? 0.35 : 1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.follows.isFull)
        .accessibilityHint(model.follows.isFull ? Text("You follow ten things already. Remove one first.") : Text("Shows every source Doddy can read for you"))
        .accessibilityIdentifier("following.add")
    }
}

/// One follow as a chip: its kind's icon, its name, and an orange dot when something new was spotted.
private struct FollowChip: View {
    let follow: NewsFollow
    let isSelected: Bool
    let hasNew: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: RadarFollowKind.icon(follow))
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(verbatim: follow.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                if hasNew {
                    Circle().fill(Theme.orangeCue).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Theme.canvas : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isSelected ? Theme.ink : Theme.canvas, in: Capsule())
            .overlay { if !isSelected { Capsule().strokeBorder(Theme.separator, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(hasNew ? Text("New stories spotted") : Text(verbatim: ""))
        .accessibilityHint(Text("Shows only this follow's stories"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One story. Everything on it came from the publisher's feed; a tap opens it with its AI summary.
private struct StoryCard: View {
    let card: NewsCard
    let polish: Bool
    let now: Date
    /// The person's own "tell me when" words this story mentions (matched on this iPhone).
    var flags: [String] = []
    let isSaved: Bool
    let read: () -> Void
    let open: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: read) {
                VStack(alignment: .leading, spacing: 0) {
                    if card.image != nil { picture }
                    text
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the story with a short AI summary"))
            actions
        }
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("following.card")
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            RadarPublisherLine(card: card, polish: polish, now: now)
            if !flags.isEmpty {
                Label { Text(verbatim: flags.joined(separator: ", ")) } icon: { Image(systemName: "flag.fill") }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: String(format: NSLocalizedString("Mentions your words: %@", comment: ""), flags.joined(separator: ", "))))
            }
            Text(card.title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !card.summary.isEmpty {
                Text(card.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            // The same story from other publishers, grouped by the server (decision 2026-11-13-news-more-sources).
            if let also = card.alsoFromLine(polish: polish) {
                Text(verbatim: also)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .accessibilityIdentifier("following.alsoFrom")
            }
            if !card.follows.isEmpty {
                Text(verbatim: card.follows.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: read) {
                Label("Summary", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkOnOrange)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Theme.orangeCue, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel(Text("AI summary"))
            .accessibilityIdentifier("following.summary")
            Spacer(minLength: 8)
            iconAction(systemName: isSaved ? "bookmark.fill" : "bookmark", label: isSaved ? Text("Saved to your notes") : Text("Save to your notes"), action: save)
                .disabled(isSaved)
                .accessibilityIdentifier("following.save")
            if let link = card.link {
                ShareLink(item: link, subject: Text(card.title), message: Text(verbatim: "\(card.title) · \(card.source)")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Share"))
            }
            iconAction(systemName: "arrow.up.right", label: Text("Open the full story"), action: open)
                .disabled(card.link == nil)
                .accessibilityIdentifier("following.open")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// An icon-only action, 44 points square, with its words for VoiceOver. Its name doesn't end in Button: the
    /// strings catalog would read the icon's name as a line to translate.
    private func iconAction(systemName: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The publisher's picture, 16:9, straight from its https address with nothing added.
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
                                Theme.canvas.opacity(0.5)
                                ProgressView()
                            }
                        }
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Publisher, initial badge and age: the first line of a story card and of the story sheet.
struct RadarPublisherLine: View {
    let card: NewsCard
    let polish: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: card.sourceInitial)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.inkOnOrange)
                .frame(width: 24, height: 24)
                .background(Theme.orangeCue, in: Circle())
                .accessibilityHidden(true)
            Text(card.source)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if let age = card.ageText(now: now, polish: polish) {
                Text(verbatim: "· \(age)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Where a picture couldn't be loaded: a quiet panel with a newspaper.
struct RadarPicturePlaceholder: View {
    var body: some View {
        ZStack {
            Theme.canvas.opacity(0.5)
            Image(systemName: "newspaper")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.secondaryText)
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
                        HStack(spacing: 12) {
                            Image(systemName: RadarFollowKind.icon(follow))
                                .foregroundStyle(Theme.secondaryText)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: follow.label).foregroundStyle(Theme.ink)
                                if !follow.keywords.isEmpty {
                                    Text(verbatim: follow.keywords.joined(separator: ", ")).font(.footnote).foregroundStyle(Theme.secondaryText)
                                }
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
