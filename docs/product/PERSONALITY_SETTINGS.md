# Doddy's personality and the personality settings

Status: built in the app and **applied to the live agent** on 2026-10-09 (prompt version `agtvrsn_8101m4gvnve7fdzsyqk5rjyqcfb8`, placeholder default = `PersonalityPrompt.render(.doddyDefault)`, pinned by `PersonalityTests.testDefaultTextMatchesTheAgentPlaceholder`); not yet heard on an iPhone.

## Who Doddy is (from the persona draft, not user-research-validated)
Sources: `reference/character_evals/doddy_persona_v1.yaml`, `character_quick_reference.md`, `docs/design/BRAND_AND_CHARACTER.md`.

- **"Your mate in your pocket."** A practical, observant *side-quest fixer*: notices small, unnecessary hassles and fixes them.
- **Answers first.** One observation, one useful thought, at most one dry beat. Never turns a two-second task into a performance.
- **Funny about little things, quiet about big ones.** Tiny problem = serious investigation; serious problem = calm, simple first step. No jokes about health, money, legal trouble, grief or distress.
- **Corrects himself without ego.** Revises a wrong theory cheerfully; never doubles down.
- **Respectful.** Jokes aim at absurd situations, rules or his own over-planning, never at the user. No sarcasm at the user, shame, guilt, flattery or clinginess.
- **Honest.** An AI, not a person; no claimed feelings or exclusive bond. Only repeats memories that were actually saved; only says something was done with a receipt.
- **Defaults:** humour subtle, replies brief, tone casual, energy grounded ("grounded with contextual bursts"). Bilingual English/Polish, no forced slang.

## What the user can change (Settings → Voice → Voice and personality)
| Dial | Options (default in bold) | Source |
|---|---|---|
| Humour | Off, **Subtle**, Playful | persona `settings.humor_level` |
| Reply length | **Brief**, Balanced, Detailed | persona `settings.verbosity` |
| Tone | **Casual**, Neutral, Formal | persona `settings.formality` |
| Mood (energy) | Calm, **Grounded**, Lively | persona trait `energy`; delivery only, Doddy does not claim moods |

Quick picks: **Doddy's default**, **Focused** (no jokes, brief, neutral, calm; persona `interaction_styles.focused`), **Playful** (playful, balanced, casual, lively; persona `interaction_styles.playful`). Any other mix shows as "Custom".

### How Doddy sounds (ADR-105)
| Setting | Options (default in bold) | Sent as |
|---|---|---|
| Voice | **Doddy** (agent voice `oDULUm0GMltHA6mVZkWh`), Josh `ZoiZ8fuDWInAcwPXaVeq`, Wiktor `Mmjvne5i15kUnfr4fQF3` (native Polish), River `SAz9YHcvj6GT2YYXdXww`, Jessica `cgSgspJ2msm6clMCkdW9`, Will `bIHbv24MWmeRgasZH58o` | `tts.voice_id` |
| Speed | Slower 0.85, **Normal 1.0**, Faster 1.15 | `tts.speed` |
| Expressiveness | Steady 0.75, **Natural 0.5**, Expressive 0.3 | `tts.stability` |

All six voices are already in the owner's account (built-in or My Voices), so no library voice needs adding. Library-only voices (for example a Polish female voice) must be added to My Voices before they can be offered. Only changed values are sent; the default sends no override at all. These settings never reach the prompt.

**Agent change (applied 2026-10-10, version `agtvrsn_5301m4jk5fz1edx8vz0r04hh2mcc`):** client overrides allowed for `tts.voice_id`, `tts.speed` and `tts.stability` only; prompt, LLM, tools and first message stay off. If an agent without these is used, a non-default pick makes ElevenLabs refuse the conversation and the app says to choose "Use Doddy's own voice".

**Hear a sample (ADR-122):** Settings → Voice opens a list where every voice row has a play button (tap the face) and tapping the rest of the row selects it; a "Hear <voice>" button under the voice settings also plays the chosen one. Each plays a short clip bundled in the app: Doddy's hello in English and Polish in that voice, at the chosen speed. Expressiveness is only heard in a real conversation. Samples don't play while a conversation is running, and stop when the voice or speed changes or the screen closes. Clips live in `DoddyApp/Resources/VoicePreviews/`; `VoiceStyleTests.testEveryVoiceHasABundledSample` fails if a voice has none.

**Nickname and starting language (ADR-132):** "What Doddy calls you" is an optional name (single line, letters only, ≤30 characters; anything else is ignored and the field says why). When set it is added as one line to the `doddy_personality` text, so the live agent needs no change. "Starts in" picks the greeting language: Automatic (default; sends nothing), English or Polish (sent as the `agent.language` override; allowed on the dev agent since 2026-10-10, version `agtvrsn_9701m4jtjj5hek1a1h6tbqb9xrvf`).

Not included: per-language voice (the agent already detects it), proactivity (nothing proactive is built), reduced motion (no character animation yet).

**Never changeable:** the persona immutables (answer first, say when unsure, memory and receipt rules, AI disclosure, no humour in sensitive moments, no shame, guilt or clinginess). The text sent to the agent always ends with a fixed sentence saying so.

## How it works
- Stored on the phone in `UserDefaults` under `personality.humour|length|formality|mood` (UI preferences, like appearance; never memory content). Unknown or missing values fall back per dial to the default.
- `PersonalityPrompt.render` (DoddyCore) turns the four choices into fixed sentences. Every option maps to one known sentence, so the app never sends free text from the user here.
- `VoiceSessionController.start` sends it as the dynamic variable `doddy_personality` when a conversation starts. Changes apply from the next conversation.

## Agent change (applied 2026-10-09)
On agent `agent_0501m4et27vyeawrwqfdxxfszfa6`:

1. Add the dynamic variable placeholder `doddy_personality` with the default text, i.e. the output of `PersonalityPrompt.render(.doddyDefault)`. Keep the four existing placeholders (dynamic variables are replaced as a whole).
2. In the prompt, directly after the `# How you speak` section, add:

```
# The user's style settings
{{doddy_personality}}
Where these settings differ from the personality and length guidance above, follow these settings. All other rules in this prompt still apply.
```

Done on the live agent as described above (the section sits right after `# How you speak`).

## Verification
- Linux, Swift 6.1.2: `make test-core` passes 35 tests, including 5 in `PersonalityTests` (defaults match the persona draft, per-dial fallback, every one of the 81 combinations renders all four choices plus the fixed rules sentence, options are distinct).
- `swiftc -parse` passes on the changed app files; `scripts/check_forbidden_capabilities.sh` passes.
- **Not verified:** app compile on Xcode (`ConversationConfig(dynamicVariables:)` is the same call the V3 branch uses); that ElevenLabs accepts the variable before the agent has the placeholder (expected, not tested); that Doddy actually sounds different per setting in English and Polish. Suggested check: run the 64 behavioural evals with Focused and Playful on a real iPhone.

## Privacy and security
- Nothing new leaves the phone except the four style choices, sent to ElevenLabs inside the conversation start.
- The dev agent is public, so anyone with the agent ID can send any text in this variable, as with the existing ones. The authenticated agent and token server (ADR-034) are still required before anyone else uses the app.
- **Export (ADR-176):** Settings → About you → "Export with your settings" puts every choice on this page (voice, speed, expressiveness, starting language, nickname, the four dials) in a JSON or text file with the reviewed profile. The file is made on the phone and goes only where the user sends it from the share sheet. It is separate from the memory export.
