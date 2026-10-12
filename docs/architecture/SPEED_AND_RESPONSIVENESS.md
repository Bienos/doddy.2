# Speed and responsiveness — making Doddy fast without making him dumb (proposal)

Status: **PROPOSAL; only the agent-setting quick wins and the prompt diet listed under Progress are applied, nothing in the app or backend is built.** Written 2026-10-12 from (1) a read of the code at `ce02763`, (2) real per-turn timings that ElevenLabs recorded for three of the owner's own voice conversations, and (3) current public guidance on voice-agent latency (sources in §9). Every change below needs the owner's go-ahead; Phase 3 is a new milestone in the sense of `CLAUDE.md` rule 6 (cloud AI changes need milestone approval). An ADR number is assigned when a part is approved.

**Progress (2026-10-12, owner: "ok do the quick wins in the agent settings first"):**
- **Applied to the live ElevenLabs agent:** 1.4, the filler after 2 s and forced pre-tool speech with a typing sound on the 10 slow online tools. 1.1, the model moved from `gemini-3.5-flash` to `gemini-3.6-flash` with minimal reasoning, chosen by a branch bake-off with 13 quality tests.
- **Applied to the live agent, part of 1.2 (owner: "ok go ahead with the prompt diet"):** `instructions.md` rewritten from 29.7k to 11.3k characters, and `recent_conversations` taken out of the prompt. Tool rules now live only in each tool's description. Per-turn prompt in the tests went from 29.1k to 23.9k tokens, with the same test score.
- **Where the details are:** versions, rollback points, test ids and results are in `voice-agent/README.md` (the two 2026-10-12 entries).
- **Not measured yet:** the real-conversation first-token time after these changes. Read it from the next real conversations.
- **Not done from 1.2:** the ≤ 8k-token target. About 17k tokens of every turn are now the tool definitions, so shortening tool descriptions (rest of 1.2) and loading fewer tools (1.3) are the next steps. Capping notes and `saved_lists` is also not done. The app still sends `recent_conversations` although the prompt no longer reads it; stopping that, and renaming the Settings switch "Remember recent conversations", are app changes.
- **Not started:** 1.3 fewer tools, 1.5 merged tools, 1.6 `available_tools`, 1.7 warm backend, and Phases 2–4.

**One-line answer:** Doddy is slow mainly because every turn sends a ~15–28k-token prompt to a reasoning model that thinks before it speaks, and because answers that need a tool cost one extra model round trip per tool. Speech recognition, the voice and the tools themselves are already fast. The fix is a **fast talker, careful doer** design: a small, lean voice layer that always answers within about a second, and a separate "brain" that does slow, clever work in the background and reports back — plus a shorter path from tap to listening.

---

## 1. What we measured (real numbers, not estimates)

Source: ElevenLabs conversation API, `conversation_turn_metrics` for agent `agent_0501m4et27vyeawrwqfdxxfszfa6`, read-only, 2026-10-12. Conversations `conv_3801m4kw9amqegparpythx8mwzmb` and `conv_8501m4kswj8gf2m9eq49cetgasep` (2026-10-10, prompt ≈ 14–16k tokens per call) and `conv_6801m4pat99qf00ramenb5atazar` (2026-10-11, prompt ≈ 28k tokens per call). All three are Polish, `swift_sdk`, public-agent mode (no token-server hop). Transcript content is deliberately not reproduced here.

| Stage | Measured | What good looks like (§9) | Verdict |
|---|---|---|---|
| End of user speech → first Doddy audio, **no tool** (`convai_ttf_audio_since_silence`, n=15) | median **1.45 s**, range 1.13–4.09 s | P50 < 0.8 s, P95 < 1.5 s | Too slow, ~2× target |
| Same, when a **tool** ran before Doddy spoke (n=4) | **2.8 – 6.0 s** | first sound < 1 s, then the result | Too slow; silence feels broken |
| LLM time to first token (`convai_llm_service_ttfb`) at ~15k-token prompt | median **0.80–0.87 s** | 0.25 s P50, 0.6 s P95 | Biggest single cost |
| Same at ~28k-token prompt (2026-10-11) | median **1.25 s**, up to 2.06 s | | Prompt growth made it ~45% slower in one day |
| One turn served by the backup model `gemini-2.5-flash` (`llm_override`) | 3.04 s | | Fallback is slower, not faster |
| Model "reasoned" before answering | `reasoned: true` on almost every turn | non-thinking or minimal thinking for live voice | Thinking is on and cannot be set for `gemini-3.5-flash` on ElevenLabs (`voice-agent/README.md`, speed settings) |
| Endpointing (`convai_turn_silence_before_initiation`) | 0.16–0.32 s typical, up to 0.96 s | 0.12–0.28 s | Already good (eager + speculative turn) |
| Speech recognition tail (Scribe v2 Realtime) | 0.02–0.05 s | 0.06–0.15 s | Excellent |
| Voice first byte (eleven_v4_turbo) | 0.07–0.15 s (one 0.54 s) | 0.11–0.22 s | Excellent |
| Tool execution itself (phone tools, Wikipedia webhooks) | 0.09–0.24 s | | Excellent — the **model hops around tools** are the cost, not the tools |
| A 4-tool answer (Wikipedia search → web search → summary → search) | 4 × ~0.8 s of model time + 0.75 s of tools → 5.2 s silence | | Chained tools multiply latency |
| Cost | ~$0.08–0.13 per minute, LLM ≈ 75% of it | | Large prompt makes it expensive too |

Two ease-of-use findings from the same data (not latency, but they make Doddy feel slow and clumsy):

- **The confirm card fights the conversation.** In `conv_6801…` the user spoke while a save card was waiting; ElevenLabs abandoned the tool call ("Tool execution was abandoned due to user input"), the retry then failed with "Another item is waiting for the user's answer", and the save never happened.
- **Wasted tool hops.** The live agent offered tools the installed app could not run (`add_to_list` "not supported", `web_search` "online accounts aren't set up"). Each failed hop cost ~1 s of model time and an apology.

Not measured (no instrumentation exists yet, §4.1): the time from tap / Back Tap / "Hey Doddy" to Doddy listening.

## 2. Where the time goes in the code

From the code audit at `ce02763` (file references are to that commit):

**A. Before the conversation starts** — all steps run one after another:
1. "Listen on open" (on by default, `OpeningModel.swift:15`) starts only **after the 2.40 s opening scene** finishes (`OpeningScene.swift:268`, `OpeningModel.finish()`), or 400 ms after Home appears without the scene.
2. `VoiceSessionController.start()` then: microphone check → `await store.reload()` (five database reads including photos, audio and corrections that voice never uses) → builds the prompt text on the main thread → learned context → token fetch (token-server mode: new ephemeral `URLSession` per fetch, `VoiceTokenClient.swift:36`) → audio session → `ElevenLabs.startConversation` (`VoiceSessionController.swift:386–509`). Nothing is prefetched or done in parallel.

**B. Every single turn** sends the whole prompt again:
- `voice-agent/instructions.md`: 29.8k characters ≈ 7.4k tokens.
- `voice-agent/tools.json`: 57 live tools, schemas ≈ 17k tokens.
- Dynamic variables up to ≈ 5k tokens: saved notes (6,000 chars), **last 10 conversations** (4,000 chars — in the measured sessions mostly greetings and silences), lists (no cap), profile, personality, learned context.
- ElevenLabs' own guidance: prompts over 2,000 tokens increase latency and cost. Doddy sends 15–28k.

**C. Tools**
- The prompt requires chains (geocode → weather, Wikipedia search → summary, read calendar before changing it). Each link is a full model round trip.
- No `tool_call_sound`, soft-timeout filler is **off** (`soft_timeout_config.timeout_seconds: -1` on the live agent), no async tools.
- Online tools go phone → Render **free** backend (sleeps after 15 min idle, ~1 min to wake per Render's docs; the app gives up after 20 s, `URLSessionTransport.swift:25`). Four Composio tools make two Composio calls in a row (worst case ≈ 40 s). Web search via Monid: p50 ≈ 7 s, p95 ≈ 17 s (comment in `backend/src/tools/websearch.ts`).

**D. Typed Ask** (`gateway/`) is not streamed, waits for the full answer (up to 800 tokens) and does up to four sequential rate-limit calls first.

## 3. Design principles

1. **Doddy always makes a sound or a visible reaction within ~1 s.** Even when the real answer takes longer, the user hears "Let me check your calendar…" or a short earcon, never silence.
2. **Cleverness moves off the critical path, it is not removed.** Quick conversational turns use a fast model with a small prompt. Hard, multi-step or slow work is handed to a background thinker that may take 5–30 s and reports back.
3. **Context on demand, not stuffed.** The voice prompt carries only what nearly every turn needs. Notes, past conversations and rarely used tools are fetched when asked for.
4. **Fewer, smarter tools.** One tool call should do what today takes a chain of three.
5. **Prepare before the user asks.** Connect while the opening animation plays; build the morning briefing before the morning.
6. **Measure every change.** A latency number goes with every agent version, and nothing ships that makes P50 or P95 worse.
7. **Trust rules stay in code.** Approval cards, payload-bound approvals, `unknown`-is-not-success, and data marking are unchanged. A faster or smaller model must never mean weaker safety (constitution, `docs/trust/`).

## 4. The proposals

### Phase 0 — Measure (≈ 1–2 days, no user-visible change)

4.1 **Latency report script** — `scripts/voice_latency_report.py` reads `conversation_turn_metrics` from the ElevenLabs API for the last N conversations and prints P50 / P95 per agent version for: speech-end → first audio, LLM first token, tool latency, prompt tokens, cost per minute. It becomes the gate for every later change (the table in §1 is its first run, done by hand).

4.2 **App timing points** — `os_signpost` intervals for tap → microphone ready → token → connected → agent ready → first audio, and emit the already-defined `latencyBucket` telemetry field (`schemas/telemetry.schema.json:48`) that no Swift code sends today.

4.3 **Targets** (proposed, owner to confirm):

| Moment | Target P50 | Target P95 |
|---|---|---|
| Tap / Back Tap → Doddy listening (app warm) | ≤ 0.6 s | ≤ 1.2 s |
| Speech end → first audio, simple reply | ≤ 0.9 s | ≤ 1.6 s |
| Speech end → first audio when a tool runs (acknowledgement or answer) | ≤ 1.0 s | ≤ 1.8 s |
| Phone-tool answer complete | ≤ 2.5 s | ≤ 4 s |
| Background task (research, email, multi-step plan) | acknowledged ≤ 1 s, result whenever ready, announced | — |

### Phase 1 — Quick wins on the agent configuration (days; mostly `voice-agent/` + ElevenLabs settings)

These need no new app build, except 1.6.

1.1 **Change the model, by measurement.** `gemini-3.5-flash` is deprecated by Google (requests are routed to 3.6 Flash), thinks on every turn, and costs twice as much as its successors on ElevenLabs ($0.073/min vs $0.036/min for `gemini-3.6/3.7/3.8-flash` at Doddy's prompt size, ElevenLabs LLM calculator, 2026-10-12). Run a bake-off on a copy of the agent (ElevenLabs branches) with the same 30–50 Polish and English test turns, including tool calls, for:
- `gemini-3.6-flash` and `gemini-3.7-flash` with the lowest thinking level ElevenLabs allows for them;
- a non-reasoning fast model: `gpt-6-luna`, `gpt-5.6-luna` or `claude-haiku-4-5` (all offered by ElevenLabs);
- keep `gemini-3.5-flash` as the control.
Pick the fastest one that passes the quality gate (4.4 below). Also choose an explicit backup model that is not slower than the primary: the default cascade put one turn on `gemini-2.5-flash` at 3.0 s.

1.2 **Shrink the prompt to ≤ 8k tokens per turn** (from 15–28k). Measured: ~15k tokens → 0.85 s first token, ~28k → 1.25 s.
- Drop `recent_conversations` from the prompt, or reduce it to one short line (for example "last talked yesterday about the shopping list"). Skip conversations that were only a greeting or silence. Offer a `recall_conversations` tool instead. This is also a privacy gain.
- Send at most ~10 pinned or recent notes, and rely on `search_memories` for the rest.
- Cut `instructions.md` from ~7.4k to ~2.5k tokens. Move tool-specific rules into each tool's description, or into ElevenLabs **procedures**, which load their instructions only when they trigger. Enforcement stays in typed code as today.
- Shorten tool descriptions (38k characters today) and cap `saved_lists`, which has no character budget.

1.3 **Load fewer tools at once.** Keep ~15–20 always-on tools. These include memory search and save, calendar read and create, reminders, timer, lists, weather, a general web lookup, and `start_task` (Phase 3). Put the rest (translator, Todoist, Outlook, Notion, Drive, bulk calendar changes, plans) behind procedures or workflow nodes that load them when the topic comes up. OpenAI's guidance is fewer than 20 functions. Anthropic measured better tool selection with on-demand tool loading (§9).

1.4 **Never leave silence.**
- Turn on the soft-timeout filler at ~2.5 s, using LLM-generated fillers so they follow the conversation language.
- Set `pre_tool_speech: force` on every tool that can take more than ~1 s (web search, online accounts, location fixes), not only on confirm-on-screen tools.
- Set `tool_call_sound: typing` with behaviour `always` on the slow tools.

1.5 **Merge tool chains into single tools.**
- `get_weather` takes a place name and geocodes inside the tool (one hop instead of two).
- `wikipedia_answer` searches and summarises in one call.
- `change_event` resolves the event itself instead of needing `read_calendar` first.
- Each merge saves ~0.8–1.2 s per use.

1.6 **Tell the agent what this app build can do.** Send an `available_tools` dynamic variable from the app (built from the existing `CapabilityCatalog`), so the model doesn't try tools the installed version cannot run.

1.7 **Fix the cold backend** (owner decision, cost).
- Move `doddy` to a paid Render instance; paid instances never sleep. Stopping the SQLite reset on redeploy needs a persistent disk as well.
- Until then, use a keep-alive ping every 10 minutes from an external scheduler. The messaging worker can't do it: `render.yaml` says `starter`, but `docs/implementation/GO_LIVE_DAILY_NEWS.md` records the live messaging service on the free plan, so it sleeps too.
- Lower web-search cost: return the first good result instead of waiting for the full Monid run, and cache identical queries for a few minutes.

**Expected effect of Phase 1** (estimate, to be confirmed by 4.1):
- Simple replies from ~1.45 s to ~0.8–1.0 s.
- Tool replies start speaking in ≤ 1 s instead of 2.8–6 s of silence.
- LLM cost per minute roughly halved.

### Phase 2 — Faster start in the app (needs a Mac build; `DoddyApp/Features/Voice`, `Features/Opening`)

2.1 **Connect while the opening scene plays.** Start `prepare()` (context, token and connection) at the *start* of the 2.4 s scene, and only open the microphone and play the greeting at hand-over. For Back Tap, Siri and the wake word (no scene), start preparing in the intent handler before the full-screen cover animates in.

2.2 **Run start-up steps in parallel.** Use `async let` for the token fetch, the notes and lists read, and learned context; they don't depend on each other. Reload only what voice uses (not photos, audio or corrections).

2.3 **Pre-warm.**
- Fetch a conversation token when the app becomes active and when Home appears, and reuse it while valid. The token lifetime is to be confirmed with ElevenLabs.
- Use one shared `URLSession` so the TLS connection is reused, instead of an ephemeral session per fetch.
- Keep the prompt variables pre-rendered and refresh them when notes change, not at tap time.

2.4 **Instant feedback.**
- Show the listening state and play a short earcon on tap (≤ 100 ms), before the connection is up.
- Show the user's words live from tentative transcripts.
- Animate Doddy's "thinking" pose from the `agent_tool_request` event.

2.5 **Take blocking work off the main thread.**
- EventKit event fetches, contact lookups and the birthday scan (`DeviceConnections.swift`) run on the main actor today. Move them off it.
- Don't run a full `store.reload()` before every list tool.

2.6 **Voice-friendly confirmations** (owner decision, see §6). While a confirm card is open, the user's next spoken turn should not abort the tool. Options:
- (a) keep the card open and let speech continue;
- (b) accept a spoken "yes / tak" as approval of the exact card on screen. This would be detected by the app from the user's own transcript, never by the model, and bound to the card's payload hash like today's tap.

### Phase 3 — Architecture: fast voice, background brain (new milestone)

This is the structural change. It also closes the "two brains" gap from the 2026-10-12 architecture review: typed Ask and voice don't share a brain today.

```
 user ──voice──▶ ElevenLabs voice layer (fast model, ≤ 8k-token prompt, ~15–20 tools)
                    │  quick turns: answers itself in < 1 s
                    │  slow/complex turn: calls start_task (async tool) and says
                    │  "I'll look into it — keep talking or I'll tell you when it's done"
                    ▼
               Doddy Brain service (backend; stronger reasoning model)
                    • plans multi-step work (today's propose_plan, without the 5-step cap)
                    • runs read tools itself (web, email, calendar via Composio)
                    • PROPOSES writes — never executes them
                    ▼
     result back to the phone ──▶ if the conversation is live: contextual update / spoken summary
                                 if it ended: notification + Activity entry
     writes ──▶ the same approval card and payload-bound approval as today
 typed Ask ──▶ same Doddy Brain service (streamed answer)
```

3.1 **`start_task` async tool** (ElevenLabs `execution_mode: async`). The voice model decides when to hand off, so there is no extra router model on the voice path. Examples: "plan my Saturday", "compare three restaurants", "go through my email and draft replies", "what changed in the news about X". The voice layer keeps talking while the work runs.

3.2 **Doddy Brain service** (new, backend).
- One endpoint used by both voice tasks and typed Ask.
- Uses a stronger reasoning model at a higher thinking level, where latency doesn't matter.
- Streams progress events ("checking your calendar…") that the app shows in Activity.
- Reuses the existing `backend/` approval store, tool catalog, receipts and `outcome_unknown` rules.

3.3 **Reporting back.**
- During a live conversation, results come back to the voice layer as a data-marked contextual update, and Doddy says "Done — here's what I found".
- After the conversation, a local notification plus an Activity entry.
- `unknown` outcomes are reported as unknown, per DOD-08.

3.4 **Typed Ask moves to the Brain service and streams tokens.** The first words appear in < 1 s, instead of waiting for the whole answer.

3.5 **Speech-to-speech stays an experiment.**
- Speech-to-speech models (`gpt-realtime`, Gemini Live) reach first audio fastest (~0.8–1.2 s, Artificial Analysis).
- But they scored 26–51% on the τ-Voice agentic tool test, against 85% for a reasoning text model. Doddy depends on reliable tool calls and approvals.
- Keep the ADR-265 OpenAI Realtime switch for a bake-off. Don't move the main path until a speech-to-speech model passes the same tool-use gate.

### Phase 4 — Speed through preparation (after Phase 3)

4.1 **Morning briefing pre-computed.** At wake time, the phone builds today's agenda, weather and the news digest (already generated server-side) into the `morning_checkin` variable. "What's my day?" then needs no tool at all.

4.2 **Session cache.** Weather, today's calendar and the location fix are cached for the length of a conversation, so the second question about them is instant.

4.3 **Learned shortcuts.** The learning loop's confirmed procedures (ADR-440) become one-tap or one-sentence plans that skip re-planning.

### 4.4 Quality gate — "stays clever"

Every model, prompt or tool change must pass before it ships:
- **Tool selection and arguments:** `evals/doddy_cases.jsonl` is doc-only today. Make it a runnable test against the agent branch, using ElevenLabs agent tests (the account shows `agent_testing` unused) or a script. Include Polish and English, memory honesty ("never claim saved"), the approval flow and data-marking cases.
- **Latency:** the §4.3 targets from the report script.
- **Owner listening test:** 10 minutes of real use on the phone before a version is promoted.

A faster model that fails the trust cases is rejected, however fast it is.

## 5. Order of work and rough effort

| Step | Effort | Needs | Expected gain |
|---|---|---|---|
| 0 Measure (4.1–4.3) | 1–2 days | ElevenLabs API key in a script; Mac for signposts | Numbers for everything else |
| 1.4 Fillers, pre-tool speech, sounds | hours | Agent config only | No more silent gaps |
| 1.2 Prompt diet + 1.3 fewer tools | 2–4 days | Agent + small app variable changes | −0.3 to −0.5 s per turn, about half the cost |
| 1.1 Model bake-off | 2–3 days | Agent branch, test set | Up to −0.5 s per turn, cheaper |
| 1.5 Merged tools, 1.6 available_tools | 2–3 days | Agent + app | −1 s on tool answers |
| 1.7 Warm backend | 1 hour + cost | Owner: paid plan | Removes ~1 min cold-start failures |
| Phase 2 app start path | 3–5 days | Mac build (blocked until the app compiles again) | Tap → listening ~2–3 s faster |
| Phase 3 Brain service | 2–3 weeks | Milestone approval, model/provider choice | Clever answers without blocking the conversation |
| Phase 4 | ongoing | Phase 3 | "Instant" common questions |

## 6. Decisions the owner needs to make

1. Approve the latency targets in §4.3 (or set others).
2. Model bake-off candidates and budget (1.1). Is a non-Google model acceptable for the voice layer?
3. Remove "last 10 conversations" from the voice prompt in favour of an on-demand tool (1.2).
4. Pay for always-on Render instances for `doddy` (and the messaging service, which also runs free today), checking the price Render shows, or accept a keep-alive ping (1.7).
5. Start connecting during the opening scene, or shorten the scene when "listen on open" is on (2.1).
6. Spoken confirmation (2.6 b): allow "yes / tak" as approval for low-risk cards such as saving a note, or keep tap-only. Tap-only is safer; spoken approval is faster and matches how the measured conversation actually went.
7. Approve Phase 3 as a milestone, including which reasoning model and provider the Brain service uses and where it runs. The EU region should be weighed against latency; ElevenLabs-hosted LLMs run in the US.

## 7. Risks and trade-offs

- **Smaller or faster model, worse judgement.** This is why §4.4 gates every change, and why hard work moves to a stronger model in Phase 3 rather than being dropped.
- **Shorter prompt, rules forgotten.** The rules that matter (approvals, memory honesty, data marking) are enforced in typed code today, not only in the prompt. Keep it that way and test them in §4.4.
- **Async tasks add states.** A task can finish after the conversation ended, fail, or have an unknown outcome. Each needs an Activity entry and an honest message; nothing is announced as done without a trusted result.
- **Fillers can annoy.** Keep them short, varied, language-matched and off for turns under ~1 s.
- **Speculative turn** (already on) spends extra LLM tokens. Keep it, but watch cost in the report.
- **Measured sample is small** (3 conversations, ~36 turns, one user, one evening). Phase 0 widens it before big bets are placed.

## 8. Constitution evidence log

| Item | State |
|---|---|
| Rules touched | External writes need explicit, payload-bound approval (unchanged in every phase). `unknown` is never success (Phase 3.3). Tool and web content is data (Phase 3.3). |
| Enforcing code | Existing: phone approval cards, `backend/src/policy.ts`, `store.createApproval`, data marking in tool replies. None changed by this document. |
| Tests run | None. This is a document. The latency figures come from ElevenLabs' recorded metrics, read through the API, not from a test. |
| Gaps | No client-side timing exists. `evals/doddy_cases.jsonl` is not executed by any code. The measured sample is small. |
| Claims to limit | Nothing here is implemented or tested. "Expected effect" numbers are estimates. Third-party benchmark figures are rolling medians from the date read. |

## 9. Sources (read 2026-10-12)

- ElevenLabs, voice agent latency budget (P50 ~680 ms, targets P50 < 800 ms / P95 < 1.5 s): https://elevenlabs.io/blog/voice-agent-latency-optimization
- ElevenLabs prompting guide ("prompts over 2000 tokens increase latency and cost"): https://elevenlabs.io/docs/eleven-agents/best-practices/prompting-guide
- ElevenLabs LLM settings ("start with a lower budget or effort for live voice agents"): https://elevenlabs.io/docs/eleven-agents/customization/llm
- ElevenLabs conversation flow (soft timeout fillers): https://elevenlabs.io/docs/eleven-agents/customization/conversation-flow
- ElevenLabs tool call sounds: https://elevenlabs.io/docs/eleven-agents/customization/tools/tool-configuration/tool-call-sounds
- ElevenLabs changelog 2026-04-27 (`pre_tool_speech`, `response_timeout_secs`, `execution_mode`): https://elevenlabs.io/docs/changelog/2026/4/27.md
- ElevenLabs procedures (instructions and tools loaded on trigger): https://elevenlabs.io/docs/eleven-agents/customization/procedures
- ElevenLabs client events (`contextual_update`, `user_message`): https://elevenlabs.io/docs/eleven-agents/customization/events/client-to-server-events
- Google, Gemini 3.5 Flash deprecated, replaced by 3.6 Flash; default thinking level `medium`: https://ai.google.dev/gemini-api/docs/whats-new-gemini-3.5
- Artificial Analysis, Gemini 3.5 Flash (minimal) 0.80 s TTFT: https://artificialanalysis.ai/models/gemini-3-5-flash-minimal/providers
- Artificial Analysis, speech-to-speech index: https://artificialanalysis.ai/speech-to-speech
- τ-Voice benchmark (voice agents 26–51% vs text reasoning 85%): https://arxiv.org/abs/2603.13686
- Voice AI primer (Pipecat), real deployments 1.2–1.3 s, tool definitions slow first token: https://voiceaiandvoiceagents.com/
- Human turn-taking gap (~100–300 ms): https://languagelog.ldc.upenn.edu/nll/?p=7997
- OpenAI function calling (aim for fewer than 20 functions): https://developers.openai.com/api/docs/guides/function-calling
- Anthropic, advanced tool use (on-demand tool search, accuracy 49% → 74%): https://www.anthropic.com/engineering/advanced-tool-use
- Talker–Reasoner architecture: https://arxiv.org/abs/2410.08328
- OpenAI GPT-Live (voice layer delegating to a backend): https://developers.openai.com/api/docs/guides/live
- Render free instances (spin down after 15 min, ~1 min to start): https://render.com/docs/free
- Nielsen Norman Group, response time limits (0.1 s / 1 s / 10 s): https://www.nngroup.com/articles/response-times-3-important-limits/
- ElevenLabs LLM price calculator for this agent (read through the ElevenLabs API, 2026-10-12): `gemini-3.5-flash` $0.073/min; `gemini-3.6/3.7/3.8-flash` $0.036/min; `gpt-6-luna` $0.004/min; `claude-haiku-4-5` $0.048/min, at a 30k-character prompt.

Not verified: which thinking level ElevenLabs actually sends to Gemini, the lifetime of a conversation token, Composio per-call overhead, and the region that serves non-Enterprise ElevenLabs sessions for users in Poland.
