import Foundation

/// The reminder store as the notification code sees it, with Private notes (ADR-310) kept out of
/// the Lock Screen (ADR-722).
///
/// "Show note text in notifications" (off by default) puts a note's first words in the banner,
/// which anyone holding the iPhone can read without unlocking it. A Private note is marked so that
/// its words never show without Face ID, so for such a note this hands the coordinator the same
/// words the banner has when that setting is off. Everything else is passed through untouched.
///
/// It sits between `NoteReminderCoordinator` and the database because every notification the
/// coordinator builds (new, snoozed, repeated, refreshed or repaired) takes its text from
/// `currentText(ofMemory:)`; the private set is read each time, so a note made Private later is
/// covered by the next refresh.
public struct PrivacyAwareNoteReminderRepository: NoteReminderRepository {
    private let base: any NoteReminderRepository
    private let privateIDs: @Sendable () -> Set<UUID>
    private let language: @Sendable () -> NotificationLanguage

    public init(
        base: any NoteReminderRepository,
        privateIDs: @escaping @Sendable () -> Set<UUID>,
        language: @escaping @Sendable () -> NotificationLanguage = { .english }
    ) {
        self.base = base
        self.privateIDs = privateIDs
        self.language = language
    }

    /// The note's words, or the generic banner words for a Private note. Nil still means the note
    /// does not exist.
    public func currentText(ofMemory memoryID: UUID) async throws -> String? {
        guard let text = try await base.currentText(ofMemory: memoryID) else { return nil }
        return privateIDs().contains(memoryID) ? NoteReminderCopy.privateBody(language()) : text
    }

    public func allReminders() async throws -> [MemoryReminder] { try await base.allReminders() }
    public func reminder(id: UUID) async throws -> MemoryReminder? { try await base.reminder(id: id) }
    public func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? { try await base.reminder(forMemory: memoryID) }
    public func reminderCount() async throws -> Int { try await base.reminderCount() }
    public func isList(memoryID: UUID) async -> Bool { await base.isList(memoryID: memoryID) }
    public func openItemCount(listID: UUID) async -> Int? { await base.openItemCount(listID: listID) }
    public func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder { try await base.upsertReminder(reminder) }
    @discardableResult
    public func deleteReminder(id: UUID) async throws -> Bool { try await base.deleteReminder(id: id) }
}
