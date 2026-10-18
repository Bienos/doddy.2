# Calls Doddy makes for you: status

Last updated 2026-10-18. Branch `claude/modest-pasteur-7jnwfd`. Decisions: ADR-500 to 507. Architecture, the docs checked and the open legal questions: `docs/decisions/calls.md`.

**State: built and tested with fakes. No real call has been placed, and the iPhone screens have never been compiled.** Nothing below may be called working until the live tests at the end pass.

## What it does
1. The user writes a brief in the app: who (name, number, where the number came from), the goal in one sentence, the one question, facts Doddy may say (only ticked ones leave the iPhone), and the longest the call may last (4 min by default).
2. The server compiles the brief into the exact payload it will send and returns a card made from it: who, goal, the opening line word for word, what Doddy may say, what it must not do, the callback line, the length and the recording notice.
3. The user approves that card. Only then does the server dial, from a Twilio number, with ElevenLabs as Doddy's voice.
4. Doddy opens with "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu <imię>." and the question. It listens, may ask one clarifying question, thanks and ends. For anything outside the card it says "Sprawdzę to u <imię> i oddzwonię." It has no tools that could book, pay or send anything.
5. During the call the app shows the live transcript, a big **Przejmij** (rings the user's phone; pressing 1 joins the call) and **Zakończ**. The Lock Screen shows the phase and the time only.
6. After the call: an answer card with the reply quoted from the transcript, a confidence flag with reasons, warnings about anything Doddy said that needs a look, the transcript, a next step, the cost, and receipts for what the servers deleted. The transcript is saved on the iPhone first; then the server deletes its copies.
7. Failed calls (no answer, busy, voicemail, phone menu, wrong number, technical failure) get an honest card and "Zadzwoń ponownie o …" with times that fit the calling hours.
8. Rehearsal: the user practises with Doddy playing the receptionist, then picks "Doddy dzwoni" or "Dzwonię sam" (the script on screen and the number to dial).

## Code
| Part | Where |
|---|---|
| Server: schema | `server/messaging/migrations/008_call_cases.sql` |
| Server: brief, payload, limits, hours, numbers, opening line | `server/messaging/src/taskCalls/{brief,payload,phone,hours,opening}.ts`, `src/config.ts` |
| Server: dial, webhooks, takeover, answer card, worker | `src/taskCalls/{service,webhooks,takeover,result,cases,worker,writer}.ts`, `src/routes/{callCases,taskCallWebhooks}.ts` |
| Server: providers | `src/providers/taskCalls.ts` (Twilio calls, ElevenLabs register-call and conversations), `src/providers/apns.ts` (Live Activity pushes) |
| Voice agent spec | `voice-agent/task-call/`, `server/messaging/scripts/setup-task-call-agent.mjs`, checked by `scripts/voice_agent_spec.py --agent task-call` |
| Terminal harness | `server/messaging/scripts/task-call.mjs` |
| Rules and client (Linux-tested) | `Packages/DoddyCore/Sources/DoddyCore/{CallCase,CallCasesClient,CallRehearsal}.swift` |
| On-iPhone store | `Packages/DoddyCore/Sources/DoddyPersistence/SQLiteCallCaseRepository.swift`, migration `v14_call_cases` |
| App screens | `DoddyApp/Features/CallCases/`, `DoddyApp/Features/Voice/CallRehearsalSession.swift`, `DoddyApp/Infrastructure/Connections/ContactNumberPicker.swift`, Settings → Phone calls → Calls for you |
| Live Activity | `Shared/CallActivity/`, `DoddyWidgets/DoddyCallLiveActivity.swift`, `DoddyApp/Features/CallCases/CallLiveActivity.swift` |

## Verified here (Linux, 2026-10-18)
- Server: `npm run typecheck` and `npm test` against a throwaway Postgres 16: **115 tests pass** (call cases: payload binding, every limit, kill switch, agent drift, webhooks and their signatures, takeover, answer card, costs, deletion receipts, retry after voicemail; plus config).
- `python3 -I scripts/voice_agent_spec.py check --agent task-call` passes; `node scripts/setup-task-call-agent.mjs --dry-run` builds a request that validates against ElevenLabs' published OpenAPI schema.
- DoddyCore: `swift test` (Swift 6.2.3): 1,115 tests, **2 failures that predate this work** (`OpenAIRealtimeTests.testOpenAIGrantParsing`, `VoiceTokenTests.testWakeWordKeyFromTheTokenServer`). The call-case tests all pass.
- App: `scripts/typecheck_app_logic.sh` type-checks `CallCasesModel.swift` in Swift 6; `scripts/test_call_cases_model.sh` runs its 7 tests (answer saved before the server deletes it, an unconfirmed approval never resent, retry times, withdrawal). A deliberate swap of save and delete made 2 of them fail.
- `tools/build_strings_catalog.py --check` passes (Polish for every new string).

## Not verified
- **No real call.** Nothing has been dialled, heard or transcribed for real; Twilio's and ElevenLabs' real callbacks have only been imitated by fakes.
- **The iPhone screens, Live Activity, widget, intents, contact picker and rehearsal have never been compiled** (no Xcode here). Expect compile fixes on the first Mac build.
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
