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

    /// When `DoddyApp.init` began (wall clock, to compare with the process's start) and how long it took
    /// (monotonic clock). Read by `launchTiming` for the Action Button's log line; two clock readings
    /// each, nothing else, so `init` pays nothing for them.
    private static var initBeganAt: Date?
    private static var initBeganUptime: Double?
    private static var initSeconds: Double?

    /// First line of `DoddyApp.init`.
    static func appInitBegan() {
        initBeganAt = Date()
        initBeganUptime = ProcessInfo.processInfo.systemUptime
        launchState = signposter.beginInterval("Launch to first screen")
        initState = signposter.beginInterval("App.init")
    }

    /// Where the time before an Action Button press went, for its log line (follow-up to decision
    /// `2026-11-13-island-first`): how old this process is, how long iOS took to reach `DoddyApp.init`, and how
    /// long `init` took. The start timeline can't show it: it begins when the intent's `perform()` runs.
    static func launchTiming(now: Date = Date()) -> TalkLaunchTiming {
        let started = ProcessStart.date()
        var beforeAppInit: Double?
        if let started, let began = initBeganAt { beforeAppInit = max(0, began.timeIntervalSince(started)) }
        return TalkLaunchTiming(
            processAge: started.map { max(0, now.timeIntervalSince($0)) },
            beforeAppInit: beforeAppInit,
            appInit: initSeconds)
    }

    /// Last line of `DoddyApp.init`.
    static func appInitEnded() {
        if let began = initBeganUptime { initSeconds = max(0, ProcessInfo.processInfo.systemUptime - began) }
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
            // A transcript or history made for the share sheet by an earlier run, never deleted because the app
            // was closed first, goes now.
            TemporaryShareFiles.removeAll()
            await store.learning?.reload()
            await SystemNoteNotifications.registerCategory()
            ShoppingModeController.shared.reattach()
            await SharedListsController.shared.load()
        }
    }

    /// A moment later: network and notification work, one job at a time. Stops if the scene goes away.
    static func later(store: MemoryStore) async {
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
            ("Weekly plan", { if WeeklyPlanSettings.stored().isOn { _ = await WeeklyPlanScheduler.apply(.stored()) } }),
            ("Birthdays", { await BirthdayScheduler.refresh() }),
            // "A thought is ready for review" (ADR-785): the next one, from the notes as they are now.
            ("Thought review", { _ = await ThoughtReviewScheduler.refresh(store: store) }),
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

/// When this process started, from the kernel's own record of it (`sysctl`, the process table), the same
/// for a process iOS started for an intent and for one the person opened. Nil if the kernel doesn't say.
enum ProcessStart {
    static func date() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        guard started.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }
}
