import DoddyCore
import SwiftUI
import XCTest
@testable import Doddy

/// Real in-memory SQLite; no cloud model, microphone or EventKit writes.
final class DeviceMessageActionsTests: XCTestCase {
    @MainActor
    func testWholeProposalExecutionAndReceiptAreKeptByRealThreadStorage() async throws {
        let defaults = UserDefaults.standard
        let keys = [PreferenceKey.assistantConsent, PrivateNotes.appLockKey]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.set(true, forKey: PreferenceKey.assistantConsent)
        defaults.set(false, forKey: PrivateNotes.appLockKey)
        let environment = AppEnvironment.live(arguments: ["-inMemoryStore"])
        let store = MemoryStore(environment: environment)
        let model = MessagesModel(repository: environment.messageThreadRepository)
        await model.load()
        let action = try XCTUnwrap(LocalMessageAction.make(name: "save_memory", parametersJSON: #"{"text":"Durable synthetic note"}"#))
        let service = AssistantService(recall: environment.recallService, client: NativeActionTestClient(action: action), backoff: [])
        model.draft = "Save this note"
        model.send(using: service, policy: AssistantPolicy(consentGranted: true, includeNotes: false, localActionsEnabled: true), locale: "en")
        for _ in 0..<400 where model.isSending { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isSending)
        let id = try XCTUnwrap(model.localActions.keys.first)
        await model.confirmLocalAction(id, using: DeviceMessageActions(store: store, polish: false))
        XCTAssertEqual(model.storage, .saving)
        let reopened = MessagesModel(repository: environment.messageThreadRepository)
        await reopened.load()
        XCTAssertEqual(reopened.messages.map(\.text), model.messages.map(\.text))
        XCTAssertEqual(reopened.messages.count, 3)
        XCTAssertTrue(reopened.messages.suffix(2).allSatisfy(\.isLocalAction))
        XCTAssertEqual(reopened.messages.last?.text, "Saved note:\nDurable synthetic note")
        XCTAssertTrue(reopened.localActions.isEmpty, "reopening restores receipts, never executable offers")
        XCTAssertEqual(store.memories.last?.source, .notedByDoddy)
    }
    @MainActor
    func testProposalCardRendersWithoutExecutingAnything() throws {
        let action = try XCTUnwrap(LocalMessageAction.make(name: "create_list", parametersJSON: #"{"name":"Weekend shopping","items":["Oat milk","Eggs","Bread"]}"#))
        var calls = 0
        let view = LocalMessageActionCard(action: action, busy: false, confirm: { calls += 1 }, dismiss: {})
            .padding(20).frame(width: 393).background(Theme.canvas)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(calls, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Messages-local-action-card-synthetic-data"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor
    func testTextWritesUseTheSameStoreAndPrivateReadsStayOut() async throws {
        let defaults = UserDefaults.standard
        let keys = [PreferenceKey.assistantConsent, PrivateNotes.appLockKey, PrivateNotes.storageKey]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.set(true, forKey: PreferenceKey.assistantConsent)
        defaults.set(false, forKey: PrivateNotes.appLockKey)
        defaults.removeObject(forKey: PrivateNotes.storageKey)
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let executor = DeviceMessageActions(store: store, polish: false)
        let note = try XCTUnwrap(LocalMessageAction.make(name: "save_memory", parametersJSON: #"{"text":"Synthetic amber notebook"}"#))
        let saved = await executor.execute(note, stillAuthorised: { true })
        XCTAssertEqual(saved, .completed("Saved note:\nSynthetic amber notebook"))
        XCTAssertEqual(store.memories.last?.source, .notedByDoddy)
        let before = store.memories.count
        _ = await executor.execute(note, stillAuthorised: { false })
        XCTAssertEqual(store.memories.count, before, "stale account/screen cannot write")
        let create = try XCTUnwrap(LocalMessageAction.make(name: "create_list", parametersJSON: #"{"name":"Synthetic shop","items":["oat milk","eggs"]}"#))
        _ = await executor.execute(create, stillAuthorised: { true })
        let list = try XCTUnwrap(store.lists.first { $0.name == "Synthetic shop" })
        XCTAssertTrue(list.items.allSatisfy { $0.source == .typed })
        let partial = try XCTUnwrap(LocalMessageAction.make(name: "remove_from_list", parametersJSON: #"{"list":"Synthetic shop","items":["milk"]}"#))
        _ = await executor.execute(partial, stillAuthorised: { true })
        XCTAssertEqual(store.list(id: list.id)?.items.count, 2, "never delete a partial match")
        let add = try XCTUnwrap(LocalMessageAction.make(name: "add_to_list", parametersJSON: #"{"list":"Synthetic shop","items":["Bread"]}"#))
        _ = await executor.execute(add, stillAuthorised: { true })
        XCTAssertEqual(store.list(id: list.id)?.items.count, 3)
        let tick = try XCTUnwrap(LocalMessageAction.make(name: "check_off", parametersJSON: #"{"list":"Synthetic shop","items":["Bread"]}"#))
        _ = await executor.execute(tick, stillAuthorised: { true })
        XCTAssertEqual(store.list(id: list.id)?.done.map(\.text), ["Bread"])
        let remove = try XCTUnwrap(LocalMessageAction.make(name: "remove_from_list", parametersJSON: #"{"list":"Synthetic shop","items":["eggs"]}"#))
        _ = await executor.execute(remove, stillAuthorised: { true })
        XCTAssertEqual(store.list(id: list.id)?.items.map(\.text), ["oat milk", "Bread"])
        let search = try XCTUnwrap(LocalMessageAction.make(name: "search_memories", parametersJSON: #"{"query":"amber notebook"}"#))
        let found = await executor.execute(search, stillAuthorised: { true })
        XCTAssertTrue(found.message.contains("Synthetic amber notebook"))
        XCTAssertTrue(PrivateNotesStore.set(list.id, isPrivate: true))
        let read = try XCTUnwrap(LocalMessageAction.make(name: "read_list", parametersJSON: #"{"list":"Synthetic shop"}"#))
        let hidden = await executor.execute(read, stillAuthorised: { true })
        XCTAssertFalse(hidden.message.contains("oat milk"))
        defaults.set(false, forKey: PreferenceKey.assistantConsent)
        _ = await executor.execute(note, stillAuthorised: { true })
        XCTAssertEqual(store.memories.count, before)
    }
}

private struct NativeActionTestClient: AssistantClient {
    let action: LocalMessageAction
    func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        AssistantReply(text: "Confirm the card", localAction: action)
    }
}
