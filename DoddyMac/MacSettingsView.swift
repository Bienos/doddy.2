import AppKit
import SwiftUI

/// What the Mac app does and doesn't do, stated from what the code does. No toggles yet: there is
/// nothing to switch (no microphone, no network, no sync).
struct MacSettingsView: View {
    let model: MacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Doddy on this Mac").font(.title3.weight(.semibold))
            fact("Notes are stored only on this Mac, in this app's own folder. They aren't sent anywhere.")
            fact("This Mac app has no microphone access and never listens. Talk to Doddy and Translate are on the iPhone.")
            fact("It doesn't sync with Doddy on your iPhone yet: notes saved there don't appear here, and the other way round.")
            fact("It makes no network connections.")
            if let url = model.databaseURL {
                Divider()
                Text("Memory file").font(.subheadline.weight(.semibold))
                Text(url.path).font(.caption.monospaced()).textSelection(.enabled)
                    .foregroundStyle(MacTheme.secondaryText)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func fact(_ text: String) -> some View {
        Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
    }
}
