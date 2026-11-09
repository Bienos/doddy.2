import DoddyCore
import Foundation

/// Messages uses the same repositories, switches and verified ReminderAction as voice.
/// No conversation SDK or microphone is started to execute a typed request.
@MainActor
final class DeviceMessageActions: LocalMessageActionExecuting {
    private let store: MemoryStore
    private let devices = DeviceConnections()
    private let polish: Bool

    init(store: MemoryStore, polish: Bool) { self.store = store; self.polish = polish }

    static var accountScope: String? {
        let account = DoddyAccountModel.shared
        return account.session?.userID ?? (account.isConfigured ? nil : "local-device")
    }

    private func text(_ pl: String, _ en: String) -> String { polish ? pl : en }

    private func permitted(_ action: LocalMessageAction, _ current: () -> Bool) -> Bool {
        guard current(), !Task.isCancelled, !AppLock.shared.isLocked,
              UserDefaults.standard.object(forKey: PreferenceKey.assistantConsent) as? Bool ?? PreferenceKey.assistantConsentDefault else { return false }
        return ToolGate.decide(toolName: action.name.rawValue, request: action.request, translatorOn: false,
            pauseAll: UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey),
            isOn: { UserDefaults.standard.bool(forKey: $0.preferenceKey) }, scope: ReleaseScopeStore.current) == .run
    }

    func execute(_ action: LocalMessageAction, stillAuthorised current: @escaping @MainActor () -> Bool) async -> LocalMessageActionOutcome {
        let stopped = LocalMessageActionOutcome.failed(text("Nie wykonano. Sprawdź połączenia i zgodę na rozmowy w ustawieniach, a potem wyślij polecenie ponownie.", "Not performed. Check Connections and Messages consent in Settings, then send the request again."))
        guard permitted(action, current) else { return stopped }
        do {
            switch action.request {
            case .saveMemory(let value):
                // Doddy's words, saved by the person's tap: the same provenance as a note from a call (ADR-753).
                let saved = try await store.save(text: value, category: .other, source: .notedByDoddy)
                return .completed(text("Zapisano notatkę:\n", "Saved note:\n") + saved.currentText)
            case .searchMemories(let query):
                let notes: [MemoryRecord]
                if let tag = NoteTags.tagQuery(query) {
                    let all = try await store.environment.memoryRepository.list(limit: nil)
                    guard permitted(action, current) else { return stopped }
                    notes = NoteTags.filter(PrivateNotesStore.current().shareable(all.filter { $0.category != .list && $0.source != .sampleFixture }), tag: tag)
                } else {
                    let found = try await store.recall(query)
                    guard permitted(action, current) else { return stopped }
                    if case .matches(let matches) = PrivateNotesStore.current().shareable(found) {
                        notes = matches.map(\.record).filter { $0.category != .list && $0.source != .sampleFixture }
                    } else { notes = [] }
                }
                guard !notes.isEmpty else { return .completed(text("Nie znaleziono pasujących notatek dostępnych dla Doddy’ego.", "No matching notes available to Doddy were found.")) }
                return .completed(text("Znalezione notatki:\n", "Matching notes:\n") + notes.prefix(20).map(\.currentText).joined(separator: "\n\n"))
            case .createList(let draft):
                let list = try await store.createList(name: draft.list, items: draft.items, source: .typed)
                return .completed(text("Utworzono listę:\n", "Created list:\n") + list.shareText)
            case .readList(let name):
                let list = try await exactList(name)
                guard permitted(action, current), !PrivateNotesStore.current().contains(list.id) else { return stopped }
                return .completed(list.shareText)
            case .addToList(let draft), .checkOff(let draft), .removeFromList(let draft):
                let list = try await exactList(draft.list)
                guard permitted(action, current), !PrivateNotesStore.current().contains(list.id) else { return stopped }
                if action.name == .addToList {
                    let result = try await store.addToList(draft.items, listID: list.id, source: .typed)
                    let added = result.added.map(\.text).joined(separator: ", ")
                    let omitted = result.alreadyThere + result.tooLong + result.noRoom
                    return .completed(text("Lista „\(list.name)”. Dodano: ", "List “\(list.name)”. Added: ") + (added.isEmpty ? "—" : added)
                        + (omitted.isEmpty ? "" : text("\nNie dodano: ", "\nNot added: ") + omitted.joined(separator: ", ")))
                }
                // Never apply a destructive action to a guessed or partially matching item.
                let candidates = action.name == .checkOff ? list.open : list.items
                var items: [ListItem] = []
                for phrase in draft.items {
                    let exact = candidates.filter { ListMatch.key($0.text) == ListMatch.key(phrase) }
                    guard exact.count == 1 else { return .failed(text("Nic nie zmieniono. Podaj dokładne, jednoznaczne nazwy pozycji z listy „\(list.name)”.", "Nothing changed. Give the exact, unambiguous item names on “\(list.name)”.")) }
                    if !items.contains(where: { $0.id == exact[0].id }) { items.append(exact[0]) }
                }
                let changed = action.name == .checkOff
                    ? try await store.setDone(items, done: true, listID: list.id)
                    : try await store.removeFromList(items, listID: list.id)
                return .completed(text("Lista „\(list.name)”. \(action.name == .checkOff ? "Oznaczono jako zrobione" : "Usunięto"): ", "List “\(list.name)”. \(action.name == .checkOff ? "Checked off" : "Removed"): ") + changed.map(\.text).joined(separator: ", "))
            case .createReminder(let draft):
                if devices.access(for: .reminders) == .notDetermined { _ = await devices.request(.reminders) }
                guard permitted(action, current) else { return stopped }
                guard devices.access(for: .reminders) == .granted else {
                    return .failed(text("Nie dodano. Zezwól Doddy’emu na dostęp do Przypomnień w ustawieniach iPhone’a.", "Not added. Allow Doddy to access Reminders in iPhone Settings."))
                }
                // The shared action performs an async duplicate check. Its adapter checks scope again
                // immediately before the synchronous EventKit write.
                let checked = ScopedReminders(base: devices, allowed: { self.permitted(action, current) })
                let result = await ReminderAction.add(draft, to: checked, now: Date())
                switch result {
                case .added(let receipt), .alreadyThere(let receipt):
                    let heading = result.isAlreadyThere ? text("Już jest w Przypomnieniach:\n", "Already in Reminders:\n") : text("Dodano do Przypomnień:\n", "Added to Reminders:\n")
                    return .completed(heading + receipt.title + "\n" + ReminderText.due(receipt.due) + "\n" + receipt.listTitle)
                case .unknown: return .unknown(text("Nie udało się potwierdzić zapisu. Sprawdź aplikację Przypomnienia przed ponownym poleceniem.", "Could not confirm the save. Check Reminders before asking again."))
                case .needsClarification(let issue): return .failed(issue.screenLine)
                case .notAdded: return .failed(text("Nie dodano przypomnienia. Sprawdź dostęp i zawartość Przypomnień, a potem spróbuj ponownie.", "Reminder not added. Check access and the Reminders app, then try again."))
                }
            default: return stopped
            }
        } catch ListError.notFound {
            return .failed(text("Nic nie zmieniono. Nie znaleziono jednoznacznej, dostępnej listy o tej nazwie. Podaj jej dokładną nazwę.", "Nothing changed. No unambiguous, available list has that name. Give its exact name."))
        } catch ListError.nameTaken {
            return .failed(text("Nie utworzono listy. Ta nazwa jest już zajęta. Podaj inną nazwę.", "List not created. That name is already taken. Give another name."))
        } catch {
            // A repository may have committed before its verification failed. Never imply no write
            // happened and never leave a retry button for an uncertain write.
            switch action.name {
            case .searchMemories, .readList:
                return .failed(text("Nie udało się odczytać. Sprawdź notatki lub listy i spróbuj ponownie.", "Could not read. Check Notes or Lists and try again."))
            default:
                return .unknown(text("Nie udało się potwierdzić zmiany. Sprawdź notatki lub listy przed ponownym poleceniem.", "Could not confirm the change. Check Notes or Lists before asking again."))
            }
        }
    }

    private func exactList(_ name: String) async throws -> DoddyList {
        let lists = try await store.environment.listRepository.lists()
        let found = lists.filter { !PrivateNotesStore.current().contains($0.id) && $0.record.source != .sampleFixture && ListMatch.key($0.name) == ListMatch.key(name) }
        guard found.count == 1 else { throw ListError.notFound }
        return found[0]
    }
}

private extension ReminderOutcome {
    var isAlreadyThere: Bool { if case .alreadyThere = self { true } else { false } }
}

@MainActor
private final class ScopedReminders: ReminderStore {
    let base: DeviceConnections
    let allowed: @MainActor () -> Bool
    init(base: DeviceConnections, allowed: @escaping @MainActor () -> Bool) { self.base = base; self.allowed = allowed }
    func incompleteReminders() async throws -> [ReminderSnapshot] {
        guard allowed() else { throw ReminderStoreError.notAllowed }
        return try await base.incompleteReminders()
    }
    func save(_ write: ReminderWrite) throws -> String {
        guard allowed() else { throw ReminderStoreError.notAllowed }
        return try base.save(write)
    }
}
