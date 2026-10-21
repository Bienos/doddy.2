# Doddy voice agent — spec in OpenAI Realtime shape

Owner decision 2026-10-09 (ADR-058): Doddy runs on **ElevenLabs Agents**, but everything that
defines Doddy is kept here in **OpenAI Realtime** form, so moving to OpenAI Realtime later means
adding one adapter, not rewriting the app or the agent.

| File | What it is | ElevenLabs today | OpenAI Realtime later |
|---|---|---|---|
| `instructions.md` | Doddy's system prompt with `{{placeholders}}` | Agent prompt; placeholders are dynamic variables the app passes at `startConversation` | `session.instructions`, rendered on the phone by `RealtimeInstructions.render` |
| `tools.json` | 10 function tools (`type`, `name`, `description`, `parameters`) + `x_doddy` | Client tools (`runs_on: phone`) and webhook tools (`runs_on: web`) | `session.tools` (drop `x_doddy`); every call comes to the app |
| `session.json` | First message, languages, variables, turn-taking, per-provider settings | Agent settings | `session.update` body |

**OpenAI Realtime voice (ADR-265; a choice in the voice picker, not the default: ElevenLabs is, ADR-546):** the picker runs these same files on OpenAI Realtime (`gpt-realtime-2.1` or `gpt-realtime-2.1-mini`, picked in the picker).
**Applied to the live agent 2026-10-20 (ADR-548, owner: "raise, don't remove"):** `platform_settings.call_limits` only: daily limit 10 → 1,000, concurrency 2 → 10, bursting off. Version `agtvrsn_0201m5a37jq9f0rtzdf9hwpfewxq` (rollback) → `agtvrsn_9601m5cg7h2jf0ctpbggw15zzq4n`. No prompt, tool or model setting was sent. Read back: the limits, and the tool ids came back as a list (not diffed against the previous version). Authentication stayed off.
**The live prompt and tool list were not re-checked on 20 Oct.** The last version this folder records for them was read on 19 Oct; the ElevenLabs agent is the default voice now, so check the live version before relying on any `agtvrsn_` id in this file.
The app bundles `instructions.md`, `tools.json` and `session.json`, renders the prompt itself and sends it
with the tools in `session.update`; see `docs/implementation/VOICE_PROVIDER_TEST_STATUS.md`. A change here
reaches OpenAI with the next app build, and ElevenLabs only after the sync below.

## Source of truth and syncing

**Applied to the live agent 21 Oct 2026, 10:28 UTC (ADR-566, ADR-567; owner: "apply the live agent change"):** translator mode first, public lookups without asking, the weather and Wikipedia webhook tools re-attached (90 tools), and ten lookup tool descriptions saying "runs at once". Version `agtvrsn_8301m5ey4kc9e9cat0w22asdgctc` (rollback) → `agtvrsn_3101m5f03ak6e3wtdjfqbb2qs95e`, read back after saving. The live version had moved on since the draft (another save had added presentations, steps, photos and the camera tool), so the changes were merged into the live text, not pasted; those other sections aren't in `instructions.md`, so `compare` still reports the prompt as drift. Not sent yet: the ADR-570 wording of `read_calendar`, `lookup_contact` and `upcoming_birthdays`, which waits for an app build with the Allow card. What was sent, the rollback and the checks: `docs/implementation/LIVE_AGENT_EDIT_2026-10-21.md`. At 10:53 UTC another session attached #118's `ask_claude` and `make_document` (`agtvrsn_4101m5f1gzv0edfat0kvfmmn1sd1`, 92 tools); their ids are now in `tools.json`. At 11:21 UTC, on the owner's choice, decks moved to Claude: `make_document` for any deck, `make_presentation` only for Keynote (`agtvrsn_1401m5f33kgffnrb4fq9dp4p3ket`).


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

**Not yet applied to the live agent (ADR-441, 2026-10-11):** this repository now has the `note_capability_gap` tool, the `{{learned_context}}` variable (declared in `session.json`) and two paragraphs in `instructions.md` (what Doddy learned, and when to note a gap). Until the owner applies them (the live prompt is ahead of `instructions.md`, so merge the two paragraphs rather than overwriting it), the app already sends the variable, which the live prompt ignores, and Doddy never calls the new tool. Run `compare` afterwards.

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

**Current state (read 2026-10-11, version `agtvrsn_8701m4nqkm9sezbaqxeyddwrey89`):** 43 tools, all with
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

**Applied to the live agent 2026-10-18 (ASK-01, ADR-483 to ADR-489; the owner said yes to the exact diff).**
- **Re-read first:** version `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk` (62 tools), read again right before writing. Its prompt is the owner's dashboard DODDY persona prompt, not `instructions.md`, so this round edited that text in place instead of replacing it. It also carries a "BLIK transfers" section and `draft_blik_transfer` from another session; both are kept.
- **Prompt:** a new "Always ask first (ASK-01)" section; "Approval cards" now has no exceptions (translator and lists ask too); the Wikipedia and weather lines became `web_search`, `news_search` and `find_places`; lines for the Google and Outlook calendar tools, `rename_todoist_task` and the email send/reply/forward/bin tools; the `sent`, `replied`, `forwarded`, `trashed` and `answered` prefixes; "Delete anything for good" added to what Doddy can't do; one ASK-01 guardrail. The "## Approval cards" heading lost its trailing space.
- **Updated in place (27):** the read tools, lists, translator, `parking_spot`, `search_memories` and `note_capability_gap` got the ASK-01 descriptions, `pre_tool_speech: force` and a 60 s timeout (90 s for `start_translator`). The two live-only lines (`@Marta` on `search_memories`, `pay_for_page` on `note_capability_gap`) were merged into `tools.json` first, so they stay.
- **New client tools (27):** ids are in `tools.json` (`x_doddy.elevenlabs_tool_id`).
- **Detached, not deleted:** `geocode_place`, `get_weather`, `wikipedia_search`, `wikipedia_summary`; the app can't ask before ElevenLabs runs them.
- **Left as they are (live-only):** `draft_blik_transfer`, `pay_for_page`, `add_to_diary`, `upcoming_renewals`. They don't ask in the app's code; they need the owner's decision.
- **Version:** `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk` → `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4`, 85 tools. The stored prompt and tool list were read back and match the approved text exactly; no other agent setting changed. All 81 spec tools were compared with the live tools (description, parameters, timeout, speak-before): no differences. Rollback: the first version.
- **Mixed versions:** an installed app from before ASK-01 doesn't show the read cards and answers "unsupported" to the 27 new tools. The app side is written but not built (needs a Mac): BLOCKED / NOT RUN.
