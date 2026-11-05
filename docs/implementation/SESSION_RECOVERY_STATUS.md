# Voice session recovery: status (ADR-360)
Date: 2026-10-11. Owner instruction: "start OP-023" (voice fallback and session recovery), from the research backlog. User story: "Were you still listening?" → "Audio stopped. I saved a partial draft, not a memory."

## What was wrong
- **Wrong message:** a conversation that dropped mid-way showed **"Couldn't connect"** (an error), or **"Conversation ended"** (a bare disconnect), the same as a normal end. The SDK's disconnect reason was ignored.
- **Card lost:** a "Save this note?" card that was showing disappeared, and its text was lost.
- **Records late or lost:** after an error, the transcript and the "ended before you answered" rows were written only at Close. **Talk again** cleared the transcript without keeping it.
- **Microphone held:** an error didn't end the voice session.

## What it does now
- **How it ended** (`VoiceSessionEnd`):
  - **User ended:** End, Close, or the island.
  - **Doddy ended:** its end_call.
  - **Quiet timeout:** a "Hey Doddy" start nobody spoke into.
  - **Dropped:** offline, connection lost, or error.
  - **Mapping from the SDK** (read in ElevenLabs Swift SDK v3.3.1, `Conversation.swift`): `onDisconnect(.agent)` is sent when the socket or room is closed from the other side, so it's a drop. `onDisconnect(.user)` comes from the SDK's own `endConversation()`, which the app's End and the agent's `end_call` both call. `.error` is declared but not raised in 3.3.1.
- **Screen:**
  - A drop after Doddy was listening shows **"The conversation dropped"** with "It stopped before you ended it, so Doddy didn't hear anything after that. Nothing was saved because of it."
  - Before Doddy was listening, it's still "Couldn't connect"; offline, it's still "You're offline".
- **Draft, not a note** (`RecoveryDraft`):
  - **Contents:** the user's lines after Doddy's last reply, or the note Doddy was asking to save.
  - **Editing and saving:** it's editable. **Save as note** saves it, explicit and read back; **Discard** drops it.
  - **Storage:** held on the screen only, never written to disk.
  - **Offline:** it prefills the offline note card.
  - **"Worth keeping?":** also offered after a drop, without the draft's lines.
- **Every ending records once:**
  - `fail()` now ends the SDK session and keeps the log and the unanswered rows right away.
  - `start()` keeps a previous conversation that wasn't kept yet.
  - The conversation log stores `ended` ("user", "doddy", "quiet", "dropped-offline", "dropped-connection", "dropped-error"). Older logs load without it.
- **Carrying on** (`SessionRecovery.withResumeNote`): within 15 minutes of a drop, the next conversation's `recent_conversations` text starts with: "Note: the newest conversation below was cut off at … Say briefly that it was cut off and offer to carry on from its last lines. Do not assume you heard anything after them or that anything after them was done."
  - It follows "Remember recent conversations", so it's never sent for Private.
  - It's only added when the dropped conversation is among those sent.
  - No change to the live agent prompt.

## Files
- **Core:**
  - `SessionRecovery.swift` (new);
  - `VoiceContext.swift` (`ConversationLog.ended`).
- **App:**
  - `VoiceSessionController.swift`: one ending path, the draft, the resume note, and suggestions after a drop.
  - `VoiceView.swift`: the title, `RecoveryDraftCard`, and the offline card prefill.
- **Tests:** `SessionRecoveryTests.swift` (8).

## Verified (Linux, Swift 6.2.1)
- `scripts/ci.sh --core-only`: PASS for core-only scope, with 832 package tests. Messaging database tests SKIPPED; iOS app NOT RUN.
- Planted bugs, each caught and then restored:
  - the draft taking all user lines instead of the unanswered ones: 4 failures;
  - a drop titled "Conversation ended": 2 failures;
  - the resume note added when the dropped conversation isn't sent: 1 failure.
- `swiftc -parse` on `VoiceSessionController.swift` and `VoiceView.swift`.

## NOT RUN / unverified
- **Not built:** the app hasn't been compiled with Xcode.
- **No real drops tested:** Wi-Fi off mid-sentence, a server-side close, the agent saying goodbye, Airplane mode, a phone call.
- **Unconfirmed on a device:** that `.agent` is what a real network drop reports, and that end_call arrives as `.user`.
- **Polish:** added (see `ACTION_STATUS_STATUS.md`, "Polish"), but not seen on a device.
- **Checklist:** Mac checklist items SR1 to SR5.

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-08 verified status / "never silently pretend listened" | A drop is shown as a drop; the next conversation is told it was cut off and not to assume anything after it | `VoiceSessionEnd.afterDisconnect`, `SessionRecovery.status`, `resumeNote` | `testOnlyTheOtherSideClosingIsADrop`, `testADropAfterListeningIsNeverCouldntConnectOrEnded`, `testTheNextConversationIsToldItWasCutOffForAWhile` | SDK reason mapping read from source, not seen on a device |
| DOD-06 / memory only on explicit save | The draft is never a note until Save; it isn't written to disk | `RecoveryDraft`, `saveRecovery` | `testTheDraftIsWhatDoddyHeardAndHadntAnswered`, `testNoDraftAfterANormalEndOrWhenNothingWasLeft` | Save path not compiled with Xcode |
| DOD-11 privacy | The resume note travels only inside the conversations the user lets Doddy remember; never for Private | `withResumeNote` used only when `logs.isEnabled`; `ConversationRetention` | `testTheNoteGoesFirstOnlyWhenTheCutOffConversationIsSent` | — |
