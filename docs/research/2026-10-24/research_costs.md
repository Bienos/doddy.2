# Doddy voice cost model (research file)

Prices read from official pages fetched 2026-10-23 (saved in `.../scratchpad/pages/`), plus the ElevenLabs MCP estimator and web searches run 2026-10-24.
CONFIRMED = read on an official page or tool today. EST = my arithmetic or assumption. UNCONFIRMED = no official source found.

## 1. Headline finding
- ElevenAgents charges **$0.08 per connected minute on every plan** (Starter $6/75 min, Creator $22/275 min, Pro $99/1,238 min, Scale $299/3,738 min, Business $990/12,375 min = $0.080 each). Higher tiers give NO unit discount (Enterprise "significant discounts", size unknown). Extra minutes $0.08; burst (over concurrency) $0.16. CONFIRMED, https://elevenlabs.io/pricing/agents
- LLM is billed separately, passed through at provider price. The ElevenLabs estimator for THIS agent (`agents_calculate_llm_usage`, agent_0501m4et27vyeawrwqfdxxfszfa6, 2026-10-24) returns **gpt-6-luna = $0.0065/min** ($0.0012/message). So LLM is about 7% of the bill; the platform minute fee is about 92%. CONFIRMED (tool output; its internal assumptions about turns/tokens are not shown).
- Silence: periods of silence longer than 10 s are billed at 5% of the rate. Duration is measured by connection time (call start to window close). CONFIRMED, https://elevenlabs.io/docs/help-center/product/eleven-agents/how-much-does-eleven-agents-cost
- Your measured 79 s = 274 credits (about $0.05) is about $0.038/min, less than half of list ($0.0865/min). I could not reconcile this (silence discount? credits ignore the minute fee and LLM?). Check the usage dashboard before trusting either.
- Same estimator, other LLMs ($/min): claude-haiku-5-5 0.0071; gemini-3.5-flash-lite 0.0216; gemini-3.6/3.7/3.8-flash 0.0535; deepseek-v41-flash 0.0380; qwen36-35b 0.0093; gpt-oss-120b 0.0120; claude-sonnet-5-5 0.1427; claude-opus-5-5 0.2853; gpt-6-sol 0.1297; gpt-6-astra 0.6485; eleven_realtime_v1_mini 0.0139; eleven_realtime_v1_max 0.1167. Switching LLM inside ElevenAgents can save at most about $0.006/min.
- ElevenLabs Realtime v1 Mini/Max (speech-to-speech): $0.08/min + tokens (Mini $0.20 in / $6.00 out per 1M; Max $1.80 / $9.00). No saving vs the current setup. CONFIRMED, https://elevenlabs.io/pricing/api and https://elevenlabs.io/docs/eleven-agents/customization/realtime-models

## 2. Price table (unit prices)
| Provider / model | Unit price | Date/source | Est. $/voice-min | Polish | Notes |
|---|---|---|---|---|---|
| ElevenAgents (Creator) | $0.08/min connected; silence >10 s at 5%; 275 min incl. | 2026-10-23 elevenlabs.io/pricing/agents | 0.0865 incl. gpt-6-luna | Good (Scribe best on Polish in AGH Kraków paper arXiv 2603.02246) | TTS/ASR bundled; LLM extra |
| ElevenLabs TTS v4 Turbo / Flash | $0.04 per 1K chars (v4 $0.08) | elevenlabs.io/pricing/api | 0.015 (378 chars/voice-min EST) | 90+ languages claimed | Flash/Turbo 32 languages |
| ElevenLabs Scribe v2 Realtime | $0.39/h | same | 0.0065 | Best in independent paper | |
| OpenAI gpt-realtime-2.1-mini | audio in $10 / cached $0.30 / out $20 per 1M; text $0.60 / $0.06 / $2.40 | developers.openai.com/api/docs/pricing, models/gpt-realtime-2.1-mini | 0.018 cached to 0.079 uncached (EST) | UNCONFIRMED on official page | 1 audio token = 100 ms user, 50 ms assistant; full history re-sent every response |
| OpenAI gpt-realtime-2.1 | audio $32 in / $0.40 cached / $64 out; text $4 / $0.40 / $24 | same | 0.071 cached, 0.33 uncached (EST) | UNCONFIRMED | |
| OpenAI GPT-Live gpt-live-1 | $0.05/min, per second; backend model/tools billed separately | pricing page + models/gpt-live-1 | 0.0565 (adds gpt-6-luna 0.0065) | UNCONFIRMED; a 3rd-party post says non-native accents possible in some languages | Full-duplex; backend delegated to gpt-6-luna |
| OpenAI gpt-6-luna (text) | $0.10 in / $0.01 cached / $0.50 out per 1M | pricing page | ~0.0065 (ElevenLabs est.) | UNCONFIRMED for persona | Batch half price |
| OpenAI transcription | gpt-live-transcribe / gpt-realtime-whisper $0.017/min; gpt-4o-mini-transcribe $0.003/min (file) | pricing page | 0.017 | OK (Whisper family) | |
| Gemini 3.8 Live (audio-to-audio) | audio in $3.00 ($0.005/min), audio out $12.00 ($0.018/min) per 1M; text in $0.75, out $4.50; 25 audio tok/s | ai.google.dev pricing, 2026-10-23 | 0.013 best case, 0.053 pessimistic (EST) | UNCONFIRMED on page (Live models multilingual) | Community says silence on open stream is billed and context may be re-billed each turn (UNVERIFIED) |
| Gemini 2.5 Flash Native Audio | audio in $3.00, audio out $12.00 | same | same as above | | older |
| Gemini 3.5 Transcribe Live | $0.005/min in + $0.004/min text out = ~$0.009/min | same | 0.009 | | |
| Claude Haiku 5.5 | $0.10 in / $0.50 out / cache read $0.01 per 1M (prompts up to 100K) | platform.claude.com pricing | 0.0071 (ElevenLabs est.) | Good, UNCONFIRMED for Polish voice | New tokenizer about 30% more tokens; US-only inference x1.1 |
| Claude Sonnet 5.5 | $2 / $10; cache read $0.10 | same | 0.143 in ElevenAgents | | Batch $1 / $5 |
| Claude Opus 5.5 | $4 / $20; cache read $0.20 | same | 0.285 in ElevenAgents | | Batch $2 / $10 |
| DeepSeek flash (V4.1) | off-peak $0.15 in / $0.003 hit / $0.60 out; peak x2 | api-docs.deepseek.com | 0.038 in ElevenAgents | Weak/UNCONFIRMED | China-hosted: GDPR risk, my flag |
| Soniox STT real-time | $0.12/h = $0.002/min; diarization/language ID included | soniox.com/pricing (updated June 2026) | 0.0020 | Claims 6% WER Polish (vendor); independent paper favours Scribe | 60+ languages |
| Soniox TTS v2 | $4/1M text tokens + $21.50/1M audio tokens = about $0.70 per hour of speech | same | 0.0053 | Polish page exists; quality UNVERIFIED | |
| Deepgram STT | Nova-3 multi $0.0058/min promo ($0.0092 regular); Flux multi $0.0078/min | deepgram.com/pricing | 0.006 to 0.009 | Polish supported in Nova-3 (changelog) | |
| Deepgram TTS | Aura-2 $0.030/1K chars; Flux TTS $0.045/1K | same | 0.011 | NOT supported (Aura-2 has en, es, nl, fr, de, it, ja; Flux TTS English only) | Rule out for Polish |
| Deepgram Voice Agent API | $0.075/min standard; $0.059 BYO LLM; $0.050 BYO LLM+TTS | same | 0.05 to 0.075 | Polish TTS gap | Only 20 to 40% below ElevenAgents |
| Cartesia Sonic-3.6 | 1 credit = 1 char; 750 to 800 credits per audio min; Startup $49/1.25M, Scale $299/8M; overage $65 / $45 / $38 per 1M | cartesia.ai/pricing | 0.014 to 0.025 | Vendor Polish page; quality UNVERIFIED | |
| Cartesia Ink-2 STT | 3 credits/s; about $0.39/h on Scale | same | 0.0065 | | |
| Cartesia managed agents | $0.06/min; LLM free "for a limited time" | same | 0.06 | UNVERIFIED | Not cheap enough to justify |
| Speechmatics | STT Melia-1 $0.12/h (pre-recorded; real-time rate not shown); TTS $0.011/1K chars, first 1M chars free | speechmatics.com/pricing | TTS 0.0042 | Polish STT likely; TTS languages UNVERIFIED | |
| LiveKit Cloud | agent session $0.01/min, plus optional inference | livekit.io/pricing | +0.01 | n/a | Optional transport/orchestration |
| Apple Foundation Models / SpeechAnalyzer | free on device | Apple docs, 9to5mac | 0 | Polish NOT in Apple Intelligence list (16 languages as of iOS 26.1); SpeechTranscriber Polish unconfirmed (forum: returns nil) | See scenario E |

## 3. Assumptions for the cost model (EST)
- 1 voice minute = 1 minute connected. User speaks 25%, assistant 45%; Polish speech about 14 chars/s, so 378 chars of TTS per voice minute.
- 4 turns/min; average conversation 3 min (12 responses). System prompt + 92 tool schemas = 9,000 text tokens (my guess; measure the real value).
- OpenAI audio tokens: user 1/100 ms, assistant 1/50 ms (official). Per 3-min conversation: 450 user audio tokens, 1,620 assistant audio tokens, 13,455 audio tokens re-read as history, 600 text output tokens.
- "Cached" assumes the prefix cache hits on every response after the first. "Uncached" assumes every response pays full input price.
- E (hybrid) assumes 40% of minutes are handled fully on device at zero marginal cost and 60% go to scenario D1. The 40% is an assumption, not a measurement.

## 4. Scenario cost per voice minute and per user per month
| Scenario | $/min | Light 30 min | Typical 100 | Heavy 400 |
|---|---|---|---|---|
| A ElevenAgents list ($0.08 + gpt-6-luna $0.0065) | 0.0865 | 2.60 | 8.65 | 34.60 |
| A with 20% of time silent (5% rate) | 0.0713 | 2.14 | 7.13 | 28.52 |
| A as measured (274 credits / 79 s) | 0.038 | 1.14 | 3.80 | 15.19 |
| B gpt-realtime-2.1-mini, cache works | 0.0179 | 0.54 | 1.79 | 7.16 |
| B gpt-realtime-2.1-mini, cache misses | 0.0792 | 2.38 | 7.92 | 31.69 |
| B2 gpt-realtime-2.1 (full), cached | 0.0712 | 2.13 | 7.12 | 28.46 |
| B3 GPT-Live gpt-live-1 + gpt-6-luna | 0.0565 | 1.70 | 5.65 | 22.60 |
| C Gemini 3.8 Live best case | 0.0126 | 0.38 | 1.26 | 5.04 |
| C planning figure | 0.030 | 0.90 | 3.00 | 12.00 |
| C pessimistic (context re-billed per turn) | 0.0531 | 1.59 | 5.31 | 21.22 |
| D1 Soniox STT + gpt-6-luna + ElevenLabs v4 Turbo | 0.0236 | 0.71 | 2.36 | 9.45 |
| D1 plus LiveKit session fee | 0.0336 | 1.01 | 3.36 | 13.45 |
| D2 Soniox STT + gpt-6-luna + Soniox TTS (quality unverified) | 0.0138 | 0.41 | 1.38 | 5.50 |
| D3 Soniox STT + gpt-6-luna + Cartesia (Scale credits) | 0.0226 | 0.68 | 2.26 | 9.05 |
| E hybrid (40% local, rest D1) | 0.0142 | 0.43 | 1.42 | 5.67 |

Math examples:
- A: 0.08 + 0.0065 = 0.0865; x100 min = $8.65. Fixed fee: Creator $22/month covers 275 min at the same $0.08, so there is no volume discount until Enterprise.
- B mini (3-min conversation): output audio 1,620 x $20/1M = 0.0324; text out 600 x $2.4/1M = 0.0014; new user audio 450 x $10/1M = 0.0045; cached audio re-read 13,455 x $0.30/1M = 0.0040; text prefix 9,000 x $0.60/1M once + 11 x 9,000 x $0.06/1M = 0.0113; total 0.0537 / 3 = 0.0179 per min. Uncached: re-read audio at $10/1M = 0.135 and prefix 12 x 9,000 x $0.60/1M = 0.065, total 0.2376 / 3 = 0.079 per min.
- C: input 60 s x 25 tok/s x $3/1M = 0.0045; output 27 s x 25 x $12/1M = 0.0081; sum 0.0126. Pessimistic adds audio history re-billed per turn (0.0135) and 9,000-token prefix x 12 turns x $0.75/1M (0.027).
- D1: STT 0.12/60 = 0.0020; LLM 0.0065 (ElevenLabs estimate; direct API with caching is probably 0.0013 to 0.004, EST); TTS 378 x $0.04/1K = 0.0151; total 0.0236.
- E: 0.6 x 0.0236 = 0.0142.

Break-even view: at $0.0865/min, a heavy user (400 min) costs $34.60/month, which is more than a typical $20 subscription. Tolan's historic pricing was $10 to $200/month by usage (notes_raw.md, third-party reporting).

## 5. Apple on-device (scenario E) feasibility for Polish
- Foundation Models: the on-device model supports only languages Apple Intelligence supports; unsupported languages throw `unsupportedLanguageOrLocale` (Apple doc, dl/foundationmodels_supporting-languages-and-locales-with-foundation-models.json). The downloaded Apple docs contain no mention of Polish.
- Polish is not on the Apple Intelligence list as of iOS 26.1 (9to5mac, https://9to5mac.com/?p=1027723); Benchmark.pl reports Siri AI launches in English first in iOS 27 and Polish is not named (https://www.benchmark.pl/siri-ai-nie-mowi-po-polsku-ale-apple-potwierdza-ze-prace-trwaja-7296359260497952a). A developer forum report says `SystemLanguageModel.isSupported` is false on Polish-language devices (https://developer.apple.com/forums/thread/805378; date and OS version unconfirmed).
- SpeechAnalyzer/SpeechTranscriber: no official confirmation of Polish; a forum report says `supportedLocale(equivalentTo:)` returns nil. Check `SpeechTranscriber.supportedLocales` at runtime on iOS 27 devices.
- Conclusion: for Polish, "Apple LLM + SpeechAnalyzer + system TTS" is NOT proven viable. A realistic E uses on-device rules/App Intents for simple commands (timers, alarms, reminders), possibly an on-device Whisper-class model for ASR (not verified here), and cloud for the rest. The 40% local share is therefore an assumption to be measured from your own logs.

## 6. Polish quality evidence (all weak)
- STT: independent AGH Kraków paper (arXiv 2603.02246, Feb 2026) finds ElevenLabs Scribe best on Polish general and medical data. Soniox's own table (vendor) claims Soniox 6%, Speechmatics 7.7%, Deepgram 10.3%, ElevenLabs 10.5%, Google 13.6% WER. These conflict; run your own Polish test set (https://soniox.com/compare-stt/soniox-vs-elevenlabs/polish).
- TTS: no independent Polish naturalness comparison found for Cartesia, Soniox, ElevenLabs. Run a blind listening test on your own Polish scripts, including numbers, names and English words.
- Speech-to-speech (OpenAI, Gemini): Polish support not stated on the official pages I read.

## 7. Cost-cutting techniques (savings vs scenario A)
1. Leave ElevenAgents' per-minute fee: self-orchestrated cascade (D1) is about 73% cheaper per minute ($0.0865 to $0.0236). Costs engineering time and you must rebuild turn-taking, barge-in, tool calls.
2. Cache-friendly speech-to-speech (B mini) if Polish quality passes: about 79% cheaper when caching works; 8% cheaper when it misses. Keep the system prompt + tool block first and byte-identical; log cached token counts from `response.done`.
3. Cap session length and idle time (auto end after 20 to 30 s of no speech, hard stop at 5 min unless user continues): protects against runaway sessions; EST 5 to 15% of billed minutes. ElevenAgents already bills long silence at 5%.
4. Tap-to-talk / push-to-talk or a "listening" mode that disconnects between turns: EST 20 to 40% fewer billed minutes on session-priced stacks (ElevenAgents, GPT-Live $0.05/min). For Gemini it also avoids billed silence.
5. Per-user caps and plan design: for example 15 min/day free, 100 to 150 min/month standard, paid top-ups. Caps the heavy 400-min user from $34.60 to $17.30 at 200 min on A.
6. Route simple intents locally without any cloud call (timers, alarms, calls, playback via App Intents/regex): EST 20 to 40% of voice minutes in a command-heavy assistant; measure first.
7. Shorter spoken answers (prompt: max 2 sentences, token cap): cuts TTS characters/audio output 20 to 30% and shortens connected time; EST.
8. Trim the 92-tool schema to 8 to 15 tools chosen per intent: saves under $0.003/min on A (LLM is 7% of the bill) and about $0.006/min on B when caching misses. Worth doing for latency and accuracy, not for the invoice.
9. Cheaper STT/TTS vendors inside a cascade: Soniox STT $0.12/h vs Scribe RT $0.39/h vs OpenAI $1.02/h (about -70 to -88% on the STT slice); Soniox TTS about $0.70/h speech vs ElevenLabs about $2 to $2.4/h of speech (about -65% on the TTS slice); Polish quality must be tested.
10. LLM routing and caching on the Claude side: Haiku 5.5 ($0.10/$0.50) for chat, Sonnet 5.5 ($2/$10) for most errands instead of Opus 5.5 ($4/$20) = 50% cheaper tokens, Batch API -50% for non-urgent errands, cache reads at 5 to 10% of input price. Avoid US-only inference (x1.1) unless required.
Also: negotiate ElevenLabs Enterprise pricing or an annual commitment if staying (discount size unknown).

## 8. Not confirmed from an official page
- Why 274 credits / 79 s is far below list price; whether the $0.08/min covers TTS+ASR for every voice and model (strongly implied, "LLM passed through separately").
- Polish support and quality of gpt-realtime-2.1(-mini), GPT-Live, Gemini 3.8 Live; Cartesia/Soniox/Speechmatics Polish TTS naturalness.
- Gemini Live context re-billing per turn and silence billing (community posts only: discuss.ai.google.dev).
- Real cache hit rates on OpenAI Realtime for your prefix; real token size of your 92 tools.
- Apple Intelligence / SpeechTranscriber Polish status on iOS 27; Apple system TTS Polish voice availability (not checked today).
- Some Gemini rows in the pricing page show a price doubling on 2027-01-01 (the row before 3.8 Live); the 3.8 Live row shows no scheduled change, but check before committing. Deepgram Nova-3 streaming prices are "limited-time promotional" (regular $0.0092 multi).
- Whisper-class on-device Polish ASR performance on iPhone (not researched).
- DeepSeek GDPR/data-location position (not researched).

## 9. Source URLs
- https://elevenlabs.io/pricing/agents ; https://elevenlabs.io/pricing/api ; https://elevenlabs.io/docs/help-center/product/eleven-agents/how-much-does-eleven-agents-cost ; https://elevenlabs.io/docs/eleven-agents/customization/llm ; https://elevenlabs.io/docs/eleven-agents/customization/llm/optimizing-costs ; https://elevenlabs.io/docs/eleven-agents/customization/realtime-models ; https://elevenlabs.io/docs/api-reference/agents/calculate
- https://developers.openai.com/api/docs/pricing ; https://developers.openai.com/api/docs/guides/realtime-costs ; https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini ; https://developers.openai.com/api/docs/models/gpt-live-1
- https://platform.claude.com/docs/en/about-claude/pricing
- https://ai.google.dev/gemini-api/docs/pricing
- https://deepgram.com/pricing ; https://developers.deepgram.com/docs/tts-models-languages-overview
- https://cartesia.ai/pricing ; https://soniox.com/pricing ; https://www.speechmatics.com/pricing ; https://api-docs.deepseek.com/quick_start/pricing ; https://livekit.io/pricing
- Apple: foundationmodels_supporting-languages-and-locales (local json); https://9to5mac.com/?p=1027723 ; https://developer.apple.com/forums/thread/805378 ; https://www.benchmark.pl/siri-ai-nie-mowi-po-polsku-ale-apple-potwierdza-ze-prace-trwaja-7296359260497952a
- Polish ASR: https://arxiv.org/abs/2603.02246v1 ; https://soniox.com/compare-stt/soniox-vs-elevenlabs/polish
- Gemini billing forum: https://discuss.ai.google.dev/t/live-api-pricing-audio-tokens-second-silent-audio/92653
(Page URLs for pricing pages are inferred from the downloaded filenames; the OpenAI, Claude, Gemini and ElevenLabs ones match the file names exactly.)
