# Translator mode: design proposal (ADR-208, awaiting owner decisions)
Owner, 2026-10-10: "we should design translator mode where he starts translating and talking in someone's language — suggest design". Canvas: **Doddy Translator** (screens 1–9 and a rules board). **Nothing here is built.**

## The job
You're with someone who doesn't speak your language: a taxi driver, a pharmacist, a neighbour. You put the phone on the table between you. Doddy translates each turn aloud in the other person's language, and writes it on their half of the screen.

## Flow (canvas screens)
1. **Start:**
   - "You speak" defaults to the iPhone's language.
   - "They speak" offers a short list, "Detect when they talk", and "All 37 languages…".
   - Two plain notes: put the phone between you; both voices go to ElevenLabs.
2. **Or ask Doddy:** "Doddy, pomóż mi pogadać z taksówkarzem, on mówi po hiszpańsku." Doddy proposes the pair on a card ("Polski ⇄ Español"). The translator opens only after Start; it is proposed with a new tool, `start_translator`.
3. **Disclosure, first and always, in their language:** "Hola, soy Doddy, un traductor de IA en este teléfono…" Your half shows what was said. If they object, you end.
4. **Face to face:**
   - Their half is rotated to face them.
   - Each half shows the latest turn in its own language, large.
   - "Show what they said" reveals the original; Say it again and Pause are available.
   - A middle bar shows who's being listened to, the pair, and End.
5. **Numbers stay exact:** prices, times, numbers, addresses and names are copied, never translated or rounded, and shown as cards on both halves.
6. **Noisy place:** "Mówię ja" / "Hablo yo" hold-to-talk buttons. Used when Doddy can't tell who is talking, or when you turn it on.
7. **A quiet word:** "Doddy, …" in your language pauses translation. The answer is text on your half only; it is said to them only if you tap "Say it to them".
8. **Careful mode** (health, law, police, money):
   - Doddy translates word for word, marks doubt, and keeps exact cards.
   - Both halves suggest writing it down or using a professional interpreter.
   - Doddy never gives his own advice. It turns on by itself for these topics and stays on until the end.
9. **End:**
   - The summary says what happened: turns, languages, length.
   - Nothing is kept on the iPhone. Copy the text, or save the facts as a note, only by tapping within 5 minutes.
   - ElevenLabs keeps its own recording, as in Settings › Privacy.

## Rules
- **Translate, don't answer:** a question is translated, never answered.
- **Same meaning:** no additions, no softening, no omissions; say "not sure: …" rather than guess.
- **AI disclosure to the other person,** before anything else, in their language. Their half always says "AI translation, may contain mistakes".
- **Their consent:** their voice is processed by ElevenLabs. The start screen says so, and the disclosure gives them the chance to say no.
- **A separate session:**
  - no tools, no saved notes, no memory of you (`{{user_profile}}` and notes are not sent) and none of them;
  - not added to "recent conversations".
- **Not for emergencies:** say "call 112".

## How it would be built (for the implementing milestone)
- **Agent:** a separate ElevenLabs agent, "Doddy (translator)".
  - Its own prompt and the same voice; the 37 language presets and `language_detection`; **no tools**.
  - Dynamic variables `owner_language` and `other_language`.
  - Its own spec in `voice-agent/translator/`, like `voice-agent/phone/`.
- **App:**
  - a `TranslatorSession` next to `VoiceSessionController`, with a face-to-face view where the top half is rotated 180°;
  - exact-fact cards extracted from the transcript in the app, with tests;
  - the 5-minute window kept in memory only;
  - the hold-to-talk fallback mutes the microphone between turns.
- **Main agent:** a `start_translator` tool that proposes only the language pair. The app ends the current conversation and opens the translator after the user taps Start.
- **Privacy text:** the translator joins "What leaves this iPhone", with a line saying the other person's voice is sent too.
- **Tests:**
  - parsing the pair;
  - the exact-fact extractor (numbers, times, prices, addresses);
  - nothing is written to the database or the conversation log;
  - the disclosure line exists for all 37 languages.

## Decisions for the owner
| ID | Question | Proposed |
|---|---|---|
| T1 | Scope of the first version | Face to face only. Later: listen-only (a guide, an announcement) and "speak for me" |
| T2 | Separate agent or a mode of the main one | Separate "Doddy (translator)" with no tools |
| T3 | Saving | Nothing by default; copy, or save the facts as a note, within 5 minutes on a tap |
| T4 | Who's talking | By language, with hold-to-talk as a fallback |
| T5 | Quiet word with Doddy during translation | Yes, as text on your half only |
| T6 | Voice | Doddy's voice in both directions (a native voice per language would be clearer but less "Doddy") |

## Risks to check before building
- **Latency:** each turn passes through speech recognition, the model and speech synthesis, so expect 1–2 s. Check it's acceptable face to face.
- **Who's talking:** detection by language fails when both people use the same language, or mix languages.
- **Accuracy:** in careful mode, accuracy can't be guaranteed; the design says so on both halves.
- **Cost:** translator minutes are ElevenLabs conversation minutes.
