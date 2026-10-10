# Translator mode: design (ADR-208; all decisions made)
Owner, 2026-10-10: "we should design translator mode where he starts translating and talking in someone's language — suggest design". Canvas: **Doddy Translator** (screens 1–9, 6b and a rules board). Owner answers, 2026-10-10: "1. both 2 mode 3. what 4 yes 5. yes 6 native". **Nothing here is built.**

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
6b. **Listen only (T1):** one way, into your language, for a guide, a talk or an announcement.
   - Each line appears as text with the original underneath; with earphones it is also read aloud quietly.
   - Doddy never speaks to the people around you.
   - It's only for things said to a group or in public, not someone's private conversation.
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
- **A mode inside Doddy's conversation (T2):**
  - The app refuses every tool call while the mode is on.
  - Doddy never tells the other person anything from your notes or profile.
  - The conversation is treated as private: not added to "recent conversations" and not kept on the iPhone.
- **Not for emergencies:** say "call 112".

## How it would be built (for the implementing milestone)
- **Agent:** a **mode of the main agent (T2)**, not a separate agent.
  - `start_translator` (pair and mode: `face_to_face` or `listen`) switches the conversation into the mode once the user taps Start; `stop_translator` switches it back.
  - The prompt gains a "Translator mode" section: translate, never answer, exact numbers, careful mode, the disclosure line, the quiet word.
  - Without a restart, your notes and profile are still in the model's context. "Never share them" is therefore a prompt rule, and the risk is listed below.
- **Native voices (T6):** one native ElevenLabs voice per language, picked and listened to before release.
  - They are set on the agent as `supported_voices` with a label per language, and the model tags each translated line with that label. Doddy's own voice stays for the quiet word and normal talk.
  - The 36 language presets can also set a `voice_id` per language.
  - Whether voices switch per line, and how much that adds to the delay, has to be checked in a live test.
- **App:**
  - **Translator state:** a translator state in `VoiceSessionController` makes every tool call fail with "translator mode: no tools" and marks the conversation private.
  - **Screens:**
    - the face-to-face view, where the top half is rotated 180°;
    - the listen-only view;
    - exact-fact cards extracted in the app from the transcript, with tests.
  - **Noisy places:** hold-to-talk mutes the microphone between turns.
- **Privacy text:** the translator joins "What leaves this iPhone", with a line saying the other person's voice is sent too, and that listen-only hears whoever is nearby.
- **Tests:**
  - parsing the pair and the mode;
  - tools refused in translator mode;
  - the exact-fact extractor (numbers, times, prices, addresses);
  - nothing written to the conversation log;
  - the disclosure line exists for all 37 languages.

## Decisions
| ID | Question | Owner's answer |
|---|---|---|
| T1 | Scope of the first version | **Both**: face to face and listen only |
| T2 | Separate agent or a mode | **A mode of Doddy** |
| T3 | What is kept after translating | **(a)**: nothing kept; copy, or save the facts as a note, within 5 minutes on a tap |
| T4 | Who's talking | **Yes**: by language, with hold-to-talk as a fallback |
| T5 | Quiet word with Doddy | **Yes**, as text on your half |
| T6 | Voice | **A native voice per language** |

**T3 options:**
- **(a) Nothing kept, copy within 5 minutes** (proposed): the text disappears when you leave the end screen, unless you tap Copy or "Save the facts as a note".
- **(b) Nothing ever:** no copy, no save; the text is gone when the session ends.
- **(c) Kept like a normal conversation:** it shows in your conversation history, and Doddy can bring it up later.

## Risks to check before building
- **T2:** your notes and profile are in the model's context during translation, so not sharing them is a prompt rule, not something the code enforces. Mitigation: careful wording, plus testing with "what do you know about him?" asked by the other person.
- **T6:** switching voice per line may add delay or occasionally use the wrong voice.
- **Latency:** each turn passes through speech recognition, the model and speech synthesis, so expect 1–2 s. Check it's acceptable face to face.
- **Who's talking:** detection by language fails when both people use the same language, or mix languages.
- **Accuracy:** in careful mode, accuracy can't be guaranteed; the design says so on both halves.
- **Cost:** translator minutes are ElevenLabs conversation minutes.
