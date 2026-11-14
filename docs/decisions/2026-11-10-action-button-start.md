# The Action Button returns as soon as the island is up, and the voice token is fetched ahead of time

- **Date:** 2026-11-10
- **Decided by:** owner (Pat, 10 Nov 2026): the Action Button "works badly, in practice it doesn't work at all" and Doddy is slow to start; chose to fetch the token ahead of time ("bilet do rozmowy z wyprzedzeniem").
- **Status:** applied in the pull request of branch `claude/action-button-start`. Not verified on a device.
- **Replaces:** nothing. Follows `2026-11-10-voice-start-timing` (its "next, from the numbers" step, taken before any numbers exist, on the owner's choice) and ADR-686.

## Why
Read from the code (no phone was available):
1. **Confirmed.** `TalkButtonIntent.perform` awaited `TalkInIsland.start`, which awaited the whole `controller.start`: notes snapshot, token request, ElevenLabs connect (capped at 10 s). A background intent has a short time budget, so iOS can end it before the island is seen. The island itself (the Live Activity) was requested at the first line of `start`, but the intent did not return until the connect was over.
2. **Partly confirmed.** `auth.restore()` ran on every press. It returns at once when the older voice session is signed in with time left, and when there is no older voice session at all. A Doddy account (the only way in since 8 Nov) never needs it, since `hasVoiceAccess` is true for it and the token request refreshes the account's token itself. So it cost little for most people, but it could refresh an older session over the network on a press.
3. **Confirmed as a risk, not as a cause.** The widget extension's copy of `TalkButtonIntent` is a no-op. `LiveActivityIntent` and `AudioRecordingIntent` are meant to run in the app's process, and the code (ADR-131) assumes it. Nothing logged which process ran it.
4. **Partly confirmed.** `DoddyAccountModel` reads its stored session in `init`, so `isSignedIn` is right before the first press. `IntentStores.store` is set in `DoddyApp.init` and held `weak` by a `@State` that lives as long as the app; its lifetime is fine. But iOS can run an intent in a freshly launched process before `init` has run, and then the press was refused "voice input unavailable".
5. By design, with Doddy on screen iOS shows no island of its own; Home's strip is the screen. Unchanged.

## Decision
- `TalkInIsland.start` runs `controller.start` in a task and waits only until the checks are done and the island and audio session are up (`VoiceSessionController.backgroundStartReady`), at most 4 s (`TalkStartHandoff`, DoddyCore). It then returns and the connect carries on in a task held by `TalkInIsland`, under a `beginBackgroundTask` assertion. A refusal or failure before that point is reported to the intent as before (open Doddy, or say why). A failure after it goes through the controller's own `fail`, which ends the island and keeps the conversation log, so no "connecting" island is left. The log says `the connection failed after the intent returned`.
- A signed-in Doddy account skips `auth.restore()` (`TalkStartAccount.needsRestore`, DoddyCore); an older voice session is restored only when not signed in or within 30 s of running out. Also in `HomeConversation.canStartInPlace`.
- `IntentStores.waitForStore()` waits up to 2 s for the stores on a cold launch.
- The widget extension's copy logs `talk button ran in the widget extension: nothing started`.
- **Token shelf.** `VoiceTokenShelf` (DoddyCore) holds the rules: one use, same account and server, at most 4 minutes old, a 15-minute cool-down after an unused one (the token server counts every token: 30 an hour and 150 a day per person). `VoiceTokenWarmer` (app) fetches one when Doddy comes to the front (`didBecomeActive`, never on a background launch) and only if the voice data notice is accepted, the microphone is allowed, a Doddy account (or older voice login) is signed in, Pause all is off, and no conversation is running. `VoiceSessionController.start` takes the shelved token if one is held, else fetches as before. A token is gone from the shelf once taken, so a start that fails to connect with it fetches a fresh one next time; it is never reused. The shelf is cleared on sign-out (account and older voice login), account change (the owner is compared at take), Pause all (observed) and consent withdrawn (`VoiceProviderConsent.reset`). The token is never logged; the start line says only `token shelf` or `token fetched`.
- No behaviour starts a conversation without a press. A token alone connects nothing and opens no microphone.

## Consequences
- The island should appear within about a second of the press, and Doddy connects behind it. The token request leaves the press path whenever the shelf had one.
- Cost: up to 4 extra tokens an hour when the shelf is never used (the cool-down), against the same 30 an hour limit that a start uses. Someone who opens Doddy often and talks rarely uses them up faster than before; the cool-down bounds it.
- If the app is suspended before the connect finishes after the intent returned, the island is up but not listening until the person opens it. The background-task assertion and the active audio session are what should prevent that; unverified.
- `VoiceSessionController.swift` changed by about 13 lines (two flags, the shelf take).

## How to read the log
Console.app with the iPhone connected, subsystem `com.bienos.doddy2.dev`, category `voice-audio`, after one press:
- `talk button: startInIsland, mode dynamicIsland` — the app's copy of the intent ran. If instead `talk button ran in the widget extension: nothing started` appears, iOS ran it in the extension: the cause is found.
- `talk in the island not started: <check>` — which check refused (terms, voice input unavailable, app lock, live activities off, microphone not allowed, voice not set up, refused in the background).
- `starting a conversation: attempt n, in background true, without opening true`, then `connecting to ElevenLabs`, then `conversation started`.
- `talk start timing: account … · profile … · island … · connect … · total … · token shelf|token fetched` — `island` is what the intent waited for; `connect` and `total` run on after it. `voice token request took …` appears only when the token was fetched, not shelved. `token shelf: one kept` / `nothing kept` shows the warm-up.

## Still unverified on a device
Whether iOS lets the connect finish after the intent returns; whether the app copy of the intent runs on the Action Button on iOS 18, 25 and 26; the real time to the island; that the warm-up happens and a shelved token connects. None of the app code is compiled here.

## Evidence
`swift test` for DoddyCore: 2930 tests pass on Linux, including `VoiceTokenShelfTests`, `TalkStartRulesTests` and the timeline tests. `swiftc -parse` on every changed app file. No Xcode: the app is not compiled.
