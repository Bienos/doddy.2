import DoddyCore
import SwiftUI

// On my radar (owner, 10 Nov 2026; decision 2026-11-10-radar-alerts): one sheet to add anything ("bitcoin",
// "CPK", "Tesla", a feed address), the tapped follow's sources and "tell me when", and the stories Doddy's
// server spotted. Nothing here is written by an AI: headlines and publishers are the feeds' own. A server check
// is offered only behind its own switch, and said to be on only when the server's answer lists it.

/// The tapped follow: where its stories come from, how Doddy tells about it, and an honest empty state.
struct FollowDetail: View {
    let model: FollowingModel
    let follow: NewsFollow
    let polish: Bool
    let tellMe: () -> Void

    var body: some View {
        let alert = model.alert(for: follow)
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: follow.label)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let line = model.sourcesLine(for: follow) {
                Label { Text(verbatim: line) } icon: { Image(systemName: "dot.radiowaves.left.and.right") }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !follow.keywords.isEmpty {
                Label {
                    Text(String(format: NSLocalizedString("Stories that mention: %@", comment: ""), follow.keywords.joined(separator: ", ")))
                } icon: { Image(systemName: "text.magnifyingglass") }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label { Text(verbatim: alert.summary(polish: polish)) } icon: {
                    Image(systemName: alert.serverChecks ? "bell.badge" : "eye")
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Button("Tell me…", action: tellMe)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("radar.tellMe")
            }
            if model.fetchedAt != nil, !model.isLoading, model.problem == nil, model.visibleCards.isEmpty {
                Text(String(format: NSLocalizedString("Nothing from the last two days for %@. Pull down to look again.", comment: ""), follow.label))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("radar.nothing")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
                Text("Doddy spotted")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .task(id: hits.map(\.id)) {
                // Seen once they have been on screen for a moment.
                try? await Task.sleep(for: .seconds(2))
                await model.markSeen(hits)
            }
        }
    }
}

/// "Tell me when" and how: shared by the add sheet and a follow's own sheet. The server switch is the only
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

/// Add to the radar: type anything; Doddy offers the catalog topic it points at, the words themselves, or the
/// person's own feed; then optionally "tell me when" and how.
struct RadarAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FollowingModel
    @State private var typed = ""
    @State private var picked: RadarChoice?
    @State private var name = ""
    @State private var keywordsText = ""
    @State private var feedLine: String?
    @State private var feedOK = false
    @State private var checking = false
    @State private var wordsText = ""
    @State private var how: RadarHow = .app
    @State private var time = RadarClock.date("18:00")
    @State private var serverChecks = false
    @State private var note: String?
    @State private var saving = false
    @FocusState private var typing: Bool
    private let polish = FollowingModel.polish

    private var choices: [RadarChoice] {
        RadarSuggest.choices(for: typed, catalog: model.catalog, following: model.follows, polish: polish)
    }

    private var follow: NewsFollow? {
        switch picked {
        case .topic(let id, let label, _)?: .topic(id: id, label: label)
        case .words?: NewsFollowList.words(name: name, keywordsText: keywordsText)
        case .feed(let url)?: feedOK ? NewsFollowList.feed(name: name, url: url, keywordsText: keywordsText) : nil
        case nil: nil
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
        NavigationStack {
            Form {
                Section {
                    TextField("Bitcoin, CPK, Tesla or a feed address", text: $typed)
                        .focused($typing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .accessibilityIdentifier("radar.typed")
                } footer: {
                    Text("Type a topic, a name or a few words, or paste the address of an RSS or Atom feed.")
                }
                if !choices.isEmpty || picked != nil {
                    Section("What to follow") {
                        ForEach(choicesShown) { choice in
                            Button { pick(choice) } label: { ChoiceRow(choice: choice, picked: picked?.id == choice.id, keywordSearch: model.keywordSearch) }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(picked?.id == choice.id ? .isSelected : [])
                        }
                    }
                }
                if case .words? = picked {
                    Section {
                        TextField("Name, e.g. CPK", text: $name)
                        TextField("Words to look for, comma separated", text: $keywordsText)
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("My own words")
                    } footer: {
                        if model.keywordSearch {
                            Text("Doddy's server searches news sources for these words.")
                        } else {
                            Text("Doddy looks for these words, with their Polish and English endings, in every publisher's feed it reads.")
                        }
                    }
                }
                if case .feed(let url)? = picked {
                    Section {
                        Button {
                            Task { await check(url) }
                        } label: {
                            HStack {
                                Text(feedOK ? "Checked" : "Check this feed")
                                Spacer()
                                if checking { ProgressView() }
                                else if feedOK { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.confirmed) }
                            }
                        }
                        .disabled(checking || feedOK)
                        if let feedLine { Text(verbatim: feedLine).font(.footnote).foregroundStyle(feedOK ? Theme.secondaryText : Theme.error) }
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
                if follow != nil {
                    RadarAlertFields(wordsText: $wordsText, how: $how, time: $time, serverChecks: $serverChecks, model: model, problem: problem)
                }
                Section("Topics") {
                    if model.availableTopics.isEmpty, model.catalog.isEmpty {
                        Text("Loading topics…").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(model.availableTopics) { topic in
                        let choice = RadarChoice.topic(id: topic.id, label: topic.label, sources: topic.sources ?? [])
                        Button { pick(choice) } label: { ChoiceRow(choice: choice, picked: picked?.id == choice.id, keywordSearch: model.keywordSearch) }
                            .buttonStyle(.plain)
                    }
                }
                if let note {
                    Section { Label(note, systemImage: "info.circle") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Add to radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(!canAdd)
                        .accessibilityIdentifier("radar.add")
                }
            }
            .task { await model.loadCatalog() }
            .task { await model.loadRadar() }
            .onAppear { typing = true }
            .onChange(of: typed) { _, _ in
                let first = choices.first
                picked = first
                name = String(typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                keywordsText = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                feedOK = false
                feedLine = nil
                if case .feed(let url)? = first { name = URL(string: url)?.host ?? "" ; keywordsText = "" }
                note = nil
            }
        }
    }

    /// The suggestions, plus a topic picked from the list below if it isn't one of them.
    private var choicesShown: [RadarChoice] {
        var list = choices
        if let picked, !list.contains(where: { $0.id == picked.id }) { list.insert(picked, at: 0) }
        return list
    }

    private func pick(_ choice: RadarChoice) {
        picked = choice
        note = nil
        if case .feed(let url) = choice, !feedOK { Task { await check(url) } }
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
            if case .words? = picked { note = NSLocalizedString("Give it a name and at least one word of two or more letters.", comment: "") }
            return
        }
        saving = true
        defer { saving = false }
        switch await model.addToRadar(follow, alert: alert) {
        case .added:
            dismiss()
        case .addedHereOnly(let why):
            model.message = String(format: NSLocalizedString("Added; it shows here only. %@", comment: ""), why)
            dismiss()
        case .notAdded(let why):
            note = why
        }
    }
}

/// One way to follow what was typed: a topic with its publishers, the words, or the person's own feed.
private struct ChoiceRow: View {
    let choice: RadarChoice
    let picked: Bool
    let keywordSearch: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(picked ? Theme.accentText : Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                switch choice {
                case .topic(_, let label, let sources):
                    Text(verbatim: label).foregroundStyle(Theme.ink)
                    if sources.isEmpty {
                        Text("A topic from Doddy's list").font(.caption).foregroundStyle(Theme.secondaryText)
                    } else {
                        Text(String(format: NSLocalizedString("Topic · %@", comment: ""), sources.joined(separator: ", ")))
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                case .words(_, let keywords):
                    Text("Follow these words").foregroundStyle(Theme.ink)
                    Text(String(format: NSLocalizedString("Stories that mention: %@", comment: ""), keywords.joined(separator: ", ")))
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                case .feed(let url):
                    Text("Your own feed").foregroundStyle(Theme.ink)
                    Text(verbatim: url).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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
