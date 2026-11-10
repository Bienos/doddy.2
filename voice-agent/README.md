# Doddy voice agent — spec in OpenAI Realtime shape

**In short:** this folder holds what Doddy's voice agents are told and which tools they have. There are three ElevenLabs agents: the main agent the app talks to (the files in this folder, 107 tools), the phone agent for Doddy's phone number (`phone/`, 3 tools) and the agent that calls a business for the user (`task-call/`, no tools). The last two are not created yet.
Check all three with `python3 -I scripts/voice_agent_spec.py check`, adding `--agent phone` or `--agent task-call`; `scripts/ci.sh --only checks` runs all three.
Editing these files doesn't change a live agent. The live agents are changed only by the owner, or on the owner's separate instruction. Most of this page is a dated log of what was applied to the live main agent, mostly newest first.
**Changed on 10 Nov 2026, about 12:20 UTC (owner: "tak zrób to wszystko", then "Ty zrób"; PR #309, decision `docs/decisions/2026-11-10-cards-pop-up-and-results-in-messages.md`):** three tools and two prompt lines, as in this folder's `tools.json` and `instructions.md`.
- `open_map` (`tool_6101m4gj36nbe1tv5mpj73rzbqsa`) gained the optional `from` and `mode` (driving, walking, transit) parameters and the route wording.
- `hand_over_errand` (`tool_0401m5y4xbkmegkaydf5p0sjfqqn`): results arrive as Doddy's message in Messages; on "started" Doddy says "Dobra, daj mi chwilę, poszukam i dam ci znać w Wiadomościach."
- `make_document` (`tool_2101m5f15tckfy0v74g5gyaqm3td`): the file also arrives in Messages, with Share.
- Prompt: the "on started… result will be in Tasks" step and the Rome example's "Wynik będzie w Zadaniach" now say the Messages line. Nothing else changed: 24,073 → 24,162 characters, read back.
- Read first and **rollback**: `agtvrsn_3601m72591fmf58rvk7gxpdnjhn2`. Published: `agtvrsn_7801m72q3h4te4r87vq8xm1m3fyr`, 109 tools, model and voice unchanged.

**Changed on 9 Nov 2026, about 20:40 UTC (owner: "niech nic nie mówi, zmień zasady", then "ok" to the exact lines; decision `docs/decisions/2026-11-09-translator-translates-at-once.md`):** the live system prompt's translator section. Removed: "Face to face: once, before translating anything, say the AI translator disclosure…" and "Right after it starts: … ask them once … what to translate…". Added in their place: "Say nothing of your own (owner's rule, 9 Nov 2026): no greeting, no AI translator disclosure, no question about what to translate. When translator mode starts, wait in silence until someone speaks, then translate. The other person's half of the screen shows, in their language, that this is an AI translation." "Listen only" lost "and don't say the disclosure". Nothing else changed. Read first: `agtvrsn_0501m706dw6tfyj8frbt6g06m3y4`, prompt 23,453 characters (**rollback**). Saved: `agtvrsn_5401m70zggkafcz88jshewy89ae8`; read back at 23,200 characters, as expected. **Not applied:** the matching sentence in the live `start_translator` description (`tool_6601m4krz5tqe0paj9jxza6vnjgp`, still "if the user hasn't said what to translate, ask once"); the session's permission check refused the tool update. `tools.json` has the new wording; the prompt line and the app's `started` reply say the same, so the live tool sentence is the only place left.

**Read again on 9 Nov 2026 (read-only; nothing changed):** `agtvrsn_2901m6zx72khevps44mpwp9rbw7v`, authentication on. The live system prompt is a much shorter prompt than `instructions.md` (about 19,000 characters against 53,000): it has no "# Claude (ask_claude, make_document)" section, and mentions `make_document` only under "Shared tool rules › Routing" ("Decks and long files → make_document") and in "Working a task" ("Background work exists only through hand_over_errand and make_document"). The live `make_document` tool (`tool_2101m5f15tckfy0v74g5gyaqm3td`) has its older description with no search-first sentence, and ElevenLabs counts one call of it in total. So a repo sentence about "the # Claude section" does not apply to the live agent as written; the live edit is one sentence in "Routing" and one at the end of the tool's description (`docs/OWNER_QUEUE.md` item 29).
**Changed on 9 Nov 2026 (owner: "you do it"):** the live `make_document` tool description gained one sentence (search first for a report about real places, products, events or facts; never from memory alone); the system prompt gained one sentence in "Shared tool rules › Routing" saying the same. **Both are live since 9 Nov 2026** (owner: "you publish"). The connector can only stage a prompt edit, and `agents_update` with a `version_description` created a version without the draft (prompt still 22,841 characters), so the same prompt was written with `agents_update_prompt_settings` (only the `prompt` field): version `agtvrsn_0501m706dw6tfyj8frbt6g06m3y4`, 23,453 characters (22,841 + the 612-character sentence, checked by length, not byte for byte), model, voice, language and the 108 tools unchanged. The editor may still show the staged draft; it holds the same text. The repo's `tools.json` has the tool sentence word for word; `instructions.md` has the longer bullet under "# Claude".
**Newest recorded read of the live main agent:** 9 Nov 2026, about 10:20 UTC, after `call_me_later` was attached (entry below), `agtvrsn_2901m6zx72khevps44mpwp9rbw7v`, 105 tools: 104 of the 107 here, plus `draft_blik_transfer` (removed from the spec on 5 Nov, below). Not on the live agent: `make_something`, `pay_for_page` and `text_me` (each below). `hand_over_errand` and `check_errands` are live (27 Oct entry below) but still say `not_synced` in `tools.json`. Nothing on the live agent was read after 2 Nov.

Owner decision 2026-10-09 (ADR-058): Doddy runs on **ElevenLabs Agents**, but everything that
defines Doddy is kept here in **OpenAI Realtime** form, so moving to OpenAI Realtime later means
adding one adapter, not rewriting the app or the agent.

| File | What it is | ElevenLabs today | OpenAI Realtime later |
|---|---|---|---|
| `instructions.md` | Doddy's system prompt with `{{placeholders}}` | Agent prompt; placeholders are dynamic variables the app passes at `startConversation` | `session.instructions`, rendered on the phone by `RealtimeInstructions.render` |
| `tools.json` | 108 function tools (`type`, `name`, `description`, `parameters`) + `x_doddy`: 104 the app answers (`runs_on: phone`), 4 weather and Wikipedia lookups (`runs_on: web`) | Client tools (`runs_on: phone`) and webhook tools (`runs_on: web`) | `session.tools` (drop `x_doddy`); every call comes to the app |
| `session.json` | First message, languages, variables, turn-taking, per-provider settings | Agent settings | `session.update` body |

**Release scope (decision `2026-11-07-release-scope`, 7 Nov 2026):** the app refuses the tools of a feature its build hides (`ReleaseScope.shipping` in DoddyCore; `docs/implementation/RELEASE_SCOPE.md` lists the 67 tools the beta's agent should lose and the 41 it keeps). The spec here still describes every tool; taking the hidden ones off the live agent is the owner's change, as always.

**`start_focus`, `stop_focus`, `check_focus`, `start_wind_down` and `stop_wind_down` (decision `docs/decisions/2026-11-10-timers-by-voice.md`, 10 Nov 2026) are in `tools.json` only; they are NOT on the live ElevenLabs agent yet** (`elevenlabs_tool_id` is `not_synced`). Home's ••• menu no longer starts the focus timer, the kitchen timer, the wind-down or the stopwatch, so until these five are created and attached, a build with this change has no way to start focus or a wind-down (the stopwatch tools and `set_timer` are live). `instructions.md` (the prompt) is unchanged: each tool's description says when to use it and how it differs from `set_timer`. To sync, render each with `python3 -I scripts/voice_agent_spec.py elevenlabs`, create it, attach it, write its id here and in `tools.json`, then `compare`.

**`make_something` (Studio, ADR-740, ADR-742) is in `tools.json` and `instructions.md` only; it is NOT on the live ElevenLabs agent** (`elevenlabs_tool_id` is `not_synced`, and its prompt lines were not applied). The agent is changed only on the owner's separate instruction, and Studio is off on the server by default. An app build that has it answers the tool; the live agent never calls it.

**OpenAI Realtime voice: removed on 9 Nov 2026** (decision `2026-11-09-elevenlabs-only-voice`). The app, the voice picker and the token server's OpenAI path are gone; ElevenLabs is the only voice. The notes below about OpenAI describe what existed (ADR-265, ADR-442, ADR-546) and are kept as history.
**Repository spec trimmed, 1 Nov 2026 (owner-approved trim from the audit of 1 Nov). NOT applied to the live agent: the live ElevenLabs agent was not read, compared or changed; syncing waits for the owner's separate instruction. Until then this folder's prompt and 66 tool descriptions are not what the live agent runs.**
- **What:** the per-tool ASK-01 endings (55 descriptions) and the sentences copied into many descriptions (switched off or not connected, Settings, Online accounts; "never say it was done… 'unknown'"; the result-prefix lists; "If the result starts with DEMO DATA") are gone from `tools.json`. Each rule is said once in `instructions.md`: ASK-01 in "Always ask first", the rest in "Online account rules". A tool keeps its own nuances (its switch's name, 'not allowed' and 'empty' results, `hand_over_errand`'s one yes) and gets one short tag: "Ask: yes/tap." (`x_doddy.ask` `yes_or_tap`), "Ask: tap only." (`tap`) or "Runs at once." (`runs_now`); the ASK-01 section says what each tag means. `stop_translator` (runs at once) had carried the read tools' ask-first text by mistake; it now says "Runs at once.". Only description strings changed: no name, parameter, `x_doddy`, `speak_before` or setting.
- **How much:** the tools as the model sees them (no `x_doddy`, compact JSON) 132,292 → 105,483 characters (about 33.1k → 26.4k tokens at 4 characters a token); `instructions.md` 52,360 → 53,740 bytes; about 6.4k tokens less on every turn. `tools.json` 165,990 → 139,025 bytes.

**`pay_for_page` is back in the spec, and NOT on the live agent (ADR-737 on branch `claude/rebase-usdc-pay-for-pages`, 5 Nov 2026; owner's go-ahead to rebase and review only, ADR-729).** The tool entry is restored in `tools.json` with ASK-01's fields (`ask: "tap"`, confirm on screen, runs on the phone) and `elevenlabs_tool_id: "not_synced"`: the ElevenLabs tool `tool_1401m4rmxkm5eg3v87sphf87c45p` was detached from the live agent on 19 Oct (ADR-544) and stays detached. Nothing was synced, no live service was called, and `instructions.md` (the prompt) has no payment line, so the spec and the live prompt still match on this point. If the owner later returns the tool to the agent, the proposed prompt line and the steps are in `docs/integrations/PAYMENTS_X402.md` ("If the tool returns to the live agent"). The old branch's `add_to_diary` and `upcoming_renewals` spec entries are not restored: ADR-544 detached them and this branch keeps the default branch's direction.


## Tools at a glance (`tools.json`)

Every tool asks first (ASK-01, `x_doddy.ask`): a read, or a request to Claude, waits for a spoken yes or a tap; anything that changes or opens something needs a tap on a card. Sums, conversions, web, news and place lookups, weather, Wikipedia and the translator run at once (ADR-575, ADR-619).

| What | Tools | Who does the work |
|---|---|---|
| Notes | `search_memories`, `save_memory`, `remind_me_about_note`, `note_capability_gap` | The app, on the iPhone |
| iPhone Calendar and Reminders | `read_calendar`, `find_free_time`, `create_calendar_event`, `change_calendar_event`, `delete_calendar_event`, `delete_calendar_events`, `create_reminder`, `change_reminder`, `delete_reminder`, `move_reminders`, `undo_last`, `remind_when_to_leave`; `propose_plan` puts several changes on one card | The app |
| Contacts and messages | `lookup_contact`, `upcoming_birthdays`, `draft_message` (the user sends it). `draft_blik_transfer` was removed on 5 Nov (ADR-810, above) | The app |
| Sums and conversions | `calculate`, `convert_units`, `convert_currency` | The app |
| Timers, alarms, stopwatch, focus, wind-down | `set_timer`, `set_alarm`, `list_alarms`, `cancel_alarm`, `start_stopwatch`, `stop_stopwatch`, `check_stopwatch`, `start_focus`, `stop_focus`, `check_focus`, `start_wind_down`, `stop_wind_down` (the last five not on the live agent yet) | The app |
| Lists | `add_to_list`, `add_ingredients`, `read_list`, `check_off`, `remove_from_list`, `create_list` | The app |
| The phone itself | `open_map`, `parking_spot`, `run_shortcut`, `open_camera`, `find_photos`, `control_home` (Apple Home), `follow_news` (Doddy's Following feed), `make_presentation` (Keynote only) | The app |
| Health and sport | `read_steps`, `read_health_week`, `open_training_plan` | The app |
| Translator | `start_translator`, `stop_translator` | The app |
| Tasks and leaflets | `hand_over_errand`, `check_errands`, `find_deals` | The app asks; the messaging server (`doddy-messaging`) does the work |
| Studio (not on the live agent) | `make_something`: a research brief (PDF) and an infographic, made in the background | The app asks; the messaging server does the work. Off on the server by default (ADR-740) |
| Invoices and a lost wallet | `draft_invoice` (fills the invoice card, sends nothing), `lost_wallet` (a checklist of what to do, the app can't block a card) | The app |
| Texts, calls and payments (`call_me_later` live since 9 Nov 2026; the others not on the live agent) | `text_me` and `call_me_later` (a text or a booked call from Doddy's own number to the person's own verified number), `pay_for_page` (proposes paying for one page; off unless the server's owner sets a wallet, test network only) | The app asks; `text_me` and `call_me_later` go to the messaging server. `pay_for_page` is answered by the app with the server's terms and a Face ID |
| Web, news, places, Claude | `web_search`, `news_search`, `find_places`, `ask_claude`, `make_document` (any deck or document except Keynote) | The app asks; Doddy's phone backend (`doddy`) runs them |
| Gmail | `check_email`, `read_email`, `draft_email`, `draft_email_reply`, `send_email`, `reply_to_email`, `forward_email`, `change_email`, `trash_email` | Doddy's phone backend, once the user connects the account |
| Outlook mail | `check_outlook_email`, `read_outlook_email`, `draft_outlook_email`, `send_outlook_email`, `reply_outlook_email`, `forward_outlook_email`, `move_outlook_email`, `mark_outlook_email` | Doddy's phone backend, once connected |
| Google and Outlook calendars | `read_google_calendar`, `create_google_event`, `change_google_event`, `delete_google_event`, `answer_google_invite`, `read_outlook_calendar`, `create_outlook_event`, `change_outlook_event`, `delete_outlook_event`, `accept_outlook_invite`, `decline_outlook_invite` | Doddy's phone backend, once connected |
| Drive, Notion, Todoist | `find_drive_file`, `create_drive_doc`, `search_notion`, `read_notion_page`, `create_notion_page`, `append_notion_page`, `trash_notion_page`, `list_todoist_tasks`, `add_todoist_task`, `complete_todoist_task`, `move_todoist_task`, `rename_todoist_task` | Doddy's phone backend, once connected |
| Weather and Wikipedia | `geocode_place`, `get_weather`, `wikipedia_search`, `wikipedia_summary` (`runs_on: web`) | ElevenLabs calls the public services itself. On the OpenAI voice the app answers that they don't work there |

The app's routing is `VoiceToolRequest.parse` and `CloudToolName` in DoddyCore. `check` fails if a phone tool has no Swift source that names it. Tools that were on the live agent and were detached because the app couldn't run them: `upcoming_renewals` and `add_to_diary` (19 Oct, ADR-544; not in `tools.json`, no app handler). `pay_for_page`, `text_me` and `call_me_later` were detached then too; they are back in `tools.json` with app handlers, but still not on the live agent.

## Changes to the live main agent, 20 Oct to 10 Nov 2026 (newest first)

**Applied to the live agent 10 Nov 2026, about 07:15 UTC (`call_me_now`, decision `2026-11-10-call-me-now-by-voice`, #305; owner on 10 Nov: "daj to już żeby działało", after the 9 Nov go-ahead for the call tools).**
- **Read right before saving:** `agtvrsn_0801m71zgg3wfj29agemmp6cx39b`, 105 tools, model `gpt-6-luna`. **Rollback:** that version.
- **Created:** `call_me_now` `tool_1301m724k8bfegwr7kaextr677tv`, exactly as `voice_agent_spec.py elevenlabs` renders it from `main` after #305 (client tool, no parameters, 90 s, speak first forced). A listing first showed no tool of that name.
- **Saved:** `agtvrsn_5601m724q731f9rvhw87tjwgqae2`, `tool_ids` only: the 105 live ids unchanged and in order, plus the new one (106). No prompt, model or other setting was sent; the read-back shows the same prompt, `gpt-6-luna`, temperature 0.7 and timezone `Europe/Warsaw`.
- **Then, the same morning (owner: "zmień sam to call me later … wgraj ten prompt"):**
  - **`call_me_later` description** (`tool_6901m57key8nftdsvny3qd3n5kr7`): one sentence replaced, nothing else. Was: "It can never call anyone else, and it can't call now (for that the user taps Call me now in Settings, Phone calls)." Now: "It can never call anyone else. For a call right now, use call_me_now instead." The read-back shows the other fields as they were (client tool, 90 s, speak first, three parameters). The first attempt was refused by the session's permission check; after the owner's explicit word it went through.
  - **Live prompt:** one new section, "# Calling the user" (599 characters), inserted before "# Unsupported"; the rest was re-sent as read. Read right before: `agtvrsn_5601m724q731f9rvhw87tjwgqae2`, 23,474 characters (**rollback**). Saved with `agents_update_prompt_settings`, only the `prompt` field: `agtvrsn_3601m72591fmf58rvk7gxpdnjhn2`; read back at 24,073 characters (23,474 + 599), by length, not byte for byte. Model, temperature, time zone and the 106 tool ids were unchanged in the save's read-back.
  - **The section says:** the agent can ring the user's own phone, only theirs, with `call_me_now` (right now) and `call_me_later` (later); each shows a card and nothing is placed until the tap; one short line before the tool; for `call_me_now`, "requested" means the phone is being rung, never that the call connected; "failed" and "unknown" follow the shared result rules; it can't call anyone else. It also settles the live "Unsupported" line that says "make calls": that line starts "Unless a tool provides it".
  - **Not done on purpose:** the live prompt was not replaced with `instructions.md`. They are different texts (23,474 characters live against about 62,000 in the repo: the live one has the owner's own voice sections and no per-tool lists). The two `call_me_now` lines in `instructions.md` sit in its own "Tools on the phone" lists and don't exist live; the new live section carries the same rules.
- **Not yet seen working:** no app build with the call-now card had run when this was written, and Twilio refused both of the owner's Call me now taps on 9 Nov (502); the reason is in the messaging server's log since #293.

**Applied to the live agent 9 Nov 2026, about 10:20 UTC (`call_me_later`, ADR-754; owner: "zrób to", after being told "Doddy, call me" by voice needs the tool on the agent, and that the agent is changed only on their word).**
- **Why:** the owner asked Doddy by voice to call them (conversations `conv_4401m6zw3e3peg1vf2rc8efxhy9v`, `conv_6501m6zw86xhfxk9tz5wfbt81g65`, 9 Nov about 10:02 and 10:04 UTC); the agent had no calling tool and said it couldn't. The messaging server already serves booked calls (`GET /v1/calls/scheduled` answered 200 in its log at 10:00 UTC), so no deploy was needed.
- **Read right before saving:** `agtvrsn_5201m6xmg5wcf0prdxf923k5b3et`, 104 tools, model `gpt-6-luna`. **Rollback:** that version.
- **The tool:** `call_me_later` already existed in the workspace as client tool `tool_6901m57key8nftdsvny3qd3n5kr7` (read 9 Nov: description, parameters, 90 s, speak first forced, the same as `tools.json`). It was not changed.
- **Saved:** `agtvrsn_2901m6zx72khevps44mpwp9rbw7v`, `tool_ids` only: the 104 live ids unchanged and in order, plus `call_me_later` (105). No prompt, model or other setting was sent; the read-back shows the prompt as before and `gpt-6-luna`. The prompt's "Unsupported" line already says "Unless a tool provides it", so it was left as the owner wrote it.
- **What it does:** "zadzwoń do mnie o szóstej" shows a card in the app; nothing is booked until the tap; the messaging server rings the verified number at that time. It can't call right now (from two minutes ahead); for now the person taps Call me now under Home › ••• › Phone calls. App builds that hide phone calls (`ReleaseScope.shipping`, the beta) refuse the tool, so in TestFlight Doddy says it can't.
- **Not yet seen working:** no booked call had been placed when this was written.


**Applied to the live agent 2 Nov 2026, about 22:10 UTC (ADR-692, `lost_wallet`; owner: "add lost_wallet to the live agent", after the question about it on PR #176).**
- **Read first, and again right before saving, unchanged between the two:** `agtvrsn_5301m6et97fde7ysr5q2em33x62h`, 103 tools, model `gpt-6-luna`. That version was saved by someone else after the 1 Nov `draft_invoice` change (`agtvrsn_7901m6bqz362eah8t83pghsbdj3e`); this change did not touch it. **Rollback:** `agtvrsn_5301m6et97fde7ysr5q2em33x62h`.
- **Created:** `lost_wallet` `tool_4201m6f4xwztfs08n8r4ht6nf0ka`, exactly as `voice_agent_spec.py elevenlabs` renders it from `claude/lost-wallet-flow` (client tool, 60 s, speak first). A listing first showed no tool of that name existed.
- **Saved:** `agtvrsn_0401m6f4z169efmrdjy87wc4ys6k`, `tool_ids` only: the 103 live ids unchanged and in order, plus the new one (104). No prompt, model or other setting was sent.
- **Checked on a read-back, by script for the list:** the 104 ids are the old 103 in the same order plus the new one; the model (`gpt-6-luna`), temperature 0.7, reasoning effort, token limit, timezone (`Europe/Warsaw`), RAG, backup LLM, cascade timeout and parallel tool calls are identical in the previous and the new version; the new tool's stored description, 60 s limit, speak-first setting and three parameters are the spec's.
- **The live prompt was not changed,** and its text was not compared with the previous version's: it has no `lost_wallet` line (`instructions.md` on this branch has one). The tool's own description carries the rules (a calm voice, no jokes, never say a card is blocked or a document cancelled, never ask for or repeat a card number, PESEL or PIN, 112 first if in danger), as for `find_deals`, `draft_invoice` and the stopwatch tools. Adding the line to the live prompt is a separate instruction.
- **Not checked:** a real conversation. Only an app build with the lost-wallet card (PR #176) can run the tool; every other build answers `lost_wallet` as unsupported, so until one is installed the voice may offer steps it cannot show.

**Applied to the live agent 1 Nov 2026 (ADR-677 to ADR-679, `draft_invoice`; owner: "Add everything", then "Go" after being told the first try on 30 Oct was refused by the session's safety check).**
- **Read first, twice (30 Oct and right before writing on 1 Nov), unchanged between the two:** `agtvrsn_1401m63gw56bfm6934d4g33gef37`, 102 tool ids (two more than the entries below record: `tool_5201m626991zfjgrw2b4mhsyqzcb`, `tool_9101m626b83yfsyr5d68zckqjnqd`, kept as found), model `gpt-6-luna`, temperature 0.5, Europe/Warsaw, backup LLMs `qwen36-35b-a3b`, `gpt-6.1-sol`. A tool listing showed no `draft_invoice`. **Rollback:** `agtvrsn_1401m63gw56bfm6934d4g33gef37`.
- **Created:** `draft_invoice` `tool_9301m6bqvywnfmv93krv5jhdpd7b`, exactly as `voice_agent_spec.py elevenlabs` renders it from this branch at `2ca3de7` (client tool, 60 s, speak first, expects a response, 28 parameters).
- **Saved:** `agtvrsn_7901m6bqz362eah8t83pghsbdj3e`, `tool_ids` only: the 102 live ids unchanged and in order, plus the new one (103). No prompt, model or other setting was sent; the read-back shows the model, temperature, time zone and backup LLMs as they were.
- **Checked, by script, on a read-back:** the tool's description, its 28 parameters (type, description, enum), required list, timeout, speech settings and expects-response equal the spec.
- **The prompt was not changed:** the tool's description carries its rules (only what the user said, NIP and VAT checked against their words, sums from the result, never "issued"). `instructions.md` has the same line for the OpenAI voice.
- **Not checked:** a real conversation. **Only an app build from `claude/invoices-by-voice-ksef` (ADR-677 or later) runs the tool**; an older build answers that it doesn't support it, and the agent then says it isn't available yet.


**Applied to the live agent 1 Nov 2026, in two steps, about 14:20 and 15:32 UTC (ADR-667 and ADR-669, `find_deals`'s wording: the shops of #156 and #157; owner: "Yes" to putting the new `find_deals` text live, then "Approved").**
- **Read first:** `tool_9201m5rpyjhfe2kv0yd5xbbfk6k3` with the text of 29 Oct (ADR-660): Biedronka, Lidl, Dino, Rossmann, Aldi and Żabka read; `chains` lists ten ids. **Rollback:** re-send that text (`git show ef3ff50:voice-agent/tools.json`, the `find_deals` entry, rendered with `voice_agent_spec.py elevenlabs`).
- **Step 1 (14:20 UTC):** the tool as `voice_agent_spec.py elevenlabs` renders it at `20f8f55` (#156, the server deployed at 13:52 UTC): Delikatesy Centrum by default, E.Leclerc when named, Maxi Zoo, CCC and Komfort for their kind of item.
- **Step 2 (15:32 UTC):** read again (step 1's text, unchanged), then the tool as rendered at `e0c755d` (#157, the server deployed at 15:31 UTC): adds Lewiatan, Natura and Action by default and zooplus and Deichmann for their kind of item; `chains` lists 20 ids. Two steps so the agent never named a shop the live server didn't read.
- **Each step changed only two descriptions** (the tool's and a chain's); every other field was re-sent as read (client tool, 90 s, speak first, expects a response, interruptions allowed). The agent itself, its prompt and its `tool_ids` were not touched.
- **Checked, by script, on each read-back:** the description and the `chains` item description equal the spec at that commit; the timeout, the pre-tool speech, the type and expects-response too.
- **Older apps:** a build from before #156 (or #157) doesn't know the new ids: if the agent names one of those shops, that app refuses the request ("chains must be some of ...") and nothing is checked; with no shop named it works as before, and the server asks the new shops itself. **Not checked:** a real conversation.

**Restored on the live agent 29 Oct 2026, about 10:00 UTC: `follow_news` was detached by a concurrent save.** The Following session saved `agtvrsn_7301m626bt8mfm1bw7qav8gtqyzx` (100 ids + `follow_news`); the home-control session then saved `control_home` over the older `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`, so `agtvrsn_6201m626c2wyf72v4nrr3xtpfszk` had 101 ids without `follow_news` (`tool_5201m626991zfjgrw2b4mhsyqzcb`, which still existed). Read twice (unchanged), then saved `tool_ids` only: the same 101 ids in order with `follow_news` before `control_home` (102). New version `agtvrsn_1401m63gw56bfm6934d4g33gef37`; the prompt, model and other settings weren't sent. Owner's request: "check if everything from other session is pushed etc and is live". **Lesson:** read the agent right before saving tool_ids; two sessions saving from the same read lose one change.

**Applied to the live agent 29 Oct 2026, about 04:10 UTC (ADR-660, `find_deals`'s wording: Aldi and Żabka are read chains; owner: "zaplikuj bez czekania", then "Tekst find_deals do agenta" to the question of what to apply).**
- **Read first:** `tool_9201m5rpyjhfe2kv0yd5xbbfk6k3` with the text created on 25 Oct (`tools.json` as of `3e678c8`): Biedronka, Lidl, Dino and Rossmann read, Żabka a link, no Aldi. **Rollback:** re-send that text (`git show 3e678c8:voice-agent/tools.json`, the `find_deals` entry, rendered with `voice_agent_spec.py elevenlabs`).
- **Saved:** the tool only, exactly as `voice_agent_spec.py elevenlabs` renders it from the default branch at `ef3ff50`. Only the three descriptions changed (the tool's, `chains`', and a chain's); every other field was re-sent as read (client tool, 90 s, speak first, expects a response, interruptions allowed). The agent itself, its prompt and its `tool_ids` were not touched.
- **Checked, by script, on a read-back:** the description, the parameter descriptions, the timeout, the pre-tool speech, the type and expects-response equal the spec.
- **Not waited for (the owner chose not to wait):** an app build from before 28 Oct (ADR-660) doesn't know `aldi`: if the agent names Aldi, that app refuses the request ("chains must be some of ...") and nothing is checked; with no shop named it works as before. The server (deployed `ef3ff50`) reads all six. **Not checked:** a real conversation.

**Applied to the live agent 28 Oct 2026 (ADR-657, "śledź CPK" by voice; owner: "Dodaj", after being told it would be added only on their word).**
- **Read first, and again right before saving:** `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`, 100 tool ids, model `gpt-6-luna`; unchanged between the two reads. **Rollback:** `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`.
- **Created:** `follow_news` `tool_5201m626991zfjgrw2b4mhsyqzcb`, exactly as `voice_agent_spec.py elevenlabs` renders it from `tools.json` (client tool, 90 s, speak first). A tool listing first showed no tool of that name existed.
- **Saved:** `agtvrsn_7301m626bt8mfm1bw7qav8gtqyzx`, `tool_ids` only: the 100 live ids unchanged and in order, plus the new one (101). No prompt, model or other setting was sent; the save's read-back shows the prompt as it was, `gpt-6-luna`, temperature 0.5, timezone Europe/Warsaw and the backup order (`qwen36-35b-a3b`, `gpt-6.1-sol`) unchanged. The prompt was not re-diffed byte for byte.
- **The prompt was not changed:** the tool's description carries its own instructions (one line before it, a tap on the card, "added" only from the result, no news from it), as for the stopwatch and `find_deals`. The `instructions.md` line stays spec-only (the OpenAI voice reads it).
- **Not checked:** a real conversation. Only an app build with ADR-657 (branch `claude/message-tracking-plugin-rd0cbn`, not merged, not compiled yet) can run it; the build on the owner's iPhone answers that it doesn't support the tool, and Doddy says it isn't available yet.
**Applied to the live agent 28 Oct 2026, about 18:10 UTC (ADR-658, voice control of the home through HomeKit: `control_home`; owner: "Ty dodaj", then "Tak dodaj" to the exact tool text and prompt line shown in the session).**
- **Read first:** live version `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh` (the rollback point), 100 tools.
- **Tool:** `control_home` created as client tool `tool_9101m626b83yfsyr5d68zckqjnqd`, exactly as `voice_agent_spec.py elevenlabs` renders it (response timeout 90 s, pre-tool speech forced, expects a response), and attached as the 101st tool. The other 100 ids are unchanged and in the same order. The Polish example in its description is correct ("jeśli mam to zrobić"); `tools.json` briefly held it double-escaped and was fixed before the sync.
- **Version:** `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh` → `agtvrsn_6201m626c2wyf72v4nrr3xtpfszk`.
- **Checked after saving:** the saved tool list has 101 unique ids; all 98 ids recorded in `tools.json` are in it, plus the two errand tools (`hand_over_errand`, `check_errands`) that were already live, plus the new one. The tool's description came back byte for byte as sent.
- **Not done:** **the prompt was not touched.** The approved `control_home` prompt line was not added, to avoid re-sending the whole live prompt (the live prompt is the owner's own rewrite, not `instructions.md`). The tool's own description already carries the same rules (what it is for, never locks, garage doors, alarms, cameras or doorbells, never guess a name, say it worked only for `changed`, `unknown` means no retry). To add the line in the live prompt's style, a `## Home` section after `## Photos` is the natural place.
- **Not checked:** a real conversation. No app build with the Home flow is on a device yet, so on today's builds the agent can call the tool and the app will answer `unsupported`/not connected. Rollback: restore `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`.

**Not yet on the live agent (ADR-660, 28 Oct 2026): `find_deals`'s new wording.** `tools.json` now says Aldi and Żabka are read and lists `aldi` and `zabka` among the chains; the live tool (`tool_9201m5rpyjhfe2kv0yd5xbbfk6k3`) still says Żabka is a link and doesn't name Aldi. The live tool keeps working: when the user names no shop, the server reads all six. **Order:** deploy the server first (an older server refuses `aldi`), then ship the app (an older app refuses `aldi` from the agent), then sync this text, and only with the owner's yes to it.


**Applied to the live agent 27 Oct 2026, about 07:44 UTC (ADR-570, voice errands: `hand_over_errand` and `check_errands`; owner: "wariant B, zapisz po PR", after PR #145 was open and its `core` job green).**
- **Read first:** `agtvrsn_8001m5ry9by6feyajtpxbdt3xrxp`, 98 tool ids, a 41,352-character prompt, model `gpt-6-luna`. Read in full twice (a dry run, and again right before writing); unchanged between the two. **Rollback:** `agtvrsn_8001m5ry9by6feyajtpxbdt3xrxp`.
- **Saved, in three writes:** (1) `agtvrsn_5301m5y4wwdpfwzs07htb7z6ysak`: the placeholder `errands` = `none`, with the 12 existing placeholders re-sent unchanged (the field is replaced wholesale); written first so the prompt never names a variable that has no default. (2) Created `hand_over_errand` `tool_0401m5y4xbkmegkaydf5p0sjfqqn` and `check_errands` `tool_1901m5y4xvzmehzb4svfx7nw51em`, exactly as `voice_agent_spec.py elevenlabs` renders them from PR #145's head (`f65e997`); a tool listing after each showed exactly one. (3) `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`: the prompt (43,312 characters) and `tool_ids` (the 98 live ids unchanged and in order, plus the two new ones: 100).
- **The wording says the result waits under Tasks in the app,** not that Doddy sends a notification or that the user can close the app: push is off on the messaging server (`push: false` in its startup log on 27 Oct), so that promise could not be kept. PR #145 made the same change in `tools.json` and `instructions.md`. When APNs is set up, revert that commit to bring the notification wording back.
- **Prompt changes (six):** the `hand_over_errand` exception in "Always ask first (ASK-01)"; Task steps 3 to 7 (hand over, shopping, the fallback in the conversation, the result, the wrap-up); the two background-work paragraphs of "How you work a task" (the old ones said Doddy can't work after the conversation and that there is no result card); the Rome example; a new "Tasks you are working on" section with `{{errands}}` after "Learned context"; and the "cannot do" bullet about coming back by yourself. Nothing else in the prompt was touched. The live prompt differs from `instructions.md` in wording elsewhere, so it was edited in place, not replaced.
- **Checked, by script, on a full read-back:** the prompt is the intended one character for character; `tool_ids` are the old list plus the two new ids; the placeholders are the old twelve plus `errands`; both tools' descriptions, timeouts and speak-first settings equal the spec; no other setting of the agent changed (model, temperature, timezone, backup models, voice and turn settings).
- **Not checked:** a real conversation. An app build from before #122 doesn't answer these tools, and one from before 24 Oct ignores the shopping fields. `ERRANDS_ENABLED=1` and `SERPER_API_KEY` are set on `doddy-messaging` (27 Oct); push is not, and the service runs on Render's free plan, which sleeps.

**Applied to the live agent 25 Oct 2026, about 05:05 UTC (ADR-609, leaflets by voice; owner: "add", to the question "add the `find_deals` voice tool to the live voice agent, exactly as in `voice-agent/tools.json`").**
- **Read first, and again right before saving:** `agtvrsn_9201m5q7ka50e5gbbrg1cftrt2zk`, 98 tools, model `gpt-6-luna`; unchanged between the two reads. **Rollback:** `agtvrsn_9201m5q7ka50e5gbbrg1cftrt2zk`.
- **Created:** `find_deals` `tool_9201m5rpyjhfe2kv0yd5xbbfk6k3`, exactly as `voice_agent_spec.py elevenlabs` renders it from the default branch at `3e678c8` (client tool, 90 s, speak first). A tool listing first showed no `find_deals` existed.
- **Saved:** `agtvrsn_2301m5rpzz0aeh7aymyth609bgpd`, `tool_ids` only: the 98 live ids unchanged and in order, plus the new one (99). No prompt, model or other setting was sent; the save's read-back shows the prompt with its translator and Apple Health sections, `gpt-6-luna`, temperature 0.5, timezone Europe/Warsaw and the backup LLM order as they were. The prompt was not re-diffed byte for byte.
- **The prompt was not changed:** the tool's description carries its own instructions (ask first, say only what the result says, never read links), as for the stopwatch tools.
- **Still `not_synced`:** `hand_over_errand`'s shopping fields (kind, priorities). Errands are off on the server (`ERRANDS_ENABLED=0`), so they wait.
- **Not checked:** a real conversation. Leaflets need `DEALS_ENABLED=1` on `doddy-messaging` (set and deployed 25 Oct) and an app build with shopping stage 1 (24 Oct or later); an older build answers that it doesn't support the tool.

**Applied to the live agent 25 Oct 2026, about 07:15 UTC (ADR-626, asking for a training plan by voice; owner: "ok zmien", then "Tak, dodaj dokładnie ten tekst" to the exact tool text shown in the session).**
- **Read first, and again right before saving:** `agtvrsn_2301m5rpzz0aeh7aymyth609bgpd`, 99 tools, model `gpt-6-luna`; unchanged between the two reads. **Rollback:** `agtvrsn_2301m5rpzz0aeh7aymyth609bgpd`.
- **Created:** `open_training_plan` `tool_3101m5ry8754fmfb0ne7nf4nzhfd`, exactly as `voice_agent_spec.py elevenlabs` renders it (client tool, 90 s, speak first). A tool listing first showed no tool of that name existed.
- **Saved:** `agtvrsn_8001m5ry9by6feyajtpxbdt3xrxp`, `tool_ids` only: the 99 live ids unchanged and in order, plus the new one (100). No prompt, model or other setting was sent; the save's read-back shows the prompt as it was (its "## Apple Health" and "## Camera" sections included), `gpt-6-luna`, temperature 0.5, timezone Europe/Warsaw and the same backup LLM order. The prompt was not re-diffed byte for byte.
- **The prompt was not changed:** the tool's description carries its own instructions (a card and a tap, never ask about health, injuries, age or medicines, never describe a plan, a doctor or physiotherapist first for pain or a condition), as for `find_deals` and the stopwatch tools.
- **Not checked:** a real conversation. Only an app build with step 5 can run the tool; an older build answers that it doesn't support it. Until that build is installed, the voice may offer a plan it cannot open.

**Applied to the live agent 24 Oct 2026, about 15:05 UTC (ADR-651 `ring`, ADR-652 the stopwatch; owner: "2 tak", then "zrób to zgadzam się" after the safety check had refused the write three times; it passed once the session's permission mode was changed).**
- **Read first:** `agtvrsn_2801m5pzdaxpepgax0wwfawyc8tp` (94 tools, prompt without Apple Health). Read again right before the `tool_ids` save: `agtvrsn_4701m5q787a7e9kvp21qvjza63t0`, 95 tools: in between, another session had added `read_health_week` (`tool_3001m5q73js3f5stcnshpx4d13f6`) and an "## Apple Health" prompt section. Kept as found. **Rollback to just before this change:** `agtvrsn_4701m5q787a7e9kvp21qvjza63t0`.
- **Created**, each exactly as `voice_agent_spec.py elevenlabs` renders it: `start_stopwatch` `tool_7101m5q7d7ffexkrq2nj9sadhcxe`, `stop_stopwatch` `tool_5401m5q7e8hzf8daj1ret0qtw220`, `check_stopwatch` `tool_8601m5q7h4w8eed9kk304qrsfq53`. The first create of `check_stopwatch` timed out after 60 s; a tool listing showed it did not exist, so it was created once more (one tool, not two).
- **Changed:** `remind_me_about_note` (`tool_7401m4k84jjgf1ctk26vj03kextq`): the boolean `ring` parameter and the last sentence of the description, as in `tools.json`; every other field re-sent as read.
- **Saved:** `agtvrsn_9201m5q7ka50e5gbbrg1cftrt2zk`, `tool_ids` only: the 95 live ids unchanged and in order, plus the 3 new (98). No prompt, model or other setting was sent; the save's read-back shows `gpt-6-luna`, temperature 0.5, timezone Europe/Warsaw, the backup LLM order and the Apple Health prompt as they were. The prompt was not re-diffed byte for byte against `agtvrsn_4701…`.
- **The prompt was not changed for these tools:** it has no `remind_me_about_note` line, and each tool's description carries its own instructions; `added`, `changed` and `declined` are already in its result prefixes. The `instructions.md` stopwatch and `ring` lines stay spec-only (OpenAI voice reads them).
- **Not checked:** a real conversation. An app build without the stopwatch (anything before #139) answers that it doesn't support the tool, and Doddy says it isn't available yet.

**Superseded by the entry above. Was: not yet applied (24 Oct 2026, ADR-651; owner: "tak" to updating it):** `remind_me_about_note` (`tool_7401m4k84jjgf1ctk26vj03kextq`) gets the optional boolean `ring` and one sentence at the end of its description, exactly as in `tools.json`; the prompt's `remind_me_about_note` line gets the sentence in `instructions.md`. The live tool was read first and matched the spec before this change. The write was refused by this session's safety check, so nothing was changed. Until it is applied, the app's card switch turns ringing on.

**Superseded by the entry above (ADR-652): the three stopwatch tools are on the live agent since 24 Oct 2026.**

*(The live version since then is `agtvrsn_9201m5q7ka50e5gbbrg1cftrt2zk`, from the stopwatch entry above; it keeps `read_health_week`.)* **Applied to the live agent 24 Oct 2026, about 15:10 UTC (ADR-623; owner: "Jazda tak" to the exact text shown in the session):** `read_health_week` created as `tool_3001m5q73js3f5stcnshpx4d13f6`, exactly as `voice_agent_spec.py elevenlabs` renders it (client tool, 60 s, speak first). **Read first, just before saving:** `agtvrsn_2801m5pzdaxpepgax0wwfawyc8tp` (92 tools, model `gpt-6-luna`), unchanged since it was read for the proposal. **Saved:** `agtvrsn_4701m5q787a7e9kvp21qvjza63t0`, prompt and `tool_ids` in one save: the 92 ids unchanged and in order, plus the new one (93). **Prompt changes, in the live prompt's own style:** "Apple Health" added to the ASK-01 list of the user's own things, and a "## Apple Health" section after "## Steps" (ask first, say only the summary's numbers, rate briefly, compare with the week before, one change, not a doctor or coach, no jokes about health, red flags to a doctor and 112, "not allowed" points to Settings › Connections › Apple Health). **Checked after saving:** the prompt the save returned is the text sent, with both changes in place; the model, temperature, backup models and time zone are unchanged. The rest of the prompt was copied from the read text, not compared by a script. **Rollback:** `agtvrsn_2801m5pzdaxpepgax0wwfawyc8tp`. **Not checked:** a conversation using the tool; an app build without it answers that it doesn't support the tool. **Also found:** the live model is `gpt-6-luna` (OpenAI); `session.json` still says `gemini-3.5-flash`.
**Applied to the live agent 24 Oct 2026 (ADR-604, owner: "do both"):** `agent_tool_request` added to `conversation.client_events`, nothing else (no prompt, tool or model setting). The app's Dynamic Island and tool cards need that event. Version `agtvrsn_3801m5hyrqhee2ya90rh9hdat0m0` (rollback) → `agtvrsn_3501m5pk6ad9ed9v77hn049th27v`. Authentication stayed off.
**Applied to the live agent 2026-10-20 (ADR-548, owner: "raise, don't remove"):** `platform_settings.call_limits` only: daily limit 10 → 1,000, concurrency 2 → 10, bursting off. Version `agtvrsn_0201m5a37jq9f0rtzdf9hwpfewxq` (rollback) → `agtvrsn_9601m5cg7h2jf0ctpbggw15zzq4n`. No prompt, tool or model setting was sent. Read back: the limits, and the tool ids came back as a list (not diffed against the previous version). Authentication stayed off.
**The live prompt and tool list were not re-checked on 20 Oct.** The last version this folder records for them was read on 19 Oct; the ElevenLabs agent is the default voice now, so check the live version before relying on any `agtvrsn_` id in this file.
The app bundles `instructions.md`, `tools.json` and `session.json`, renders the prompt itself and sends it
with the tools in `session.update`; see `docs/implementation/VOICE_PROVIDER_TEST_STATUS.md`. A change here
reaches OpenAI with the next app build, and ElevenLabs only after the sync below.

## Source of truth and syncing

**Applied to the live agent 21 Oct 2026, 10:28 UTC (ADR-574, ADR-575; owner: "apply the live agent change"):** translator mode first, public lookups without asking, the weather and Wikipedia webhook tools re-attached (90 tools), and ten lookup tool descriptions saying "runs at once". Version `agtvrsn_8301m5ey4kc9e9cat0w22asdgctc` (rollback) → `agtvrsn_3101m5f03ak6e3wtdjfqbb2qs95e`, read back after saving. The live version had moved on since the draft (another save had added presentations, steps, photos and the camera tool), so the changes were merged into the live text, not pasted; those other sections aren't in `instructions.md`, so `compare` still reports the prompt as drift. The ADR-578 wording of `read_calendar`, `lookup_contact` and `upcoming_birthdays` ("Allow it on screen and I'll carry on") was sent on 22 Oct, after #119 merged. What was sent, the rollback and the checks: `docs/implementation/LIVE_AGENT_EDIT_2026-10-21.md`. At 10:53 UTC another session attached #118's `ask_claude` and `make_document` (`agtvrsn_4101m5f1gzv0edfat0kvfmmn1sd1`, 92 tools); their ids are now in `tools.json`. At 11:21 UTC, on the owner's choice, decks moved to Claude: `make_document` for any deck, `make_presentation` only for Keynote (`agtvrsn_1401m5f33kgffnrb4fq9dp4p3ket`).

**Applied to the live agent 2026-10-21, later (the Claude tools, ADR-564; owner: "yes, sync the Claude tools to the live agent too").**
- **Read first, just before saving:** `agtvrsn_3101m5f03ak6e3wtdjfqbb2qs95e` (90 tools). It is not the version recorded below: someone saved after it. Its prompt has the owner's public-lookups rule ("Exception, the owner's rule of 21 October 2026 …") and four older tools attached again (`geocode_place`, `get_weather`, `wikipedia_search`, `wikipedia_summary`). All of it was kept. Who saved it isn't recorded here. **Rollback to exactly that:** `agtvrsn_3101m5f03ak6e3wtdjfqbb2qs95e`.
- **Created:** `ask_claude` `tool_1601m5f15swpeetbygr32gwr4h5a` and `make_document` `tool_2101m5f15tckfy0v74g5gyaqm3td`, as `voice_agent_spec.py elevenlabs` renders them (client tools, 60 s, speak first).
- **Saved:** `agtvrsn_4101m5f1gzv0edfat0kvfmmn1sd1`, prompt and `tool_ids` in one save: the 90 ids unchanged and in order, plus the 2 new (92).
- **Prompt changes, in the live prompt's own style:** a "## Claude" section after "## Photos" (ask first, copy material in, keep the answer short, never read out a link), and "started" in the success prefixes with a line on what it means.
- **Not applied:** the `not_connected` / "a Connect button is on the user's screen" lines and "connecting turns its tools on" from `instructions.md` (ADR-563). They are a different change and need their own go-ahead.
- **Checked after saving:** the prompt the save returned equals the intended text character for character (SHA-256 `9a9f70db…`, 38,745 characters), and the tool list is the 90 plus the 2, in order. Model (`gpt-6-luna`), temperature, backup LLM, timezone and every other setting were not sent and came back as they were. The full agent document was not re-read and diffed leaf by leaf this time.
- **Not checked:** a real conversation with these tools. They also need `ANTHROPIC_API_KEY` on Render `doddy` and an app build from main (#118) or later; an older app build answers that it doesn't support the tool.

**Applied to the live agent 2026-10-21 (ADR-566 to 569; owner: "Ok", then "yes, create the tools and update the live agent").**
- **First attempt (about 01:30 UTC):** `make_presentation` was created (`tool_9601m5em00c3f66tbpag9f27kf4h`); creating the next tool was refused by Claude Code's permission check, so nothing on the agent changed then.
- **Created after the owner's go-ahead:** `read_steps` `tool_4601m5ewmkptekprzmx9vy9114eb`, `find_photos` `tool_0401m5ewmm8xems98kv871105z43`, `open_camera` `tool_3501m5ewmn09fmw9n8j15kx7x8n7`, each exactly as `voice_agent_spec.py elevenlabs` renders it.
- **Read first, just before saving:** `agtvrsn_6201m5ewm90bezjvesacr57ma1gv` (82 tools). Its prompt was **not** the 20 Oct text: shortly before, someone else had added a "sidekick" opening, "Polish is your default", a "# Talk or task: pick one every time" section and two "Unsupported capabilities" lines. Who saved it isn't recorded here; all of it was kept. **Rollback to exactly that:** `agtvrsn_6201m5ewm90bezjvesacr57ma1gv`.
- **Saved:** `agtvrsn_8301m5ey4kc9e9cat0w22asdgctc`, prompt and `tool_ids` in one save: the 82 ids unchanged and in order, plus the 4 new ones (86).
- **Prompt changes, in the live prompt's own style:** "## Presentations", "## Steps" and "## Photos" after "## BLIK transfers"; "## Camera" now calls `open_camera`, with the "Doddy Camera" Shortcut kept for older app builds (which answer that they don't support `open_camera`); "made" in the success prefixes; the "made", "not allowed" and "unavailable" result lines after "shown"; two "# Unsupported capabilities" lines (Keynote, Pages or Numbers; what is in the photos). The "## Access" section was left as it was: it already says "Allow it on screen and I'll carry on", which fits the permission sheet.
- **Checked after saving:** the full agent was read back. The prompt equals the intended text byte for byte (SHA-256 `c85c7a59…`). The tool list is the 82 plus the 4, and each new tool matches this folder's spec field by field. No existing tool and no other setting changed (compared leaf by leaf; tools by name).
- **Older app builds:** a build without these tools answers "The app does not support the tool below", and Doddy says it isn't available yet.
- **Not checked:** a real conversation with the new prompt.

**Applied to the live agent 2026-10-21, about 07:30 UTC (ADR-571, the sidekick's Talk and Task modes; owner: "1. Yes", then "Yes, save it" on the exact changes):** the live prompt is still the owner's own rewrite, so `instructions.md` wasn't copied in. 37 lines were added in its style and 2 reworded, nothing else changed:
- **Identity:** "You are their sidekick: sharp, always online, living in their phone", sprawy, "you can find the restaurant, you can't walk there".
- **Tone:** "Sharp, warm and direct. No filler. No apologising for being an AI." and "Honest always…".
- **Language:** "Polish is your default…"; "If language recognition is uncertain, ask briefly." became "If you can't tell which language the user is using, use Polish."
- **New "# Talk or task: pick one every time"** (Talk, Task, How you work a task, the Rome example) before "# Knowledge and research". It keeps ASK-01 for each look-up and says Doddy can't keep working after the conversation, because no app build has `hand_over_errand` yet (ADR-570).
- **Unsupported capabilities:** two lines (working after the conversation ends; booking).
- **Read first:** `agtvrsn_5201m5dtmpvne48vt1hxc6h53hh0` ("Configure localized language presets and terms for agent interface", saved 20 Oct 23:34 UTC by the owner's account; its prompt is the ADR-556 text, SHA-256 `b3030a46…`). Read again right before saving, after a worker restart: unchanged. **Rollback:** that version.
- **Saved:** `agtvrsn_6201m5ewm90bezjvesacr57ma1gv`. Only the prompt was sent.
- **Checked after saving:** the stored prompt equals the approved text byte for byte (SHA-256 `13521dd9…`); the 82 tool ids came back unchanged and match `tools.json`'s ids exactly; the LLM (`gpt-6-luna`) is unchanged. Not checked: a real conversation.
- **Next (ADR-570, `docs/implementation/ERRANDS.md`):** `hand_over_errand`, `check_errands` and `{{errands}}`. They go live only with an app build that answers those tools: then the two tools are created and attached, the placeholder `errands` = `none` is added, and the live Task lines change to hand work over. **Done on 27 Oct 2026** (the first entry above).

**Applied to the live agent 2026-10-20, about 14:08 UTC (ADR-556, Brand Guidelines V2.2; owner: "do it"):** the guide's verbal identity (pp.49–66). The live prompt is the owner's own rewrite, so this folder's new "# Who you are" and "# How you speak" were not copied in. Eleven short lines were added in the live prompt's own style, and nothing else in the prompt changed:
- **Identity:** what he says when asked what he is, and that he explains tools, permissions and data plainly when asked.
- **Personality:** no loyalty speeches, no manufactured closeness.
- **Tone and speaking style:** natural contractions and "the useful bit comes first"; three more "do not say" lines ("Unlock your full potential!", "Trust me, I always find a way.", "Anything you need, no limits."); "warmth without sugary reassurance".
- **Humour:** "a joke is optional, the answer must still stand without it"; "never make someone feel foolish for needing help".
- **Thinking together:** the kind-disagreement example. **Sensitive situations:** the opening line "That sounds difficult. What would be most useful right now?"
- **Tool results:** the plain receipt, "never 'All sorted!' without a result", and the unknown-outcome line. **Unsupported capabilities:** "I can help draft it, but I can't send it from here."
- **Placeholder:** `opening_line` is now "I'm here. What's up?"; the other eleven placeholders were re-sent exactly as read, because the API replaces the set.
- **Read first:** `agtvrsn_9601m5cg7h2jf0ctpbggw15zzq4n` (82 tools), read immediately before saving. It is not the 19 Oct version named in `STATUS.md`; whoever saved it later isn't recorded. **Rollback to exactly that:** `agtvrsn_9601m5cg7h2jf0ctpbggw15zzq4n`.
- **Saved:** `agtvrsn_0301m5ct85ywet5tp3hadj85gf5h` (the prompt), then `agtvrsn_8701m5ct8dxsf8htebwpdykppqbv` (the placeholder): the live version now.
- **Checked after saving:** both full agent documents were read back and compared leaf by leaf. Only the prompt, `opening_line` and the version id differ. The new prompt equals the intended text byte for byte (SHA-256 `b3030a46…`). The 82 tool ids are identical and in the same order. `first_message` is still `{{opening_line}}`. The language presets, voice, turn-taking, workflow and every other setting are unchanged.
- **Not checked:** a real conversation with the new prompt. The Polish and other language presets use the app's `opening_line`, so they follow the app build, which sends "Hi, I'm Doddy. What's on your mind?" for a first conversation and "I'm here. What's up?" after that.
- **Still different:** this folder's `instructions.md` wording and the live prompt differ, as before, so `compare` reports the whole prompt as drift. OpenAI Realtime reads `instructions.md` from the app build.

**Not yet applied (ADR-309, camera shortcut help):** one sentence in the "Opening the camera" line differs from the live prompt on purpose. In `instructions.md`, the "camera didn't open" sentence sends the user to "Don't have the shortcut?" on the camera card or to Settings, Connections, Shortcuts. The live prompt still has the ADR-291 sentence. Apply it once an app build with that card button ships; until then, the compare step reports this one sentence.

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

**Found on the live agent 2026-10-18 (ADR-441):** `note_capability_gap` exists and is attached (`tool_3801m4rntsxbf9yr0vf8r8jnf6n9`), with a newer description than this file's (it mentions `pay_for_page` and ASK-01, from another branch), and the live prompt has the `{{learned_context}}` section and the capability-gap line. Applied outside this branch; left as it is.

**Applied to the live agent 2026-10-18 (ADR-752 and ADR-754; owner: "update the voice agents"):** two client tools that wait for the app's answer (90 s): `text_me` (`tool_7901m57kexstfma8fsdzdxvjj9jc`) and `call_me_later` (`tool_6901m57key8nftdsvny3qd3n5kr7`), attached to agent `agent_0501m4et27vyeawrwqfdxxfszfa6`. The live prompt has its own structure (the owner's "Always ask first", ASK-01) and is far ahead of `instructions.md`, so it was not overwritten: only additions were merged, diffed before saving. A section "Texts and calls from Doddy's number" after "BLIK transfers" (the same rules as the `text_me` and `call_me_later` lines here), `delivered` and `booked` in the result prefixes with what each means, and two "Unsupported capabilities" lines narrowed ("Send text messages to anyone else…", "Make phone calls now or to anyone else…"). Version `agtvrsn_2801m57etpkkfhfbjvqt95nptfha` (rollback) → `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx`; the stored prompt and tool list were read back after saving. Not tried in a conversation yet. `compare` would report the whole ASK-01 prompt as drift, as before this change. **5 Nov 2026 (ADR-755):** this branch was merged with the default branch for review only. The live agent was not read or changed by that work: the tool ids above are what the 18 Oct session recorded, and the repository files now give both tools `ask: tap` (ASK-01), which the live tools may not have. Compare and sync only on the owner's separate instruction. The phone agent (`phone/`) doesn't exist in ElevenLabs yet: `setup-phone-agent.mjs` creates it from these files, U4's `{{doddy_call_opening}}`, `{{doddy_call_reason}}` and rule 6 included.

**Applied to the live agent 2026-10-22 (voice and personality block; owner: "applied to the live ElevenLabs agent", then "do it in a way so it works"):** the live `# Personality` and `# Tone and speaking style` sections now carry the owner's new wording (answer first, one sentence for simple requests, dry British humour, opinions when asked, stop once the answer is complete). The no-sarcasm list, ASK-01, translator mode, tools and guardrails are unchanged, and the Polish default stays (now "match the user's language when they switch"). The "detailed results on screen" line was left out because the app has no result card yet. Version `agtvrsn_1401m5f33kgffnrb4fq9dp4p3ket` (rollback) → `agtvrsn_3801m5hyrqhee2ya90rh9hdat0m0`; the stored prompt was read back after saving. `instructions.md` got the same wording in its own sections ("Who you are", "How you speak"); the live prompt is still the owner's longer rewrite, so `compare` still reports prompt drift. Not tested by voice call.

**Not yet applied to the live agent (22 Oct, owner: "Doddy speaks as she, not he"):** in Polish the live agent used feminine forms about itself ("żebym sprawdziła", "pomogła") on version `agtvrsn_3801m5hyrqhee2ya90rh9hdat0m0` (conversation `conv_2001m5j3cn5ye41r7hn41sh2vcak`, 17:25 Warsaw), because neither the live prompt nor this folder said which gender Doddy is. `instructions.md` now opens "Who you are" with a rule that Doddy is a he and always uses masculine forms in Polish and other gendered languages. The live prompt still needs the same sentence, on the owner's instruction (read the live prompt first and add the sentence; don't overwrite it). Run `compare` afterwards. Not tested by voice call.

**Applied to the live agent 2026-10-18 (ADR-510, BLIK transfers; owner: "sync it to ElevenLabs now"):**
- **Read first:** live version `agtvrsn_3501m5219zqke9tv2thaxz3m729t` (the rollback point), 61 tools. Its prompt is the owner's own rewrite (headings such as "# Identity", "# Tools", "# Tool results"), not this folder's `instructions.md`, so `compare` reports the whole prompt as drift. That is not from this change.
- **Tool:** `draft_blik_transfer` created as client tool `tool_5701m57c1717fmebcs14kbrjqmdq`, exactly as `voice_agent_spec.py elevenlabs` renders it, and attached as the 62nd tool. The other 61 ids are unchanged.
- **Prompt:** the owner's text is kept word for word. The `instructions.md` lines weren't copied in; three passages were added in the live prompt's own style:
  - a "## BLIK transfers" section after "## Email";
  - what a `"shown"` result means, after the `"opened"` line in "# Tool results";
  - "Send or pay money …" in "# Unsupported capabilities".
- **Version:** `agtvrsn_3501m5219zqke9tv2thaxz3m729t` → `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk`.
- **Checked after saving:** the full agent was read back. The prompt is byte for byte the intended merge, the tool list is the 61 plus the new one, and no other agent setting changed. The live tool matches this spec field by field.
- **Then `paid` removed** (owner: "yes, remove 'paid' from the live prompt"). It was in the live prompt's list of success prefixes, though no Doddy tool returns it, so Doddy could never read a result as a payment made.
  - **Version:** `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk` (rollback) → `agtvrsn_4301m57e2fxjfkb9fsc54tmjtyca`.
  - **Checked:** read back, that one line is the only change to the prompt, and the 62 tool ids are unchanged.
- **Correction (same day): that save overwrote the owner's ASK-01 sync, and it was restored.**
  - **What happened:** at 11:59 UTC another session (`claude/trusting-sagan-7lky84`, commit 43a94083) applied ASK-01 with the owner's yes, as `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4` (85 tools). The "paid" edit above had read the prompt before that, the worker restarted, and the save went out without reading the version again. So `agtvrsn_4301m57e2…` replaced ASK-01's prompt and tool list with the old ones. The 27 tool edits noted at the time were ASK-01's, not an unknown change.
  - **Restored** at the owner's choice: `agtvrsn_4301m57e2fxjfkb9fsc54tmjtyca` → `agtvrsn_2801m57etpkkfhfbjvqt95nptfha`. That is ASK-01's prompt with only its `paid` line removed, plus its 85 tools.
  - **Checked:** read back in full, the prompt is ASK-01's minus that line, the tool list and every embedded tool config equal `agtvrsn_6401…`'s, and no other setting differs. Rollback to ASK-01 exactly: `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4`.
  - **Rule for every live edit:** read the version immediately before saving, never from a read made before a pause or restart. This branch's `tools.json` doesn't have the ASK-01 tools; `claude/trusting-sagan-7lky84` does.

**Live agent changes after 18 Oct (read back from ElevenLabs on 19 Oct):**
- **18 Oct 13:41 UTC, from `claude/awesome-cray-2lb9ia` (commit `6672259f`):** `text_me` and `call_me_later` were attached, giving `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx` (87 tools). Those tools are not in this folder's `tools.json`, have no handler in the app on main and lack ASK-01's `x_doddy.ask`. The live prompt also gained a "## Texts and calls from Doddy's number" section.
- **19 Oct, owner: "remove" (ADR-544):** five tools the app can't run were detached: `upcoming_renewals` (`tool_8801m4p10mbbe2avb1a9ygw4vjky`), `add_to_diary` (`tool_8201m4p10nhsfdqayngyjt5g2pp7`), `pay_for_page` (`tool_1401m4rmxkm5eg3v87sphf87c45p`), `text_me` (`tool_7901m57kexstfma8fsdzdxvjj9jc`) and `call_me_later` (`tool_6901m57key8nftdsvny3qd3n5kr7`). Each was confirmed by id with `agents_get_tool` first; the version was re-read right before saving.
  - **Version:** `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx` (rollback) → `agtvrsn_8901m59m3bdqe6takgkfbcmfh2yh`, 82 tools. Only `tool_ids` changed; the prompt and model settings came back unchanged in the save's response.
  - **19 Oct, owner: "yes trim":** the prompt's "## Texts and calls from Doddy's number" section was removed, with the `delivered`/`booked` result lines and the `text_me`/`call_me_later` lines under "# Unsupported capabilities" (now "Send text messages yourself." and "Make phone calls."). Nothing else in the prompt changed; `tool_ids` were not sent and came back unchanged (82). Version `agtvrsn_8901m59m3bdqe6takgkfbcmfh2yh` → `agtvrsn_0201m5a37jq9f0rtzdf9hwpfewxq`. The live prompt still differs from this folder's `instructions.md` (it predates this note), so `compare` still reports drift.
  - The tools are detached, not deleted, and stay in the ElevenLabs workspace.

**Not yet applied to the live agent (2026-10-16):** `start_translator` now starts immediately after the user asks, with no confirmation card or forced pre-tool speech. The app still gives the AI-translator disclosure after starting and keeps microphone access subject to iOS permission. Read the live prompt and tools before syncing; preserve remote edits and compare the fetched configuration after saving.

Editing the agent in the ElevenLabs dashboard without updating these files is drift; the compare
step catches it. Each tool's `x_doddy.elevenlabs_tool_id` is its live id; a tool not yet on the live agent
says `not_synced`, and `check` fails on a missing id or on a phone tool no Swift source answers.

**State read on 2026-10-11 (old; newer reads are at the top of this file), version `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89`:** 43 tools, all with
their ids here. The dynamic-variable placeholders are recorded in `session.json` (`elevenlabs.placeholders`).
The history below lists each change applied and its rollback version.

**Applied to the live agent 2026-10-11 (voice-agent review and the C4 data markers; owner: "go ahead"):**
- **Read first:** live version `agtvrsn_9901m4nydc9qegk8npkv8jvprm90`. Its prompt was not this branch's `instructions.md`. It had the live camera sentence (ADR-291; the ADR-309 sentence here is still held back) and two passages from the unmerged `claude/hopeful-fermat-1a63x0` / `claude/lucid-johnson-pmwwg4` lines: "Nothing is asked up front…" and the declined/iPhone-allow sentence. It did not yet have those lines' `@Marta` search sentence, `upcoming_renewals` or `add_to_diary`.
- **Prompt:** only the 23 changed lines between `8ea86be` and this branch were merged into the live text (three-way merge). These are:
  - the `<<<DATA` markers and their rule (review C4);
  - the profile line;
  - undo, partly, "not added", created / not created, alarm not found or unreadable, and DEMO DATA.

  Everything else is as found. The other lines' passages were kept, and their unreleased lines were not added. The text sent was checked byte for byte against the merge result before saving.
- **Tool `geocode_place`** (`tool_5701m4f28p90fm186x0zhn54sy71`): the `language: pl` query constant was removed, and every other setting was kept as read.
- **Version:** `agtvrsn_9901m4nydc9qegk8npkv8jvprm90` (rollback) → `agtvrsn_4901m4p0dby0fj6sba6a04emb9b4`. The LLM, temperature and the 57 tool ids are unchanged (read back from the save). Tool updates don't create a version.
- **Read again 2026-10-12:** live is now `agtvrsn_5201m4p132brf30th15nggeqarf0` (59 tools). Another line added its own changes on top: `@Marta` search, `upcoming_renewals`, `add_to_diary`, the parcel-code note on `read_email`, and two tools. All 23 lines above are still there.
- **For the other lines:** when you next apply your prompt, start from this live version (or merge the default branch first). Otherwise these 23 lines are lost.
- **Phone agent (`phone/instructions.md`):** `save_note` statuses, `not_recognised`, and a missing tries count. These apply when `setup-phone-agent.mjs` first creates the agent; it doesn't exist yet.

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

**How the app really connects (ADR-265):** `VoiceSessionController` talks to a `LiveVoiceLink`
(`DoddyApp/Features/Voice/LiveVoiceLink.swift`). The ElevenLabs SDK's `Conversation` conforms to it
with small shims; it was the only one after `OpenAIRealtimeSession` was removed (9 Nov 2026). No app type implements
`RealtimeVoiceSession`, the app doesn't use `RealtimeConversationState`, and there is no
`ElevenLabsRealtimeSession`. The table below is the mapping such an adapter would use; it isn't built.

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

## OpenAI Realtime: what was built (ADR-265). Removed 9 Nov 2026; history only

1. **Built:** a token server that mints short-lived client secrets (`server/voice-token`; the API key never ships in the app).
2. **Built, for testing:** `OpenAIRealtimeSession` in the app: a WebSocket to OpenAI (not WebRTC). The app
   builds `session.update` itself (`OpenAIRealtimeWire.sessionUpdate`) from the bundled files, with the
   instructions rendered on the phone. Not yet heard on a device (`session.json`, `openai_realtime.status`).
3. **Not built:** the four `web` tools (weather, Wikipedia) don't run on OpenAI, because OpenAI sends every
   function call to the client. The app answers them as unavailable and Doddy says so. Running them would
   mean the app or the token server making those requests (`x_doddy.http`).
4. **Done:** the token server picks the voice (`OPENAI_REALTIME_VOICE`, default `marin`). OpenAI has preset
   voices only; Doddy's ElevenLabs voice does not carry over.
5. **Not done:** a bake-off on the same Polish/English phrases (latency, interruptions, cost).

## Speed settings (2026-10-09)

| Setting | Before | Now | Why |
|---|---|---|---|
| Turn eagerness | normal | **eager** | Replies sooner after the user pauses (≈ Realtime `semantic_vad` eagerness high). May cut in on long pauses. |
| Speculative turn | on | on | Starts the reply before the turn is certain. |
| Reasoning / thinking budget | — | — | Not supported for `gemini-3.5-flash` (ElevenLabs rejects the setting). |
| Background voice detection | off | **on** | A video playing nearby was transcribed as one endless user turn, so Doddy never got to reply (conversation conv_6101m4g87cmjefgvjek1gdpxvqmp). Filters voices that are not the user. |
| Voice model | eleven_v4_turbo | unchanged | Changing it changes how the chosen voice sounds; compare on device first. |

## Phone agent (`phone/`, S2)

`voice-agent/phone/` defines the separate ElevenLabs agent **"Doddy (phone)"** that answers and
places phone calls through the Twilio number (ADR-152, ADR-172). Same three files, same rules:

| File | What it is |
|---|---|
| `phone/instructions.md` | The phone prompt, with `{{doddy_caller}}`, `{{doddy_direction}}`, `{{doddy_memory}}`, `{{doddy_pin}}`, `{{doddy_call_reason}}` filled by the messaging server through register-call; the first message is `{{doddy_call_opening}}` (ADR-754) |
| `phone/tools.json` | `verify_pin`, `search_memories`, `save_note`: webhooks to `server/messaging`. Instead of a fixed url they give `x_doddy.http.base` (the `PUBLIC_BASE_URL` env name), a `path_template` and `body` parameters; headers reference the workspace secret `doddy_tool_secret` and the secret variable `secret__doddy_session` |
| `phone/session.json` | First message, LLM, privacy (no audio recording, 30-day transcripts), placeholders; the server passes the variables with `register-call` (ADR-750), so there is no call-start webhook |

- Check: `python3 -I scripts/voice_agent_spec.py check --agent phone` (in `scripts/ci.sh`).
- Create the agent: `server/messaging/scripts/setup-phone-agent.mjs` reads these files; `--dry-run` prints every request.
- **Voice: not set (decision needed).** Neither `phone/session.json` nor the setup script sets a TTS model or voice, and `languages` is only `en`. ElevenLabs therefore uses its default for an English agent. The prompt says to answer Polish callers in Polish, but whether that voice speaks Polish hasn't been checked. Before the first real call, choose a multilingual TTS model, or add a `pl` preset, and record it in `phone/session.json`.
- Drift: export the live phone agent's prompt and tools as above and run `voice_agent_spec.py compare EXPORT.json --agent phone`.
- Status: **not created yet** (needs the deployed messaging server, a Twilio number and the owner's go-ahead). An older status note (24 Oct, branch `claude/phone-agent-pl-en`, since deleted) said a phone agent already existed in ElevenLabs with no number. List the workspace's agents (read only) before running the setup script, so a second one isn't made.

## Task-call agent (`task-call/`, ADR-500)

`voice-agent/task-call/` defines the separate ElevenLabs agent **"Doddy (calls for you)"**: it phones a business for the user and asks one question the user approved, in Polish.

- **Tools:** none of its own, only the `end_call` and `voicemail_detection` system tools. It can't look anything up or act.
- **Variables:** the first message is `{{doddy_opening_line}}` (the AI disclosure and the question), built by the server from the approved brief, like the other `doddy_*` variables (`server/messaging/src/taskCalls/payload.ts`).
- **Settings (`task-call/session.json`):** Polish only, phone audio (`ulaw_8000`), no audio recording, transcripts kept one day as a backstop, authentication on, at most 330 s.
- **Check:** `python3 -I scripts/voice_agent_spec.py check --agent task-call` (in `scripts/ci.sh`). It also checks that the server's copy, `server/messaging/src/taskCalls/agentSpec.ts`, matches this folder. The server refuses to call while the live agent differs from it.
- **Create:** `server/messaging/scripts/setup-task-call-agent.mjs` (`--dry-run` prints the request). It needs a Polish voice id in `TASK_CALL_VOICE_ID`; `session.json` holds only a placeholder.
- **Status: not created yet.** The owner's steps are in `docs/decisions/calls.md` and `docs/implementation/CALL_CASES_STATUS.md`.

## Changes to the live main agent, 11 and 18 Oct 2026 (rounds 4 to 6, ASK-01)

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

**Applied to the live agent 2026-10-18 (ASK-01, ADR-483 to ADR-489; the owner said yes to the exact diff).**
- **Re-read first:** version `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk` (62 tools), read again right before writing. Its prompt is the owner's dashboard DODDY persona prompt, not `instructions.md`, so this round edited that text in place instead of replacing it. It also carries a "BLIK transfers" section and `draft_blik_transfer` from another session; both are kept.
- **Prompt:** a new "Always ask first (ASK-01)" section; "Approval cards" now has no exceptions (translator and lists ask too); the Wikipedia and weather lines became `web_search`, `news_search` and `find_places`; lines for the Google and Outlook calendar tools, `rename_todoist_task` and the email send/reply/forward/bin tools; the `sent`, `replied`, `forwarded`, `trashed` and `answered` prefixes; "Delete anything for good" added to what Doddy can't do; one ASK-01 guardrail. The "## Approval cards" heading lost its trailing space.
- **Updated in place (27):** the read tools, lists, translator, `parking_spot`, `search_memories` and `note_capability_gap` got the ASK-01 descriptions, `pre_tool_speech: force` and a 60 s timeout (90 s for `start_translator`). The two live-only lines (`@Marta` on `search_memories`, `pay_for_page` on `note_capability_gap`) were merged into `tools.json` first, so they stay.
- **New client tools (27):** ids are in `tools.json` (`x_doddy.elevenlabs_tool_id`).
- **Detached, not deleted:** `geocode_place`, `get_weather`, `wikipedia_search`, `wikipedia_summary`; the app can't ask before ElevenLabs runs them.
- **Left as they are (live-only):** `draft_blik_transfer`, `pay_for_page`, `add_to_diary`, `upcoming_renewals`. They don't ask in the app's code; they need the owner's decision.
- **Version:** `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk` → `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4`, 85 tools. The stored prompt and tool list were read back and match the approved text exactly; no other agent setting changed. All 81 spec tools were compared with the live tools (description, parameters, timeout, speak-before): no differences. Rollback: the first version.
- **Mixed versions:** an installed app from before ASK-01 doesn't show the read cards and answers "unsupported" to the 27 new tools. The app side is written but not built (needs a Mac): BLOCKED / NOT RUN.

## 24 Oct 2026: translator without asking (ADR-619), live
- `start_translator` and `stop_translator` updated on the live agent (descriptions: start or stop at once, then ask what to translate; `pre_tool_speech` auto).
- The prompt saved with four in-place translator edits after the owner's "Rób dalej": `agtvrsn_3501m5pk6ad9ed9v77hn049th27v` (rollback) → `agtvrsn_2801m5pzdaxpepgax0wwfawyc8tp`, read back byte for byte, 92 tools unchanged. Exact text: `docs/implementation/LIVE_AGENT_EDIT_2026-10-24.md`.

## Live agent change, 10 Nov 2026: screen look and timers
**Owner's yes** ("Tak", 10 Nov 2026) to adding `look_at_screen` and the five timer tools. **Read first, right before attaching:** `agtvrsn_7801m72q3h4te4r87vq8xm1m3fyr`, 109 tools, `gpt-6-luna`, temperature 0.7, reasoning none, Europe/Warsaw. **Rollback:** that version. **Done:** six client tools created exactly as `voice_agent_spec.py elevenlabs` renders them (`look_at_screen` `tool_9001m73dt7v2fdc9kn3qtzd6nx9r`, `start_focus` `tool_0101m73dt87yfpp8mfemhhfrvc8z`, `stop_focus` `tool_3801m73dv4pxe3z9dde443s203zr`, `check_focus` `tool_4301m73dv5f1eaevnwkj1q8ra8tg`, `start_wind_down` `tool_5001m73dv5xjeyp8cb9pvn69p34r`, `stop_wind_down` `tool_6101m73dv6gkfkcab7xxmr7jkpw7`), attached to the main branch and published as `agtvrsn_5101m73dwr02eqc9q36eanbyjz2k` (115 tools). **Read back:** the model, temperature, reasoning effort, timezone, backup LLM and turn settings are unchanged; the prompt is still 24,162 characters (it was not sent). The ids are now in `tools.json`. **Not checked:** a real conversation using any of the six; builds without the matching app handlers (every build before #319 and #301's app) answer that the app doesn't support the tool.

## Live agent change, 10 Nov 2026: one file tool, with clarifying questions
**Owner's yes** ("zrób update agenta", 10 Nov 2026). **Read first, right before:** `agtvrsn_5101m73dwr02eqc9q36eanbyjz2k`, 115 tools, `gpt-6-luna`, temperature 0.7, reasoning none. **Done:** (1) `make_document` (`tool_2101m5f15tckfy0v74g5gyaqm3td`) got the description in `tools.json` (ask at most two short questions, `need_details`, one file tool for decks, Word, Excel, PDF and text); a tool edit is live at once and makes no version. Parameters unchanged. (2) `make_presentation` (`tool_9601m5em00c3f66tbpag9f27kf4h`, the phone-made deck) was detached from the main branch (the tool is kept) and published as `agtvrsn_9701m73p1qa2enntd72ahjr3p3nz` (114 tools). **Read back:** model, temperature, reasoning effort, backup LLM and turn settings unchanged; prompt still 24,162 characters (not sent). **Rollback:** reattach `make_presentation` and publish (previous version `agtvrsn_5101m73dwr02eqc9q36eanbyjz2k`), and put the old `make_document` description back:

> Use for any deck, slides or presentation unless the user asks for Keynote by name (then make_presentation), and for Word, Excel, PDF or long text. Claude makes a finished file with its own skills: deck (PowerPoint), doc (Word), spreadsheet (Excel), PDF, or text (blog post, article, speech or long email, as Markdown). If the user didn't say, ask for the title and what it should cover in one short question. Pass material copied from this conversation when the user refers to it. For a report, guide or list about real places, products, events or facts, run web_search first and pass what it returned as material; never make it from memory alone. It takes one to three minutes in the background; the result starts with 'started:', a card with Open and Share is on screen at once, and the file also arrives as Doddy's message in Messages, where Share saves it to Files or sends it on. Say so in one sentence, e.g. 'Robię, za minutę lub dwie będzie w Wiadomościach.' Never read out a link. ASK-01 read: one short line saying what you'll ask Claude to do, then wait for yes/tap; "declined" = nothing was sent, say so.

**Not checked:** a real conversation. Until `doddy` is deployed with #322 the server never answers `need_details`; the agent's own questions work without it. `make_presentation` stays in `tools.json` (the app still handles it in Debug builds, where the beta scope shows everything).
