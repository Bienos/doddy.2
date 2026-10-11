import DoddyCore
import SwiftUI

/// "Open Doddy": the notes saved on this Mac, newest first. Read-only in this version.
struct NotesWindow: View {
    let model: MacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DoddyFace(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes on this Mac").font(.title3.weight(.semibold))
                    Text("Doddy doesn't sync with your iPhone yet, so notes saved on the iPhone aren't here.")
                        .font(.caption).foregroundStyle(MacTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            Divider()
            if let problem = model.storageProblem {
                message(problem, color: MacTheme.error)
            } else if let error = model.loadError {
                message(error, color: MacTheme.error)
            } else if model.memories.isEmpty {
                message("Nothing saved on this Mac yet. Use Remember something in the menu bar.", color: MacTheme.secondaryText)
            }
            List(model.memories, id: \.id) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.currentText)
                    if let date = record.capturedAt {
                        Text("Saved \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(MacTheme.secondaryText)
                    }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .task { await model.reload() }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text).font(.callout).foregroundStyle(color).padding(16)
            .fixedSize(horizontal: false, vertical: true)
    }
}
