import DoddyCore
import SwiftUI

/// Clips waiting from the Share menu and Safari (ADR-352). A clip is only a file in the inbox
/// until the person saves it: it is never a note by itself, and nothing is read from the page
/// beyond what the person chose to send.
struct MacClipsColumn: View {
    @Environment(MacStore.self) private var store
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(store.clips, id: \.id) { clip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.text).lineLimit(3)
                    Text(clip.sharedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(clip.id)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay {
            if store.clips.isEmpty {
                if ClipInboxLocation.isAvailable {
                    ContentUnavailableView("No clips waiting", systemImage: "tray",
                                           description: Text("Send a page from Safari or use the Share menu in any app."))
                } else {
                    ContentUnavailableView("Clips aren't set up", systemImage: "tray",
                                           description: Text("This build has no shared folder for the Share menu and Safari. See Settings › Extensions."))
                }
            }
        }
        .onAppear { store.refreshClips() }
        .accessibilityIdentifier("mac.clips")
    }
}

struct MacClipDetail: View {
    @Environment(MacStore.self) private var store
    let clip: ShareInboxItem
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(clip.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            Text(String(format: NSLocalizedString("Waiting since %@. It is not a note until you save it.", comment: ""), clip.sharedAt.formatted(date: .abbreviated, time: .shortened)))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Throw away", role: .destructive) { store.discardClip(clip) }
                Spacer()
                Button("Edit and save…") { store.newNote = NewNoteRequest(text: clip.text, clip: clip) }
                Button("Save as note") { Task { await saveAsIs() } }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mac.clipSave")
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func saveAsIs() async {
        do {
            try await store.saveClip(clip, text: clip.text, category: .other)
            message = nil
        } catch {
            // The clip stays in the inbox, so nothing is lost.
            message = MacError.message(for: error)
        }
    }
}
