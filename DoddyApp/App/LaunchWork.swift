import DoddyCore
import Foundation
import os

/// What Doddy does once the first screen is up, and the signposts that let Instruments time launch
/// (docs/implementation/LAUNCH_PROFILING.md, ADR-547). Nothing here changes what Doddy does, only
/// when: every job that used to start with the first frame still runs. The cheap local ones start
/// as soon as the first screen shows; the network and notification ones wait a moment and run one
/// at a time, so they don't compete with the first screen's animations or with each other.
@MainActor
enum LaunchWork {
    static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "Doddy", category: "Launch")

    /// Pause before the first later job, so the intro and the hello aren't sharing the main actor
    /// with iCloud, push and notification work.
    static let settle: Duration = .milliseconds(1500)
    /// Gap between later jobs.
    static let gap: Duration = .milliseconds(300)

    private static var launchState: OSSignpostIntervalState?
    private static var initState: OSSignpostIntervalState?

    /// First line of `DoddyApp.init`.
    static func appInitBegan() {
        launchState = signposter.beginInterval("Launch to first screen")
        initState = signposter.beginInterval("App.init")
    }

    /// Last line of `DoddyApp.init`.
    static func appInitEnded() {
        guard let state = initState else { return }
        signposter.endInterval("App.init", state)
        initState = nil
    }

    /// The profile has loaded, so `RootView` shows Home (or the introduction) instead of a blank canvas.
    static func firstScreenShown() {
        guard let state = launchState else { return }
        signposter.emitEvent("First screen shown")
        signposter.endInterval("Launch to first screen", state)
        launchState = nil
    }

    private static func timed(_ name: StaticString, _ work: () async -> Void) async {
        let state = signposter.beginInterval(name)
        await work()
        signposter.endInterval(name, state)
    }

    /// Right after the first screen: cheap, local, and read by screens the user can open at once.
    static func afterFirstScreen(store: MemoryStore) async {
        await timed("Early jobs") {
            await store.learning?.reload()
            await SystemNoteNotifications.registerCategory()
            ShoppingModeController.shared.reattach()
            await SharedListsController.shared.load()
        }
    }

    /// A moment later: network and notification work, one job at a time. Stops if the scene goes away.
    static func later() async {
        try? await Task.sleep(for: settle)
        // If the user turned Doddy's notifications on earlier, re-send the (possibly new) token.
        let jobs: [(StaticString, () async -> Void)] = [
            ("Push token", { await UpdatesModel().syncPushTokenIfOn() }),
            ("Shared lists sync", {
                await SharedListsController.shared.syncAllUnlessRecent()
                await SharedListsController.shared.startLiveUpdates()
            }),
            // Keeps the check-ins' words in the iPhone's current language (ADR-220).
            ("Morning check-in", { if MorningCheckInSettings.stored().isOn { _ = await MorningCheckInScheduler.apply(.stored()) } }),
            ("Tidy up", { if TidyUpSettings.stored().isOn { _ = await TidyUpScheduler.apply(.stored()) } }),
            ("Evening wrap-up", { if EveningWrapUpSettings.stored().isOn { _ = await EveningWrapUpScheduler.apply(.stored()) } }),
            ("Weekly look back", { if WeeklyLookBackSettings.stored().isOn { _ = await WeeklyLookBackScheduler.apply(.stored()) } }),
            ("Birthdays", { await BirthdayScheduler.refresh() }),
            // A recording Doddy was closed in the middle of is finished, or reported lost (ADR-588).
            ("Recordings recovery", { await RecordingCoordinator.shared.recoverUnfinished() }),
        ]
        for (name, job) in jobs {
            if Task.isCancelled { return }
            await timed(name, job)
            try? await Task.sleep(for: gap)
        }
    }
}
