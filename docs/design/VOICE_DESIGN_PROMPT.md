# Doddy's voice: ElevenLabs Voice Design prompt (draft, 2026-11-07)


*Kept in `docs/design/` (owner, 9 Nov 2026: keep the draft). Written 7 Nov on `claude/tender-franklin-olu7l0` as `voice-agent/VOICE_DESIGN_PROMPT.md`; moved here because `voice-agent/` holds the live agent spec. Still a proposal: nothing on the live agent changes.*
**Status: proposal.** Nothing here is applied. The live agent still speaks with the owner's pick `oDULUm0GMltHA6mVZkWh` (ADR-051); the Settings list is still the six voices of ADR-105. Adopting a designed voice is an owner decision recorded as its own ADR, after it has been heard on a device in both languages.

## Where the brief comes from

- Character and verbal identity: Brand Guidelines V2.2 (`design/brand-v2.2/`, pp. 1, 5–6, 34, 49–51, 53, 60, 64–65): a sharp mind, a good heart, a little everyday chaos; lightly sarcastic and easy to like; the useful bit first; warmth without sugary reassurance, confidence without showing off; no corporate language, baby talk or forced slang; calm and direct in serious moments.
- The spec's "Who you are" and "How you speak" (`voice-agent/instructions.md`, ADR-556 item 4) and the owner's own live wording ("dry British humour", `voice-agent/README.md`, 22 Oct).
- `docs/design/BRAND_GUIDELINES.md` §2: tone by context (natural tempo for tasks, slower and clearer as stakes rise), humour that is deadpan and observational, no UK-isms as a tic.
- Doddy is a he and uses masculine forms in Polish (`voice-agent/instructions.md`, owner, 22 Oct). One voice for both languages (ADR-051, ADR-224).
- ElevenLabs Voice Design prompt guide (docs read 7 Nov 2026): "Native <Language>. <Gender>, <Age range>. <Quality level>. Persona: <2–5 words>. Emotion: <2–3 adjectives>. <1–2 sentences about timbre, pacing, delivery>"; say "accent" only for accent; no FX words (reverb, phone, tape); match the preview text to the description; longer previews are more stable; guidance scale 20–40 % in their examples, higher when accent and tone accuracy matter. The connector's limits: description 20–1000 characters, preview text 100–1000.

## Prompt A (recommended): English first

Paste into **Voice description**:

```
Native British English, a light modern southern-English accent, not posh and not regional. Male, late 20s to early 30s. Studio-quality recording, close and clean. Persona: sharp-witted everyday mate. Emotion: warm, dry, curious, unhurried. Mid-pitched, clear and light with a little natural texture; sounds like a quick-thinking friend in the room, not an announcer, a presenter or a customer-service agent. Relaxed conversational pacing with short sentences and real pauses; matter-of-fact, slightly deadpan intonation that lands the useful point first and lets a dry aside sit without pushing it; a natural smile in the voice without any sugary brightness. Calm, steady and plain when the subject is serious. Never cartoonish, squeaky, breathy, hyped or gravelly.
```

Paste into **Text** (the line the previews speak; these are the guide's own lines, so the voice is judged on what Doddy actually says):

```
Hi, I'm Doddy. What's on your mind? Start with the deadline, then we can work backwards. That plan has six priorities, which is an ambitious definition of priority. Let's pick the first one. I'm not sure yet, but here's what we can check. Added for tomorrow at nine. I explained the complicated bit, then pushed the pull door. Again. Okay, that sounds difficult. What would be most useful right now?
```

Settings: model **Eleven v3** (`eleven_ttv_v3`), language **English**, guidance scale **32 %** (go to 40 % if the accent drifts American, down to 25 % if the previews sound strained), loudness default, no quality slider (v3 has none). Write down the seed of the round you like so it can be reproduced.

Why these choices:

- **British, light, southern:** the owner's live prompt says "dry British humour" and the tagline is "Your mate in your pocket". Light, because the guide bans forced slang and a thick accent becomes a costume; the accent is sound only, the words stay free of "mate" and "cheers" as tics (`BRAND_GUIDELINES.md` §2.5). If a non-British Doddy is wanted, replace the first sentence with "Native English, a neutral accent that does not place him in one country." and keep the rest.
- **Late 20s to early 30s:** a peer, not a parent or a child. Old enough for "his intelligence is real", young enough for everyday chaos. No baby talk (p. 65), so nothing cartoonish even though he is a stick figure.
- **Mid-pitched, light, a little texture:** a deep radio baritone shows off (p. 65, "confidence without showing off"); a bright high voice reads as customer-service cheer (`BRAND_GUIDELINES.md` §2.7). Texture keeps him from sounding like a product.
- **Deadpan, point first, pauses:** tone principles 1–3 (pp. 50–51) in sound: answer, then the optional aside, with nothing sold.
- **Calm when serious:** p. 51 and p. 60; the voice must be able to drop the smile without changing who he is.

## Prompt B (fallback): Polish first

Use only if, after saving voice A, its Polish sounds foreign on a device. The live agent's default language is Polish, so this matters.

Voice description:

```
Native Polish, a standard neutral accent, with natural fluent English as a second language. Male, late 20s to early 30s. Studio-quality recording, close and clean. Persona: sharp-witted everyday mate. Emotion: warm, dry, curious, unhurried. Mid-pitched, clear and light with a little natural texture; a quick-thinking friend in the room, not a lektor, a presenter or a call-centre agent. Relaxed conversational pacing with short sentences and real pauses; matter-of-fact, slightly deadpan intonation that lands the useful point first and lets a dry aside sit without pushing it; a natural smile in the voice without any sugary brightness. Calm, steady and plain when the subject is serious. Never cartoonish, squeaky, breathy, hyped or gravelly.
```

Text (language **Polish**; masculine forms on purpose):

```
Cześć, tu Doddy. Co ci chodzi po głowie? Zacznijmy od terminu, a potem pójdziemy wstecz. Ten plan ma sześć priorytetów. Odważna definicja słowa priorytet. Wybierzmy pierwszy. Jeszcze nie wiem, ale oto, co możemy sprawdzić. Dodane na jutro na dziewiątą. Wyjaśniłem tę skomplikowaną część, a potem pchnąłem drzwi z napisem „ciągnąć”. Znowu. Dobrze. To brzmi trudno. Co byłoby teraz najbardziej pomocne?
```

Same settings as A. The Polish lines are drafts in the style of `l10n/REVIEW_NOTES.md`; a Polish speaker reads them before they are used anywhere else.

## How to judge the three previews

Listen for, in this order: (1) does the useful line ("Start with the deadline…") sound like a friend stating a fact, not a presenter; (2) does the aside ("ambitious definition of priority") stay dry, with no laugh at the listener; (3) does "that sounds difficult" drop the smile without becoming a different voice; (4) is "nine" / "dziewiątą" said naturally. Reject any preview that is breathy, hyped, squeaky or announcer-like, however good the accent.

## After saving (not done here)

1. Save the pick as "Doddy" with the description above as its library description.
2. Generate the same two texts with the saved voice on **`eleven_v4_turbo`**, the agent's model (`voice-agent/session.json`): ElevenLabs says designed voices can be less performative on v4 than on v3. Try stability 0.5 (the agent's default) and 0.3 (the Settings "expressive" option, ADR-105).
3. Only then, on the owner's separate "do it": set `tts.voice_id` on the live agent following the read-then-save rule in `voice-agent/README.md`, update `session.json`, the `VoiceStyle` list (ADR-105) and `docs/product/PERSONALITY_SETTINGS.md`, and record the ADR with the seed, guidance scale and the exact description used.
4. Licence: a designed voice is the workspace's own, which closes the library-licence question left open in ADR-038 and `V1_VOICE_STATUS.md` for the current voice; confirm against ElevenLabs' current terms before release.

Generating previews spends credits (three previews per round, charged once per round).
