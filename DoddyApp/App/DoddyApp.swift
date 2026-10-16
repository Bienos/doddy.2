import DoddyCore
import Foundation
import Observation
import os
import SwiftUI

/// DODDY V2. Local text memory (M1) and the reviewed profile, voice with the ElevenLabs agent (V1),
/// the Talk to Doddy shortcut and Back Tap guide (V2) and the conversation's Dynamic Island (V3).
/// No sign-in: the optional messaging server (notifications, texts, calls, news) uses an anonymous
/// device account.
@main
struct DoddyApp: App {
    /// APNs device-token callbacks for Doddy's notifications (server/messaging).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime: AppRuntime

    init() {
        // The screens' language is read when the app starts: English unless the person picked another (ADR-459).
        AppLanguageStore.applyAtLaunch()
        // Before anything reads them: a fresh install doesn't pick up an earlier install's server tokens.
        ServerKeychainStore.clearLeftoversOnFreshInstall()
        _runtime = State(initialValue: AppRuntime.shared)
        // A conversation never survives a relaunch, so neither may its island.
        VoiceLiveActivity.endStale()
        // A focus timer does survive one (it is saved); this also lets its island's buttons work
        // when iOS starts the app just to run them (ADR-241). Breathing and read-aloud don't.
        FocusController.shared.refresh()
        ToolLiveActivity.endLeftovers(keeping: [.focus, .timer])
        ToolActivityActions.shared.cancelTimer = { identifier in
            await KitchenTimerActivities.shared.cancel(identifier: identifier)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let store = runtime.store,
                   let profiles = runtime.profiles,
                   let noteReminders = runtime.noteReminders {
                    RootView()
                        .environment(store)
                        .environment(profiles)
                        .environment(noteReminders)
                        .environment(\.appEnvironment, store.environment)
                        // If the user turned Doddy's notifications on earlier, re-send the (possibly new) token.
                        .task { await UpdatesModel().syncPushTokenIfOn() }
                        .task { await SystemNoteNotifications.registerCategory() }
                        .task { await store.learning?.reload() }
                        .task { ShoppingModeController.shared.reattach() }
                        .task {
                            await SharedListsController.shared.load()
                            await SharedListsController.shared.syncAll()
                            await SharedListsController.shared.startLiveUpdates()
                        }
                        // Keeps the morning check-in's words in the iPhone's current language (ADR-220).
                        .task { if MorningCheckInSettings.stored().isOn { _ = await MorningCheckInScheduler.apply(.stored()) } }
                        .task { if TidyUpSettings.stored().isOn { _ = await TidyUpScheduler.apply(.stored()) } }
                        .task { if EveningWrapUpSettings.stored().isOn { _ = await EveningWrapUpScheduler.apply(.stored()) } }
                        .task { if WeeklyLookBackSettings.stored().isOn { _ = await WeeklyLookBackScheduler.apply(.stored()) } }
                        .task { await BirthdayScheduler.refresh() }
                        .task { await KitchenTimerActivities.shared.reconcile() }
                } else {
                    AppBootstrapView()
                }
            }
            .task { await runtime.prepare() }
        }
    }
}

/// Opens the single shared store away from the launch-critical main-thread path. App Intents use
/// the same preparation task, so they cannot construct a second database or see a fake empty store.
@MainActor
@Observable
final class AppRuntime {
    static let shared = AppRuntime()

    private(set) var store: MemoryStore?
    private(set) var profiles: ProfileStore?
    private(set) var noteReminders: NoteReminderStore?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    private static let startupLog = Logger(subsystem: "com.bienos.doddy2.dev", category: "startup")

    func prepare() async {
        if let preparationTask {
            await preparationTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            let environment = await Task.detached(priority: .userInitiated) {
                AppEnvironment.live()
            }.value
            let elapsedMilliseconds = Int(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            Self.startupLog.notice(
                "phase=environment_ready elapsed_ms=\(elapsedMilliseconds, privacy: .public) storage_available=\(environment.storageProblem == nil, privacy: .public)"
            )
            self.configure(environment)
        }
        preparationTask = task
        await task.value
    }

    private func configure(_ environment: AppEnvironment) {
        guard store == nil else { return }

        let store = MemoryStore(environment: environment)
        let noteReminders = NoteReminderStore(coordinator: environment.noteReminders)
        store.noteReminders = noteReminders

        // The learning loop (ADR-440) listens to "What Doddy did" for what was corrected.
        let learning = LearningStore(service: environment.learningService)
        learning.attach(to: ActivityLogStore.shared)
        store.learning = learning
        store.activity = ActivityLogStore.shared

        NoteReminderRouter.shared.reminders = noteReminders
        WidgetSync.shared.store = store
        IntentStores.store = store
        WidgetSync.shared.reminders = noteReminders
        PhoneWatchLink.shared.store = store
        PhoneWatchLink.shared.activate()
        ShoppingModeController.shared.store = store
        SharedListsController.shared.store = store

        self.store = store
        self.noteReminders = noteReminders
        self.profiles = ProfileStore(environment: environment)

        WakeWordListener.shared.store = store
        WakeWordListener.shared.profiles = self.profiles
    }
}

private struct AppBootstrapView: View {
    var body: some View {
        Theme.canvas
            .ignoresSafeArea()
            .overlay {
                ProgressView("Loading notes")
                    .foregroundStyle(Theme.ink)
            }
    }
}
