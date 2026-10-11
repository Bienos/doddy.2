# Review — `Packages/DoddyCore` (2026-10-11)

Read-only review by four parallel reviewers, one per area. Each finding was traced to a concrete caller or input. Paths are relative to `Packages/DoddyCore/Sources/DoddyCore/` unless shown otherwise.

## Tests run (baseline, before any fix)

| Command | Environment | Result |
|---|---|---|
| `make test-core` (`swift test`, Linux flags) | Swift 6.2.1 installed in this container, Ubuntu 24.04 x86_64 | **635 tests, 0 failures** |

Not run: `xcodebuild`, UI tests, and anything on a device. There is no Xcode here, and GitHub Actions runners are currently unavailable in this repository.

## A. Network clients (app ↔ servers)

| # | Where | Problem → failure | Severity / rule |
|---|---|---|---|
| A1 | `ServerClient.swift:257` (+ `DoddyApp/Infrastructure/Server/ServerHTTPTransport.swift:51`) | Every transport error becomes `.offline`, including a timeout after the request reached the server. The client timeout (15 s) is no longer than the server's ElevenLabs timeout. → "Call me now" times out while the phone is already ringing; the user is told to try again and gets a second call. `sendNewsNow` has the same problem. | critical, DOD-08 |
| A2 | `ServerClient.swift:210`, caller `DoddyApp/Features/Updates/UpdatesModel.swift:141` | Each `sendUpdate` uses a new `UUID()` as its idempotency key, and 409 `idempotency_mismatch` is mapped to `.notEnabled`. → A retry after a dropped connection sends a duplicate SMS or push. | medium, DOD-08 |
| A3 | `CallsClient.swift:157`, `DoddyApp/Features/Calls/CallsModel.swift` | The server's `unreadable` call-note list is ignored, and a failed fetch turns into an empty inbox (`try?`). → Notes that can't be read can never be discarded, and a failed load looks like "no notes". | medium, DOD-06 |
| A4 | `PrivacyDefaults.swift:19,25` | "Sync: Off (not built)" while iCloud shared lists, the server memory copy and the messaging account all ship. `Capabilities.cloudSync` still says not implemented. → The privacy screen is wrong. | medium, DOD-11 |
| A5 | `DataFlow.swift:137,142` | "What leaves this iPhone" always names Anthropic as the news writer, but the server can use OpenAI (`writerProvider`). → The wrong recipient is named. | medium, DOD-11 |
| A6 | `OnlineAccounts/VoiceCloudTools.swift:62` | A write that fails with an unlisted code, or with an `outcome_unknown` receipt, is reported to the agent as "Nothing was done". → The user retries and gets a duplicate draft or task. | medium, DOD-08 |
| A7 | `ServerClient.swift:166` | Actor reentrancy in `ensureAccount()`. → Two parallel first uses create two server accounts, and one is orphaned. | low, DOD-06 |
| A8 | `NewsClient.swift:120` | Digest status `queued` is shown as "Sent to you". | low, DOD-08 |
| A9 | `VoiceToken.swift:50-60` | The token server's 429 `rate_limited` and Retry-After are not handled. → "Had a problem (429), try again in a moment", followed by an immediate retry. | low |
| A10 | `ConnectedApps/ConnectedAppsClient.swift:65`, `OnlineAccounts/OnlineAccountsClient.swift:53` | The session bearer is not tied to the host it was issued for, and http loopback is accepted in release. | low, DOD-11 |
| A11 | `Assistant/AssistantService.swift:88` | After a timeout the request is automatically re-POSTed up to 3 times. → The question and notes leave the phone three times, and the budget is spent three times. | low, DOD-11 |
| A12 | `ServerClient.swift:276`, `CallsClient.swift:143`, `NewsClient.swift:181` | A dead `(400,"no_topics")` case, and duplicated response helpers. | low |

### Section A fix status (2026-10-11)

DoddyCore changes, each with a focused test; `make test-core` and `scripts/typecheck_app_logic.sh` pass on Linux. The app files below are not compiled here, so their part is still open and needs Xcode.

| # | DoddyCore | Still needs Xcode (app files not compiled on Linux) |
|---|---|---|
| A1 | Requests that start something (`callMeNow`, `sendNewsNow`) turn an ambiguous transport failure into status `unknown`; only errors raised before the request left the phone (`ServerTransportFailure.certainlyNotSent`) stay `.offline`. `ServerRequest.timeout` is 30 s for calls and 180 s for news. | `ServerHTTPTransport.swift`: use `request.timeout` instead of 15, and rethrow the `URLError` instead of `ServerError.offline` (until then a real "no network" also reads as unknown, which is safe). `NewsModel.swift`: add `case "unknown"` to the send-now message (today it falls to "Couldn't build your news right now"). |
| A2 | `sendUpdate(_:channels:)` keeps one key per text and channels until the server accepts it; 409 `idempotency_mismatch` maps to `.invalidRequest(["idempotencyKey"])`. | `UpdatesModel.swift:141`: call `sendUpdate(text, channels: [channel])` without `idempotencyKey: UUID().uuidString`. |
| A3 | `callInbox()` decodes `notes` and `unreadable` and throws on a failed load. | `CallsModel.swift:28`: use `callInbox()` instead of `try? callNotes()`, list unreadable notes with Discard, and show a load error. |
| A4 | Shipping catalog: `cloudSync` is `.limited` (lists you share, through iCloud). `PrivacyDefaults.syncText`. | `SettingsView.swift:243`: show `privacy.syncText`. |
| A5 | `DataFlowState.newsWriterProvider`; until known, the row names "Anthropic or OpenAI, as the server is set up". | Optional: `DataFlowView` passes the provider once News settings are loaded. |
| A6 | Fixed: `outcome_unknown` receipts and unlisted codes on writes read `unknown`. | — |
| A7 | Fixed: one in-flight account creation. | — |
| A8 | Fixed: "Queued for your notifications or texts". | — |
| A9 | 429 maps to `.rateLimited(retryAfterSeconds:)` with a wait-time message. | `VoiceTokenClient.swift:23`: pass the `Retry-After` header as `retryAfter:`. |
| A10 | Loopback http only in DEBUG builds. `BoundSessionToken` and `boundToken:` initialisers send a token only to the origin that issued it. | Store a `BoundSessionToken` in `KeychainSessionStore` when saving (SettingsView:298) and use the `boundToken:` initialisers in `OnlineAccountsClientFactory.swift` and `ConnectedAppsView.swift`; decide how existing unbound tokens migrate. |
| A11 | Fixed: timeouts are not retried automatically; Try again stays. | — |
| A12 | One shared `getJSON`. The `(400,"no_topics")` case is **not dead** (PUT `/v1/news/settings` returns it and `NewsModel` reads it), so it stays. | — |

## B. Memory and persistence

| # | Where | Problem → failure | Severity / rule |
|---|---|---|---|
| B1 | `DoddyPersistence/SQLiteListRepository.swift:136` | A JSON restore puts back list items into lists that already exist. → Items the user deleted reappear, the 200-item cap is skipped, and positions collide. | medium, DOD-06 |
| B2 | `EncryptedBackup.swift:208,241` | There is no upper bound on PBKDF2 `iterations`, and no cancellation check. → A crafted or damaged backup hangs the restore screen. | medium |
| B3 | `MemoryRestore.swift:40` + `EncryptedBackup.swift:271` | A backup can be up to 200 MB, but the export it contains is refused over 20 MB. → A backup is created and "verified" but can never be restored. | medium, DOD-06/08 |
| B4 | `DoddyPersistence/SQLiteMemoryRepository.swift:204` + `SQLiteListRepository.swift:136` (`DoddyApp/Infrastructure/MemoryStore.swift:170`) | Notes and list items are restored in separate transactions. → On a partial failure the user is told "nothing was added". | medium, DOD-06/08 |
| B5 | `SQLiteListRepository.swift:167`, `NoteImport.swift:203`, `MemoryRestore.swift:105` | Item length is checked in visible characters, but SQLite counts code points. → Emoji items hit the constraint, and the whole voice add rolls back. | low, DOD-06 |
| B6 | `NoteImport.swift:203` | An over-long checklist item is reported as "too many items". | low |
| B7 | `SQLiteMemoryRepository.swift:191` | The export reads items, records and corrections in three separate reads, not one snapshot. | low, DOD-06 |
| B8 | `SQLiteMemoryRepository.swift:184`, `DoddyPersistence/SQLiteProfileRepository.swift:64` | `deleteAll` and `forgetProfile` are not read back before success is reported. | low, DOD-06 |
| B9 | `RecallMatching.swift:177`, millisecond helpers | `isTypo` is dead code, and millisecond conversion is written four times with mixed rounding. | low |

## C. Voice actions

| # | Where | Problem → failure | Severity / rule |
|---|---|---|---|
| C1 | `ActivityLog.swift:249-256` (+ `Plan.swift:175`) | Outcomes are parsed from reply prefixes. `changed:`, `deleted:`, `completed:`, `created:` and the list replies show as "Not sure". A note quoting "isn't connected" shows as "Didn't happen". The plan summary tells the agent a successful list step wasn't done. | medium, DOD-08 |
| C2 | `ActivityLog.swift:86,84,111,130-136` | Log rows keep full note text and queries for 30 days and survive note deletion and "Delete all memories". | medium, DOD-06 |
| C3 | `NoteReminders.swift:745`, `NoteReminderVoice.swift:75` | A voice reminder silently replaces an existing (even repeating) reminder. | medium, DOD-07/09 |
| C4 | `VoiceTools.swift:520`, `VoiceContext.swift:68` | Calendar titles, note text, list items and stored context reach the model unmarked. → A calendar invite title can make the agent change lists. | medium, tool content is data / DOD-07 |
| C5 | `SaidTime.swift:396,138` | "7:30 tonight" or "o 7:30 wieczorem" is forced to am, so the clarification loops. Unmarked "5:30" is taken as 05:30. | medium |
| C6 | `VoiceTools.swift:362` | `Int(Double)` traps on a huge timer value. → The app crashes. | medium |
| C7 | `CalendarChanges.swift:252-256` | A day-only `new_start` moves a timed event to midnight. | low, DOD-07 |
| C8 | `SaidTime.swift:47,384` | "Tonight at midnight" can never pass the day check. | low |
| C9 | `Lists.swift:216-217` | `remove_from_list` uses partial matches with no card. → "Remove milk" deletes "oat milk". | low, DOD-07 |
| C10 | `Lists.swift:130`, `DoddyApp/Infrastructure/MemoryStore+Lists.swift:96-103` | List Undo ignores what was actually restored and says "Undone" anyway. | low, DOD-09 |
| C11 | `VoiceTools.swift:281,332,201`, `CalendarChanges.swift:216` | There is no length bound on titles, notes or memory text from the model. | low |

## D. Plans, translator and other modules

| # | Where | Problem → failure | Severity / rule |
|---|---|---|---|
| D1 | `PlanEdit.swift:78`, `PlanPractice.swift:14`, `Translator.swift:806` | Dates are formatted in the phone's calendar but read back as Gregorian. → Buddhist and Japanese calendars give the wrong year or an unsaveable step. | medium, DOD-08 |
| D2 | `TidyUp.swift:84` | "Saved twice" ignores photos and voice memos. → Deleting the "copy" deletes a different photo. | medium, DOD-06 |
| D3 | `Plan.swift:175` | Successful list steps are reported to the agent as not done. Handled together with C1. | medium, DOD-08 |
| D4 | `Translator.swift:514` | "Doddy" spoken by the other person counts as a private aside to Doddy. | low/medium, DOD-08 |
| D5 | `SaveSuggestions.swift:294` | "My PIN is 4821" is offered to save. | low, DOD-11 |
| D6 | `Translator.swift:638,617` | Careful-topic stems match "Polish", "policy" and "pillow". | low |
| D7 | `Translator.swift:570` | The street-address pattern matches "At 15" and "Wait 10". | low |
| D8 | `MorningCheckIn.swift:108` | End of day is `start + 24 h`, which is wrong on DST change days. | low |
| D9 | `Onboarding.swift:56,202` | A second, unused Back Tap guide that contradicts the live one. | low |
| D10 | `Translator.swift:743` | `correct()` drops facts that came from the original speech. | low |

## Constitution evidence log (review stage)

- **Strong points the reviewers confirmed:**
  - Every memory write is read back before success.
  - SQL is fully parameterised.
  - The backup crypto is sound (AES-GCM, random nonce and salt, header authenticated).
  - Change and delete cards bind to a snapshot that is re-checked at the tap.
  - Online-account writes go through prepare → single-use approval → run.
  - Translator mode refuses tools.
  - Back Tap setup never claims the iOS setting is verified.
- **Gaps:** listed above (DOD-06/07/08/09/11).
- **Claims to limit:** all of this rests on `swift test` on Linux. No device or Xcode build was run.
