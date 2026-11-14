# A finished task reaches Messages while the app is open, and the person is told once

- **Date:** 2026-11-12
- **Decided by:** owner: "jak ja proszę go o zrobienie jakiegoś taska, mówi, że to będzie w wiadomościach i potem na przykład ja nie dostaję notyfikacji żadnej, że to jest w tych wiadomościach […] albo on mi dodaje kartę, która się nie pojawia, muszę sobie scrollować", then "zrób teraz Wiadomości" (12 Nov 2026). The mechanics below are the implementation's.
- **Status:** accepted; built on branch `claude/messages-results-and-cards`
- **Replaces:** nothing. Builds on `2026-11-10-cards-pop-up-and-results-in-messages`.

## Why
The review of 12 Nov (`docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md`, section 2) found, in the code:
- A finished task was written into Messages only by `ErrandsModel.refresh()`, which ran only when the app came to the front.
- The server's push was the only notification, and nothing refreshed when it arrived. A push that came while the app was open showed a banner, but the result appeared in Messages only after the app was closed and opened again. Tapping the push opened Messages without it.
- The push carried no `content-available`, so iOS never woke the app to save the result.
- The voice tool told Doddy "the user gets a notification when it's done" whether or not notifications were allowed.
- In Messages, only a new message scrolled the thread. A file card, a finished task, a call's answer, the typing bubble or a problem appeared below the fold.

## Decision
- **Server:** the "task finished" and "file ready" pushes carry `content-available: 1` next to their alert, which is unchanged (`alertPayload` in `providers/apns.ts`). The app already has the `remote-notification` background mode (ADR-284).
- **App: the result is fetched when a push says so.**
  - In the background, `AppDelegate.didReceiveRemoteNotification` fetches it.
  - While the app is open, `TimerBanners.willPresent` fetches it.
  - On a tap, `didReceive` opens Messages first and fetches at the same time.
- **App: while open, the app asks every 30 seconds while a task runs** (`ErrandsModel.watchWhileRunning`). Watching starts after a hand-over and when the app comes to the front, stops when it goes to the background, ends when nothing runs, and lasts at most 45 minutes. A read that failed before is tried again rather than stopping results until a restart.
- **The app's own notice** (DoddyCore `ResultNotice`, `ResultNoticePoster`): when the app itself saved a result, it shows a notice in the server's push's own words ("Done. The result is waiting in Messages." / "Doddy couldn't finish a task."). It does this only when all of these hold:
  - the app is in front;
  - Messages isn't on screen;
  - neither the server's push nor an earlier notice arrived in the last 10 minutes.

  A server push that arrives just after the app's own notice is not shown. The notice carries the push's routing kind only, no title and no words, so a tap opens Messages the same way.
- **Doddy's words:** the tool reply now says the result comes "with a notification if the user allowed Doddy's notifications".
- **Messages:**
  - An end marker after the last item; the thread scrolls to it whenever something is added at the bottom, never when something is deleted.
  - The files list is set only when it changed. It was reassigned on every 6 or 30 second poll, redrawing the whole thread.
  - Web addresses in bubbles are found once per text, not on every redraw.
  - A file made from a Messages card shows the brief the person said yes to as its words, clipped to 280 characters; the name stays on the file's card.

## Consequences
- **What the person sees:** a result shows up in Messages within about 30 seconds while the app is open, and on a push when it is closed (unless the app was swiped away, when iOS doesn't wake it; then it arrives when the app opens, as before). One notice per result, not two.
- **Load:** up to 2 requests a minute to `GET /v1/errands/:id` per running task while the app is open, for at most 45 minutes. A task usually takes a few minutes.
- **Privacy:**
  - Notices say no title and no result, like the pushes.
  - A file's brief now becomes part of the saved thread and its encrypted web copy. It was shown on the card before, and the conversation it came from was already copied.
- **Not done here:**
  - A card raised in a voice conversation can still sit below the transcript. That is `VoiceView.swift`, which open pull requests #349 and #332 are changing; it waits for them.
  - A file made by voice still has no description: that needs `VoiceSessionController.swift` (also open elsewhere) and a description argument on `make_document` / `make_presentation`, which changes the live agent only on the owner's word.
  - The rows of `MessagesView` are still built in one large body; splitting them is a larger change for a session with Xcode.

## Evidence
- `make test-core` (Swift 6.1.2, Linux): the new `ResultNoticeTests`, the file description test and the reply wording test; numbers in the pull request.
- `npm test` in `server/messaging` with Postgres 16: 917/917, including the `content-available` test.
- `swiftc -parse` on every changed app file; the string catalogs' `--check`.
- The SwiftUI and the notification handlers were **not compiled** here; the pull request's `ios-build` job is the first compile. Not seen on a device.
