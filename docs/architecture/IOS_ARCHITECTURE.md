# iOS application architecture — proposed
## Layers and dependency direction
```
DoddyApp (SwiftUI navigation, CompositionRoot, Settings)
    ↓
DoddyFeatures (Capture, Memories, Assistant, Voice, Actions)
    ↓
DoddyCore (types, use cases, ports/protocols, policy, privacy permissions)
    ↑ implemented by
DoddyPersistence (GRDB/SQLite + migration + FTS)
DoddyAI (gateway client + request builder + grounding verifier)
DoddyAudio (foreground ASR/TTS adapters)
DoddyActions (Reminders/EventKit adapter)
DoddyDesignSystem (tokens, accessible character components)
```
For M0 use folders/modules with clear protocols; do not require a complex multi-package monorepo. Split packages only where tests/build benefit.

## Key protocols (illustrative, implement and test)
```
protocol MemoryRepository {
  func save(_ draft: NewMemory) async throws -> MemoryRecord
  func query(_ query: String, limit: Int) async throws -> [MemoryCandidate]
  func update(id: UUID, currentText: String) async throws -> MemoryRecord
  func delete(id: UUID) async throws
  func export() async throws -> Data
}
protocol AssistantClient {
  func respond(_ request: AssistantRequest) async throws -> AssistantReply
}
protocol ReminderWriting {
  func propose(_ draft: ReminderDraft) throws -> ReminderProposal
  func create(_ confirmed: ConfirmedReminder) async throws -> ActionReceipt
}
```
Do not mark a method `async` if synchronous GRDB actor isolation offers a safer contract; adjust under Swift compiler feedback. Avoid making UI a source of truth for permissions, storage success or action receipts.

## State management
One coordinator per workflow, cancellable tasks and unique session/operation IDs. Views render explicit state; no side-effects on mere SwiftUI body recomputation. Use observable view models/`@Observable` where target OS supports and Swift Concurrency isolation is clear.

## Native structure in M0
```
Doddy.xcodeproj
DoddyApp/App/DoddyApp.swift
DoddyApp/Features/Memory/...
DoddyApp/Features/Assistant/...
DoddyApp/Infrastructure/Persistence/...
DoddyApp/Infrastructure/Network/...
DoddyApp/DesignSystem/...
DoddyTests/...
DoddyUITests/...
Docs (pack contents)
```
Do not fabricate working Xcode project files if Xcode/Swift compiler unavailable; give exact manual next command and label as unverified.

## Lifecycle
App enter foreground → load local store → render truthful Idle state → user explicitly saves/searches → show result only when repository confirms → optional network AI uses a carefully scoped request → app background cancels capture and discards private-session context. Filesystem protection/backup behavior requires device testing.
