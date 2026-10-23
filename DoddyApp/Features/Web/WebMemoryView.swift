import DoddyCore
import SwiftUI

/// Settings → Doddy on the web → Keep on Doddy's server (ADR-595): two switches (notes, conversations),
/// a consent screen before either goes on, and one button that deletes everything the server keeps. The
/// rules are `WebMemoryModel` in DoddyCore, tested on Linux; this file only draws them. A switch changes
/// only after Doddy's server said so, and nothing is called kept or deleted before it did.
struct WebMemorySection: View {
    @Environment(MemoryStore.self) private var store
    @State private var asking: Consent?
    @State private var confirmingDelete = false
    @State private var deletedMessage: String?
    private let model = WebMemory.shared

    private struct Consent: Identifiable {
        let kind: WebMemoryModel.Kind
        var id: String { kind == .notes ? "notes" : "conversations" }
    }

    var body: some View {
        Section {
            Toggle("Notes", isOn: binding(.notes))
                .disabled(model.working)
                .accessibilityIdentifier("webMemory.notes")
            Toggle("Conversations", isOn: binding(.conversations))
                .disabled(model.working)
                .accessibilityIdentifier("webMemory.conversations")
            if model.working {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for Doddy's server…")
                }
            }
            if let problem = model.problem {
                WebMemoryProblemText(problem: problem)
                    .accessibilityIdentifier("webMemory.problem")
            }
            notesStatus
            if let deletedMessage {
                Text(deletedMessage)
                    .foregroundStyle(Theme.secondaryText)
            }
            if model.notesOn || model.conversationsOn {
                Button("Delete everything on Doddy's server", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(model.working)
                .accessibilityIdentifier("webMemory.deleteAll")
            }
        } header: {
            Text("Keep on Doddy's server")
        } footer: {
            Text("Off unless you turn it on. Otherwise your notes and what you and Doddy say stay on this iPhone. Text only, never audio; private notes and private conversations are never kept. Read and search it on the web, or ask Doddy about it there.")
        }
        .sheet(item: $asking) { consent in
            WebMemoryConsent(
                kind: consent.kind,
                turnOn: {
                    asking = nil
                    Task { await turn(consent.kind, on: true) }
                },
                notNow: { asking = nil })
        }
        .confirmationDialog("Delete everything Doddy's server keeps for you?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task { await deleteEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your notes and conversations on this iPhone stay. Both switches go off.")
        }
    }

    /// Off is asked of the server at once. On goes through the consent screen first, and the switch stays
    /// off until the server confirmed.
    private func binding(_ kind: WebMemoryModel.Kind) -> Binding<Bool> {
        Binding(
            get: { kind == .notes ? model.notesOn : model.conversationsOn },
            set: { wantOn in
                deletedMessage = nil
                if wantOn {
                    asking = Consent(kind: kind)
                } else {
                    Task { await turn(kind, on: false) }
                }
            })
    }

    private func turn(_ kind: WebMemoryModel.Kind, on: Bool) async {
        await model.setKept(kind, on: on, records: store.memories, privateNotes: PrivateNotesStore.current())
    }

    private func deleteEverything() async {
        guard let done = await model.deleteEverythingOnServer() else { return }
        deletedMessage = done.deletedNotes + done.deletedConversations == 0
            ? NSLocalizedString("Nothing was kept, so nothing was deleted.", comment: "")
            : NSLocalizedString("Deleted from Doddy's server. Both switches are off.", comment: "")
    }

    @ViewBuilder private var notesStatus: some View {
        switch model.notesStatus {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 12) {
                ProgressView()
                Text("Sending your notes…")
            }
        case .sent(let count, _):
            HStack(spacing: 4) {
                Text("Notes on Doddy's server:")
                Text(verbatim: "\(count)")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement(children: .combine)
        case .failed(let problem):
            WebMemoryProblemText(problem: problem)
            Text("Doddy will try again.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// What it means to turn this on, said before it is turned on. "Turn on" and "Not now" are the same size.
private struct WebMemoryConsent: View {
    let kind: WebMemoryModel.Kind
    let turnOn: () -> Void
    let notNow: () -> Void

    // Text("…") in each branch, so every sentence is in the string catalog and can be translated.
    private var title: Text {
        switch kind {
        case .notes: Text("Keep your notes on Doddy's server?")
        case .conversations: Text("Keep your conversations on Doddy's server?")
        }
    }

    private var what: Text {
        switch kind {
        case .notes:
            Text("Doddy keeps a copy of your saved notes, as text, so you can read and search them on the web and ask Doddy about them there. Private notes are never kept. The copy matches this iPhone: a note you delete here is deleted there at the next send.")
        case .conversations:
            Text("Doddy keeps what you and Doddy said in each conversation, as text, for 1 year, so you can read and search it on the web and ask Doddy about it there. Never audio. Private conversations are never kept.")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    title
                        .font(.title2.weight(.bold))
                    what
                    Text("It is stored encrypted, but Doddy's server can read it, so it can be searched. When you ask a question on the web, Claude (made by Anthropic) reads the best matches to write the answer. It is not sold and not used for ads.")
                    Text("You can turn this off whenever you like. That deletes it from Doddy's server. You can also read it, download it and delete it on the web.")
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button(action: turnOn) {
                        Text("Turn on")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("webMemory.consent.turnOn")
                    Button(action: notNow) {
                        Text("Not now")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("webMemory.consent.notNow")
                }
                .padding(20)
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }
}

/// What went wrong, in the person's language. Nothing here claims an action happened.
private struct WebMemoryProblemText: View {
    let problem: WebMemoryModel.Problem

    var body: some View {
        Group {
            switch problem {
            case .notConfigured:
                Text("Doddy on the web needs Doddy's server, which isn't set up in this build.")
            case .signedOut:
                Text("Doddy's server didn't accept this iPhone. Try again in a moment.")
            case .off:
                Text("Doddy's server isn't keeping this any more (it may have been deleted on the web). Turn it on again if you want it kept.")
            case .notSetUp:
                Text("Doddy's server isn't set up to keep this yet. Nothing was sent.")
            case .tooLarge:
                Text("That was more than Doddy's server will keep. Nothing was stored.")
            case .tooMany:
                Text("Too many tries. Try again later.")
            case .offline:
                Text("Doddy's server couldn't be reached. Check your connection and try again.")
            case .unreadable:
                Text("Doddy's server sent something the app couldn't read. Nothing was changed here.")
            case .server:
                Text("Something went wrong on Doddy's server. Nothing was changed.")
            }
        }
        .foregroundStyle(Theme.error)
    }
}
