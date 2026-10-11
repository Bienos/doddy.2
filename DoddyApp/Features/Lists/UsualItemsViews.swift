import DoddyCore
import SwiftUI

/// Items ticked at least twice on lists with this name, offered unticked. Only the ones the user
/// ticks here are added, through the same path as typing them.
struct UsualItemsSheet: View {
    let list: DoddyList
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var problem: String?
    @State private var working = false
    @State private var confirmForget = false

    private var suggestions: [UsualItem] { UsualItemsStore.current().suggestions(for: list) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions, id: \.text) { item in
                        let on = picked.contains(item.text)
                        Button {
                            if on { picked.remove(item.text) } else { picked.insert(item.text) }
                        } label: {
                            HStack {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                                Text(item.text)
                                Spacer()
                                Text(String(format: NSLocalizedString("ticked %lld times", comment: "Usual item"), item.count))
                                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                } footer: {
                    Text("From what you ticked off on lists called this before. It stays on this iPhone.")
                }
                if let problem { Section { Text(problem).foregroundStyle(Theme.error) } }
                Section {
                    Button("Forget what I usually get here", role: .destructive) { confirmForget = true }
                }
            }
            .navigationTitle("The usual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(format: NSLocalizedString("Add %lld", comment: "Usual items"), picked.count)) { Task { await add() } }
                        .disabled(picked.isEmpty || working)
                }
            }
            .confirmationDialog("Forget what you usually get on this list?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    if UsualItemsStore.forget(listNamed: list.name) { dismiss() } else { problem = NSLocalizedString("It couldn't be forgotten. Try again.", comment: "") }
                }
            } message: {
                Text("Doddy starts counting again from your next ticks. Your lists don't change.")
            }
        }
    }

    private func add() async {
        working = true
        defer { working = false }
        // In the order shown.
        let texts = suggestions.map(\.text).filter(picked.contains)
        do {
            try await store.addToList(texts, listID: list.id, source: .typed)
            dismiss()
        } catch {
            problem = UserFacingError.listMessage(for: error)
        }
    }
}
