import AppIntents
import DoddyCore
import Foundation

// Lists from Siri, Shortcuts and the Action Button (ADR-226). App target only: these run in the
// app's process (iOS starts it in the background when needed), through the same store calls as
// the list screen and voice, and Siri says only what the store read back. Changing or reading a
// list needs the iPhone unlocked, so nothing is read out on a locked phone.

/// The store the intents use; set once in `DoddyApp.init`.
@MainActor
enum IntentStores {
    static weak var store: MemoryStore?
    /// The reviewed profile, for Talk in the Island's "Hey <name>" (ADR-577).
    static weak var profiles: ProfileStore?

    static func loaded() async -> MemoryStore? {
        guard let store else { return nil }
        await store.reload()
        return store
    }

    /// The lists read from the store first, so a Siri lookup on a cold launch doesn't see the
    /// empty list from before the first load and answer "list not found" (review H5).
    static func loadedLists() async -> [DoddyList] {
        await loaded()?.lists ?? []
    }
}

struct DoddyListEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Doddy list" }
    static var defaultQuery: DoddyListQuery { DoddyListQuery() }

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct DoddyListQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [DoddyListEntity] {
        await Self.lists().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DoddyListEntity] { await Self.lists() }

    /// The same exact matching as voice: "shopping list" finds "Shopping"; no closest guess.
    func entities(matching string: String) async throws -> [DoddyListEntity] {
        let lists = await IntentStores.loadedLists()
        switch ListMatch.list(named: string, in: lists) {
        case .one(let list): return [DoddyListEntity(id: list.id, name: list.name)]
        case .several(let found): return found.map { DoddyListEntity(id: $0.id, name: $0.name) }
        case .none: return []
        }
    }

    private static func lists() async -> [DoddyListEntity] {
        await IntentStores.loadedLists().map { DoddyListEntity(id: $0.id, name: $0.name) }
    }
}

/// "Add milk to my shopping list in Doddy".
struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to a list in Doddy"
    static var description: IntentDescription {
        IntentDescription("Adds items to one of your Doddy lists. Separate several items with commas.")
    }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Items", requestValueDialog: "What should I add?")
    var items: String

    @Parameter(title: "List", requestValueDialog: "Which list?")
    var list: DoddyListEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$items) to \(\.$list)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let language = NotificationLanguage.current
        guard let store = await IntentStores.loaded() else { return .result(dialog: "\(ListSiri.failed(language))") }
        guard let current = store.list(id: list.id) else { return .result(dialog: "\(ListSiri.listGone(language))") }
        let texts = ListSiri.items(from: items)
        guard !texts.isEmpty else { return .result(dialog: "\(ListSiri.nothingToAdd(language))") }
        do {
            let result = try await store.addToList(texts, listID: current.id, source: .voice)
            return .result(dialog: "\(ListSiri.added(result, list: current.name, language))")
        } catch {
            return .result(dialog: "\(ListSiri.failed(language))")
        }
    }
}

/// "What's on my shopping list in Doddy?"
struct ReadListIntent: AppIntent {
    static let title: LocalizedStringResource = "Read a list in Doddy"
    static var description: IntentDescription {
        IntentDescription("Says what is left on one of your Doddy lists.")
    }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "List", requestValueDialog: "Which list?")
    var list: DoddyListEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Read \(\.$list)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let language = NotificationLanguage.current
        guard let store = await IntentStores.loaded() else { return .result(dialog: "\(ListSiri.failed(language))") }
        guard let current = store.list(id: list.id) else { return .result(dialog: "\(ListSiri.listGone(language))") }
        return .result(dialog: "\(ListSiri.read(current, language))")
    }
}

/// "Tick milk on my shopping list in Doddy".
struct CheckOffListItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick an item on a list in Doddy"
    static var description: IntentDescription {
        IntentDescription("Ticks one item on one of your Doddy lists. If it could be more than one item, nothing is ticked.")
    }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Item", requestValueDialog: "What should I tick?")
    var item: String

    @Parameter(title: "List", requestValueDialog: "Which list?")
    var list: DoddyListEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Tick \(\.$item) on \(\.$list)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let language = NotificationLanguage.current
        guard let store = await IntentStores.loaded() else { return .result(dialog: "\(ListSiri.failed(language))") }
        guard let current = store.list(id: list.id) else { return .result(dialog: "\(ListSiri.listGone(language))") }
        switch ListMatch.item(item, in: current.open) {
        case .none:
            return .result(dialog: "\(ListSiri.notOnList(item, list: current.name, language))")
        case .several(let options):
            return .result(dialog: "\(ListSiri.several(item, options: options, list: current.name, language))")
        case .one(let match):
            do {
                let changed = try await store.setDone([match], done: true, listID: current.id)
                guard let ticked = changed.first(where: { $0.id == match.id }), ticked.isDone else {
                    return .result(dialog: "\(ListSiri.failed(language))")
                }
                return .result(dialog: "\(ListSiri.ticked(ticked, list: current.name, language))")
            } catch {
                return .result(dialog: "\(ListSiri.failed(language))")
            }
        }
    }
}
