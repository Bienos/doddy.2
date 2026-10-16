import DoddyCore
import SwiftUI

/// The profile values the user approved, with a direct route back to Settings for changes.
struct HomeAboutYouCard: View {
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(PreferenceKey.shareProfileWithVoice) private var shareProfileWithVoice = false

    var body: some View {
        let profile = profiles.profile
        let shown = [ProfileKey.context, .help, .style].filter { profile.value($0) != nil }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("What you told me")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(shown, id: \.self) { key in
                    StatusRow(title: key.label, value: profile.value(key) ?? "")
                }
                Text(shareProfileWithVoice
                    ? "Doddy knows these in voice conversations. Change or forget them in Settings."
                    : "Change or forget these in Settings. Voice conversations don't use them unless you turn that on there.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(16)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Recent saved memories, including the existing private-note check before offering a conversation.
struct HomeRecentMemories: View {
    @Environment(MemoryStore.self) private var store
    private var router: ShortcutRouter { .shared }

    var body: some View {
        if !store.memories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently saved")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                let privateNotes = PrivateNotesStore.current()
                let canTalk = store.environment.capabilities.isAvailable(.voiceInput)
                ForEach(store.memories.prefix(3)) { record in
                    HStack(spacing: 8) {
                        NavigationLink(value: record.id) {
                            MemoryRow(record: record)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if canTalk && NoteQuestion.canAsk(about: record, privateNotes: privateNotes) {
                            Button { router.askAboutNote(record.id) } label: {
                                Image(systemName: "waveform.circle")
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accentText)
                            .accessibilityLabel("Ask me about it")
                            .accessibilityIdentifier("home.recent.ask")
                        }
                    }
                    Divider()
                }
            }
        } else if store.hasLoaded {
            Text("Nothing saved yet. You choose what stays.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

enum HomeTool: String, Identifiable {
    case focus, breathe
    var id: String { rawValue }
}

struct HomeActionTile: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(title).font(.subheadline)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// Whether Home's idle breaths have played in this launch (ADR-313).
@MainActor
enum HomeIdle {
    static var played = false
    /// He sat down on his box this launch (ADR-323): later visits show him seated, without replaying.
    static var sat = false

    /// The day Home last waved (ADR-380), on this iPhone only. Not a note.
    static let waveDayKey = "home.lastWaveDay"

    /// True the first time it is asked on a morning; it then records the day (`MorningWave`).
    static func wavesThisMorning(now: Date, defaults: UserDefaults = .standard) -> Bool {
        guard let day = MorningWave.dayToRecord(now: now, lastWaveDay: defaults.string(forKey: waveDayKey)) else { return false }
        defaults.set(day, forKey: waveDayKey)
        return true
    }
}

/// The newest unfinished note on Home (ADR-362): Continue opens it on the capture screen; Discard
/// removes it after asking. It is a draft, not a note.
struct UnfinishedNoteCard: View {
    let note: UnfinishedNote
    let more: Int
    let onContinue: () -> Void
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unfinished note", systemImage: "doc.badge.clock").font(.headline)
            Text(verbatim: note.preview())
                .lineLimit(2)
            Text(String(format: NSLocalizedString("Not saved yet · last changed %@", comment: ""),
                        note.updatedAt.formatted(date: .abbreviated, time: .shortened)))
                .font(.caption).foregroundStyle(Theme.secondaryText)
            if more > 0 {
                Text(String(format: NSLocalizedString("%lld more unfinished notes; each opens when you start a new note.", comment: ""), more))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 12) {
                Button(action: onContinue) {
                    HStack { Text("Continue"); Spacer(); Image(systemName: "square.and.pencil") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("home.unfinishedNote.continue")
                Button("Discard") { confirmDiscard = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("home.unfinishedNote")
        .confirmationDialog("Discard this unfinished note?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { UnfinishedNoteStore.shared.remove(id: note.id) }
            Button("Keep it", role: .cancel) {}
        } message: { Text("It was never saved, so it can't be brought back.") }
    }
}

/// Settings › Privacy › What leaves this iPhone, opened from Home's footer (ADR-326).
struct DataFlowSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DataFlowView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// "Hey Doddy" with one tap (ADR-328): offered once, after a few conversations that really
/// connected, and only when one tap is enough (`HeyDoddyOffer`). Turn on and Not now both end the
/// offer for good. After Turn on it shows the listener's own state, never a "Listening" it isn't.
struct HeyDoddyCard: View {
    @AppStorage(PreferenceKey.connectedConversations) private var conversations = 0
    @AppStorage(PreferenceKey.heyDoddyOn) private var heyDoddyOn = false
    @AppStorage(PreferenceKey.heyDoddyOfferDone) private var offerDone = false
    @State private var listener = WakeWordListener.shared
    /// Read once: the Keychain isn't read again on every redraw of Home.
    @State private var oneTapReady = WakeOneTapSetup.isReady
    @State private var isTurningOn = false
    @State private var showsResult = false

    var body: some View {
        if showsResult {
            result
        } else if HeyDoddyOffer.shouldOffer(conversations: conversations, heyDoddyOn: heyDoddyOn,
                                            dismissed: offerDone, oneTapReady: oneTapReady) {
            offer
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Talk without tapping")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Say \u{201C}Hey Doddy\u{201D} and I'll answer. I listen for it on this iPhone, with iOS's orange microphone dot showing, until you stop me. It uses some battery.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button {
                    isTurningOn = true
                    offerDone = true
                    Task {
                        await listener.turnOn()
                        isTurningOn = false
                        showsResult = true
                    }
                } label: {
                    if isTurningOn { Text("Turning on…") } else { Text("Turn on") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isTurningOn)
                .accessibilityIdentifier("home.heyDoddy.turnOn")
                Button("Not now") { offerDone = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isTurningOn)
                    .accessibilityIdentifier("home.heyDoddy.notNow")
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hey Doddy")
                .font(.headline)
            Text(listener.keyProblem ?? listener.state.summary)
                .font(.subheadline)
                .foregroundStyle(listener.keyProblem == nil ? Theme.secondaryText : Theme.error)
                .accessibilityIdentifier("home.heyDoddy.status")
            Text("Change it in Settings \u{203A} Hey Doddy.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}
