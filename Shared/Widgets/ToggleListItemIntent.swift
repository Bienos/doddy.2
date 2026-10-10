import AppIntents
import Foundation

/// A tap on a list item in a widget (ADR-219, owner: "Yes, tick from widget"). It runs in the
/// Doddy app's process, never in the widget extension: like the Dynamic Island buttons
/// (ADR-131) it is a `LiveActivityIntent`, which iOS performs in the app, starting it in the
/// background when needed. There the tick goes through the same store as in the app and is read
/// back; the widget then redraws from the new snapshot. Needs the iPhone unlocked.
struct ToggleListItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Tick a list item in Doddy"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    /// See `EndDoddyConversationIntent.allowedExecutionTargets` (ADR-131): only the app has the store.
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "List") var listID: String
    @Parameter(title: "Item") var itemID: String
    /// Whether the widget showed it ticked: a stale widget never flips an item changed since.
    @Parameter(title: "Shown ticked") var shownDone: Bool

    init() {}

    init(listID: UUID, itemID: UUID, shownDone: Bool) {
        self.listID = listID.uuidString
        self.itemID = itemID.uuidString
        self.shownDone = shownDone
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        if let list = UUID(uuidString: listID), let item = UUID(uuidString: itemID) {
            _ = await WidgetSync.shared.tick(listID: list, itemID: item, shownDone: shownDone)
        }
        #endif
        return .result()
    }
}
