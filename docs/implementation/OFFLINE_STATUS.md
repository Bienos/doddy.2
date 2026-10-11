# Offline: status (ADR-273)
Date: 2026-10-11. Owner: "do all of them" (round 3, item 10).

## What ships
- **Recognising offline** (`Offline.isNoConnection`):
  - the token server's `offline`;
  - a URL loading error meaning no connection (no internet, lost connection, host not found or unreachable, DNS, timed out, mobile data off, roaming off), also when it is inside another error, such as one from the voice SDK.
  - A server that answered "no" doesn't count as offline.
- **The voice screen** says "You're offline. Doddy's voice needs the internet." instead of a technical error. It shows a card with what still works:
  - a note written or dictated there (dictation is the keyboard's own);
  - saved on this iPhone only after **Save note**, with the same validation as Capture, read back by the store ("Saved on this iPhone: …");
  - "When you're back online, close this and talk to Doddy again."
- **Nothing is queued** to send later, and the voice agent isn't involved.
- **No network monitoring:** the capability guard forbids the Network framework, so Doddy recognises the errors it already gets rather than watching the connection.

## Files
- **Core:** `Offline.swift`.
- **App:** `VoiceSessionController` (`isOffline`, `failOffline`, `saveOfflineNote`); `VoiceView` (`OfflineNoteCard`).
- **Tests:** `OfflineTests` (2).

## Verified (Linux)
- `OfflineTests` pass.

## NOT RUN
- No Xcode build, and never tried in flight mode.
- Not known: which error the ElevenLabs SDK reports when there's no connection. If it doesn't wrap a URL error, the screen shows the old message.
- Not known: whether keyboard dictation works offline in the user's language.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-01 useful_first | A plain "You're offline" and a way to save a note anyway | `testNoConnectionIsRecognisedAlsoWhenWrapped` | SDK error shape unknown |
| DOD-08 verified_status_and_receipts | "Saved on this iPhone" only after the store reads it back | — | UI not compiled |
| DOD-02 honesty_over_agreeableness | A server refusal is never called "offline" | `testServerAnswersAreNotOffline` | — |
