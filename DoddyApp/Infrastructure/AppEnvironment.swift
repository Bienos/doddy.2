import SwiftUI
import DoddyCore

/// Composition root. M0 wires only explicit `Unavailable*` adapters: every port fails loudly
/// instead of simulating behaviour. Replace an adapter only together with real tests.
struct AppEnvironment: Sendable {
    let memoryRepository: any MemoryRepository
    let recallService: any RecallService
    let assistantClient: any AssistantClient
    let toolExecutor: any ToolExecutor
    let capabilities: CapabilityCatalog
    let privacy: PrivacyDefaults

    static let m0 = AppEnvironment(
        memoryRepository: UnavailableMemoryRepository(),
        recallService: UnavailableRecallService(),
        assistantClient: UnavailableAssistantClient(),
        toolExecutor: UnavailableToolExecutor(),
        capabilities: .m0,
        privacy: .m0)
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.m0
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
