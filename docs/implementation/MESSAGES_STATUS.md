# Messages: the typed conversation with Doddy, inside the app (ADR-585)

Branch `claude/gifted-pascal-3e117c-messages`, off main at `8aa42c59`. No pull request yet. Owner, 22 Oct: "but i wnated to build imessage like section inside doddy", then "go for ti".

## What it is, in one paragraph

Ask Doddy (typed questions, ADR-115) is now a thread. Home's bottom-left button, which said **Type**, says **Messages** and opens it. Your messages and Doddy's answers are bubbles with a date heading after an hour of silence, saved **on this iPhone** until you delete them (the ••• menu → Delete conversation, or Settings → Delete all). It is not Apple's iMessage and not SMS. **Since 28 Oct 2026 a copy (without photos) is kept encrypted on Doddy's server for Doddy Web** (owner: sync always on; `MESSAGES_WEB_SYNC.md`). **Replies now come from Claude through Doddy's messaging server** (ADR-586, owner: "4. B"), not from the Ask gateway. Same consent, same Settings switch, off by default.

## Decisions the owner made (22 Oct)

| Question | Answer | What it means in the build |
|---|---|---|
| 1. Consent wording | "c" (read as: leave it as it is) | No sentence about the saved chat was added to the "Turn on Ask Doddy?" dialog or the Settings privacy text. **The provider named in them did change, from OpenAI to Anthropic, because the route changed** (B). The line under the thread itself still says it is saved on this iPhone. Gap: someone can agree without seeing that |
| 2. One thread or two | Separate | Voice conversations are not copied into Messages; only answered typed messages go to the model as context |
| 3. Expiry | "your pick" = keep until deleted | Nothing expires; the screen shows the newest 200 |
| 4. How Messages gets answers | **B** | `POST /v1/assistant/ask` on the messaging server asks Claude, text only. Needs the owner steps below before it answers anything |

## What changed and what did not

| Before | Now |
|---|---|
| Chat in memory; closing the screen discarded it | Every message saved in `thread_messages` (migration `v17_message_thread`), read back before it counts as saved |
| A failed question went back into the box | If the question could not leave (Ask Doddy off, not set up, too long) it still goes back into the box and nothing is saved. If it left and got no answer, it stays in the thread: **"No answer yet. Tap to try again."**, which sends it again as a new message at the end |
| Earlier turns for the model: whatever was on screen (the service keeps the last six) | Only answered messages from the last 12 hours (`ThreadRules.history`); a message nobody answered is never sent as context; yesterday's chat is not sent today |
| Sources shown from the answer in memory | The answer keeps the ids of the notes it cited; they are looked up again from your notes when you reopen it. A note you deleted since is not shown, and the answer says "Some of these notes have since been deleted." |
| Nothing said about storage | The disclosure under the thread says the conversation is saved on this iPhone until you delete it; if saving or reading fails, the thread says what you write is gone when you close the screen |
| Replies from the Ask gateway (OpenAI), set up with a gateway address and an invite code in Settings | Replies from Claude through the messaging server (`ServerAssistantClient`, `server/messaging/src/routes/assistant.ts`). **The gateway address and invite code fields are gone from Settings**; the anonymous Doddy account every server feature uses is the only credential |
| Title "Ask Doddy" | Title "Doddy"; the Settings switch is still "Turn on Ask Doddy" |

Kept as they were: the Ask Doddy switch and consent dialog (provider name aside), "Use relevant saved notes", private notes never sent (ADR-310), every `ask.*` and `home.ask` accessibility id the UI tests use, the "Turn on Ask Doddy in Settings first" wording, Doddy's motion hooks (`askOpened`, `askSending`, `askClosing`).

## What the delivery line may claim

`ThreadRules.deliveryLine` is the only source. A message you sent says **Sending…** while it is on its way, nothing once it has an answer, and **No answer yet. Tap to try again.** if it got none. There is no "Delivered" and no "Read": nothing here can know either, so nothing says it. A message still "sending" when the app was closed is marked "no answer yet" the next time the thread opens (`failUnfinished`).

## Files

- DoddyCore (all platforms; Watch and Mac are paused and do not use these): `Messages/ThreadMessage.swift` (message, repository port, unavailable repository), `Messages/ThreadRules.swift` (history, headings, send and retry rules, delivery line).
- DoddyPersistence: `SQLiteMessageThreadRepository.swift`; `DoddyDatabase` migration `v17_message_thread` (v16 is Capture's, ADR-579, on `claude/gifted-pascal-3e117c`; if both merge, v16 is registered first). The table refuses a Doddy message that is not "sent", a user message with a basis, and a Doddy message without one.
- App: `Features/Messages/MessagesModel.swift` (state, no SwiftUI, type-checked and tested on Linux), `Features/Messages/MessagesView.swift`; `AppEnvironment.messageThreadRepository`; Settings → Delete all also empties the thread; Home's button and cover. `Features/Ask/AskView.swift` and `AskController.swift` are gone.
- S0 (ADR-586): `DoddyCore/Assistant/ServerAssistantClient.swift`; server `src/routes/assistant.ts`, `src/assistant/{request,prompt,responder,usage,deps}.ts`, migration `010_assistant_usage.sql`; `AssistantWiring` in `AppEnvironment.swift`; settings `ASSISTANT_*` in `config.ts`, `render.yaml`, `.env.example`, `secrets/manifest.json`. The old `GatewayAssistantClient`, `KeychainCredentialStore` and `AppHTTPTransport` are no longer used by the app and can be deleted in a cleanup; the gateway folder is untouched.
- Tests: `ThreadRulesTests`, `SQLiteMessageThreadRepositoryTests`, `DoddyTests/MessagesModelTests.swift` (also run on Linux by `scripts/test_messages_model.sh`, which `scripts/ci.sh` calls).
- Strings: 11 new UI strings and 2 removed in `l10n/*.json`; nine languages. The new text is a machine-written draft like the other tables (ADR-234); the disclosure and the delete texts go to a native reader first.

## Checks run (Linux, Swift 6.1.2 and Node 22, 22 Oct 2026)

| Check | Result |
|---|---|
| `swift test` for DoddyCore | 1,399 tests, 0 failures (new: 8 rules, 9 store, 10 server client, 1 data-flow) |
| Raw-file check: a message's words are in the database file before `deleteAll` (control) and not after | passes |
| `scripts/test_messages_model.sh`: `MessagesModel` with a fake store and a scripted client | 9 tests, 0 failures |
| `scripts/typecheck_app_logic.sh` | PASS, 25 files including `MessagesModel.swift` (Swift 6) |
| `tools/build_strings_catalog.py --check`, the capability guard, `tools/secrets/sync.mjs check` | PASS |
| Messaging server, `npm test` against a **local Postgres 16** | 174 tests, 0 failures (21 new: the route with a fake responder, the real responder against a local stand-in for the API, the daily caps under concurrency, the shared wire fixtures, config) |

**Not run.** `MessagesView.swift`, the Home, Settings and `AppEnvironment` changes have not been compiled: there is no Xcode here, so the hosted Mac build is the first compile. Nothing has been seen on a simulator or a device. The UI tests that open Ask (`LaunchSmokeTests`, `MotionRideTests`, `MotionSurfaceTests`) have not been run against the new screen; they use the unchanged ids. **Claude has never answered a Messages question**: no Anthropic key is set anywhere I can reach, so the responder has only been run against a local stand-in that returns what the API's documentation says it returns. The hosted CI skips the server's database tests (no `TEST_DATABASE_URL`), so only my local run covered the caps, the migration and the route; the server's older database tests are skipped there too.

## To turn it on (only the owner can do these)

1. **Deploy the messaging server** (`render.yaml`, service `doddy-messaging`) on a plan that doesn't sleep. The free plan sleeps after about 15 minutes, and the free database is deleted on 10 Nov (STATUS.md). The server exists on Render's free plan (it sleeps and takes about 20 s to wake, longer than the app waits to create its account), so the first question after a quiet period often fails until it is on a paid instance.
2. **Set on `doddy-messaging`:** `ANTHROPIC_API_KEY` (a secret; the owner added it on 22 Oct, not seen by me) and `ASSISTANT_ENABLED=1` (not yet; changing it restarts the server). Optional: `ASSISTANT_MODEL` (default `claude-haiku-5-5`), `ASSISTANT_EFFORT`, `ASSISTANT_DAILY_PER_ACCOUNT` (default 100) and `ASSISTANT_DAILY_PER_SERVER` (default 1000). Also set a spend limit on the key in Anthropic's console: the caps here count requests, not money.
3. **Done (owner: "2 yes", 22 Oct): the app has the server's address**, `https://doddy-messaging-zw1n.onrender.com` (`ServerConfig.defaultBaseURL`). That switches every server feature on in a build, not only Messages. UI-test launches (`-inMemoryStore`) still have no server. Release builds ignore an address typed in Settings (ADR-175), on purpose.
4. Turn on Ask Doddy in Settings and ask something. Settings → Ask Doddy → Status then reads "Ready (not yet tested with a real server)". That wording is fixed text: it does not change when a real answer arrives, so the answer itself is the test.

## Constitution evidence log

| Rule | Enforced by | Tests run | Gap / claim to limit |
|---|---|---|---|
| DOD-06 user-controlled memory; `memory_policy` | The thread is a conversation, not a memory: nothing in it becomes a saved note, an answer's notes are read from the user's own, nothing is added to Memory on calls | `ThreadRulesTests` (history), `MessagesModelTests` | A saved conversation is new stored data about the user; the Settings privacy text and "What leaves this iPhone" rows do not name it yet |
| DOD-08 verified status | `append`, `setDelivery`, `delete`, `deleteAll`, `failUnfinished` read back and throw otherwise; the delivery line is a function of stored state | `SQLiteMessageThreadRepositoryTests` (9), `testDeletingEmptiesTheScreenOnlyAfterTheStoreReadBackEmpty` | If the store is down the screen says so and keeps the conversation in memory only |
| DOD-02 honesty over agreeableness | Source label from `VerifiedAnswer.basis` ("From your saved notes" or "Not from your notes"); no "read"/"delivered" | Rules tests | No answer has been produced by a real model |
| DOD-09 correction and recovery | A message nobody answered stays and can be sent again; Stop leaves it as "No answer yet" without an error card; killed mid-send is swept on the next open | `testAMessageWithNoAnswerStaysInTheThreadAndCanBeSentAgainAtTheEnd`, `testStoppingLeavesTheMessage…`, `testAMessageLeftSendingWhenTheAppWasClosed…` | Kill during a real request not tried on a device |
| DOD-11 observable privacy; `privacy_policy` | Disclosure on the screen says what is sent (to Anthropic, through Doddy's server) and that the thread is saved here; consent checked before anything is saved or sent; What leaves this iPhone and Settings' Cloud AI and Network rows name Anthropic and need a server to be active | `testNothingIsSavedOrSentWhileAskDoddyIsOffOrNotSetUp`, `testAskDoddyNamesAnthropicAndNeedsTheMessagingServer` | Owner chose "c": the consent dialog and Settings privacy text do not say the chat is saved on this iPhone. The provider name in them was changed to Anthropic. Anthropic's own retention is stated as unverified |
| `memory_policy.deletion_claim_requires_storage_confirmation` | Delete is read back before the screen empties; `secure_delete` is on | Raw database file test | Same gap as Capture: notes, learned facts and procedures have no such test |
| ADR-310 Face ID app lock | The lock cover is an overlay on the root view and a full-screen cover sits above it, so `MessagesView` closes itself when `AppLock.shared.isLocked` turns true. Found while answering the owner's questions: without it, a Messages screen left open could show the saved history over the lock | Not tested: the view is not compiled and `AppLock` needs iOS | Check item 8 below. The Voice conversation screen and other covers were not looked at |
| ASK-01 | No tool, action or external write is added. The server's model call has no tools: the request contains none (tested), so nothing it reads can search, send or change anything | `route` and `responder` tests: `tools` is absent from the API request | Studio's later steps (web research, documents, sending) need cards |
| `privacy_policy` data minimisation (server) | The route stores counts per account and day only (tested: no text-capable column); the log has model, counts and codes; note ids never reach the model (aliases); private notes are not sent (ADR-310) | `only counts are stored…`, `notes become short aliases…` | Anthropic receives the question, up to six earlier turns and the notes the app sends |
| DOD-07 content is data | Reply text is shown as text; citation check unchanged (A-14) | Existing `CitationVerifier` tests | - |

## Still open

1. **Consent gap (your "c").** If you later want the sentence "The conversation is saved on this iPhone until you delete it." in the dialog, it is one line plus nine translations.
2. **Retention by Anthropic.** The dialog says Anthropic keeps requests under its own rules and that we can't verify for how long. Check Anthropic's current terms for your account before relying on anything stronger.
3. **Home button width.** Longer than "Type", and in Polish "Wiadomości" next to "Wspomnienia" does not fit a 393 pt screen with icons, so the bar falls back to the Messages icon alone (still named "Messages" for VoiceOver) when the words do not fit (`ViewThatFits`). Not compiled or seen. If you would rather have a shorter word, say which.
4. **Model.** Haiku 5.5 is the default for speed and cost; it is a setting. Say if answers should come from a larger model.

## Device checks (for when it is built)

0. Do the owner steps above first. With no server address, Messages says "Ask Doddy isn't available yet" and offers no Try again or Settings button.
1. Turn on Ask Doddy, send a question. It shows "Sending…", then Doddy's answer; close and reopen: both are there.
2. Airplane mode, send: "No answer yet. Tap to try again." Turn it off, tap it: a new message at the end gets an answer, the old one is gone.
3. Send, then kill the app mid-request. Reopen: the message says "No answer yet".
4. Ask about something you saved: the answer shows its notes; delete one of those notes, reopen: the answer says some notes were deleted.
5. ••• → Delete conversation → confirm. The thread is empty; Settings → Delete all also empties it.
6. Home in Polish and in English, default and largest text: the bottom bar shows "Messages" and "Memories" with icons when they fit, the Messages icon alone when they do not, and the + button is always on screen.
7. Turn Ask Doddy off: the box keeps what you type and nothing is saved.
8. Turn the Face ID lock on (Settings). Open Messages, leave Doddy for longer than the lock's delay, come back: the lock shows and Messages is closed, not readable above it.

## Next

Studio S1: the same thread can ask Claude to research on the web (cards for each search, ASK-01), then S2 documents and presentations stored on Doddy's page, then the "Home voice stays on screen" milestone (V1) so a conversation can run while this thread is open.
