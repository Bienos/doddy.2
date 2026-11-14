import DoddyCore
import SwiftUI

/// Settings › Doddy on the web › Logbook (ADR-602): one switch, on unless the person turned it off
/// (decision 2026-11-09-usage-counts-on-by-default). The rules are `LogbookModel` in DoddyCore,
/// tested on Linux; this file only draws them. "Deleted" is said only after Doddy's server confirmed.
struct LogbookSection: View {
    @Environment(MemoryStore.self) private var store
    private let model = Logbook.shared

    var body: some View {
        Section {
            Toggle("Count how I use Doddy", isOn: Binding(
                get: { model.isOn },
                set: { on in
                    let sources = Logbook.sources(store: store)
                    Task { await model.setOn(on, sources: sources) }
                }))
                .disabled(model.working)
                .accessibilityIdentifier("logbook.switch")
            if model.working {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for Doddy's server…")
                }
            }
            if model.isOn, let sent = model.lastSent {
                LabeledContent("Last sent") {
                    Text(sent.formatted(date: .omitted, time: .shortened))
                }
            }
            if !model.isOn {
                if model.deletionPending {
                    Text("Counting stopped. The counts already on Doddy's server will be deleted when it can be reached.")
                        .foregroundStyle(Theme.secondaryText)
                } else if model.deletedDays != nil {
                    Text("Counting stopped. Doddy's server deleted the counts it held.")
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("logbook.deleted")
                }
            }
            if let problem = model.problem {
                LogbookProblemText(problem: problem)
                    .accessibilityIdentifier("logbook.problem")
            }
        } header: {
            Text("Logbook")
        } footer: {
            Text("On unless you turn it off. Doddy counts how you use him: conversations, what he did for you, notes and list items saved. Never the words of your conversations or notes. The counts go to Doddy's server, where you see them in Logbook on the web and Doddy's team can see them with your account. Turning this off stops counting and deletes the counts on the server.")
        }
    }
}

private struct LogbookProblemText: View {
    let problem: LogbookModel.Problem

    var body: some View {
        Group {
            switch problem {
            case .notConfigured:
                Text("Doddy on the web needs Doddy's server, which isn't set up in this build.")
            case .signedOut:
                Text("Doddy's server didn't accept this iPhone. Try again in a moment.")
            case .offline:
                Text("Doddy's server couldn't be reached. Check your connection and try again.")
            case .tooMany:
                Text("Too many tries. Try again later.")
            case .notSetUp:
                Text("Doddy's server isn't set up to keep this yet. Nothing was sent.")
            case .unreadable:
                Text("Doddy's server sent something the app couldn't read. Nothing was changed here.")
            case .server:
                Text("Something went wrong on Doddy's server. Nothing was changed.")
            case .otherAccountsData:
                // Decision 2026-11-12-local-data-owner.
                Text("This iPhone holds Doddy data from another account, so nothing from it is sent to yours. Nothing was sent.")
            }
        }
        .foregroundStyle(Theme.error)
    }
}
