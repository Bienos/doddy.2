# On my radar offers alerts only when Doddy's server said it checks follows, a radar notification opens the radar, and the voice names the screen as the app does

- **Date:** 2026-11-13
- **Decided by:** owner, 12 to 13 Nov 2026, in the review `docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md` section 6 ("Ukryć „Daj znać…” do czasu włączenia alertów", "Poprawić tekst odpowiedzi głosowej i dać „Pokaż” jako następny krok", "powiadomienie ma otwierać radar", "połączyć radar z „Wiadomościami dnia”"), then "Wszystko dawaj". Parts 4 and 5 below are proposals, owner approval pending.
- **Status:** applied in #401 (parts 1 to 3) and, for Home opening the sheet, in the pull request from branch `claude/radar-push-opens-radar`
- **Replaces:** nothing; builds on `2026-11-10-radar-alerts` and `2026-11-11-radar-alerts-by-voice`

## Why
The review found, on `main` at 12 Nov 2026:
1. Alerts are off on the messaging server (`RADAR_ALERTS_ENABLED=0`; `GET /v1/news/radar` answers `available: false`), yet every follow showed "Tell me…" („Daj znać…”), whose sheet then offered only "Here only".
2. Following by voice replied "now following this in Following (Home's menu, then Following)", a name the app hasn't shown since 10 Nov ("On my radar", Polish „Na radarze”). The follow itself is kept on the iPhone by design (ADR-656); alerts by voice were merged in #347.
3. Tapping a radar notification didn't open the radar: the server queued it under `radar:<alert>:<story>` and `pushData` gave no routing hint for that key, so the app had nothing to route.
4. Settings › Daily news keeps a second, separate set of topics.

## Decision
1. **Alerts are offered only on the server's word.** DoddyCore `RadarAlertsAvailability` reads the server's last answer: `on` (said yes), `off` (said no), `unknown` (no answer, which is not a yes). `RadarTellMe` decides:
   - "Tell me…" under a follow shows when the server said `on`, or when the follow already has something to change (flag words, or a server check kept on this iPhone), so nothing is left that can't be turned off. Otherwise the button and its "Shown here only" line are gone.
   - The Add sheet shows "tell me when" only when the server said `on`.
   - A follow's own sheet offers the three ways and the server switch only when the server said `on`; otherwise its footer says why. After `off` ("doesn't check follows for anyone yet") Save keeps the alert here only (`RadarTellMe.kept`); with no answer ("only the words can be changed now") the way of telling stays as it was set and the server's answer to the save decides, as before, so a missing answer never turns a check off by itself.
   - A check the server once took is never said to run once the server says it checks nothing (`RadarTellMe.line`).
   - `FollowingModel.loadRadar` asks the server what it holds even after a refused re-send, so a refused send no longer leaves the answer unknown.
2. **The voice names the screen as the app does.** `VoiceToolReply.newsFollow` says "the On my radar screen (in Polish "Na radarze"; Home, the ••• menu, then On my radar)" and asks the agent to offer one next step in the same sentence: they can look there now. No voice tool opens a screen, so the reply also says "Never promise a story; you can't open the screen for them, so never say you did". The (now unused) card lines, the "What Doddy did" row ("Add to radar" / „Dodaj do radaru”; rows kept under the old title "Follow in Following" show the new Polish too) and the privacy screen's description of what goes to the messaging server (`DataFlow.swift`, English only as before) say the same. `voice-agent/tools.json` is unchanged.
3. **A radar notification opens On my radar.** The messaging server's `pushData` maps `radar:` keys to `{ kind: "radar" }` (the kind only: never the follow, the story or the words; no `content-available`). DoddyCore `ServerPushKind.radar` (`opensRadar`); the app's notification handler (`TimerBanners`, in `NoteReminderNotifications.swift`) calls `ShortcutRouter.radarOpened()`, which asks the Face ID lock like every other way in and sets `isRadarRequested`. Home opens the sheet with this, next to the `isMessagesRequested` handler (added on branch `claude/radar-push-opens-radar`, with a check that the build shows On my radar):
   ```swift
   // A radar story's push, tapped (decision 2026-11-13-radar-fixes): On my radar, where "Doddy spotted" lists it.
   .onChange(of: router.isRadarRequested, initial: true) { _, requested in
       guard requested else { return }
       router.isRadarRequested = false
       guard scope.shows(.following) else { return }
       showFollowing = true
   }
   ```
   and, so a tap from another tab comes back to Home first, in `RootView.swift` next to the Recordings line: `.onChange(of: router.isRadarRequested) { _, requested in if requested { selectedTab = .home } }`.
4. **Daily news and the radar (proposal).** For now Settings › Daily news says under its topics that they are only for the daily message and that On my radar is a separate list (a footer; nothing else changes). Proposed, in separate pull requests, each needing the owner's yes:
   1. One list: what is on the radar is what the daily message covers. Daily news keeps its own settings (on or off, time, notification or text, language) and loses its own topics, own words and own feeds.
   2. The daily message then needs the radar's follows on Doddy's server, which today keeps them only for follows the person let it check. So turning the daily message on asks the same explicit consent as the radar's server switch, with the same footer saying what the server keeps.
   3. Existing Daily news topics are offered once as radar follows ("Add your daily news topics to your radar?"), on a tap, never moved by themselves; the server's `news_settings` topics are deleted only after the person's answer.
   4. "One field of words per topic" (review section 6): the follow's own words become the alert's words by default, and the separate "Words to look out for" field moves under "More". While alerts are off this pull request already leaves one words field in the Add sheet.
   5. A daily news notification's tap could then open On my radar too (a `news:` kind next to `radar`).
   Not built here: it changes a server table's meaning, a privacy promise ("the server keeps none of it") and Settings screens held by other pull requests (`SettingsView.swift`, `SettingsScreens.swift`).
5. **"Doddy noticed" on Home (proposal, not built).** A quiet card on Home with the newest unseen "Doddy spotted" story, opening On my radar. `HomeView.swift` is held by other pull requests; it waits for them, and for alerts to be on (with alerts off there is nothing the server spots).

The "Show" button after a voice follow (review: „dać „Pokaż” jako następny krok”) is said, not shown: a button in the conversation needs `VoiceSessionController.swift` (to record the follow as something to show) and `VoiceView.swift` or `HomeConversation.swift` (to draw it), the first two held by other pull requests. When they are free: record the added follow's id, show a "Show" chip that calls the same `router.radarOpened()`.

## Consequences
- With alerts off, On my radar is calmer: no "Tell me…", no "Shown here only" lines, and the Add sheet ends at the follow. Turning `RADAR_ALERTS_ENABLED` on brings them back with no app change, once the screen has the server's answer.
- When the server can't be reached the alert controls stay hidden; a follow with flag words or a server check can still be opened and its words changed (its sheet says the server hasn't answered). A save that can't reach the server behaves as before: `FollowingModel.apply` keeps it here only, says so, and re-sends the list on the next load.
- Privacy: the push's routing hint is a kind, like `call-result`; nothing about the follow or story is added to the payload. No new data is kept anywhere.
- Radar pushes still need `RADAR_ALERTS_ENABLED=1` and working APNs (`docs/OWNER_QUEUE.md` 8); the server change ships with the next `doddy-messaging` deploy and changes nothing until then.

## Evidence
See the pull request: DoddyCore tests (`RadarOfferTests`, `NewsFollowVoiceTests`, `ServerPushKindTests`), the messaging server's tests (`pushKind.test.ts`, `pushKindDb.test.ts` against PostgreSQL 16), `scripts/typecheck_app_logic.sh` (covers `FollowingModel.swift` and `ShortcutRouter.swift`), `swiftc -parse` on every changed Swift file. The SwiftUI views (`RadarViews.swift`, `NewsSettingsView.swift`) and the notification handler are **not compiled** here (no Xcode); nothing was run on a device.
