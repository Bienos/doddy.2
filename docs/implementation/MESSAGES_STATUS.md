# Messages: the typed conversation with Doddy, inside the app (ADR-585)

Branch `claude/gifted-pascal-3e117c-messages`, off main at `8aa42c59`. No pull request yet. Owner, 22 Oct: "but i wnated to build imessage like section inside doddy", then "go for ti".

## What it is, in one paragraph

Ask Doddy (typed questions, ADR-115) is now a thread. Home's bottom-left button, which said **Type**, says **Messages** and opens it. Your messages and Doddy's answers are bubbles with a date heading after an hour of silence, saved **on this iPhone** until you delete them (the ••• menu → Delete conversation, or Settings → Delete all). It is not Apple's iMessage, not SMS, and nothing is stored on a server. Replies still come from the same gateway as before (ADR-115): same consent, same Settings switch, same off-by-default.

## What changed and what did not

| Before | Now |
|---|---|
| Chat in memory; closing the screen discarded it | Every message saved in `thread_messages` (migration `v17_message_thread`), read back before it counts as saved |
| A failed question went back into the box | If the question could not leave (Ask Doddy off, not set up, too long) it still goes back into the box and nothing is saved. If it left and got no answer, it stays in the thread: **"No answer yet. Tap to try again."**, which sends it again as a new message at the end |
| Earlier turns for the model: whatever was on screen (the service keeps the last six) | Only answered messages from the last 12 hours (`ThreadRules.history`); a message nobody answered is never sent as context; yesterday's chat is not sent today |
| Sources shown from the answer in memory | The answer keeps the ids of the notes it cited; they are looked up again from your notes when you reopen it. A note you deleted since is not shown, and the answer says "Some of these notes have since been deleted." |
| Nothing said about storage | The disclosure under the thread says the conversation is saved on this iPhone until you delete it; if saving or reading fails, the thread says what you write is gone when you close the screen |
| Title "Ask Doddy" | Title "Doddy"; the Settings switch is still "Turn on Ask Doddy" and the consent text is untouched (see Owner decisions) |

Kept as they were: the Ask Doddy switch and consent, the invite code and gateway address, "Use relevant saved notes", private notes never sent (ADR-310), every `ask.*` and `home.ask` accessibility id the UI tests use, the "Turn on Ask Doddy in Settings first" wording, Doddy's motion hooks (`askOpened`, `askSending`, `askClosing`).

## What the delivery line may claim

`ThreadRules.deliveryLine` is the only source. A message you sent says **Sending…** while it is on its way, nothing once it has an answer, and **No answer yet. Tap to try again.** if it got none. There is no "Delivered" and no "Read": nothing here can know either, so nothing says it. A message still "sending" when the app was closed is marked "no answer yet" the next time the thread opens (`failUnfinished`).

## Files

- DoddyCore (all platforms; Watch and Mac are paused and do not use these): `Messages/ThreadMessage.swift` (message, repository port, unavailable repository), `Messages/ThreadRules.swift` (history, headings, send and retry rules, delivery line).
- DoddyPersistence: `SQLiteMessageThreadRepository.swift`; `DoddyDatabase` migration `v17_message_thread` (v16 is Capture's, ADR-579, on `claude/gifted-pascal-3e117c`; if both merge, v16 is registered first). The table refuses a Doddy message that is not "sent", a user message with a basis, and a Doddy message without one.
- App: `Features/Messages/MessagesModel.swift` (state, no SwiftUI, type-checked and tested on Linux), `Features/Messages/MessagesView.swift`; `AppEnvironment.messageThreadRepository`; Settings → Delete all also empties the thread; Home's button and cover. `Features/Ask/AskView.swift` and `AskController.swift` are gone.
- Tests: `ThreadRulesTests`, `SQLiteMessageThreadRepositoryTests`, `DoddyTests/MessagesModelTests.swift` (also run on Linux by `scripts/test_messages_model.sh`, which `scripts/ci.sh` calls).
- Strings: 11 new UI strings and 2 removed in `l10n/*.json`; nine languages. The new text is a machine-written draft like the other tables (ADR-234); the disclosure and the delete texts go to a native reader first.

## Checks run (Linux, Swift 6.1.2, 22 Oct 2026)

| Check | Result |
|---|---|
| `swift test` for DoddyCore | 1,388 tests, 0 failures (17 of them new: 8 rules, 9 store) |
| Raw-file check: a message's words are in the database file before `deleteAll` (control) and not after | passes (`testDeletedWordsAreNotLeftInTheDatabaseFile`) |
| `scripts/test_messages_model.sh`: `MessagesModel` with a fake store and a scripted client | 9 tests, 0 failures |
| `scripts/typecheck_app_logic.sh` | PASS, 25 files including `MessagesModel.swift` (Swift 6) |
| `tools/build_strings_catalog.py --check` | PASS |

**Not run.** `MessagesView.swift`, the Home change, `AppEnvironment` and the Settings change have not been compiled: there is no Xcode here, so the hosted Mac build is the first compile. Nothing has been seen on a simulator or a device. The UI tests that open Ask (`LaunchSmokeTests`, `MotionRideTests`, `MotionSurfaceTests`) have not been run against the new screen; they use the unchanged ids. **An answer has never been produced end to end**: the gateway (`gateway/`) is not deployed and has no environment variables (STATUS.md), so on a phone the thread shows "The assistant is unavailable right now" or "isn't set up" until the gateway is deployed or the replies move to the messaging server (Studio S0).

## Constitution evidence log

| Rule | Enforced by | Tests run | Gap / claim to limit |
|---|---|---|---|
| DOD-06 user-controlled memory; `memory_policy` | The thread is a conversation, not a memory: nothing in it becomes a saved note, an answer's notes are read from the user's own, nothing is added to Memory on calls | `ThreadRulesTests` (history), `MessagesModelTests` | A saved conversation is new stored data about the user; the Settings privacy text and "What leaves this iPhone" rows do not name it yet |
| DOD-08 verified status | `append`, `setDelivery`, `delete`, `deleteAll`, `failUnfinished` read back and throw otherwise; the delivery line is a function of stored state | `SQLiteMessageThreadRepositoryTests` (9), `testDeletingEmptiesTheScreenOnlyAfterTheStoreReadBackEmpty` | If the store is down the screen says so and keeps the conversation in memory only |
| DOD-02 honesty over agreeableness | Source label from `VerifiedAnswer.basis` ("From your saved notes" or "Not from your notes"); no "read"/"delivered" | Rules tests | No answer has been produced by a real model |
| DOD-09 correction and recovery | A message nobody answered stays and can be sent again; Stop leaves it as "No answer yet" without an error card; killed mid-send is swept on the next open | `testAMessageWithNoAnswerStaysInTheThreadAndCanBeSentAgainAtTheEnd`, `testStoppingLeavesTheMessage…`, `testAMessageLeftSendingWhenTheAppWasClosed…` | Kill during a real request not tried on a device |
| DOD-11 observable privacy; `privacy_policy` | Disclosure on the screen says what is sent and that the thread is saved here; consent unchanged and checked before anything is saved or sent | `testNothingIsSavedOrSentWhileAskDoddyIsOffOrNotSetUp` | The consent dialog and Settings text were not reworded (owner decision 3) |
| `memory_policy.deletion_claim_requires_storage_confirmation` | Delete is read back before the screen empties; `secure_delete` is on | Raw database file test | Same gap as Capture: notes, learned facts and procedures have no such test |
| ADR-310 Face ID app lock | The lock cover is an overlay on the root view and a full-screen cover sits above it, so `MessagesView` closes itself when `AppLock.shared.isLocked` turns true. Found while answering the owner's questions: without it, a Messages screen left open could show the saved history over the lock | Not tested: the view is not compiled and `AppLock` needs iOS | Check item 8 below. The Voice conversation screen and other covers were not looked at |
| ASK-01 | No tool, action or external write is added; a reply is text only | - | Studio's later steps (documents, sending) need cards |
| DOD-07 content is data | Reply text is shown as text; citation check unchanged (A-14) | Existing `CitationVerifier` tests | - |

## Owner decisions

1. **Phone first, or also a copy on a server?** Built: phone only, nothing on a server. A later "Keep on my page" per item (Studio) would be the only way anything leaves, and would ask each time.
2. **Should the typed thread and the voice conversation be one thread?** Built: separate. Merging means saving voice transcripts too (they are kept in `ConversationLogStore` today under their own setting).
3. **Consent wording.** The "Turn on Ask Doddy?" dialog and the long privacy text do not say the typed conversation is now saved on this iPhone. I did not reword a consent text on my own. Suggested addition: "The conversation is saved on this iPhone until you delete it."
4. **The button said "Type" and now says "Messages".** Longer than before, and in Polish "Wiadomości" next to "Wspomnienia" does not fit a 393 pt screen with icons. Home's bottom bar therefore falls back to the Messages icon alone (still named "Messages" for VoiceOver) when the words do not fit (`ViewThatFits`). Not compiled or seen; if you would rather have a shorter word, say which.
5. **Retention.** Nothing expires. The screen loads the newest 200 messages; older ones stay saved. Say if it should expire after N days.

## Device checks (for when it is built)

1. Turn on Ask Doddy, send a question. It shows "Sending…", then Doddy's answer; close and reopen: both are there.
2. Airplane mode, send: "No answer yet. Tap to try again." Turn it off, tap it: a new message at the end gets an answer, the old one is gone.
3. Send, then kill the app mid-request. Reopen: the message says "No answer yet".
4. Ask about something you saved: the answer shows its notes; delete one of those notes, reopen: the answer says some notes were deleted.
5. ••• → Delete conversation → confirm. The thread is empty; Settings → Delete all also empties it.
6. Home in Polish and in English, default and largest text: the bottom bar shows "Messages" and "Memories" with icons when they fit, the Messages icon alone when they do not, and the + button is always on screen.
7. Turn Ask Doddy off: the box keeps what you type and nothing is saved.
8. Turn the Face ID lock on (Settings). Open Messages, leave Doddy for longer than the lock's delay, come back: the lock shows and Messages is closed, not readable above it.

## Next

Studio S0 (the same thread, replies from the messaging server's Claude with web search, ASK-01 cards for anything that makes a file or sends something), then the "Home voice stays on screen" milestone (V1) so a conversation can run while this thread is open.
