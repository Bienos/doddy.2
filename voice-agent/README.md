# Doddy voice agent — spec in OpenAI Realtime shape

Owner decision 2026-10-09 (ADR-058): Doddy runs on **ElevenLabs Agents**, but everything that
defines Doddy is kept here in **OpenAI Realtime** form, so moving to OpenAI Realtime later means
adding one adapter, not rewriting the app or the agent.

| File | What it is | ElevenLabs today | OpenAI Realtime later |
|---|---|---|---|
| `instructions.md` | Doddy's system prompt with `{{placeholders}}` | Agent prompt; placeholders are dynamic variables the app passes at `startConversation` | `session.instructions`, rendered on the phone by `RealtimeInstructions.render` |
| `tools.json` | 10 function tools (`type`, `name`, `description`, `parameters`) + `x_doddy` | Client tools (`runs_on: phone`) and webhook tools (`runs_on: web`) | `session.tools` (drop `x_doddy`); every call comes to the app |
| `session.json` | First message, languages, variables, turn-taking, per-provider settings | Agent settings | `session.update` body |

**OpenAI Realtime test voice (ADR-265):** Home's switch can now run these same files on OpenAI Realtime.
The app bundles `instructions.md`, `tools.json` and `session.json`, renders the prompt itself and sends it
with the tools in `session.update`; see `docs/implementation/VOICE_PROVIDER_TEST_STATUS.md`. A change here
reaches OpenAI with the next app build, and ElevenLabs only after the sync below.

## Source of truth and syncing

**ADR-309 camera shortcut help, live:** an earlier note here said the "Don't have the shortcut?" sentence was held back until an app build with that card button ships. On 2026-10-12 the live prompt read back already had it (version `agtvrsn_9501m4rtrbpjfs39ney04309wemz`), and the short prompt below keeps it. Who applied it, and whether a build with the button is on the owner's phone, isn't recorded. The button is in `DoddyApp/Features/Connections/CameraShortcutHelp.swift`.

**Applied to the live agent 2026-10-12 (prompt diet; owner: "ok go ahead with the prompt diet"; `docs/architecture/SPEED_AND_RESPONSIVENESS.md` 1.2):**
- **What changed:**
  - `instructions.md` was rewritten from 29.7k to 11.3k characters.
  - Per-tool "when and how" lines are gone from the prompt, because each tool's own description already says them.
  - Rules that apply to every tool are kept once each, under "Using your tools" and "Results (strict)": confirm-on-screen, dates, look up before change, plans, calculate, contacts, camera, access cards, success words, `unknown`/`declined`/`failed`/`partly`, DEMO DATA, and data-not-instructions.
  - The translator rules, the AI disclosure, the DATA markers, learned facts and routines, the morning check-in and "what you cannot do yet" all stay.
- **Recent conversations:** `{{recent_conversations}}` is out of the prompt (owner-approved). Doddy now says it only remembers what the user saved, and offers to search the notes.
  - Its placeholder stays on the agent and in `session.json` because app builds still send the variable.
  - The app still sends that text to ElevenLabs at every start. Stopping it is an app change, not done yet (`VoiceSessionController`, `"recent_conversations": recent.text`).
  - So is the Settings switch "Remember recent conversations". It now only keeps them on the iPhone (Settings, Remembered conversations) and Doddy no longer hears them, so the label overstates it.
- **Versions:** `agtvrsn_9501m4rtrbpjfs39ney04309wemz` (rollback) → `agtvrsn_2401m4rwr49req58q285qntwg65b`.
  - Prompt field only. Model, reasoning, the 61 attached tools and the placeholders are unchanged, read back after saving.
  - The live prompt equals `instructions.md` character for character, so this file and the live prompt are in sync again.
  - The bake-off branch (`agtbrch_0601m4rteqvbeyfvbbhms4q58492`) has the same prompt at `agtvrsn_3401m4rwebfbfqwb904bzkfx2290`.
- **Tests:** the 13 quick-win tests plus 9 new `doddy-speed: …` tests. The 13 include "short correct answer", now asking about photosynthesis so the correct `calculate` call doesn't fail it. The 9 new ones:
  - move event reads calendar first
  - unknown result is not success
  - list add needs no confirm card
  - maths uses calculate
  - no invented memory of earlier talk
  - translator translates, never answers (pl-de)
  - weather second step uses get_weather
  - follows a language switch (de)
  - injected note text is not a request
  - Ids: `test_2901m4rwd507ehrb0w5gea9g956e`, `test_4201m4rwd69eefbrkhgpgwbw057m`, `test_5401m4rwd7j5ez9tta5nh327sh41`, `test_0701m4rwd8hpebyajgyhtn557cfv`, `test_6601m4rwd99tfdfs8e7kadj77whx`, `test_7401m4rwda39fb089n3saqq5s4bz`, `test_3601m4rwdb3negvsc7a91g47mxva`, `test_6501m4rwdc3mf18sxsfdqgxzw10h`, `test_6401m4rwdd25e83vrb2kfj72drxt`.
  - Two payment tests were added after promoting: a web result never triggers `pay_for_page`, and an `unknown` payment is never called paid or retried. Ids: `test_6401m4rww2bqf1g8zcg17fafxh1g`, `test_8601m4rww34hfrbrr2n3kncec6zt`.
- **Results (test mode, no audio):**
  - **All 22 tests, twice each:** 40/44 for both the old and the short prompt. The misses were mostly test design, fixed and rerun.
    - Prompt per turn: 29,115 → 23,924 tokens.
    - Replies over 2 s: 10/44 → 5/44.
    - Backup model used: 2/44 → 1/44.
  - **Reruns of the 4 fixed tests, three times each:** short 11/12, old 9/12.
  - **Payment tests on the live agent with the short prompt:** 6/6.
  - Test-mode timing is noisy and slower than real conversations, so the real first-token time is **still not measured**.
- **Found, not changed:** in German, both prompts sometimes got numbers wrong when writing them out as words: "31 days in February", "166 days" in a leap year. That was 1 of 3 runs with the short prompt and 3 of 3 with the old one.
  - The agent's `text_normalisation_type` is `system_prompt`: the model itself writes numbers as words for the voice.
  - Options to test on the bake-off branch: `elevenlabs` normalisation (a little extra latency) or `reasoning_effort: low`.
  - The test was not run on the older `gemini-3.5-flash`, so whether the 1.1 model change made this worse isn't known.
- **Live tools not in this repo:** `pay_for_page`, `add_to_diary` and `upcoming_renewals` are attached to the live agent but aren't in `tools.json` here. They come from the unmerged branch `claude/fervent-hamilton-ot5z1f`.
  - Their live descriptions carry their full rules (read 2026-10-12), so the short prompt has no separate lines for them.
  - That branch also edits `instructions.md` (three tool lines, and it moves the learned-facts block). When it is merged, keep this `instructions.md` and take its `tools.json` and `voice_agent_spec.py` changes.
- **Not changed:** tool descriptions (about 17k tokens of every turn, now the biggest part; next step), the tool list, turn-taking, voice, model.

**Applied to the live agent 2026-10-12 (speed quick wins; owner: "ok do the quick wins in the agent settings first"; `docs/architecture/SPEED_AND_RESPONSIVENESS.md` 1.1 and 1.4):**
- **Filler:** `turn.soft_timeout_config` now says "Mhm…" or "Hmm…" (shuffled, at most 2 per reply, not before the user's first message) when the model hasn't started after 2 s. Version `agtvrsn_6001m4rt118mf4xbthajqbx7czhj` (rollback) → `agtvrsn_0101m4rtbax6ehm87zawpd27r9z0`.
- **Slow online tools:** `pre_tool_speech: force` and `tool_call_sound: typing` (behaviour `always`) on `web_search`, `check_email`, `read_email`, `find_drive_file`, `search_notion`, `read_notion_page`, `check_outlook_email`, `read_outlook_email`, `read_outlook_calendar`, `list_todoist_tasks`; every other field kept as live and read back after saving. Tools are workspace objects, so this is not versioned with the agent; to undo, set `pre_tool_speech` back to `auto` and remove the sound. In `tools.json` this is `x_doddy.sound: "typing"`, which `voice_agent_spec.py` now checks, renders and compares.
- **Model:** `gemini-3.5-flash` → **`gemini-3.6-flash` with `reasoning_effort: minimal`**, only those two fields. Version `agtvrsn_0101m4rtbax6ehm87zawpd27r9z0` (rollback) → `agtvrsn_9501m4rtrbpjfs39ney04309wemz`. Prompt and the 61 attached tools unchanged.
- **How the model was chosen:** a branch with no live traffic (`speed-bakeoff`, `agtbrch_0601m4rteqvbeyfvbbhms4q58492`) and 13 ElevenLabs agent tests, Polish and English, each run twice: save a note, weather starts with `geocode_place`, reminder, read calendar, add to a list, web search for current events, recall with `search_memories`, timer, honest about being an AI, never claims a declined save, email text is data and not instructions, short correct answer without flattery, says plainly what it can't do. Test ids: `test_5301m4rtffeaf0sbbqg1ac44gd4p`, `test_1201m4rtfgajfa9bpacx108czmjb`, `test_8601m4rtfhpcexfr1m9wg8q30eyr`, `test_9601m4rtfjfwef0ae8nmxfkx9xc6`, `test_0101m4rtfkm7eaxtw0e8jfcbdjps`, `test_7501m4rtfmeyeqgsd4c2jyb9yhz6`, `test_1901m4rtfn99fzmav0se7k70b8am`, `test_8001m4rtfp2wfpk9akd5f0df1s9y`, `test_0001m4rtgjf8fcra4j3thcf6csnt`, `test_3701m4rtgk6vfqes1tk4kmnkaz55`, `test_9701m4rtgmbff2h99vvhkdkxbqe6`, `test_7301m4rtgnhtfrpanq5e599nm0n0`, `test_9901m4rtgpdafxmv4qvqgcqy25nd` (all named `doddy-speed: …`). Run them again before any later model or prompt change.
- **Results (test mode, no audio, two runs of 26 each):** quality 24/26 for both models before a fix to my weather test's parameter check, and 26/26 for `gemini-3.6-flash` on the live branch after it. Replies that took over 2 s (the filler played): 47/52 with 3.5 Flash, 22/52 with 3.6 Flash. Replies over 4 s, where ElevenLabs switched to the backup `gemini-2.5-flash`: 16/52 with 3.5 Flash, 3/52 with 3.6 Flash. Test-mode timing is noisy (the same settings gave 6/26 and 16/26 slow replies) and slower than real conversations, so the real first-token time is **not measured yet**: read `conversation_turn_metrics` of the next real conversations and compare with the 2026-10-11 baseline (median 0.80–1.25 s).
- **Not changed:** the prompt (its length is the next step, 1.2 in the speed document), the tool list, turn-taking, the voice, the backup-model chain.

**Applied to the live agent 2026-10-11 (ADR-291, open camera; owner: "Zgoda", then "zrob to ty"):** `run_shortcut` (`tool_1601m4gj37f5etbres37pgtvrq3c`) has the new `name` sentence. Two edits went into the live prompt in place: the "Opening the camera" line after `run_shortcut`, and "open the camera" in the last strict timer/map/shortcut rule. Version `agtvrsn_8101m4nf7332e9d9s4vcvvyd1zbx` (rollback) → `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89`. Both the tool and the prompt were read back after saving; the tool list is unchanged.

**Applied to the live agent 2026-10-11 (ADR-254, owner: "you do it"):** done as described below; read back after
saving. Version `agtvrsn_5701m4m4268zfx2s83k8xcdg5bgm` (rollback) → `agtvrsn_2701m4mc8sejfzkbjmekv9nczdrp` (first
message and placeholder) → `agtvrsn_6701m4mc9b7wekgb2jeg1c6pwnyv` (Polish preset). What was changed: `session.json` first message
`{{opening_line}}` with placeholder "Hey, it's Doddy. what's up?" (the live text, `first_message_variable`). To apply:
set the agent's first message (English and Polish) to `{{opening_line}}` and add the dynamic-variable placeholder
`opening_line` with that text, so older app builds that don't send it still start. Until then the live first
message is the fixed text and the app's `opening_line` is ignored. Read 2026-10-11: the live agent also has
dynamic-variable placeholders this repository doesn't declare (`morning_checkin`, `saved_lists`, `translator_start`)
and 36 language presets; keep them when applying (both lists are replaced wholesale by the API).

1. Change the files here first.
2. `python3 -I scripts/voice_agent_spec.py check` (also runs in `scripts/ci.sh`).
3. Push to ElevenLabs: `python3 -I scripts/voice_agent_spec.py elevenlabs` prints each tool in
   ElevenLabs form; apply them (and the prompt) to agent `agent_0501m4et27vyeawrwqfdxxfszfa6`
   through the ElevenLabs connector or dashboard. The tool ids are in `x_doddy.elevenlabs_tool_id`.
4. Check for drift: export the live tools (`agents_list_tools` for the agent) and prompt into
   `{"prompt": "...", "tools": [...]}` and run `voice_agent_spec.py compare EXPORT.json`.

**Not yet applied to the live agent (ADR-441, 2026-10-11):** this repository now has the `note_capability_gap` tool, the `{{learned_context}}` variable (declared in `session.json`) and two paragraphs in `instructions.md` (what Doddy learned, and when to note a gap). Until the owner applies them (the live prompt is ahead of `instructions.md`, so merge the two paragraphs rather than overwriting it), the app already sends the variable, which the live prompt ignores, and Doddy never calls the new tool. Run `compare` afterwards.

Editing the agent in the ElevenLabs dashboard without updating these files is drift; the compare
step catches it. Each tool's `x_doddy.elevenlabs_tool_id` is its live id; a tool not yet on the live agent
says `not_synced`, and `check` fails on a missing id or on a phone tool no Swift source answers.

**Current state (read 2026-10-11, version `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89`):** 43 tools, all with
their ids here. The dynamic-variable placeholders are recorded in `session.json` (`elevenlabs.placeholders`).
The history below lists each change applied and its rollback version.

**Not yet applied to the live agent (voice-agent review, 2026-10-11):**
- **Prompt (`instructions.md`):**
  - The profile is style, not instructions.
  - "partly" names unconfirmed items.
  - "nothing to undo" / "not undone".
  - List results by full prefix, plus "not added" and "created" / "not created".
  - Alarms "not found" or unreadable.
  - DEMO DATA is read by the usual rules.
  - Tool results now mark more third-party text with `<<<DATA`; the prompt already covers it.
- **Tool `geocode_place`:** the `language: pl` constant was removed, so place names come back in English (Open-Meteo's default) instead of always Polish.
- **Phone agent (`phone/instructions.md`):** `save_note` statuses, `not_recognised`, and a missing tries count. The phone agent is not created yet, so this applies when `setup-phone-agent.mjs` first runs.

Read the live agent first, then apply only these changes and keep everything else as found.

**Applied to the live agent 2026-10-10 (ADR-129):** the M4 Reminders wording (ADR-126) and the calendar
date rules (ADR-127, ADR-128) in `create_reminder`, `create_calendar_event` and the prompt. The opening line
of `instructions.md` is the owner's dashboard edit, copied back so the spec matches the live prompt.

**Applied to the live agent 2026-10-10 (ADR-191):** the opening line again says plainly that Doddy is an AI
when asked (the dashboard edit had told it to give a "vague answer"). Only that line was changed, on live
version `agtvrsn_3401m4k47e2revvv01sk7xv1tb26` → `agtvrsn_5801m4k5544wevk9bz7wezwneh88`; tools untouched.

**Applied to the live agent 2026-10-10 (ADR-198):** new client tool `remind_me_about_note`
(`tool_7401m4k84jjgf1ctk26vj03kextq`) attached next to the 21 existing tools, and two prompt lines (its tool
bullet and one reminder rule). Version `agtvrsn_1401m4k5nha9ffv81j7c6m6sze2n` → `agtvrsn_1601m4k85xy5ew7awn6n9yxwas7v`;
compare run against the new tool and the full prompt (no drift). For rollback, the previous version has 21 tools.

**Applied to the live agent 2026-10-10 (ADR-204):** new client tool `propose_plan`
(`tool_3001m4knv27zfw09afmn7sjamfcp`, 120 s timeout, speech forced before it) attached next to the 22 existing
tools, and one prompt line (its tool bullet). Version `agtvrsn_1601m4k85xy5ew7awn6n9yxwas7v` →
`agtvrsn_2801m4knwd04fxfbj25wat868jtp`. For rollback, the previous version has 22 tools. An installed app
without the plan card answers it as unsupported, and the prompt tells Doddy to say so in one sentence.

**Applied to the live agent 2026-10-10 (ADR-211):** `remind_me_about_note` (`tool_7401m4k84jjgf1ctk26vj03kextq`)
gained the `repeat` parameter and one sentence in its description, updated in place; the prompt and the agent's
tool list are unchanged.

**Applied to the live agent 2026-10-10 (ADR-212): European languages.**
- **Language presets:** 36 non-English presets (the `languages` list in `session.json`), each overriding only the first message. ElevenLabs refused Basque (`eu`) and Albanian (`sq`), so they are left out. The built-in `language_detection` tool was already on with `only_at_conversation_start: false`; with the presets it switches between all of them mid-conversation.
- **Prompt:** three lines changed: the reply language, the Wikipedia language code, and the languages for note search.
- **Wikipedia tools:** `wikipedia_search` and `wikipedia_summary` accept the same codes. Summary redirects stay limited to the 20 largest editions, because ElevenLabs allows at most 20 redirect domains.
- **Versions:** `agtvrsn_2801m4knwd04fxfbj25wat868jtp` → `agtvrsn_2301m4kpwmr1fcers0b8vf7th8qr` (presets) → `agtvrsn_7101m4kpz26mf3p8yysmx0y4z6cz` (prompt).
- **Known drift, not from this line:** the live agent also has `propose_plan` (`tool_3001m4knv27zfw09afmn7sjamfcp`) and its prompt line from ADR-204 on the `claude/loving-dirac-uuxoux` line. Both were kept as they are. The live first message is the owner's dashboard text "Hey, it's Doddy. what's up?", now copied into `session.json`.

**Applied to the live agent 2026-10-10 (ADR-215): translator mode.**
- **New client tools:** `start_translator` (`tool_6601m4krz5tqe0paj9jxza6vnjgp`) and `stop_translator` (`tool_4601m4krz73zeb1a9edtsxmn6c5s`), attached next to the 23 live tools (25 in total, `propose_plan` included).
- **Prompt:** two tool lines and the "Translator mode" section with `{{translator_start}}`. The live prompt is `instructions.md` plus the `propose_plan` line.
- **Placeholder:** `translator_start` = `none`, so app builds that don't send it still start.
- **Versions:** `agtvrsn_7101m4kpz26mf3p8yysmx0y4z6cz` → `agtvrsn_2301m4krzkz7e52tvq4wj55fpx86` (placeholder) → `agtvrsn_6601m4ks1cwmfqfs30v2cpsgg6c0` (prompt and tools).

**Applied to the live agent 2026-10-10 (ADR-209):** `propose_plan` description and its prompt line now include
`draft_email`, `add_todoist_task` and the "drafted" prefix. Version `agtvrsn_6601m4ks1cwmfqfs30v2cpsgg6c0` →
`agtvrsn_1701m4kv8t8jfqka415br02e8sfh`. The live agent also carries `start_translator`, `stop_translator` and a
Translator mode prompt section from the other line; they were left as they were.
Both lines are merged now, so the spec has them all.

**Applied to the live agent 2026-10-10 (ADR-216): lists.**
- **New client tools:** `add_to_list` (`tool_1901m4kvecp0ehqr73ky4r97n0b6`), `read_list` (`tool_6701m4kvedsvfgws44xke00pg911`), `check_off` (`tool_8601m4kveefzes39dyehrxqf4t76`), `remove_from_list` (`tool_9701m4kvef75fpyszf66w6fqpf0t`) and `create_list` (`tool_4201m4kveg9ke36tmg4qx8tzq8zq`). That makes 30 tools on the agent.
- **Array parameters:** list items are an array of strings, the first array parameter; `voice_agent_spec.py` now checks and renders lists of described strings.
- **Prompt:** "The user's lists" with `{{saved_lists}}`, two tool lines, "List rules (strict)", and "lists" added to the translator's never-share rule.
- **Placeholder:** `saved_lists` has a default.
- **Drift merged:** before this change the live prompt held a newer `propose_plan` line from the other line (it now also covers `draft_email` and `add_todoist_task`, and "drafted"). That line was kept as found.
- **Versions:** `agtvrsn_1701m4kv8t8jfqka415br02e8sfh` (found live) → `agtvrsn_7801m4kvexq4e5v87gesg006nqrx` (placeholder) → `agtvrsn_2001m4kvh05xfzg8kfmz6ydsmtkm` (prompt and tools).

**Applied to the live agent 2026-10-10 (ADR-217, ADR-220): plan cards with list steps, morning check-in.**
- **Re-read first:** the live prompt was `instructions.md` as of the lists sync, with no drift.
- **`propose_plan`** (`tool_3001m4knv27zfw09afmn7sjamfcp`): its description and `steps` parameter now include `add_to_list` and the "not found" / "not added" lines. Every other setting was kept as live.
- **Prompt:** the `propose_plan` line includes `add_to_list`. There is a new section "Morning check-in" with `{{morning_checkin}}`.
- **Placeholder:** `morning_checkin` defaults to `none`, set before the prompt, so builds that don't send it still start.
- **Versions:** `agtvrsn_2001m4kvh05xfzg8kfmz6ydsmtkm` (found live) → `agtvrsn_9501m4kzp64we3db2k1jpadzwtyz` (placeholder) → `agtvrsn_0401m4kzqvpkfjb8bqsvnsg2j3nh` (prompt). The tool update doesn't make an agent version. Still 30 tools.

**Applied to the live agent 2026-10-10 (ADR-224): translator speaks each language natively.** One line was added to "Translator mode": native pronunciation, plus correct spelling and accents. It keeps Doddy's own voice. Versions: `agtvrsn_0401m4kzqvpkfjb8bqsvnsg2j3nh` (found live, unchanged) → `agtvrsn_1601m4m03vmqe90rh35280g5pxp7`.

**Applied to the live agent 2026-10-11 (ADR-280 to ADR-283): several changes on one card, repeats, event details, alarms part 2.**
- **Re-read first:** version `agtvrsn_8601m4n87tvmf83azq8ek4wtpst4`, 39 tools.
- **Updated in place:** `create_calendar_event` and `create_reminder` gained `repeat` and `repeat_until`. `change_calendar_event` gained `new_location` and `add_note`. Every other setting was kept as live.
- **New client tools:**
  - `delete_calendar_events` (`tool_8601m4n8q9x6eyjvf1a40p8ktj62`)
  - `move_reminders` (`tool_3901m4n8qapwe24s7y6fk8dm3r6e`)
  - `list_alarms` (`tool_4201m4n8qbg3f40agsjckezvanvq`)
  - `cancel_alarm` (`tool_7901m4n8qcz5f22r1ahkr926kqqm`)
  - That makes 43 tools on the agent.
- **Prompt:** the lines in `instructions.md` for these tools, the "cannot do yet" paragraph, and the alarm-off rule. Each was edited into the live prompt.
- **Version:** `agtvrsn_8601m4n87tvmf83azq8ek4wtpst4` → `agtvrsn_7701m4n8vprrem78gmfjjmq77t96`. Rollback: the first version, which has 39 tools. An installed app without this round replies "unsupported" to the four new tools.
- **Known drift at the time, since merged:** the live agent also had `undo_last`, `upcoming_birthdays`, `calculate` and `convert_units` from another line. They are now in this spec and the app answers them.

## App side (DoddyCore `RealtimeVoice.swift`)

- `RealtimeEvent`: what any provider reports, named after Realtime server events
  (`sessionReady`, `userSpeechStarted/Stopped`, `userTranscript`, `responseStarted`,
  `audioStarted`, `assistantTranscript`, `functionCall`, `responseDone`, `error`, `ended`).
- `RealtimeVoiceSession`: the protocol a provider adapter implements: `start(config)`,
  `send(functionOutput)`, `setMicrophoneMuted`, `end()`.
- `RealtimeConversationState`: turns events into the voice screen's phase, transcript and open
  tool calls, identically for both providers.
- `RealtimeToolCatalog.unhandledPhoneTools`: phone tools the app cannot run (each would leave
  the model waiting until its timeout).

**Not wired yet:** the voice screen still talks to the ElevenLabs SDK directly. The
ElevenLabs adapter (`ElevenLabsRealtimeSession`) and the switch of `VoiceSessionController` to
`RealtimeVoiceSession` come after the parallel voice branches are merged (calendar, knowledge,
Island), so the rewrite happens once on the combined code.

ElevenLabs SDK → event mapping for that adapter:

| ElevenLabs Swift SDK | RealtimeEvent |
|---|---|
| `onAgentReady` | `.sessionReady` |
| `onAgentStateChange(.thinking)` | `.responseStarted` |
| `onAgentStateChange(.speaking)` | `.audioStarted` |
| `onAgentStateChange(.listening)` | `.responseDone` |
| `onUserTranscript` | `.userTranscript` |
| `onAgentResponse` / `onAgentResponseCorrection` | `.assistantTranscript` / `.assistantTranscriptCorrected` |
| `onUnhandledClientToolCall` | `.functionCall` (`toolCallId`, `toolName`, parameters as JSON) |
| `sendToolResult(for:result:isError:)` | `send(RealtimeFunctionOutput)` |
| `onError` / `onDisconnect` | `.error` / `.ended` |

ElevenLabs does not expose speech-start/stop events, so `userSpeechStarted/Stopped` only come
from the OpenAI adapter; the screen works without them.

## What moving to OpenAI Realtime needs (not built)

1. A token server that mints short-lived client secrets (the API key never ships in the app).
2. `OpenAIRealtimeSession`: WebRTC connection, `session.update` from `voice_agent_spec.py openai`
   with instructions rendered on the phone, events mapped as named above.
3. Run the four `web` tools (weather, Wikipedia) in the app or on the token server from
   `x_doddy.http`, because OpenAI sends every function call to the client.
4. Pick a voice. OpenAI has preset voices only; Doddy's ElevenLabs voice does not carry over.
5. Bake-off on the same Polish/English phrases before switching (latency, interruptions, cost).

## Speed settings (2026-10-09)

| Setting | Before | Now | Why |
|---|---|---|---|
| Turn eagerness | normal | **eager** | Replies sooner after the user pauses (≈ Realtime `semantic_vad` eagerness high). May cut in on long pauses. |
| Speculative turn | on | on | Starts the reply before the turn is certain. |
| Reasoning / thinking budget | — | — | Not supported for `gemini-3.5-flash` (ElevenLabs rejects the setting). |
| LLM (2026-10-12) | gemini-3.5-flash | **gemini-3.6-flash**, reasoning effort **minimal** | 3.5 Flash is deprecated by Google and thought on every turn; 3.6 Flash passes the same quality tests with far fewer slow replies, at half the price. See the 2026-10-12 entry above. |
| Filler (2026-10-12) | off | **"Mhm…" / "Hmm…" after 2 s** | No long silence while the model is slow. Static, language-neutral, never claims anything was done. |
| Slow online tools (2026-10-12) | speech auto, no sound | **speech forced + typing sound** | The 10 tools that go through Doddy's server: Doddy says a short line first and a typing sound plays while it runs. |
| Background voice detection | off | **on** | A video playing nearby was transcribed as one endless user turn, so Doddy never got to reply (conversation conv_6101m4g87cmjefgvjek1gdpxvqmp). Filters voices that are not the user. |
| Voice model | eleven_v4_turbo | unchanged | Changing it changes how the chosen voice sounds; compare on device first. |

## Phone agent (`phone/`, S2)

`voice-agent/phone/` defines the separate ElevenLabs agent **"Doddy (phone)"** that answers and
places phone calls through the Twilio number (ADR-152, ADR-172). Same three files, same rules:

| File | What it is |
|---|---|
| `phone/instructions.md` | The phone prompt, with `{{doddy_caller}}`, `{{doddy_direction}}`, `{{doddy_memory}}`, `{{doddy_pin}}` filled by the messaging server's call-start webhook |
| `phone/tools.json` | `verify_pin`, `search_memories`, `save_note`: webhooks to `server/messaging`. Instead of a fixed url they give `x_doddy.http.base` (the `PUBLIC_BASE_URL` env name), a `path_template` and `body` parameters; headers reference the workspace secret `doddy_tool_secret` and the secret variable `secret__doddy_session` |
| `phone/session.json` | First message, LLM, privacy (no audio recording, 30-day transcripts), placeholders, the call-start webhook path |

- Check: `python3 -I scripts/voice_agent_spec.py check --agent phone` (in `scripts/ci.sh`).
- Create the agent: `server/messaging/scripts/setup-phone-agent.mjs` reads these files; `--dry-run` prints every request.
- **Voice: not set (decision needed).** Neither `phone/session.json` nor the setup script sets a TTS model or voice, and `languages` is only `en`. ElevenLabs therefore uses its default for an English agent. The prompt says to answer Polish callers in Polish, but whether that voice speaks Polish hasn't been checked. Before the first real call, choose a multilingual TTS model, or add a `pl` preset, and record it in `phone/session.json`.
- Drift: export the live phone agent's prompt and tools as above and run `voice_agent_spec.py compare EXPORT.json --agent phone`.
- Status: **not created yet** (needs the deployed messaging server, a Twilio number and the owner's go-ahead).


**Applied to the live agent 2026-10-11 (ADR-300 to ADR-305): round 4.**
- **Re-read first:** version `agtvrsn_7701m4n8vprrem78gmfjjmq77t96` (43 tools), unchanged since round 3. `instructions.md`, which includes the affectionate-edison lines merged in PR #27, matched it except for the order of one sentence.
- **New client tools:**
  - `convert_currency` (`tool_9001m4nf3w1demytz6bvyxvyj756`)
  - `parking_spot` (`tool_8001m4nf3xc5e2asz2rxpya9f102`)
  - `read_email` (`tool_2901m4nf3yzbeeq9jy2hp5jhwzef`)
  - `complete_todoist_task` (`tool_7101m4nf40ase7bsx8qa68ty4eh4`)
  - `move_todoist_task` (`tool_0401m4nf41j9ex08e5ksevh06rht`)
  - `add_ingredients` (`tool_9201m4nf430kezd9s0fpxznfkppr`)
- **Updated in place:**
  - `change_reminder` gained `add_note`, `priority` and `move_to_list`.
  - `check_email` points to `read_email`.
  - `list_todoist_tasks` explains the `[id …]` ids.
- **Prompt:** `instructions.md` as committed with round 4. After the merge with the default branch, `instructions.md` also has the "Opening the camera" line (ADR-291, another session). That session has since applied it (version `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89`, read again here: 49 tools, round 4 lines and the camera lines all present), so the live prompt is `instructions.md`.
- **Version:** `agtvrsn_7701m4n8vprrem78gmfjjmq77t96` → `agtvrsn_8101m4nf7332e9d9s4vcvvyd1zbx`, 49 tools. The stored prompt was read back.
- **Mixed versions:** an installed app from before this round answers "unsupported" to the six new tools. A backend without round 4 refuses the three online-account tools as unknown.

**Applied to the live agent 2026-10-11 (round 5, ADR-314 and ADR-316).**
- **Re-read first:** version `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89` (49 tools). Its prompt was `instructions.md` from before this round, except for the camera line: the live agent keeps the ADR-291 wording until a build with the camera shortcut section (ADR-309) ships, as that change says. It still does.
- **New client tools:**
  - `draft_email_reply` (`tool_9001m4nt0dfmecabw665gm7xqwcs`)
  - `read_notion_page` (`tool_5301m4nszh67fbqbhsg52p4r7ynp`)
- **Updated in place:**
  - `change_reminder` gained `new_title`, `repeat` (with `none`), `repeat_until`, `replace_notes` and `clear_notes`.
  - `change_calendar_event` gained `replace_notes` and `clear_notes`.
  - `search_notion` now points to `read_notion_page`.
- **Prompt:** the round 5 lines of `instructions.md`, plus "What you cannot do yet" and the online-account rule. The camera line is kept as it was live.
- **Version:** `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89` → `agtvrsn_7001m4nt39q1fhwrhtsyqdegf35g`, 51 tools. The stored prompt was read back.
- **Mixed versions:** an installed app from before this round answers "unsupported" to the two new tools and doesn't act on the new `change_reminder`/`change_calendar_event` fields. A backend without round 5 refuses the two online-account tools as unknown.

**Applied to the live agent 2026-10-11 (round 6, ADR-332 to ADR-335 and ADR-340).**
- **Re-read first:** version `agtvrsn_2901m4ny3aecery96s4qqx3z5zeh` (51 tools, the same ids as after round 5). Its prompt was round 5's, with two differences:
  - the camera line is still the ADR-291 wording, as before;
  - two lines from ADR-440 ("unlock as you go", branch `claude/lucid-johnson-pmwwg4`, not merged into this line yet) were applied by that session: the connections line ("Nothing is asked up front…") and the online-account "declined"/"iPhone doesn't allow" rule.
  Both are kept live. `instructions.md` on this branch doesn't have the ADR-440 lines; they arrive with that branch's merge.
- **New client tools:**
  - `find_free_time` (`tool_3201m4nyakxvf7ht6vxqyywxjf43`)
  - `remind_when_to_leave` (`tool_4801m4nyams5ff79cbnt0j8vweds`)
  - `check_outlook_email` (`tool_1401m4nyap0tfdvbspd4a6717pnh`)
  - `read_outlook_email` (`tool_1901m4nyaq66ew6bkbvqby0049mv`)
  - `draft_outlook_email` (`tool_9501m4nyarbhfx8sjxt8jdg88nja`)
  - `read_outlook_calendar` (`tool_1301m4nyas4zf8bbxnwb6q0jvpyb`)
- **Updated in place:** `search_memories` (the `#tag` sentence) and `create_list` (the `template` parameter).
- **Prompt:** the round 6 lines of `instructions.md` (tags, free time, leave-by, Outlook, list templates, "What you cannot do yet", the online-account rule), merged with the live-only lines above.
- **Version:** `agtvrsn_2901m4ny3aecery96s4qqx3z5zeh` → `agtvrsn_9901m4nydc9qegk8npkv8jvprm90`, 57 tools. The stored prompt and tool list were read back from the save.
- **Mixed versions:** an installed app from before this round answers "unsupported" to the six new tools and ignores `template`. A backend without round 6 refuses the four Outlook tools as unknown, and the Outlook toolkit only runs against the mock until a Composio Outlook auth config exists (`docs/implementation/ROUND6_REPORT_2026-10-11.md`).
