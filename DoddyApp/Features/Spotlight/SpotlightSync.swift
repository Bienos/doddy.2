@preconcurrency import CoreSpotlight
import DoddyCore
import Foundation
import SwiftUI

/// Keeps iPhone search (Spotlight) equal to Doddy's notes and lists when the user turned it on
/// (ADR-330). Private notes are never indexed; switching it off removes Doddy's whole domain.
/// The index stays on this iPhone; iOS reads it after the first unlock.
@MainActor
final class SpotlightSync {
    static let shared = SpotlightSync()

    weak var store: MemoryStore?
    private var lastSignature: String?
    private let index = CSSearchableIndex(name: "doddy", protectionClass: .completeUntilFirstUserAuthentication)

    private init() {}

    static var isOn: Bool { UserDefaults.standard.bool(forKey: SpotlightIndex.enabledKey) }

    func refresh() {
        guard let store, store.hasLoaded else { return }
        let entries = SpotlightIndex.entries(
            memories: store.memories, lists: store.lists,
            privateNotes: PrivateNotesStore.current(), isOn: Self.isOn)
        let signature = SpotlightIndex.signature(entries)
        guard signature != lastSignature else { return }
        lastSignature = signature
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.title
            attributes.contentDescription = entry.content
            attributes.keywords = entry.keywords
            return CSSearchableItem(uniqueIdentifier: entry.id.uuidString, domainIdentifier: SpotlightIndex.domain, attributeSet: attributes)
        }
        let index = index
        // Rebuilt as a whole: notes that were deleted or made private go too.
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// The note or list a Spotlight result stands for.
    static func memoryID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return UUID(uuidString: id)
    }
}

/// Settings › Privacy: "Show in iPhone search", off by default.
struct SpotlightToggle: View {
    @AppStorage(SpotlightIndex.enabledKey) private var isOn = false

    var body: some View {
        Toggle("Show notes in iPhone search", isOn: $isOn)
            .onChange(of: isOn) { SpotlightSync.shared.refresh() }
            .accessibilityIdentifier("settings.spotlight")
        Text("Your notes and lists can be found from the iPhone's search. The index stays on this iPhone. Private notes are never included, and turning this off removes them all from search.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }
}
