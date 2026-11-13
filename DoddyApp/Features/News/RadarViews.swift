import DoddyCore
import SwiftUI

// On my radar (owner, 10 Nov 2026; decision 2026-11-10-radar-alerts; redesigned 13 Nov 2026): the Sources list,
// which shows every publisher Doddy's server can read, by topic, and the three ways to follow (owner, 13 Nov:
// "trzeba też wiedzieć z jakich źródeł można podłączyć to, żeby to się działo, a nie tak to randomowo pokazuje");
// the follow form with "tell me when"; the tapped follow's sources; and the stories Doddy's server spotted. Nothing
// here is written by an AI: headlines and publishers are the feeds' own. A server check is offered only behind its
// own switch, and said to be on only when the server's answer lists it.

/// The icon for each kind of follow, shared by the chips, the detail card and the edit list.
enum RadarFollowKind {
    static func icon(_ follow: NewsFollow) -> String {
        switch follow {
        case .topic: "newspaper"
        case .words: "text.magnifyingglass"
        case .feed: "dot.radiowaves.up.forward"
        }
    }
}

/// One publisher and the host its feed is read from, with whether it answered on the last refresh when known.
private struct PublisherRow: View {
    let name: String
    var domain: String?
    /// nil before the first refresh; false when it didn't answer this time.
    var answered: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let domain {
                    Text(verbatim: domain)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if answered == false {
                    Text("Not answering right now")
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch answered {
        case true?:
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.confirmed)
                .accessibilityLabel(Text("Answered"))
        case false?:
            Image(systemName: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Theme.error)
                .accessibilityHidden(true)
        case nil:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
    }
}

/// The tapped follow: where its stories come from, how Doddy tells about it, and an honest empty state.
struct FollowDetail: View {
    let model: FollowingModel
    let follow: NewsFollow
    let polish: Bool
    let tellMe: () -> Void

    var body: some View {
        let alert = model.alert(for: follow)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DoddyIconBadge(systemName: RadarFollowKind.icon(follow), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: follow.label)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    kindLine
                }
            }
            Text("Where its stories come from")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            sources
            Divider().overlay(Theme.separator)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label { Text(verbatim: alert.summary(polish: polish)) } icon: {
                    Image(systemName: alert.serverChecks ? "bell.badge" : "eye")
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Button("Tell me…", action: tellMe)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("radar.tellMe")
            }
            if model.fetchedAt != nil, !model.isLoading, model.problem == nil, model.visibleCards.isEmpty {
                Text(verbatim: String(format: NSLocalizedString("Nothing from the last two days for %@. Pull down to look again.", comment: ""), follow.label))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("radar.nothing")
            }
        }
        .doddyCard(accent: true)
    }

    @ViewBuilder
    private var kindLine: some View {
        switch follow {
        case .topic:
            Text("A topic from Doddy's list").font(.footnote).foregroundStyle(Theme.secondaryText)
        case .words(_, let keywords):
            Text(verbatim: String(format: NSLocalizedString("Your own words: %@", comment: ""), keywords.joined(separator: ", ")))
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        case .feed:
            Text("Your own feed").font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }

    /// The publishers, from the last refresh (with whether each answered) or, before one, from the catalog.
    @ViewBuilder
    private var sources: some View {
        let report = model.report(for: follow)
        switch follow {
        case .topic:
            let publishers = model.catalogTopic(for: follow)?.publisherList ?? []
            let reported = report?.sources ?? []
            if publishers.isEmpty && reported.isEmpty {
                Text("The publishers show after the first refresh.").font(.footnote).foregroundStyle(Theme.secondaryText)
            } else if publishers.isEmpty {
                ForEach(reported, id: \.name) { source in
                    PublisherRow(name: source.name, answered: source.ok)
                }
            } else {
                ForEach(publishers, id: \.name) { publisher in
                    PublisherRow(name: publisher.name, domain: publisher.domain,
                                 answered: reported.first(where: { $0.name == publisher.name })?.ok)
                }
            }
        case .words:
            if model.keywordSearch {
                Text("Doddy's server searches news sources for these words.").font(.footnote).foregroundStyle(Theme.ink)
            } else {
                Text("Doddy looks for these words, with their Polish and English endings, in every publisher's feed it reads.")
                    .font(.footnote).foregroundStyle(Theme.ink)
                if let searched = report?.searchedFeeds {
                    Text(verbatim: String(format: NSLocalizedString("%lld feeds looked through on the last refresh.", comment: ""), Int64(searched)))
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        case .feed(_, let url, let keywords):
            PublisherRow(name: report?.sources.first?.name ?? (URL(string: url)?.host ?? url),
                         domain: URL(string: url)?.host, answered: report?.sources.first?.ok)
            if !keywords.isEmpty {
                Text(verbatim: String(format: NSLocalizedString("Stories that mention: %@", comment: ""), keywords.joined(separator: ", ")))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// What Doddy's server spotted for the follows it checks (or for the tapped one), newest first. Shown here
/// whether or not a notification went out, so nothing depends on a push arriving.
struct SpottedList: View {
    let model: FollowingModel
    let follow: NewsFollow?
    let polish: Bool
    let open: (RadarServerState.Hit) -> Void

    var body: some View {
        let hits = Array(model.spotted(for: follow).prefix(10))
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    DoddyIconBadge(systemName: "bell", size: 32)
                    Text("Doddy spotted")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(hits) { hit in
                    Button { open(hit) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(hit.seen ? Color.clear : Theme.orangeCue)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: hit.title)
                                    .font(.subheadline.weight(hit.seen ? .regular : .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Text(verbatim: ([hit.source, hit.label] + (hit.matched.isEmpty ? [] : [hit.matched.joined(separator: ", ")])).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(hit.link == nil)
                    .accessibilityIdentifier("radar.spotted")
                }
                if model.radar?.push == false {
                    Text("Notifications can't reach this iPhone yet, so what Doddy finds is listed here.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .doddyCard()
            .task(id: hits.map(\.id)) {
                // Seen once they have been on screen for a moment.
                try? await Task.sleep(for: .seconds(2))
                await model.markSeen(hits)
            }
        }
    }
}

/// "Tell me when" and how: shared by the follow form and a follow's own sheet. The server switch is the only
/// way to have Doddy's server check a follow, and its footer says what it keeps.
struct RadarAlertFields: View {
    @Binding var wordsText: String
    @Binding var how: RadarHow
    @Binding var time: Date
    @Binding var serverChecks: Bool
    let model: FollowingModel
    let problem: RadarAlertProblem?

    private var serverOff: Bool { model.radar?.available == false }

    var body: some View {
        Section {
            TextField("Words to look out for, e.g. ETF, ban, record", text: $wordsText)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("radar.alertWords")
        } header: {
            Text("Tell me when a story mentions")
        } footer: {
            Text("Leave it empty for every new story. Stories that mention these words get a flag.")
        }
        Section {
            // While Doddy's server checks nobody's follows, only "Here only" is offered (11 Nov 2026): the other two
            // used to grey out Add with nothing saying why, and the toggle that would have unlocked it was disabled.
            if !serverOff {
                Picker("How should Doddy tell you?", selection: $how) {
                    Text("Here only").tag(RadarHow.app)
                    Text("As it happens").tag(RadarHow.instant)
                    Text("Once a day").tag(RadarHow.daily)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("radar.how")
            }
            if how == .daily {
                DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
            }
            if how != .app && !serverOff {
                Toggle("Let Doddy's server check this for you", isOn: $serverChecks)
                    .tint(Theme.orangeCue)
                    .accessibilityIdentifier("radar.serverChecks")
            }
        } header: {
            Text("How should Doddy tell you?")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if how == .app || serverOff {
                    Text("Shown on this screen when you open it. Nothing about this follow is kept on Doddy's server.")
                    if serverOff {
                        Text("Doddy's server doesn't check follows for anyone yet, so this one shows here only.")
                    }
                } else {
                    Text("Doddy's server keeps this follow: its name, its words or feed address, the words above, how and when to tell you, and your time zone. It reads the publishers' feeds about every 20 minutes and sends a notification: as it happens outside quiet hours (21:00–8:00) and at most 8 a day, or once a day at your time. Turning it off deletes it from the server.")
                    if how == .daily {
                        Text("A daily summary may have short lines written by AI from the publishers' headlines; it says so when it does.")
                    }
                    if model.radar?.push == false {
                        Text("Notifications can't reach this iPhone yet, so what Doddy finds is listed here.")
                    }
                    if problem == .wordsNeeded {
                        Text("As it happens needs words to look out for.").foregroundStyle(Theme.error)
                    } else if !serverChecks {
                        // Say why Add waits, instead of only greying it out.
                        Text("Turn on the switch above, or choose Here only.").foregroundStyle(Theme.error)
                    }
                }
            }
        }
    }
}

enum RadarClock {
    static func date(_ text: String) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 18, minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func text(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 18, c.minute ?? 0)
    }
}

// MARK: - Sources: what can be followed

/// Add sources (13 Nov 2026): every publisher Doddy's server can read, on its shelves, and the three ways to follow.
/// Typing offers the topic the words point at, the words themselves, or the person's own feed. Picking anything
/// opens the follow form (RadarFollowForm), which shows where its stories will come from before it is added.
struct RadarAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FollowingModel
    @State private var typed = ""
    @State private var chosen: RadarChoice?
    @State private var showForm = false
    @FocusState private var typing: Bool
    private let polish = FollowingModel.polish

    private var choices: [RadarChoice] {
        RadarSuggest.choices(for: typed, catalog: model.catalog, following: model.follows, polish: polish)
    }

    private var shelves: [NewsCatalogShelf] {
        NewsCatalogShelves.group(model.catalog, polish: polish)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DoddyPageHeader(eyebrow: "On my radar", title: "Sources",
                                    subtitle: "Doddy's server reads the public news feeds of the publishers below. Follow a topic, look for your own words in all of them, or add your own feed.")
                    waysCard
                    typeSection
                    catalogSection
                    DoddyFinePrint(text: Text("Doddy's server reads only public feeds, as a polite automated reader. What you follow is kept on this iPhone and goes to your Doddy server with each refresh; the server keeps it only if you let it check a follow for you."))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(isPresented: $showForm) {
                if let chosen {
                    RadarFollowForm(model: model, choice: chosen, finish: { dismiss() })
                }
            }
            .task { await model.loadCatalog() }
            .task { await model.loadRadar() }
        }
    }

    private func pick(_ choice: RadarChoice) {
        chosen = choice
        typing = false
        showForm = true
    }

    // MARK: The three ways

    @ViewBuilder
    private var waysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Three ways to follow")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            WayRow(systemImage: "newspaper", title: "A topic from Doddy's list",
                   subtitle: "Pick a topic below: you see the newest stories of the publishers listed under it.")
            if model.keywordSearch {
                WayRow(systemImage: "text.magnifyingglass", title: "Your own words",
                       subtitle: "Type a name or a few words. Doddy's server searches news sources for them.")
            } else {
                WayRow(systemImage: "text.magnifyingglass", title: "Your own words",
                       subtitle: "Type a name or a few words. Doddy looks for them in the stories of every publisher on this list.")
            }
            WayRow(systemImage: "dot.radiowaves.up.forward", title: "Your own RSS or Atom feed",
                   subtitle: "Paste a feed's address, for example a blog or a local paper. Doddy's server reads it from there, https only.")
        }
        .doddyCard()
    }

    // MARK: Typing

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DoddySectionTitle(title: "Follow something")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                TextField("Bitcoin, CPK, Tesla or a feed address", text: $typed)
                    .focused($typing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("radar.typed")
            }
            .doddyField()
            if model.follows.isFull {
                DoddyNotice(text: Text("You follow ten things already. Remove one in Edit to add another."))
            }
            ForEach(choices) { choice in
                Button { pick(choice) } label: {
                    ChoiceCard(choice: choice, keywordSearch: model.keywordSearch, catalog: model.catalog)
                }
                .buttonStyle(.plain)
                .disabled(model.follows.isFull)
                .accessibilityIdentifier("radar.choice")
            }
        }
    }

    // MARK: Doddy's list

    @ViewBuilder
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Doddy's list")
            Text("Each topic with the publishers whose public feeds Doddy's server reads for it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !model.isServerConfigured {
                DoddyNotice(text: Text("On my radar needs a Doddy messaging server, and none is connected in this build yet."))
            } else if model.catalog.isEmpty, model.catalogFailed {
                DoddyNotice(text: Text("Doddy's list couldn't be loaded. Close this and open it again to try again."), isProblem: true)
            } else if model.catalog.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading topics…").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            ForEach(shelves) { shelf in
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: shelf.label)
                        .textCase(.uppercase)
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(shelf.topics) { topic in
                        let followed = model.isFollowing(topicID: topic.id)
                        Button {
                            pick(.topic(id: topic.id, label: topic.label, sources: topic.sources ?? []))
                        } label: {
                            TopicSourceCard(topic: topic, isFollowed: followed)
                        }
                        .buttonStyle(.plain)
                        .disabled(followed || model.follows.isFull)
                        .accessibilityHint(followed ? Text("You follow this topic") : Text("Opens this topic to follow it"))
                        .accessibilityIdentifier("radar.topic")
                    }
                }
            }
        }
    }
}

/// One way to follow, in the three-ways card.
private struct WayRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DoddyIconBadge(systemName: systemImage, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A catalog topic with every publisher that feeds it and the host Doddy's server reads it from.
private struct TopicSourceCard: View {
    let topic: NewsCatalogTopic
    let isFollowed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: topic.label)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if isFollowed {
                    Label("Following", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.confirmed)
                } else {
                    Label("Follow", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkOnOrange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.orangeCue, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(topic.publisherList, id: \.name) { publisher in
                    PublisherRow(name: publisher.name, domain: publisher.domain)
                }
            }
        }
        .doddyCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// One way to follow what was typed: a topic with its publishers, the words, or the person's own feed.
private struct ChoiceCard: View {
    let choice: RadarChoice
    let keywordSearch: Bool
    let catalog: [NewsCatalogTopic]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DoddyIconBadge(systemName: icon, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                details
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .doddyCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var icon: String {
        switch choice {
        case .topic: "newspaper"
        case .words: "text.magnifyingglass"
        case .feed: "dot.radiowaves.up.forward"
        }
    }

    @ViewBuilder
    private var details: some View {
        switch choice {
        case .topic(let id, let label, let sources):
            Text(verbatim: label).font(.headline).foregroundStyle(Theme.ink)
            Text("A topic from Doddy's list").font(.caption).foregroundStyle(Theme.secondaryText)
            let names = catalog.first(where: { $0.id == id })?.publisherList.map(\.name) ?? sources
            if !names.isEmpty {
                Text(verbatim: names.joined(separator: ", ")).font(.footnote).foregroundStyle(Theme.ink)
            }
        case .words(_, let keywords):
            Text("Follow these words").font(.headline).foregroundStyle(Theme.ink)
            Text(verbatim: String(format: NSLocalizedString("Stories that mention: %@", comment: ""), keywords.joined(separator: ", ")))
                .font(.footnote).foregroundStyle(Theme.ink)
            if keywordSearch {
                Text("Doddy's server searches news sources for these words.").font(.caption).foregroundStyle(Theme.secondaryText)
            } else {
                Text("Looked for in every publisher's feed on this list.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        case .feed(let url):
            Text("Your own feed").font(.headline).foregroundStyle(Theme.ink)
            Text(verbatim: url).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(2)
        }
    }
}

// MARK: - The follow form

/// What was picked, before it is added: where its stories come from, its name and words, a check of an own feed,
/// and "tell me when". Add keeps it on this iPhone (and, behind the switch, on Doddy's server).
struct RadarFollowForm: View {
    let model: FollowingModel
    let choice: RadarChoice
    /// Closes the whole Sources sheet once the follow was added.
    let finish: () -> Void
    @State private var name: String
    @State private var keywordsText: String
    @State private var feedLine: String?
    @State private var feedOK = false
    @State private var checking = false
    @State private var wordsText = ""
    @State private var how: RadarHow = .app
    @State private var time = RadarClock.date("18:00")
    @State private var serverChecks = false
    @State private var note: String?
    @State private var saving = false

    init(model: FollowingModel, choice: RadarChoice, finish: @escaping () -> Void) {
        self.model = model
        self.choice = choice
        self.finish = finish
        switch choice {
        case .topic(_, let label, _):
            _name = State(initialValue: label)
            _keywordsText = State(initialValue: "")
        case .words(let label, let keywords):
            _name = State(initialValue: label)
            _keywordsText = State(initialValue: keywords.joined(separator: ", "))
        case .feed(let url):
            _name = State(initialValue: URL(string: url)?.host ?? "")
            _keywordsText = State(initialValue: "")
        }
    }

    private var follow: NewsFollow? {
        switch choice {
        case .topic(let id, let label, _): .topic(id: id, label: label)
        case .words: NewsFollowList.words(name: name, keywordsText: keywordsText)
        case .feed(let url): feedOK ? NewsFollowList.feed(name: name, url: url, keywordsText: keywordsText) : nil
        }
    }

    private var alert: RadarAlert? {
        follow.map { RadarAlert(followID: $0.id, words: NewsTopic.keywords(from: wordsText), how: serverChecks ? how : .app, dailyTime: RadarClock.text(time)) }
    }

    private var problem: RadarAlertProblem? {
        guard let follow else { return nil }
        return RadarAlert(followID: follow.id, words: NewsTopic.keywords(from: wordsText), how: how, dailyTime: RadarClock.text(time)).problem(for: follow)
    }

    /// The server doesn't check follows: whatever was picked, the follow is kept here only (the picker is hidden).
    private var hereOnly: Bool { how == .app || model.radar?.available == false }

    private var canAdd: Bool {
        follow != nil && !saving && !model.follows.isFull && (hereOnly || (serverChecks && problem == nil))
    }

    var body: some View {
        Form {
            sourcesSection
            if case .words = choice { wordsSection }
            if case .feed(let url) = choice { feedSection(url) }
            if follow != nil {
                RadarAlertFields(wordsText: $wordsText, how: $how, time: $time, serverChecks: $serverChecks, model: model, problem: problem)
            }
            if let note {
                Section { Label(note, systemImage: "info.circle") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { Task { await add() } }
                    .disabled(!canAdd)
                    .accessibilityIdentifier("radar.add")
            }
        }
        .task {
            if case .feed(let url) = choice, !feedOK { await check(url) }
        }
    }

    private var title: Text {
        switch choice {
        case .topic(_, let label, _): Text(verbatim: label)
        case .words: Text("My own words")
        case .feed: Text("Your own feed")
        }
    }

    // MARK: Where its stories come from

    @ViewBuilder
    private var sourcesSection: some View {
        switch choice {
        case .topic(let id, _, let sources):
            Section {
                let publishers = model.catalog.first(where: { $0.id == id })?.publisherList
                    ?? sources.map { NewsCatalogTopic.Publisher(name: $0, domain: nil) }
                ForEach(publishers, id: \.name) { publisher in
                    PublisherRow(name: publisher.name, domain: publisher.domain)
                }
            } header: {
                Text("Where its stories come from")
            } footer: {
                Text("Doddy's server reads these publishers' public feeds when you open or refresh On my radar. Their stories from the last two days show up there.")
            }
        case .words:
            Section {
                if model.keywordSearch {
                    Text("Doddy's server searches news sources for these words.")
                } else {
                    Text("Doddy looks for these words, with their Polish and English endings, in every publisher's feed it reads.")
                }
            } header: {
                Text("Where its stories come from")
            }
        case .feed:
            EmptyView()
        }
    }

    private var wordsSection: some View {
        Section {
            TextField("Name, e.g. CPK", text: $name)
            TextField("Words to look for, comma separated", text: $keywordsText)
                .textInputAutocapitalization(.never)
        } header: {
            Text("My own words")
        } footer: {
            Text("A name for the row at the top, and the words a story must mention.")
        }
    }

    private func feedSection(_ url: String) -> some View {
        Section {
            Text(verbatim: url).font(.footnote).foregroundStyle(Theme.secondaryText)
            Button {
                Task { await check(url) }
            } label: {
                HStack {
                    Text(feedOK ? "Checked" : "Check this feed")
                    Spacer()
                    if checking {
                        ProgressView()
                    } else if feedOK {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.confirmed)
                    }
                }
            }
            .disabled(checking || feedOK)
            if let feedLine {
                Text(verbatim: feedLine).font(.footnote).foregroundStyle(feedOK ? Theme.secondaryText : Theme.error)
            }
            if feedOK {
                TextField("Name, e.g. CPK", text: $name)
                TextField("Words to look for, comma separated", text: $keywordsText)
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Your own feed")
        } footer: {
            Text("Doddy's server reads the feed from its address, https only, and never a private network. Leave the words empty to see everything from it.")
        }
    }

    private func check(_ url: String) async {
        checking = true
        defer { checking = false }
        switch await model.checkFeed(url) {
        case .ok(let feed):
            feedOK = true
            if name.isEmpty || name == URL(string: url)?.host { name = String(feed.title.prefix(60)) }
            feedLine = String(format: NSLocalizedString("%@ · %lld stories now", comment: ""), feed.title, Int64(feed.items))
        case .failed(let why):
            feedOK = false
            feedLine = why
        }
    }

    private func add() async {
        guard let follow, let alert else {
            if case .words = choice { note = NSLocalizedString("Give it a name and at least one word of two or more letters.", comment: "") }
            return
        }
        saving = true
        defer { saving = false }
        switch await model.addToRadar(follow, alert: alert) {
        case .added:
            finish()
        case .addedHereOnly(let why):
            model.message = String(format: NSLocalizedString("Added; it shows here only. %@", comment: ""), why)
            finish()
        case .notAdded(let why):
            note = why
        }
    }
}

/// A follow's own "tell me when", from the Tell me… button under its name.
struct RadarAlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FollowingModel
    let follow: NewsFollow
    @State private var wordsText: String
    @State private var how: RadarHow
    @State private var time: Date
    @State private var serverChecks: Bool
    @State private var note: String?
    @State private var saving = false

    init(model: FollowingModel, follow: NewsFollow) {
        self.model = model
        self.follow = follow
        let alert = model.alert(for: follow)
        _wordsText = State(initialValue: alert.words.joined(separator: ", "))
        _how = State(initialValue: alert.how)
        _time = State(initialValue: RadarClock.date(alert.dailyTime))
        _serverChecks = State(initialValue: alert.serverChecks)
    }

    private var draft: RadarAlert {
        RadarAlert(followID: follow.id, words: NewsTopic.keywords(from: wordsText), how: serverChecks ? how : .app, dailyTime: RadarClock.text(time))
    }

    private var problem: RadarAlertProblem? {
        RadarAlert(followID: follow.id, words: NewsTopic.keywords(from: wordsText), how: how, dailyTime: RadarClock.text(time)).problem(for: follow)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: follow.label).font(.headline).foregroundStyle(Theme.ink)
                    if let line = model.sourcesLine(for: follow) {
                        Text(verbatim: line).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                RadarAlertFields(wordsText: $wordsText, how: $how, time: $time, serverChecks: $serverChecks, model: model, problem: problem)
                if let note {
                    Section { Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Tell me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || (how != .app && model.radar?.available != false && (!serverChecks || problem != nil)))
                        .accessibilityIdentifier("radar.saveAlert")
                }
            }
            .task { await model.loadRadar() }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let alert = draft
        if await model.apply(alert, to: follow) {
            dismiss()
        } else if !alert.serverChecks {
            // Off on this iPhone; the server is told again the next time this screen loads.
            model.message = NSLocalizedString("Turned off on this iPhone. Doddy's server will be told the next time this screen loads.", comment: "")
            dismiss()
        } else {
            note = model.radarProblem
        }
    }
}
