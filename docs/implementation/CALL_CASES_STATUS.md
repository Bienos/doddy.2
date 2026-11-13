# Calls Doddy makes for you: status

Last updated 2026-10-18. Branch `claude/modest-pasteur-7jnwfd`. Decisions: ADR-500 to 507. Architecture, the docs checked and the open legal questions: `docs/decisions/calls.md`.

**State: built and tested with fakes. No real call has been placed. The iPhone screens compile (hosted CI, Xcode 26.6) but have never been run on a device or seen on screen.** Nothing below may be called working until the live tests at the end pass.

> **5 Nov 2026 (ADR-730):** the transcript is the owner's log. Only the account that verified a number in `CALL_TRANSCRIPT_PHONE_NUMBERS` gets the live words and the saved transcript; every other account gets the answer card without it. Where this page says the transcript is kept on the iPhone, that holds for those accounts only. The recap in Files › Calls has no transcript for anyone.

## What it does
1. The user writes a brief in the app: who (name, number, where the number came from), the goal in one sentence, the one question, facts Doddy may say (only ticked ones leave the iPhone), and the longest the call may last (4 min by default).
2. The server compiles the brief into the exact payload it will send and returns a card made from it: who, goal, the opening line word for word, what Doddy may say, what it must not do, the callback line, the length and the recording notice.
3. The user approves that card. Only then does the server dial, from a Twilio number, with ElevenLabs as Doddy's voice.
4. Doddy opens with "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu <imię>." and the question. It listens, may ask one clarifying question, thanks and ends. For anything outside the card it says "Sprawdzę to u <imię> i oddzwonię." It has no tools that could book, pay or send anything.
5. During the call the app shows the live transcript, a big **Przejmij** (rings the user's phone; pressing 1 joins the call) and **Zakończ**. The Lock Screen shows the phase and the time only.
6. After the call: an answer card with the reply quoted from the transcript, a confidence flag with reasons, warnings about anything Doddy said that needs a look, the transcript, a next step, the cost, and receipts for what the servers deleted. The transcript is saved on the iPhone first; then the server deletes its copies.
7. Failed calls (no answer, busy, voicemail, phone menu, wrong number, technical failure) get an honest card and "Zadzwoń ponownie o …" with times that fit the calling hours.
8. ~~Rehearsal~~ (removed 9 Nov 2026 with OpenAI voice; it ran only on OpenAI Realtime). "Dzwonię sam" stays: the script on screen and the number to dial, from the card.

## Code
| Part | Where |
|---|---|
| Server: schema | `server/messaging/migrations/008_call_cases.sql` |
| Server: brief, payload, limits, hours, numbers, opening line | `server/messaging/src/taskCalls/{brief,payload,phone,hours,opening}.ts`, `src/config.ts` |
| Server: dial, webhooks, takeover, answer card, worker | `src/taskCalls/{service,webhooks,takeover,result,cases,worker,writer}.ts`, `src/routes/{callCases,taskCallWebhooks}.ts` |
| Server: providers | `src/providers/taskCalls.ts` (Twilio calls, ElevenLabs register-call and conversations), `src/providers/apns.ts` (Live Activity pushes) |
| Voice agent spec | `voice-agent/task-call/`, `server/messaging/scripts/setup-task-call-agent.mjs`, checked by `scripts/voice_agent_spec.py --agent task-call` |
| Terminal harness | `server/messaging/scripts/task-call.mjs` |
| Rules and client (Linux-tested) | `Packages/DoddyCore/Sources/DoddyCore/{CallCase,CallCasesClient,CallRehearsal}.swift` (`CallRehearsal.swift` now holds only `SelfCallScript`) |
| On-iPhone store | `Packages/DoddyCore/Sources/DoddyPersistence/SQLiteCallCaseRepository.swift`, migration `v14_call_cases` |
| App screens | `DoddyApp/Features/CallCases/`, `DoddyApp/Infrastructure/Connections/ContactNumberPicker.swift`, Settings → Phone calls → Calls for you |
| Live Activity | `Shared/CallActivity/`, `DoddyWidgets/DoddyCallLiveActivity.swift`, `DoddyApp/Features/CallCases/CallLiveActivity.swift` |
| "Who and why" (13 Nov 2026) | Server `src/taskCalls/{draft,drafter}.ts`, `POST /v1/call-cases/draft` in `src/routes/callCases.ts`; DoddyCore `CallBriefSuggestion.swift`; app `DoddyApp/Features/CallCases/CallBriefStartView.swift` |

## "Who and why": a new call from one field (13 Nov 2026)
Decision `docs/decisions/2026-11-13-calls-one-field-brief.md`. **Server tested with a fake model against Postgres; the app screens are not compiled (no Xcode here) and not run; no real model call has been made.**
- New call opens one field, "Who and why", with the contact pick as an option and "Fill in every field myself" for the full editor.
- `POST /v1/call-cases/draft {text, contactName?}` (strict; device token; task calls configured and not switched off; a verified phone; 20 per device per hour). Code reads the one number from the words (`readNumbers`, the call allowlist, not the user's or Doddy's own number) and replaces every number with `[numer]`; words holding a PESEL, card or account number are refused (400 `brief_refused`, field `text`) before any model call. Claude (`ClaudeBriefDrafter`, `claude-opus-5-5`, low effort, closed schema without a number field) proposes the name, goal, question and facts; `checkDraft` drops any field that fails (words the user didn't write, a number or hour the user didn't write, a question that commits or isn't a question, braces, PESEL, card, account, an address outside a fact, length) and lists what is missing. Nothing is stored; logs carry codes and counts only. Answers: 200 the draft, 409 `no_verified_phone`, 502 `draft_failed`, 503 `not_configured` / `calls_disabled` / `drafter_not_configured`.
- The app fills the editor from it (`CallBriefDraft.drafted`): the picked contact's number wins; the server's number only if its digits are in the words; facts only if the user wrote them, a PESEL or address unticked. Details (on whose behalf, where the number came from, facts, must-not, length) start folded and open when one needs fixing. Any failure opens the editor with the user's own words (`CallBriefDraft.ownWords`). The card and its approval are unchanged.
- Tests: `server/messaging/test/callBriefDraft.test.ts` (25), `Packages/DoddyCore/Tests/DoddyCoreTests/CallBriefSuggestionTests.swift` (8).

## Call tasks: up to three places, one tap (9 Nov 2026)
Decision `docs/decisions/2026-11-09-restaurant-calls-one-tap.md`, step 2. **Server only, tested with fakes; no app screen uses it yet, and no real call has been placed.**
- `POST /v1/call-tasks` takes up to 3 places (name, number, source, including the new source `places` for a number from Doddy's place search) and one shared question, principal, goal and facts. Each place is checked and compiled exactly like a single case (`compileCase`); the same number twice is refused. The answer is one card: every place's preview and the task digest, which covers the case digests in order and the "text me the result" choice.
- `POST /v1/call-tasks/:id/approve {digest}` calls the first place now. After each place's result the worker calls the next one (`advanceTask`, in the transaction that stores the result), within 3 hours of the tap and inside calling hours, with every dial gate run again.
- The task stops at the first clear yes (the result step's `answer: yes` and a quote cut from the transcript, with no warnings), or as **unclear** when the answer isn't a clear yes or no, so Doddy never guesses and moves on. A place that doesn't pick up, is busy, a voicemail or a phone menu is skipped. Taking a call over, cancelling, the end of calling hours or the kill switch stops the task.
- At the end: one content-free push (the same kind as a single call's, so the app opens the recap) and, if the card said so and the person has consented to texts, one text to their own number with the place's name and the quoted answer. The briefs of places never called are deleted, with receipts.
- A place of a task can't be approved on its own (`part_of_task`); cancelling one place cancels the task.
- Tests: `server/messaging/test/callTasks.test.ts` (9).
- **The app's side (step 4, 9 Nov 2026):** the voice tool `call_places` (up to three places and their numbers from `find_places`, one question, a goal, `text_result`) asks Doddy's server for the task's card (`createCallTask`) and shows it in the conversation: every place, its number, "Numbers from Doddy's place search", the exact opening line, what Doddy won't do, and how the answer comes back. "Call them" approves the task's digest (`approveCallTask`); "Don't call" cancels it on the server. The tool's reply is only "started", never an answer; the answers reach the user through the existing Calls for you sync. DoddyCore's `CallNumberSource` has `places`. **Not compiled here** (no Xcode): `VoiceSessionController.swift`, `VoiceView.swift`, `CallCaseView.swift`; DoddyCore's rules are tested on Linux (`CallTaskTests`). Not on the live ElevenLabs agent (`not_synced`); the OpenAI voice takes it from the app.

## Verified here (Linux, 2026-10-18)
- Server: `npm run typecheck` and `npm test` against a throwaway Postgres 16: **115 tests pass** (call cases: payload binding, every limit, kill switch, agent drift, webhooks and their signatures, takeover, answer card, costs, deletion receipts, retry after voicemail; plus config).
- `python3 -I scripts/voice_agent_spec.py check --agent task-call` passes; `node scripts/setup-task-call-agent.mjs --dry-run` builds a request that validates against ElevenLabs' published OpenAPI schema.
- DoddyCore: `swift test` (Swift 6.2.3 here, 6.1.3 in hosted CI): 1,133 tests, 0 failures, once PR #84's fix for two token-server test expectations (from 754e5d6) is carried here. The call-case tests all pass.
- App: `scripts/typecheck_app_logic.sh` type-checks `CallCasesModel.swift` in Swift 6; `scripts/test_call_cases_model.sh` runs its 8 tests (answer saved before the server deletes it, an unconfirmed approval never resent, retry times, withdrawal, a case the server no longer has). A deliberate swap of save and delete made 2 of them fail.
- `tools/build_strings_catalog.py --check` passes (Polish for every new string).

## Not verified
- **No real call.** Nothing has been dialled, heard or transcribed for real; Twilio's and ElevenLabs' real callbacks have only been imitated by fakes.
- **The iPhone screens, Live Activity, widget, intents, contact picker have never been run.** They compile on hosted CI (Xcode 26.6, PR #90), where `CallCasesModelTests` (8) passed on the iOS simulator and the existing 29 UI tests still pass; no UI test covers the call screens.
- APNs Live Activity pushes, Twilio Real-Time Transcription in Polish (track labels, latency, quality), the takeover conference, the voicemail tool on Polish voicemail greetings, ElevenLabs' post-call webhook arriving and its deletion.
- How long callees wait in silence after "Halo" before Doddy speaks.
- The Polish wording has not been read by a native speaker in context; the recording notice wording has not been reviewed legally.

## Live tests (owner)
Before them: the owner actions in `docs/decisions/calls.md` (a Poland-only Twilio subaccount, the env, the agent with a Polish voice, the post-call webhook).

**Live test #1, from a terminal (no app):**
1. `export DODDY_SERVER=https://<doddy-messaging host>`; `node scripts/task-call.mjs init --phone "<your main phone>"` and type the SMS code.
2. `node scripts/task-call.mjs status`: `available: true`, no agent problems.
3. `node scripts/task-call.mjs brief --to "<your second phone>" --callee "Drugi telefon" --me <imię> --me-gen <dopełniacz> --goal "Sprawdzić, czy laptop jest gotowy." --question "Czy laptop z serwisu jest gotowy?"`
4. `node scripts/task-call.mjs approve`: read the card, type TAK.
5. Answer the second phone. Check: the opening line is exactly as on the card and says it's an AI; the question is asked once; give a short answer; Doddy thanks and ends.
6. `node scripts/task-call.mjs live`, then `card`: the quote must be your reply word for word; the cost has items for the line, the transcript and the voice; `ack` then shows the deletion receipts.
7. Note: seconds of silence after "Halo", whether the live transcript labels the speakers right, and what the call cost.

**Live test #2, take over and end:** start another call; in a second terminal run `takeover`, answer your main phone, press 1: you should be talking to the second phone, with Doddy gone. Another call: `end` while Doddy talks: it says goodbye and hangs up. Try a question the second phone answers with "Proszę podać PESEL": Doddy must say it will check and call back.

**Live test #3, the app on a device:** Settings → Phone calls → Calls for you → New call, the same brief; approve the card; watch the transcript; press Przejmij once; check the Lock Screen shows only the phase and time; check the answer card, cost and receipts; delete the case. Then rehearse once and open "Dzwonię sam".

**Done when** (owner's list): a brief is approved, Doddy calls the second phone in Polish, discloses it's an AI, asks one question, and the answer card quotes the reply correctly; take over works mid-call; a call outside the card's permissions is impossible by construction (tested on the server: only the approved payload can be sent, and the agent has no tools); every call has a cost on its case.

## Decisions waiting on the owner
The nine open questions in `docs/decisions/calls.md` (legal basis for transcribing the callee and the notice wording, AI Act disclosure, processors, a do-not-call list, call-backs reaching the English S2 agent, Sundays and holidays, Twilio's call log), plus: the Polish voice, the price values for the estimated cost items, and whether "Dzwonię sam" should have a gender-neutral label.
