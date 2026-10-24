# Doddy main-app runtime performance audit (static review)

Repo `/home/user/doddy.2`, HEAD `0e65006`. Static reading only (Linux, no Xcode, no Instruments, nothing was run or measured).
Every "main thread" claim below names the actor that proves it (`@MainActor`, `@Observable` view-model, CADisplayLink on `.main`). Where I could not see the actor I say so.
Out of scope (someone else): `DoddyWidgets/*LiveActivity.swift`, `Shared/IslandArt/*` (except the one shared modifier used by the main-app sprite, finding 2), `Shared/VoiceActivity/*`, `VoiceLiveActivity.swift`, `IslandExtension.swift`.
Not read for lack of budget: Memories/Settings/Web/Capture screens in depth, `WidgetSync`, `MemoryCopySync`, `PrivateNotesStore`, `MotionEngine` internals beyond the frame-demand logic.

If "stutter" means Doddy's *voice* cuts out (audio), nothing here explains it: the audio render path is the ElevenLabs/LiveKit SDK on its own threads. Main-thread stalls delay UI and state callbacks, not audio rendering. Worth asking the owner which one it is.

## Ranking

| # | Sev | Finding | Measure first? |
|---|---|---|---|
| 1 | High | Blocking EventKit/Contacts/Photos reads run on the main actor during tool calls and at launch | yes (signposts) |
| 2 | High | Doddy's display link asks for 120 Hz for every micro-motion; per-tick SwiftUI publish; 4 always-on shadows and blurred eye covers on the sprite | yes (Hitches, Core Animation) |
| 3 | Med | Home-wide `DragGesture(minimumDistance: 0)` calls the director on every touch sample and pins the link at 120 Hz | yes |
| 4 | Med | Opening scene: uncapped `TimelineView(.animation)` over a live Home, replays on cold launch and after 5 min away | yes |
| 5 | Med | `LaunchWork.later()` runs 7 jobs on the main actor while the opening plays | yes |
| 6 | Med | `ActivityLogStore.save()` (@MainActor) re-encodes the whole log and does an atomic write on every append | yes (signpost) |
| 7 | Med | `DoddyApp.init` does Keychain, SQLite open+migrate and two JSON log loads synchronously before the first frame | yes (already planned in LAUNCH_PROFILING.md) |
| 8 | Med | `store.reload()` on every conversation start; unconditional `revision += 1` fans out to Widget/MemoryCopy/Spotlight; non-indexable ORDER BY | yes |
| 9 | Med | `RootView.body` depends on live conversation state, so each phase change re-evaluates the app root | yes (SwiftUI instrument) |
| 10 | Low-Med | `phase.didSet` has no same-value guard; each call re-lays out the listening-indicator window | no |
| 11 | Low-Med | `onGeometryChange(.global)` reports on every scroll frame (Home talk button, every Memories card) | yes |
| 12 | Low-Med | 63 sprite frames decode lazily on first use; one asset is 3.6x larger than needed | yes |
| 13 | Low | Transcript sheet is a non-lazy `VStack` in one large body | no |
| 14 | Low | Memories list builds `Array(shown.enumerated())` per body, index inside the surface id | no |
| 15 | Low | FTS5 `optimize` inside every delete/rewrite transaction on a single-connection `DatabaseQueue` | yes |
| 16 | Low | DEBUG-only per-tick string work; Debug builds are not a valid smoothness test | no |
| 17 | Low | `AliveDoddy` re-evaluates its body at 30 Hz | no |

---

## 1. [High] Blocking EventKit / Contacts / Photos reads run on the main actor

**Where**
- `DoddyApp/Infrastructure/Connections/DeviceConnections.swift:12-13` `@MainActor final class DeviceConnections`
- `:206-207` and `:416-417` `eventStore.events(matching: predicate)`
- `:699` `contactStore.unifiedContacts(matching: …)`, `:718` (`contactBirthdays()`) and `:736` (`birthdays()`): `try contactStore.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { … }`
- The protocol declares them synchronous (`DeviceConnections.swift:763-783`: `func findContacts(named:) throws`, `func contactBirthdays() throws`, `func findPhotos(…) -> PhotoSearchFound`).
- Call sites inside `VoiceSessionController` (`@MainActor @Observable`, lines 19-21): `:2433`, `:2441` `let events = devices.events(in: range)`; `:2478` `try devices.findContacts(named: name)`; `:2519` `try devices.contactBirthdays()`; `:2625` `devices.findPhotos(request, now: Date())`; `:3378` `devices.events(in: EventChange.searchRange(…))`.
- Launch: `DoddyApp/Features/Birthdays/BirthdayViews.swift` `BirthdayScheduler.refresh()` is `guard !picked.isEmpty, let contacts = DeviceConnections().birthdays()`; `LaunchWork.later()` runs it as the 7th job (about 3.3 s after the first screen, plus the run time of the six jobs before it). Only for users who picked birthdays.

**What happens**
`events(matching:)` and `enumerateContacts` are synchronous IPC to the calendar and contacts daemons; time grows with events in range and with the number of contacts (tens to hundreds of ms on a large account). `DeviceConnections` is `@MainActor`, the controller is `@MainActor`, and the calls are not `await`ed, so they execute inline on the main thread. During that time there are no frames: Doddy freezes mid-"thinking", the island and transcript don't update. A tool call is exactly the moment the user is watching Doddy. `BirthdayScheduler.refresh()` is a nonisolated async function that constructs a `@MainActor` class, so it hops to main for the whole enumeration (build setting is `SWIFT_VERSION: "6.0"`, `project.yml:36`, so no nonisolated-nonsending default).

**Fix**
Make the blocking reads `nonisolated async`, run them on a background task and return `Sendable` value types. `EKEventStore` and `CNContactStore` can be used off the main thread for reads.
```swift
// DeviceConnections.swift
private struct Stores: @unchecked Sendable { let events: EKEventStore; let contacts: CNContactStore }

func events(in range: DateInterval) async -> [CalendarEventSummary] {
    let s = Stores(events: eventStore, contacts: contactStore)       // captured on main
    return await Task.detached(priority: .userInitiated) {
        let p = s.events.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return s.events.events(matching: p).map(CalendarEventSummary.init)   // map to value types off-main
    }.value
}
// VoiceSessionController ~2433:  let events = await devices.events(in: range)
```
Same shape for `contactBirthdays`, `findContacts`, `birthdays`, `findPhotos`. The `DeviceConnecting` methods become `async`; fakes in tests change trivially. In `LaunchWork`, run Birthdays off-main and after the opening (finding 5).

**Measure first:** yes. Wrap each call in an `OSSignposter` interval, then run "what's on my calendar", "whose birthday is next", "find a contact" on an account with a large calendar and 1-3k contacts, with Time Profiler on the main thread.

---

## 2. [High, unverified] The display link runs at 120 Hz for every micro-motion, and each tick republishes a figure that carries four shadows and blurred eye covers

**Where / code**
- `DoddyApp/DesignSystem/Motion/DoddyClock.swift:47`
  `l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)` (link added to `.main`, line 48; class is `@MainActor`).
- `Packages/DoddyCore/Sources/DoddyCore/Motion/MotionEngine.swift:2183-2196` `isStill` is false while `breath != 0`, `blinkT >= 0`, `thinking`/gesture/micro states are set or any of 22 springs is moving; `breathPhase` (line ~2178) is `(now - breathT) / 4200` over 0..<3 breaths, so one breath episode keeps the link running for about 12.6 s. `nextDue` also returns `now + 16` while `thinking != nil`.
- `DoddyApp/DesignSystem/Motion/DoddyDirector.swift:441-444` `tick` → `advance` (two 4.17 ms sub-steps per 120 Hz frame, `substep = 1000.0 / 240`) → `afterSteps` (`host.settle()`, `publish()`, then `clock?.run()` again, lines 473-493). `publish()` (508-533) builds a new `DoddyFigure` with `MotionArt.choose(…)` (allocates face-layer arrays) every frame and assigns `figure` when it differs.
- `DoddyApp/DesignSystem/Motion/DoddyFigureView.swift:58` `.islandCreamEdge(colorScheme == .dark)` → `Shared/IslandArt/IslandViews.swift:519-525`:
  ```swift
  let edge = on ? Color.islandCream : .clear
  return shadow(color: edge, radius: 0, x: 1, y: 0).shadow(color: edge, radius: 0, x: -1, y: 0)
      .shadow(color: edge, radius: 0, x: 0, y: 1).shadow(color: edge, radius: 0, x: 0, y: -1)
  ```
  Four shadow effects are always attached, in light mode with a clear colour.
- `DoddyFigureView.swift:116-118` the eye covers are `Ellipse().fill(…).blur(radius: CGFloat(blur) * unit)`.
- Observation scope is good: only `DoddySlotFigure` (`:131`), `DoddyTouchArea` (`MotionSurfaceViews.swift:204`) and `DoddyOverlay` (`:154`, only while in flight) read `figure`, so a tick re-evaluates two small subtrees, not Home. The cost is per-frame SwiftUI diff + Core Animation commit + GPU for the sprite.

**Why it can stutter**
Each frame must finish in 8.3 ms (body evaluation, diff, CA commit, and the offscreen passes the shadows and blur need, in a layer whose content changes every frame). `preferred: 120` with `minimum: 80` leaves the system no room to settle on an even 60 Hz; when frames are missed the cadence alternates between rates, which reads as judder on ProMotion more than a steady 60 would. A breath or a blink does not need 120 Hz. On Home this is an always-on loop (every idle breath episode).

**Fix**
Request the high rate only for fast motion; idle micro-motion at 60 (or 30-60).
```swift
// DoddyClock
func run(highRate: Bool) {
    wake?.cancel(); wake = nil
    let range = highRate ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                         : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    if let link { link.preferredFrameRateRange = range; return }
    let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
    l.preferredFrameRateRange = range; l.add(to: .main, forMode: .common); link = l
}
// DoddyDirector.afterSteps(): clock?.run(highRate: engine.mode == .flight || host.scene.finger.isDown || engine.hasGesture)
```
(`hasGesture` = a small new computed property in DoddyCore: gesture/micro/homeTouch/shuf/ducking.) Cream edge only in dark mode:
```swift
.modifier(CreamEdge(on: colorScheme == .dark))
struct CreamEdge: ViewModifier { let on: Bool
    @ViewBuilder func body(content: Content) -> some View { if on { content.islandCreamEdge() } else { content } } }
```
Longer term: bake the cream outline into dark-mode sprite variants instead of four runtime shadows. Skip the eye `blur` when `unit` is unchanged between frames (the cover shape is static; only the parent transform moves).

**Measure first:** yes. Instruments "SwiftUI" + "Animation Hitches" + "Core Animation" (Color Offscreen-Rendered Yellow) on a 120 Hz iPhone while Home idles through a breath episode, in light and dark. Add an `OSSignposter` interval around `DoddyDirector.tick` to get ms per tick.

---

## 3. [Med] Home-wide `DragGesture(minimumDistance: 0)` calls the director on every touch sample

**Where / code**
`DoddyApp/Features/Home/HomeView.swift:75-81`
```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 0, coordinateSpace: .global)
        .onChanged { DoddyDirector.shared.fingerElsewhere(x: Double($0.location.x), y: Double($0.location.y)) }
        .onEnded { _ in DoddyDirector.shared.fingerElsewhereLifted() })
```
`DoddyDirector.swift:330-335` (`@MainActor`):
```swift
func fingerElsewhere(x: Double, y: Double) {
    guard isActive else { return }
    catchUp(); host.fingerElsewhere(x: x, y: y); poke()      // poke() = catchUp() + afterSteps()
}
```
`MotionRiding.swift:~113` `wantsFrames` returns true while `scene.finger.isDown`, so the 120 Hz link stays up for the whole touch (finding 2's loop).

**What happens**
On a 120 Hz touch screen that is up to 120 handler calls per second, each doing two `catchUp()` passes (engine sub-steps), `host.settle()`, `publish()` and `clock?.run()`, plus the display-link tick doing the same work, all on the main run loop that also drives the ScrollView's own pan. Touching the ScrollView with a zero-distance simultaneous drag also means SwiftUI evaluates the gesture closure for every sample of every scroll. `DoddyTouchArea` (`MotionSurfaceViews.swift:214-228`) adds a second `touchMoved` → `poke()` stream while the finger is on him (both gestures run, since the outer one is simultaneous).

**Fix**
The eyes only need the latest finger position at display rate: store it and let the (already running) tick consume it.
```swift
@State private var lastFollow: CFTimeInterval = 0
… .onChanged { v in
    let t = CACurrentMediaTime(); guard t - lastFollow >= 1.0 / 30 else { return }
    lastFollow = t
    DoddyDirector.shared.fingerElsewhere(x: v.location.x, y: v.location.y) }

// DoddyDirector: no second poke(), and do not step the engine from the touch handler at all
func fingerElsewhere(x: Double, y: Double) {
    guard isActive else { return }
    host.fingerElsewhere(x: x, y: y)        // only records the point + wakes the clock
    if asleep { clock?.run() }
}
```
(`host.fingerElsewhere` must tolerate being applied at the next tick instead of after a catch-up; check `MotionHost.fingerElsewhere` first.)

**Measure first:** yes. SwiftUI instrument + Hitches while dragging on Home (with cards so it scrolls) with the gesture on and off (temporary flag).

---

## 4. [Med] Opening scene: uncapped `TimelineView(.animation)` at up to 120 Hz over a live Home

**Where / code**
- `DoddyApp/Features/Opening/OpeningSceneView.swift:33` `TimelineView(.animation(paused: done)) { context in … scene(OpeningScene.frame(at: t, …), at: t, in: geo) }`, inside a `GeometryReader`. This is the only uncapped `TimelineView(.animation)` in the main app besides `IslandExtension.swift:58` (not mine). All others use `minimumInterval: 1/30` (`HomeView.swift:720`, `WelcomeView.swift:171`) or `.periodic`.
- `RootView.swift:430-437` the scene sits in the same `ZStack` as `tabContent`, so the real Home (with its geometry reports, Doddy director, cards) stays mounted and live under it.
- `Packages/DoddyCore/Sources/DoddyCore/OpeningPolicy.swift:81` `replayAfter: TimeInterval = 5 * 60`: it plays on cold launch and on return after 5 minutes away (unless `decide(...)` returns `.nothing` for another reason; I read only part of it).
- `OpeningSceneView.swift:49-66` also polls every 30 ms with `Task.sleep` (cheap).

**What happens**
Pen sketch, ball, ring, confetti and shake are rebuilt as a SwiftUI tree every display frame (120 Hz on ProMotion) for several seconds, while the app is also starting (finding 5) and Home is laying out. Any slice above 8.3 ms is a dropped frame, in the first seconds the owner sees on every launch.

**Fix**
```swift
TimelineView(.animation(minimumInterval: 1.0 / 60, paused: done)) { … }
```
A hand-drawn sketch does not gain from 120 Hz; the hand-over to Home (where Doddy must land exactly) is time-based (`OpeningScene.frame(at: t)`), so a 60 Hz sample does not change where he ends. Put the confetti/particle layer in `.drawingGroup()` or a `Canvas`.

**Measure first:** yes. Time Profiler + Hitches for the first 8 s after a cold launch, release build, device.

---

## 5. [Med] `LaunchWork.later()` runs 7 jobs on the main actor while the opening plays

**Where / code**
`DoddyApp/App/LaunchWork.swift`: `@MainActor enum LaunchWork`; `later()` waits `settle = 1500 ms`, then runs, 300 ms apart: `UpdatesModel().syncPushTokenIfOn()`, `SharedListsController…syncAllUnlessRecent()` + `startLiveUpdates()`, four notification schedulers (`MorningCheckInScheduler.apply`, `TidyUpScheduler.apply`, `EveningWrapUpScheduler.apply`, `WeeklyLookBackScheduler.apply`), `BirthdayScheduler.refresh()`, `RecordingCoordinator.shared.recoverUnfinished()`. The closures are created in a main-actor function, so they inherit main-actor isolation; whatever synchronous part each has runs on main.
`DoddyApp/App/DoddyApp.swift` `.task(id: profiles.hasLoaded)` starts this as soon as the profile has loaded, i.e. during the opening.
`docs/implementation/LAUNCH_PROFILING.md` itself lists `refreshOnForeground`, `MemoryCopySync`, `heyDoddyAppBecameActive` as still running twice at launch ("measure first").

**Fix**
Start `later()` when the opening is finished (`opening.play == nil`; `OpeningModel.finish()`), or when `scenePhase == .active` and the first interaction is idle. Run jobs that need no UI off-main (`Task.detached(priority: .utility)`), at minimum Birthdays (finding 1) and the notification schedulers' request building.

**Measure first:** yes: the `Launch` signposts exist (`LaunchWork.signposter`); use them with the App Launch template as the doc describes and look at the main thread between 1.5 s and ~6 s.

---

## 6. [Med] `ActivityLogStore.save()` is main-actor, rewrites the whole log on every append

**Where / code**
`DoddyApp/Infrastructure/ActivityLogStore.swift:9-11` `@MainActor final class ActivityLogStore`; `append` (:28) and `replace` (:34) each call `save()` (:81-91):
```swift
let data = try JSONEncoder().encode(entries)
try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
```
`VoiceSessionController` calls the store from 8 places (tool call "asked" / "started" / result). `ConversationLogStore.swift:62-72` has the same encode-all + atomic write for `[ConversationLog]` (the isolation annotation was not checked; its callers are on the main actor), run when a conversation is kept and on delete/clear.

**What happens**
Each tool call costs at least two O(n) encodes and two atomic writes (write temp file, fsync, rename; plus the protection class) on the main thread, at the moment the card/receipt appears and Doddy changes pose. A few ms typically, with occasional outliers when the flash is busy.

**Fix**
Keep `entries` as the in-memory truth and write behind it:
```swift
private var pendingSave: Task<Void, Never>?
private func save() {
    let snapshot = entries, url = fileURL
    pendingSave?.cancel()
    pendingSave = Task.detached(priority: .utility) {
        try? await Task.sleep(for: .milliseconds(300))          // coalesce a burst of appends
        guard !Task.isCancelled, let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
```
Flush on `scenePhase == .background`. Keep the *delete/clear* paths of both stores synchronous and verified (they return `Bool` on purpose so a failed write never looks like a deletion, and CLAUDE.md requires verified storage claims).

**Measure first:** yes: signpost around both `save()` functions; check the max, not the mean.

---

## 7. [Med] `DoddyApp.init` does synchronous Keychain, SQLite and JSON-file work before the first frame

**Where**
`DoddyApp/App/DoddyApp.swift:15-66` (`init`, main thread): `VoiceSessionKeychain.removeLegacySetup()`, `ServerKeychainStore.clearLeftoversOnFreshInstall()` (Keychain IPC); `AppEnvironment.shared` (`AppEnvironment.swift:76-83`, `static let shared = AppEnvironment.live()` → `DoddyDatabase(path:)` → `DatabaseQueue(path:)` + `Self.migrator.migrate(queue)` for 17 migrations, `DoddyDatabase.swift:25-31`); `ActivityLogStore.shared` (`load()` reads and decodes the whole file; `if entries != stored { save() }` can also encode and write synchronously, `ActivityLogStore.swift:72-80`); `ConversationLogStore` (`load()` decodes `recent.json`, `:60-63`); `FocusController.shared.refresh()` (JSON decode); `PhoneWatchLink.shared.activate()`; `VoiceLiveActivity.endStale()`, `ToolLiveActivity.endLeftovers`; `RecordingCoordinator.shared.install()`.
Then the first screen is gated on `profiles.hasLoaded` (`RootView.swift:364` `.task { await profiles.load() }`), so the canvas is blank until the profile read returns.
`docs/implementation/LAUNCH_PROFILING.md` says: written, never measured; `App.init` is the named next suspect.

**Fix**
Instrument first: one `signposter.beginInterval` per step above (`LaunchWork.signposter` already exists). Then defer what the first frame does not need: the two log stores can load lazily on first use (Settings, first tool call) or from `Task.detached`; the Keychain clean-ups only need to run before the first read of those tokens, so run them inside the token store's first access or in `afterFirstScreen`. Keep database open + migration synchronous (the repositories need it); on an up-to-date file it is one read of `grdb_migrations`, but on the first launch after an update it runs the new migrations (FTS5 + triggers) on main.

**Measure first:** yes: App Launch template, release build, device (procedure is in the doc).

---

## 8. [Med] `store.reload()` at every conversation start, unconditional `revision += 1`, non-indexable ORDER BY

**Where / code**
- `VoiceSessionController.swift` ~649 (in `start(...)`, after `phase = .connecting` ~613): `await store.reload()`, then synchronous context building on main: `VoiceContext.savedNotes(PrivateNotesStore.current().shareable(store.memories))` (~653), `ListsPrompt.render`, `ProfilePrompt.render`, `PersonalityPrompt.render` and a dozen prompt renders into the `variables` dictionary.
- `DoddyApp/Infrastructure/MemoryStore.swift:61-90`: five sequential `await`s (`memoryRepository.list(limit: nil)`, `allCorrections`, `lists`, `allPhotos`, `allAudio`, then `noteReminders?.reload()`), replaces `memories`, `corrections`, `lists`, `photos`, `recordings` wholesale, and at line 88 `revision += 1` **unconditionally**.
- `RootView.swift:281` `.onChange(of: store.revision) { WidgetSync.shared.refresh() }`, `:338-340` `MemoryCopySync.shared.schedule(PrivateNotesStore.current().shareable(store.memories))`; `SpotlightSync.swift:21-26` rebuilds `SpotlightIndex.entries(...)` + `signature` over all notes on the main actor before its signature guard.
- `Packages/DoddyCore/Sources/DoddyPersistence/SQLiteMemoryRepository.swift:~57` `"SELECT * FROM memories ORDER BY captured_at_ms IS NULL, captured_at_ms DESC, rowid DESC"`: the expression in the first sort key cannot use the `memories_captured_at` index (`DoddyDatabase.swift:68`), so it is a full scan and a temp-b-tree sort on every reload, and `SELECT *` also reads `raw_text`, `current_text` and the folded duplicate `search_text` for every row. These GRDB calls are `async` (they run on the DB queue, not on main).

**What happens**
Tapping Doddy triggers a reload-everything, a revision bump, and the fan-out to widget snapshot + share copy + Spotlight signature, all while Doddy is in `connecting`. The DB work is off-main; the `.filter`, the assignments, the observers and the sync/prompt building are on the main side.

**Fix**
```swift
// MemoryStore.reload()
let changed = notes != memories || storedLists != lists || storedCorrections != corrections
memories = notes; …
if changed { revision += 1 }
```
Optionally skip the reload in `start()` when `hasLoaded` and nothing outside the store writes (owner decision: the reload is currently the safety net for writers like intents/widgets). Replace the ORDER BY with an index-friendly form or an expression index (`CREATE INDEX memories_order ON memories((captured_at_ms IS NULL), captured_at_ms DESC, rowid DESC)`) and list only the needed columns. Check with `EXPLAIN QUERY PLAN` on 2-5k notes.

**Measure first:** yes: signpost `reload()` and the sync part of `start()` with 500 / 2,000 notes.

---

## 9. [Med] `RootView.body` depends on live conversation state

**Where / code**
`DoddyApp/App/RootView.swift:471` `.onChange(of: HomeConversation.shared.needsYou) …`, `:522` `.onChange(of: HomeConversation.shared.live != nil) …`, `:283` `.onChange(of: store.lists.map(\.name)) …`. `HomeConversation.needsYou` (`HomeConversation.swift:~25-37`) reads `controller.phase`, `pendingAction`, `accessRequest`, `accountNeeded`, `permissionRequest`; `live` reads `controller.isLive`. The `of:` expressions are evaluated while building `RootView.body`, so Observation registers all of those as dependencies of the app's root body (about 35 modifiers, `RootView.swift:193-526`, plus `store.lists.map(\.name)` allocating a name array each pass).

**What happens**
Every `phase` flip (3 or more per turn: listening → thinking → speaking), every pending-action change and every list edit re-evaluates the root body and diffs the whole tab tree. The diff stops at unchanged child views, so this is a CPU tax per event rather than a re-render of everything, but it lands on the same frames as Doddy's pose change and the island update.

**Fix**
Move the observers into a `ViewModifier`/child view so they get their own invalidation scope:
```swift
private struct ConversationWatcher: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onChange(of: HomeConversation.shared.needsYou) { … }
            .onChange(of: HomeConversation.shared.live != nil) { … }
    }
}
// RootView: .modifier(ConversationWatcher())   (same for the lists-name observer)
```
**Measure first:** yes: SwiftUI instrument, "View Body" count for `RootView` during a 5-turn conversation.

---

## 10. [Low-Med] `phase.didSet` has no same-value guard; each call re-lays out the indicator window

**Where / code**
`VoiceSessionController.swift:198-225`:
```swift
private(set) var phase: Phase = .idle {
    didSet {
        Self.conversationInProgress = isLive
        if isLive { Self.current = self } else if Self.current === self { Self.current = nil }
        ListeningIndicatorModel.shared.refresh()
        … syncIsland() …  expandIslandIfDue() …  UserDefaults reads/writes (once per conversation)
```
`didSet` runs on every assignment, equal value or not. The OpenAI path assigns `phase = .listening` for both `.userSpeechStarted` and `.responseDone` (`:~930`). `isMuted.didSet` (`:313-318`) and `longTurn.didSet` (`:342-344`) call `refresh()` too.
`ListeningStop.swift:111-115` `refresh()` → `ListeningIndicatorWindow.shared.update()` (`:173-183`) → `DispatchQueue.main.async { layout() }` → `host.sizeThatFits(…)` (a SwiftUI layout pass) + window frame + `isHidden = false`. The window exists for the whole conversation (level `.alert + 1`).

**Fix**
```swift
didSet {
    guard phase != oldValue else { return }
    …
}
// ListeningIndicatorModel.refresh(): compute the new indicator first; return early if indicator and isHidden are unchanged
```
and only call `layout()` when `indicator` or `result` changed. Safe quick win.
**Measure first:** no (logic is unambiguous; the size of the gain is not).

---

## 11. [Low-Med] `onGeometryChange(.global)` fires on every scroll frame

**Where / code**
- `HomeView.swift:322-326`:
  ```swift
  .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [opening] rect in
      Task { @MainActor in opening?.homeArtBox = ScreenBox(centerX: rect.midX, …) } }
  ```
  Inside a `ScrollView`, so the global frame changes each scroll frame: one unstructured `Task` and one `@Observable` write per frame. `RootView.swift:436` reads `opening.homeArtBox` only inside `if let play = opening.play`, so after the opening nobody observes it: pure waste.
- `MotionSurfaceViews.swift:97-99` every `motionSurface` (Home stage line, each visible Memories card via `MemoriesView.swift:95`) does `MainActor.assumeIsolated { DoddyDirector.shared.surfaceMoved(id, to: MotionRect(frame)) }` per scroll frame; `:48-50` `onScrollGeometryChange` → `listScrolled(to:)` → `catchUp(); host.listScrolled; poke()` per frame (publish + link kept at 120 Hz while scrolling).

**Fix**
Report `homeArtBox` only while `opening?.play != nil` and only if changed (`guard opening?.homeArtBox != new`). For Memories keep the per-frame work cheap (it is: dictionary writes), and consider throttling `listScrolled` to the display-link tick instead of calling `poke()` from the scroll callback.
**Measure first:** yes: Memories with 200+ notes, SwiftUI instrument + Time Profiler while flicking.

---

## 12. [Low-Med] Sprite frames decode lazily on first use; one asset is oversized

**Where / measured**
`python3 -I` PNG header read of `DoddyApp/Resources/Assets.xcassets`: 172 PNGs, 63.5 MB decoded if all loaded. 63 `DoddyMotion_*`/`VoiceDoddy_*`/`WholeDoddy_*` frames at 300x450 (@3x, 0.54 MB decoded each, about 34 MB for all) plus their 200x300 @2x partners; 4 poses at 512x768 (1.6 MB each); `UploadedDoddy_Listening` 800x1200 (3.8 MB); AppIcon 1024² (not decoded at runtime).
Display: the figure is `pictureHeight * scale` = 133.3 pt * 1.4 = 187 pt tall on Home = 560 px at @3x, so the 450 px strips are *upscaled* (about 1.25x), not oversized. `UploadedDoddy_Listening` (`HomeView.swift` `UploadedCharacterView(assetName:…, height: 210)`) needs about 630 px tall but ships 1200: 3.6x the pixels needed.
`DoddyFigureView.swift:47` `Image(picture.asset)` is created on each tick for whichever strip frame `MotionArt.choose` selected; the first draw of each frame decodes a PNG (ImageIO).

**Fix**
Pre-warm the frames Home actually plays (idle, wave, hop, thinking, listening) off-main at launch: `Task.detached(priority: .utility) { for n in hotFrames { _ = UIImage(named: n)?.preparingForDisplay() } }`. Don't preload all 63 (34 MB). Re-export `UploadedDoddy_Listening` at about 640x960.
**Measure first:** yes: Time Profiler for `ImageIO` PNG decode on first play of a strip, Allocations for resident image memory.

---

## 13. [Low] Transcript sheet is a non-lazy `VStack` inside one large body

`VoiceView.swift:152-153,216-218`: `ScrollViewReader { ScrollView { VStack(alignment: .leading, spacing: 16) { … ForEach(controller.lines) { … .id(line.id) } … } } }`, plus 14 `.onChange(of: controller.X)` (lines 313-347) and a ~700-character footnote `Text`. The helper methods (`conversation(_:)`, `problem(_:)`, cards) are plain functions of the same `VoiceView` struct, so every observed property read in them is a dependency of the one `VoiceView.body`: any phase/card change re-evaluates all lines and cards (O(lines + cards)), and `scrollTo` on a non-lazy stack measures everything. Bounded effect: lines are appended once per final utterance (`onUserTranscript`/`onAgentResponse`, no per-token or level binding exists), and it only matters while the Transcript sheet is open.
Fix: `LazyVStack`; line rows as `Equatable` structs; cards as child views that read their own controller property.

## 14. [Low] Memories list

`MemoriesView.swift:89-95` `LazyVStack { ForEach(Array(shown.enumerated()), id: \.element.id) { index, record in … .motionSurface(.rule(index)) } }`: `Array(shown.enumerated())` is allocated on every body pass (the cost of computing `shown` was not reviewed), and `index` is part of the surface id, so inserting a note at the top changes every card's id and `MotionSurfaceModifier` (`:103-106`) calls `surfaceGone(old)`/`surfaceAppeared(new)` (each `poke()`) for each visible card.

## 15. [Low] DB: single connection, FTS5 optimize per edit

`DoddyDatabase.swift:18` `DatabaseQueue(path:)` (one connection, default rollback journal, `secure_delete = ON` at :36). `compactSearchIndex` (`:44-47`) runs `INSERT INTO idx(idx) VALUES('optimize')` inside every delete/rewrite transaction (ADR-584, a privacy requirement): FTS5 `optimize` merges all segments, cost proportional to index size, on every note edit. Everything else (`reload()`'s awaits, recordings' segment writes) queues behind it on the one connection. All of this is `async` GRDB, so it does not block main; it delays Save/Delete confirmations and any concurrent reload. Measure with 2-5k notes before touching it; `DatabasePool`/WAL would let reads run during writes.

## 16. [Low] DEBUG-only work and Debug builds

`DoddyDirector.swift:478-480` (`#if DEBUG`) evaluates `drawnCount` and `drawingsDescription` (sort + `String(format:)` + join) as arguments on every tick, even with no finding. A Debug build (-Onone) also makes SwiftUI several times slower: judge smoothness only on a Release build (the same applies to the opening and the transcript). Make the description an `@autoclosure`.

## 17. [Low] `AliveDoddy`

`HomeView.swift:720-730` re-evaluates `WholeDoddyView(…).id(pose)…scaleEffect…rotationEffect` at 30 Hz for the breath/sway (only when the motion world is off: iPad/sidebar layout, `HomeView.swift:~318`). A `phaseAnimator`/`keyframeAnimator` keeps it on Core Animation with no body passes.

---

## Quick wins (small, local, low risk)

1. `VoiceSessionController.swift:199`: `guard phase != oldValue else { return }` as the first line of `phase.didSet`; same-value early-return in `ListeningIndicatorModel.refresh()` (`ListeningStop.swift:111`) (finding 10).
2. `DoddyFigureView.swift:58`: attach the cream-edge shadows only in dark mode (finding 2).
3. `OpeningSceneView.swift:33`: `.animation(minimumInterval: 1.0 / 60, paused: done)` (finding 4).
4. `HomeView.swift:75-81`: throttle the finger-follow gesture to 30 Hz (finding 3).
5. `HomeView.swift:322-326`: report `homeArtBox` only while the opening plays and only when changed (finding 11).
6. `MemoryStore.reload()`: bump `revision` only when the data changed (finding 8).
7. `DoddyClock.swift:47`: preferred 60 for idle motion, 120 only for flight/drag (finding 2; check on a device).
8. `LaunchWork.later()`: begin after the opening has ended (finding 5).
9. `DoddyDirector.swift:478-480`: lazy `drawingsDescription` (finding 16).

## Instruments plan (real iPhone with ProMotion, Release build)

- **Time Profiler + Hangs/Hitches, main thread only**: (a) cold launch to Home including the opening, first 8 s (findings 4, 5, 7); (b) Home idle for 60 s through two breath episodes (finding 2); (c) finger drag/scroll on Home (finding 3); (d) tap Doddy → connecting → listening (findings 8, 9, 10; island part belongs to the other review); (e) turns with calendar, birthdays, contacts and photos tool calls (finding 1) and with list/note tool calls (finding 6); (f) End conversation (log save); (g) Memories flick with 200+ notes (findings 11, 14).
- **SwiftUI instrument** (View Body, Update Groups, cause and effect): body counts for `RootView`, `HomeView`, `VoiceView`, `DoddySlotFigure`, `PersistentDoddyView` during a conversation.
- **Core Animation / Metal System Trace**: "Color Offscreen-Rendered Yellow", GPU time per frame while the sprite breathes, in light and dark appearance (shadows, blur).
- **Animation Hitches** with the display link at 120 vs 60 (build the quick win 7 to compare).
- **Allocations / VM Tracker**: resident image memory after cycling through all strips (finding 12).
- **os_signpost** (Points of Interest): add intervals for `DeviceConnections` reads, `ActivityLogStore.save`, `ConversationLogStore.save`, `MemoryStore.reload`, the sync part of `VoiceSessionController.start`, `DoddyDirector.tick`, and each step in `DoddyApp.init`.
- **System Trace / File Activity**: main-thread file IO and Keychain waits in `App.init`.

## Checked and found fine

- No `AnyView` in `DoddyApp` (0 matches). No `Timer.publish`, `Timer.scheduledTimer` or `.onReceive` (0 matches). No `print`/`NSLog` in the app target.
- `NotificationCenter` observers are few and low-rate: keyboard show/hide and power state (`DoddyClock.swift:27-36`, guarded and idempotent), audio interruption/route/config changes (`VoiceSessionController.swift:~1014`, `OpenAIRealtimeSession.swift:311-314`, `RecordingCoordinator.swift:662-673`).
- All `TimelineView(.animation)` except the opening scene (and the island's) are capped at 30 Hz or `.periodic`; `DoddyMotionView` uses `motion.frameDuration`.
- No audio-level/meter property is bound to the `@Observable` controller; transcript `lines` grow once per final utterance (`append` at `VoiceSessionController.swift:2119-2154`; `correct` is a `lastIndex` from the end); JSON encode/decode only in store load/save paths, never in view bodies.
- Observation granularity in the motion layer is good: `figure`/`placement` are read only by `DoddySlotFigure`, `DoddyTouchArea`, `DoddyOverlay`; frames/marks/mount counts are `@ObservationIgnored`; `publish()` assigns only when the figure differs. HomeView does not read `figure`, so a tick does not re-evaluate Home.
- The GRDB repositories use `async` `dbQueue.read/write`, so SQL runs off the main actor. Indexes exist for the time-ordered tables (`DoddyDatabase.swift:68,106,136,164,244,280,297-298,321,343,368,390,399,425`); notes search is FTS5, with no in-memory text search (`localizedCaseInsensitiveContains` has 0 matches). I found no N+1 loop in the parts I read (the one `for row in try Row.fetchAll` is a single query).
- Sprite assets are not oversized for their display size (finding 12 has the one exception).
