import DoddyCore
import SwiftUI

/// Settings → Daily news: what to follow, when, and where Doddy sends the short message.
struct NewsSettingsView: View {
    @State private var model = NewsModel()
    @State private var newFeed = ""

    var body: some View {
        Form {
            if !model.isServerConfigured {
                Section { Text("Daily news needs a Doddy messaging server, and none is connected in this build yet.") }
            } else if model.loaded != nil {
                content
            } else if !model.isWorking {
                Section { Button("Try again") { Task { await model.refresh() } } }
            }
            if let message = model.message {
                Section { Label(message, systemImage: "info.circle").accessibilityIdentifier("news.message") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Daily news")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView() } }
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        let available = model.loaded?.available

        Section {
            Toggle("Send me daily news", isOn: $model.enabled)
                .accessibilityIdentifier("news.enabled")
            DatePicker("Time", selection: $model.sendTime, displayedComponents: .hourAndMinute)
            Picker("Language", selection: $model.language) {
                Text("English").tag("en")
                Text("Polski").tag("pl")
            }
            if model.enabled, let next = model.nextRunText {
                StatusRow(title: "Next", value: next)
            }
        } footer: {
            Text("Once a day, in your current time zone (\(TimeZone.current.identifier)).")
        }

        Section("Send it as") {
            Toggle("Notification", isOn: $model.push)
            Toggle("Text message", isOn: $model.sms)
            NavigationLink("Notifications and texts setup") { UpdatesSettingsView() }
            Text("Notifications show a short list; tap it and the links are below. Texts include up to three links and may cost the usual SMS rate.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }

        Section("Topics") {
            ForEach(model.catalog) { topic in
                Button {
                    model.toggleCatalog(topic.id)
                } label: {
                    HStack {
                        Text(topic.label).foregroundStyle(Theme.ink)
                        Spacer()
                        if model.selectedCatalog.contains(topic.id) {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accentText)
                        }
                    }
                }
                .accessibilityAddTraits(model.selectedCatalog.contains(topic.id) ? .isSelected : [])
            }
        }

        Section {
            ForEach($model.ownTopics) { $topic in
                VStack(alignment: .leading) {
                    TextField("Name, e.g. Coffee", text: $topic.label)
                    TextField("Keywords, comma separated", text: $topic.keywordsText)
                        .textInputAutocapitalization(.never)
                        .font(.footnote)
                }
            }
            .onDelete { model.ownTopics.remove(atOffsets: $0) }
            Button("Add my own topic") { model.ownTopics.append(.init(label: "", keywordsText: "")) }
                .disabled(model.ownTopics.count + model.selectedCatalog.count >= 10)
        } header: {
            Text("My own topics")
        } footer: {
            Text(available?.keywordSearch == true
                 ? "Doddy searches news sources for these words."
                 : "Doddy looks for these words in the stories from your topics and feeds.")
        }

        Section {
            ForEach(model.feeds, id: \.self) { url in
                VStack(alignment: .leading) {
                    Text(model.loaded?.feeds.first { $0.url == url }?.title ?? url)
                    if model.loaded?.feeds.first(where: { $0.url == url })?.failing == true {
                        Text("Couldn't load this feed last time").font(.footnote).foregroundStyle(Theme.error)
                    }
                }
            }
            .onDelete { model.feeds.remove(atOffsets: $0) }
            TextField("https://example.com/feed", text: $newFeed)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Check and add") { Task { await model.addFeed(newFeed); newFeed = "" } }
                .disabled(newFeed.isEmpty || model.feeds.count >= 10)
        } header: {
            Text("My feeds")
        } footer: {
            Text("Any RSS or Atom feed, for example a blog or a local newspaper.")
        }

        Section {
            Button("Save") { Task { await model.save() } }
                .accessibilityIdentifier("news.save")
            Button("Send me one now") { Task { await model.sendNow() } }
                .disabled(model.loaded?.topics.isEmpty != false && model.loaded?.feeds.isEmpty != false)
        } footer: {
            Text(available?.writer == true
                 ? "An AI (Claude, by Anthropic) picks the stories and writes each line from the headline and the publisher's summary. It can get things wrong: the link always goes to the full story. Only your topics and public headlines are sent to it."
                 : "AI summaries aren't set up on the server, so you'll get the top headlines.")
        }

        if !model.digests.isEmpty {
            Section("Recent") {
                ForEach(model.digests) { digest in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(DateText.full(digest.createdDate))\(digest.aiWritten ? " · written by AI" : "")")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        if digest.items.isEmpty {
                            Text(digest.status == "empty" ? "Nothing new that day." : "Not sent.")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(digest.items, id: \.url) { item in
                            if let url = URL(string: item.url) {
                                Link(destination: url) {
                                    Text("\(item.line) ") + Text(item.source).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
